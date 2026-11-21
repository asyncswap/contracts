// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {BookFiller, FlashFillTest, MockFlashFiller} from "./FlashFill.t.sol";
import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";
import {IAsyncSwapCallback} from "@async-swap/interfaces/IAsyncSwapCallback.sol";
import {RouterFlashFills} from "@async-swap/RouterFlashFills.sol";
import {IAsyncSwapFlashFiller} from "@async-swap/interfaces/IAsyncSwapFlashFiller.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolIdLibrary, PoolKey} from "v4-core/types/PoolKey.sol";

/// @notice Refuses plain ETH, like a maker contract that only accounts for native claims.
contract RefusesEth {
    receive() external payable {
        revert("no ETH");
    }
}

/// @notice A flash filler with no `receive`: it fills the orders in `data` inside the callback and cannot take plain ETH.
contract NoReceiveFiller is IAsyncSwapFlashFiller {
    IPoolManager immutable manager;
    IAsyncSwapCallback immutable router;

    constructor(IPoolManager _manager, IAsyncSwapCallback _router) {
        manager = _manager;
        router = _router;
    }

    function fill(AsyncOrder calldata order, uint256 maxPrice, bytes calldata data) external payable {
        router.fillOrderWithCallback{value: msg.value}(order, maxPrice, data);
    }

    function asyncSwapFlashFill(AsyncOrder calldata order, uint256, uint256 amountOwed, bytes calldata data) external {
        AsyncOrder[] memory orders = abi.decode(data, (AsyncOrder[]));
        for (uint256 i; i < orders.length; ++i) {
            Currency out = orders[i].zeroForOne ? orders[i].key.currency1 : orders[i].key.currency0;
            manager.approve(address(router), out.toId(), orders[i].amountOutMin);
            router.fillOrderInCallback(orders[i], orders[i].amountOutMin);
        }
        Currency output = order.zeroForOne ? order.key.currency1 : order.key.currency0;
        manager.approve(address(router), output.toId(), amountOwed);
    }
}

/// @notice Flash fills whose output is native ETH. Every native payout to a maker is a PoolManager claim (id 0), so
///         no fill ever calls the maker's code.
contract FlashFillNativeTest is FlashFillTest {
    using PoolIdLibrary for PoolKey;

    /// @dev Alice sells 100 TOKEN for at least 0.9 ETH. Bob bids USDC for TOKEN and Carol asks USDC for ETH, so a
    ///      filler can route 100 TOKEN into about 0.9998 ETH.
    function _nativeBook() internal returns (AsyncOrder memory a, AsyncOrder memory bid, AsyncOrder memory ask) {
        bid = _place(bob, tokenUsdc, USDC, 2500 ether, 99 ether);
        ask = _place(carol, ethUsdc, ETH, 1 ether, 2400 ether);
        a = _place(alice, ethToken, TOKEN, 100 ether, 0.9 ether);
    }

    /// @notice A maker whose code refuses ETH is still filled: its ETH arrives as claims, no plain transfer.
    function test_nativeOutput_makerThatRefusesEth() public {
        (AsyncOrder memory a, AsyncOrder memory bid, AsyncOrder memory ask) = _nativeBook();
        vm.etch(alice, address(new RefusesEth()).code);
        uint256 aliceEth = alice.balance;

        filler.run(a, 0.9 ether, _steps2(_fillStep(bid), _fillStep(ask)), 0);

        assertEq(alice.balance, aliceEth, "no plain ETH sent to the maker");
        assertEq(manager.balanceOf(alice, ETH.toId()), 0.9 ether - _fee(0.9 ether), "minimum less fee, as claims");
        assertEq(manager.balanceOf(address(router), ETH.toId()), 0, "router keeps nothing");
        assertEq(address(router).balance, 0);
        assertEq(_live(a), 0);
    }

    /// @notice The same for an ETH-output order filled inside another flash fill (`fillOrderInCallback`).
    function test_nativeOutput_inCallbackMakerThatRefusesEth() public {
        // Outer: Carol sells 1 ETH for at least 2400 USDC. Inside, the filler spends that ETH on Alice's ETH-output
        // order and sells her TOKEN into Bob's TOKEN/USDC bid to pay Carol.
        AsyncOrder memory bid = _place(bob, tokenUsdc, USDC, 2500 ether, 99 ether);
        AsyncOrder memory outer = _place(carol, ethUsdc, ETH, 1 ether, 2400 ether);
        AsyncOrder memory a = _place(alice, ethToken, TOKEN, 100 ether, 0.9 ether);
        vm.etch(alice, address(new RefusesEth()).code);

        MockFlashFiller.Step memory fillAlice = MockFlashFiller.Step({
            payCurrency: ETH,
            payAmount: 0.9 ether,
            target: address(router),
            callData: abi.encodeCall(IAsyncSwapCallback.fillOrderInCallback, (a, 0.9 ether))
        });
        filler.run(outer, 2400 ether, _steps2(fillAlice, _fillStep(bid)), 0);

        assertEq(manager.balanceOf(alice, ETH.toId()), 0.9 ether - _fee(0.9 ether));
        assertEq(_live(a), 0);
        assertEq(_live(outer), 0);
    }
}

