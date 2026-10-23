// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {SetupHook} from "../SetupHook.t.sol";
import {AsyncSwap} from "@async-swap/AsyncSwap.sol";
import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";
import {MockERC20} from "../utils/MockERC20.sol";
import {Currency} from "v4-core/types/Currency.sol";

/// @notice Regression for exact eligibility with real Router, hook and PoolManager.
contract CoarsePriceBlockingTest is SetupHook {
    address blocker = makeAddr("blocker");
    address seller = makeAddr("seller");
    address buyer = makeAddr("buyer");

    function setUp() public override {
        _deployManager();
        vm.startPrank(owner);
        deployCodeTo("test/utils/MockERC20.sol:MockERC20", abi.encode("Asset", "ASSET", uint8(18)), address(0x100000));
        deployCodeTo(
            "test/utils/MockERC20.sol:MockERC20", abi.encode("USD Coin fixture", "USDC", uint8(6)), address(0x200000)
        );
        vm.stopPrank();
        token0 = MockERC20(address(0x100000));
        token1 = MockERC20(address(0x200000));
        currency0 = Currency.wrap(address(token0));
        currency1 = Currency.wrap(address(token1));
        _deployHook();
        _deployRouter();
        _createKey();
        // 1,000 USDC per 18-decimal asset: raw token1/token0 ratio = 1e-9.
        manager.initialize(key, 2505414483750479311864138);
        _mintToOwner();
        hook.setMinOrder(key, 1_000_000);
        topUp(blocker, 100 ether);
        topUp(seller, 100 ether);
        topUp(buyer, 100 ether);
    }

    function submit(address maker, bool zfo, uint256 amount, uint256 minimum, uint256 bid)
        internal
        returns (AsyncOrder memory order)
    {
        bytes32 salt =
            keccak256(abi.encode(block.timestamp, block.number, address(manager), maker, amount, minimum, bid));
        while (hook.asyncOrder(poolId, _orderIdFor(maker, zfo, salt)) != 0) {
            salt = keccak256(abi.encode(salt));
        }
        order = AsyncOrder(key, maker, zfo, amount, minimum, bid, 2 ** 96, salt);
        vm.startPrank(maker);
        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        router.swap(order, abi.encode(AsyncSwap.UserParams(maker, address(router), minimum, bid)));
        vm.stopPrank();
    }

    function test_twoDollarBlockerCannotStallTwentyThousandDollars() public {
        AsyncOrder memory bad = submit(blocker, true, 2e15 - 1, 2_000_000, 100_001);
        for (uint256 i; i < 20; ++i) {
            submit(seller, true, 1e18, 1_000_000_000, 100_000);
        }
        uint256 before = manager.balanceOf(seller, currency1.toId());
        for (uint256 i; i < 20; ++i) {
            submit(buyer, false, 1_000_000_000, 1e18, 100_000);
        }
        // Match proceeds are credited as PoolManager claims.
        assertEq(manager.balanceOf(seller, currency1.toId()) - before, 20_000_000_000);
        assertEq(hook.asyncOrder(poolId, _orderIdFor(blocker, true, bad.salt)), 2e15 - 1);
        (bool hasAsk, uint128 price, bytes32 head,) = hook.bestOrder(poolId, false);
        assertTrue(hasAsk);
        assertEq(price, 1_000_000_000);
        assertEq(head, _orderIdFor(blocker, true, bad.salt));
        (bool hasBid,,,) = hook.bestOrder(poolId, true);
        assertFalse(hasBid);
        vm.prank(blocker);
        router.cancelOrder(bad);
        (hasAsk,,,) = hook.bestOrder(poolId, false);
        assertFalse(hasAsk);
    }

    function test_incomingSellSkipsHigherFeeNoncrossingBuy() public {
        // Both bids have key 1e9; the higher-fee buyer wants too much asset.
        AsyncOrder memory bad = submit(blocker, false, 1_000_000_001, 1e18 + 1, 100_001);
        AsyncOrder memory good = submit(buyer, false, 1_000_000_001, 1e18, 100_000);
        submit(seller, true, 1e18, 1_000_000_001, 100_000);
        assertEq(hook.asyncOrder(poolId, _orderIdFor(buyer, false, good.salt)), 0);
        assertEq(hook.asyncOrder(poolId, _orderIdFor(blocker, false, bad.salt)), 1_000_000_001);
    }

    function test_higherBidOnCrossingOrderCanBypassBlocker() public {
        submit(blocker, true, 2e15 - 1, 2_000_000, 100_001);
        AsyncOrder memory good = submit(seller, true, 1e18, 1_000_000_000, 100_002);
        submit(buyer, false, 1_000_000_000, 1e18, 100_000);
        assertEq(hook.asyncOrder(poolId, _orderIdFor(seller, true, good.salt)), 0);
    }
}
