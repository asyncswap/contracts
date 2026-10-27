// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {ISignatureTransfer} from "@async-swap/interfaces/ISignatureTransfer.sol";
import {AsyncSwap} from "@async-swap/AsyncSwap.sol";
import {Router} from "@async-swap/Router.sol";
import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";
import {MockERC20} from "../utils/MockERC20.sol";
import {NoReturnERC20} from "../utils/NoReturnERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Permit2Bytecode} from "../utils/Permit2Bytecode.sol";
import {Test} from "forge-std/Test.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {Currency, IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {PoolIdLibrary, PoolKey} from "v4-core/types/PoolKey.sol";

/// @notice Tokens that return no data from transfer (USDT-style) work for create, fill and cancel.
contract NoReturnTokenTest is Test {
    using PoolIdLibrary for PoolKey;

    IPoolManager manager;
    AsyncSwap hook;
    Router router;
    NoReturnERC20 usdt;
    MockERC20 usdc;
    PoolKey key;
    PoolId poolId;
    bool usdtIsZero;
    address maker = makeAddr("maker");
    address filler = makeAddr("filler");

    function setUp() public {
        manager = new PoolManager(address(this));
        usdt = new NoReturnERC20();
        usdc = new MockERC20("USDC", "USDC", 6);
        usdtIsZero = address(usdt) < address(usdc);
        (address t0, address t1) = usdtIsZero ? (address(usdt), address(usdc)) : (address(usdc), address(usdt));

        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );
        router = new Router(manager, AsyncSwap(payable(address(flags))), ISignatureTransfer(Permit2Bytecode.PERMIT2));
        deployCodeTo(
            "AsyncSwap.sol",
            abi.encode(manager, Currency.wrap(address(usdc)), address(this), address(router)),
            address(flags)
        );
        hook = AsyncSwap(payable(address(flags)));
        key = PoolKey(Currency.wrap(t0), Currency.wrap(t1), LPFeeLibrary.DYNAMIC_FEE_FLAG, 1, hook);
        poolId = key.toId();
        manager.initialize(key, 2 ** 96);

        for (uint256 i; i < 2; i++) {
            address u = i == 0 ? maker : filler;
            usdt.mint(u, 1000e6);
            usdc.mint(u, 1000e6);
            vm.startPrank(u);
            usdt.approve(address(router), type(uint256).max);
            usdc.approve(address(router), type(uint256).max);
            hook.setExecutor(poolId, address(router), true);
            vm.stopPrank();
        }
    }

    function _place(bool usdtIn, uint256 amountIn, uint256 amountOutMin) internal returns (AsyncOrder memory order) {
        bool zeroForOne = usdtIn == usdtIsZero;
        order = AsyncOrder({
            key: key,
            owner: maker,
            zeroForOne: zeroForOne,
            amountIn: amountIn,
            amountOutMin: amountOutMin,
            priorityFee: 100_000,
            sqrtPrice: zeroForOne ? 4295128740 : 1461446703485210103287273052203988822378723970341,
            salt: bytes32(0)
        });
        vm.prank(maker);
        router.swap(
            order,
            abi.encode(
                AsyncSwap.UserParams({
                    user: maker, executor: address(router), amountOutMin: amountOutMin, priorityFee: 100_000
                })
            )
        );
        order.salt = keccak256(
            abi.encode(block.timestamp, block.number, address(manager), maker, amountIn, amountOutMin, 100_000)
        );
    }

    function test_noReturnTokenAsMakerInput_createAndCancel() public {
        AsyncOrder memory order = _place(true, 100e6, 99e6);
        assertEq(usdt.balanceOf(maker), 900e6, "input escrowed");
        vm.prank(maker);
        router.cancelOrder(order);
        assertEq(usdt.balanceOf(maker), 1000e6, "input returned");
    }

    function test_noReturnTokenAsFillerOutput_fill() public {
        AsyncOrder memory order = _place(false, 100e6, 99e6);
        uint256 gross = 99e6 + hook.calculatePoolFee(key.fee, 99e6);
        // The filler receives the input net of the maker's 0.03% fee.
        uint256 netIn = 100e6 - Math.mulDiv(100e6, 3, 10_000, Math.Rounding.Ceil);
        order.amountIn = netIn;
        vm.prank(filler);
        router.fillOrder(order, type(uint256).max, "");
        assertEq(usdt.balanceOf(maker), 1000e6 + 99e6, "maker paid net output");
        assertEq(usdt.balanceOf(filler), 1000e6 - gross, "filler paid gross output");
        assertEq(usdc.balanceOf(filler), 1000e6 + netIn, "filler received net input");
    }
}
