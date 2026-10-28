// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {FormalBase} from "./FormalBase.sol";
import {AsyncSwap} from "@async-swap/AsyncSwap.sol";
import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";
import {Router} from "@async-swap/router.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {CustomRevert} from "v4-core/libraries/CustomRevert.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";

/// @notice Evidence for plan item 225: `BaseHook.beforeSwap` → `AsyncSwap._beforeSwap` →
///         `_createOrder` → `addOrder` (price key via `TickPrice.floorTick` → `TickMath`) never reverts
///         with `TickMath.InvalidSqrtPrice` / `TickMath.InvalidTick`, for any `amountIn`/`amountOutMin`.
///         `formal/Refinement/Swarm/AsyncSwapBeforeSwap.lean` proves the def itself raises no TickMath
///         revert; `_createOrder` is opaque in the Lean model, so this fuzz test covers that hop.
contract AsyncSwapBeforeSwapNoTickRevertTest is FormalBase {
    using PoolIdLibrary for *;

    uint256 constant PF = 100_000; // >= minPriorityFee for every amount (it is capped at 100_000)

    /// @dev True iff `r` is a TickMath revert, directly or wrapped by v4's `WrappedError` (the
    ///      PoolManager wraps hook reverts), at any depth.
    function _isTickRevert(bytes memory r) internal pure returns (bool) {
        if (r.length < 4) return false;
        bytes4 s = bytes4(r);
        if (s == TickMath.InvalidSqrtPrice.selector || s == TickMath.InvalidTick.selector) return true;
        if (s == CustomRevert.WrappedError.selector) {
            bytes memory body = new bytes(r.length - 4);
            for (uint256 i = 0; i < body.length; i++) {
                body[i] = r[i + 4];
            }
            (, bytes4 inner, bytes memory reason,) = abi.decode(body, (address, bytes4, bytes, bytes));
            if (inner == TickMath.InvalidSqrtPrice.selector || inner == TickMath.InvalidTick.selector) return true;
            return _isTickRevert(reason);
        }
        return false;
    }

    function _swap(address maker, bool zeroForOne, uint256 amountIn, uint256 amountOutMin)
        internal
        returns (bool ok, bytes memory ret)
    {
        AsyncOrder memory order = _orderFromMaker(maker, zeroForOne, amountIn, amountOutMin);
        bytes memory ud = abi.encode(
            AsyncSwap.UserParams({user: maker, executor: address(router), amountOutMin: amountOutMin, priorityFee: PF})
        );
        vm.prank(maker);
        (ok, ret) = address(router).call(abi.encodeCall(Router.swap, (order, ud)));
    }

    /// @notice Any `amountIn ∈ [1, 50 ether]`, any `amountOutMin ≥ 1` and either direction: the swap
    ///         through `beforeSwap` never reverts with a TickMath error; with `amountOutMin < 2^128`
    ///         (the order fits the book's `uint128` amounts) it succeeds and escrows `amountIn`.
    function testFuzz_beforeSwap_noTickMathRevert(bool zeroForOne, uint256 amountIn, uint256 amountOutMin) public {
        amountIn = bound(amountIn, 1, 50 ether);
        amountOutMin = bound(amountOutMin, 1, type(uint256).max);
        (bool ok, bytes memory ret) = _swap(alice, zeroForOne, amountIn, amountOutMin);
        assertFalse(!ok && _isTickRevert(ret), "TickMath revert through beforeSwap");
        if (amountOutMin <= type(uint128).max) {
            assertTrue(ok, "in-range order must be created");
            bytes32 id = _orderIdFor(alice, zeroForOne, _expectedSalt(alice, amountIn, amountOutMin));
            assertEq(hook.asyncOrder(key.toId(), id), amountIn, "escrowed amountIn");
        }
    }

    /// @notice The extreme ratios (price key clamped at MIN_TICK / MAX_TICK by `floorTick`).
    function testFuzz_beforeSwap_noTickMathRevert_extremes(bool zeroForOne, bool tiny, uint256 big) public {
        big = bound(big, 2 ** 64, type(uint128).max);
        (uint256 amountIn, uint256 amountOutMin) = tiny ? (uint256(50 ether), uint256(1)) : (uint256(1), big);
        (bool ok, bytes memory ret) = _swap(alice, zeroForOne, amountIn, amountOutMin);
        assertFalse(!ok && _isTickRevert(ret), "TickMath revert through beforeSwap");
        assertTrue(ok, "extreme-ratio order must be created");
    }

    /// @notice A second order on top of an existing one (the book is non-empty, so `addOrder` links
    ///         into an existing level or a new one): still no TickMath revert.
    function testFuzz_beforeSwap_noTickMathRevert_twoOrders(
        bool z1,
        uint256 in1,
        uint256 out1,
        bool z2,
        uint256 in2,
        uint256 out2
    ) public {
        in1 = bound(in1, 1, 20 ether);
        in2 = bound(in2, 1, 20 ether);
        out1 = bound(out1, 1, type(uint128).max);
        out2 = bound(out2, 1, type(uint256).max);
        (bool ok1, bytes memory r1) = _swap(alice, z1, in1, out1);
        assertFalse(!ok1 && _isTickRevert(r1), "TickMath revert (first order)");
        assertTrue(ok1, "first order");
        vm.warp(block.timestamp + 1); // a distinct salt for the second order
        (bool ok2, bytes memory r2) = _swap(bob, z2, in2, out2);
        assertFalse(!ok2 && _isTickRevert(r2), "TickMath revert (second order)");
    }
}