/// @notice ETH-output flash fills with a live MEV tax: the tax ledger (the Router's native delta) stays exact.
contract FlashFillNativeMevTaxTest is FlashFillNativeTest {
    uint256 constant TAX_GAS = 100_000;
    uint256 constant PRIORITY = 2 gwei;
    uint256 constant TAX = TAX_GAS * PRIORITY;

    function _mevTaxGas() internal pure override returns (uint256) {
        return TAX_GAS;
    }

    function test_nativeOutput_withMevTax_baseFiller() public {
        (AsyncOrder memory a, AsyncOrder memory bid, AsyncOrder memory ask) = _nativeBook();
        BookFiller base = new BookFiller(manager, IAsyncSwapCallback(address(router)));
        vm.etch(alice, address(new RefusesEth()).code);
        vm.fee(1 gwei);
        vm.txGasPrice(1 gwei + PRIORITY);
        AsyncOrder[] memory route = new AsyncOrder[](2);
        route[0] = bid;
        route[1] = ask;
        uint256 vaultBefore = manager.balanceOf(address(hook.feeVault()), ETH.toId());

        base.fill{value: 3 * TAX}(a, 0.9 ether, abi.encode(route));

        assertEq(manager.balanceOf(alice, ETH.toId()), 0.9 ether - _fee(0.9 ether), "alice");
        assertEq(address(base).balance, 0, "exactly three fills taxed");
        // Vault: the tax for three fills, Carol's ETH input fee, Alice's ETH output fee.
        assertEq(
            manager.balanceOf(address(hook.feeVault()), ETH.toId()) - vaultBefore,
            3 * TAX + _fee(1 ether) + _fee(0.9 ether)
        );
        assertEq(manager.balanceOf(address(base), ETH.toId()), (1 ether - _fee(1 ether)) - 0.9 ether, "surplus");
        assertEq(address(router).balance, 0);
        assertEq(_live(a), 0);
    }

    /// @notice A filler that cannot receive ETH may still overpay the tax: the surplus comes back as native claims.
    function test_mevTax_surplusToFillerWithoutReceive() public {
        (AsyncOrder memory a, AsyncOrder memory b, AsyncOrder memory c) = _crossBook();
        NoReceiveFiller strict = new NoReceiveFiller(manager, IAsyncSwapCallback(address(router)));
        vm.deal(address(this), 1 ether);
        vm.fee(1 gwei);
        vm.txGasPrice(1 gwei + PRIORITY);
        AsyncOrder[] memory route = new AsyncOrder[](2);
        route[0] = b;
        route[1] = c;

        vm.expectEmit(true, false, false, true, address(router));
        emit RouterFlashFills.MevTaxRefunded(address(strict), 5);
        strict.fill{value: 3 * TAX + 5}(a, 90 ether, abi.encode(route));

        assertEq(address(strict).balance, 0);
        assertEq(manager.balanceOf(address(strict), ETH.toId()), (1 ether - _fee(1 ether)) - 0.99 ether + 5);
        assertEq(address(router).balance, 0);
        assertEq(_live(a), 0);
    }
}
