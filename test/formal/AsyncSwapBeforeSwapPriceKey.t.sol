// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {FormalBase} from "./FormalBase.sol";
import {AsyncSwap} from "@async-swap/AsyncSwap.sol";
import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";
import {Router} from "@async-swap/router.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {CustomRevert} from "v4-core/libraries/CustomRevert.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";

/// @notice Evidence for plan item 229 (S-04 at the entry point): `BaseHook.beforeSwap` →
///         `AsyncSwap._beforeSwap` → `_createOrder` → `AsyncMatching.addOrder` → `AsyncFiller.addOrder`
///         → `_priceKey` (`TickPrice.key`). For nonzero `amountIn` / `amountOutMin` no revert comes out
///         of the price key: not its division-by-zero panic (0x12), not an arithmetic panic, not a
///         `mulDiv` overflow, not a TickMath error.
///
///         `formal/Refinement/Swarm/AsyncSwapAddOrder.lean` proves `AsyncFiller.addOrder`'s key step
///         succeeds iff its denominator is nonzero (`addOrder_key_ok`, `addOrder_key_zero`) and records
///         that the library has no zero-amount guard of its own; `_createOrder` (opaque in the model)
///         supplies it (`amountIn == 0 || amountOutMin == 0 → ZeroAmount`). This file covers that hop.
contract AsyncSwapBeforeSwapPriceKeyTest is FormalBase {
    using PoolIdLibrary for *;

    uint256 constant PF = 100_000; // >= minPriorityFee for every amount (it is capped at 100_000)

    bytes4 constant PANIC = 0x4e487b71; // Panic(uint256)
    bytes4 constant MULDIV_OVERFLOW = bytes4(keccak256("MathOverflowedMulDiv()"));

    /// @dev True iff `s` (with payload `r`) is a revert the price key could raise.
    function _isKeySelector(bytes4 s) internal pure returns (bool) {
        return s == PANIC || s == MULDIV_OVERFLOW || s == TickMath.InvalidSqrtPrice.selector
            || s == TickMath.InvalidTick.selector;
    }

    /// @dev True iff `r` is a price-key-class revert, directly or wrapped by v4's `WrappedError` (the
    ///      PoolManager wraps hook reverts), at any depth.
    function _isKeyRevert(bytes memory r) internal pure returns (bool) {
        if (r.length < 4) return false;
        bytes4 s = bytes4(r);
        if (_isKeySelector(s)) return true;
        if (s == CustomRevert.WrappedError.selector) {
            bytes memory body = new bytes(r.length - 4);
            for (uint256 i = 0; i < body.length; i++) {
                body[i] = r[i + 4];
            }
            (, bytes4 inner, bytes memory reason,) = abi.decode(body, (address, bytes4, bytes, bytes));
            if (_isKeySelector(inner)) return true;
            return _isKeyRevert(reason);
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

    /// @notice Nonzero `amountIn ∈ [1, 50 ether]`, nonzero `amountOutMin < 2^128`, either direction
    ///         (so both `isBuy` sides and both key denominators): order creation through `beforeSwap`
    ///         succeeds, so nothing (in particular nothing from `TickPrice.key`) reverts, and the order
    ///         escrows `amountIn`.
    function testFuzz_beforeSwap_priceKeyNeverReverts(bool zeroForOne, uint256 amountIn, uint256 amountOutMin)
        public
    {
        amountIn = bound(amountIn, 1, 50 ether);
        amountOutMin = bound(amountOutMin, 1, type(uint128).max);
        (bool ok, bytes memory ret) = _swap(alice, zeroForOne, amountIn, amountOutMin);
        assertFalse(!ok && _isKeyRevert(ret), "price-key revert through beforeSwap");
        assertTrue(ok, "nonzero order must be created");
        bytes32 id = _orderIdFor(alice, zeroForOne, _expectedSalt(alice, amountIn, amountOutMin));
        assertEq(hook.asyncOrder(key.toId(), id), amountIn, "escrowed amountIn");
    }

    /// @notice Any nonzero `amountOutMin` up to `2^256 - 1`: whatever else may reject an oversized
    ///         order, it is never a price-key revert (division by zero, panic, mulDiv overflow, TickMath).
    function testFuzz_beforeSwap_priceKeyNeverReverts_wide(bool zeroForOne, uint256 amountIn, uint256 amountOutMin)
        public
    {
        amountIn = bound(amountIn, 1, 50 ether);
        amountOutMin = bound(amountOutMin, 1, type(uint256).max);
        (bool ok, bytes memory ret) = _swap(alice, zeroForOne, amountIn, amountOutMin);
        assertFalse(!ok && _isKeyRevert(ret), "price-key revert through beforeSwap");
    }

    /// @notice The extreme ratios (key clamped at either end of the tick range): created, no revert.
    function testFuzz_beforeSwap_priceKeyNeverReverts_extremes(bool zeroForOne, bool tiny, uint256 big) public {
        big = bound(big, 2 ** 64, type(uint128).max);
        (uint256 amountIn, uint256 amountOutMin) = tiny ? (uint256(50 ether), uint256(1)) : (uint256(1), big);
        (bool ok, bytes memory ret) = _swap(alice, zeroForOne, amountIn, amountOutMin);
        assertFalse(!ok && _isKeyRevert(ret), "price-key revert through beforeSwap");
        assertTrue(ok, "extreme-ratio order must be created");
    }

    /// @notice A second order on a non-empty book (it may cross the first and partially fill it,
    ///         which re-keys the resting order): no price-key revert on either.
    function testFuzz_beforeSwap_priceKeyNeverReverts_twoOrders(
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
        out2 = bound(out2, 1, type(uint128).max);
        (bool ok1, bytes memory r1) = _swap(alice, z1, in1, out1);
        assertFalse(!ok1 && _isKeyRevert(r1), "price-key revert (first order)");
        assertTrue(ok1, "first order");
        vm.warp(block.timestamp + 1); // a distinct salt for the second order
        (bool ok2, bytes memory r2) = _swap(bob, z2, in2, out2);
        assertFalse(!ok2 && _isKeyRevert(r2), "price-key revert (second order)");
    }

    /// @notice The guard the library lacks: with `amountOutMin = 0` (the key denominator of a
    ///         oneForZero order) the swap reverts before the price key: never with its panic 0x12.
    function testFuzz_beforeSwap_zeroAmountOutMin_guarded(bool zeroForOne, uint256 amountIn) public {
        amountIn = bound(amountIn, 1, 50 ether);
        (bool ok, bytes memory ret) = _swap(alice, zeroForOne, amountIn, 0);
        assertFalse(ok, "zero amountOutMin must be rejected");
        assertFalse(_isKeyRevert(ret), "rejected by the price key instead of ZeroAmount");
    }
}
