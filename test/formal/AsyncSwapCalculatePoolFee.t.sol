// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {FormalSlotsB} from "./FormalSlotsB.sol";
import {AsyncSwap} from "@async-swap/AsyncSwap.sol";
import {FullMath} from "v4-core/libraries/FullMath.sol";

/// @notice Bytecode checks of `formal/Refinement/Swarm/AsyncSwapCalculatePoolFee.lean`.
contract AsyncSwapCalculatePoolFeeFormalTest is FormalSlotsB {
    /// @dev `pf a = a / 9997 * 3 + a % 9997 * 3 / 9997` over unbounded naturals (no term can overflow for a < 2^256).
    function _pf(uint256 a) internal pure returns (uint256) {
        unchecked {
            return a / 9997 * 3 + a % 9997 * 3 / 9997;
        }
    }

    function _call(uint24 f, uint256 a) internal returns (bool ok, bytes memory ret) {
        (ok, ret) = address(hook).call(abi.encodeCall(AsyncSwap.calculatePoolFee, (f, a)));
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapCalculatePoolFee.lean:32 — panics iff pf a ≥ 2^256 (never, for uint256),
    ///         otherwise returns pf a with the world unchanged. (semantics changed by the 0.03% trade fee; Lean
    ///         statement needs updating: pf now divides by 9997, not 997.)
    function testFuzz_calculatePoolFee_run(uint24 f, uint256 a) public {
        vm.record();
        (bool ok, bytes memory ret) = _call(f, a);
        assertTrue(ok, "pf a < 2^256 for every uint256");
        assertEq(abi.decode(ret, (uint256)), _pf(a));
        _assertNoHookWrites();
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapCalculatePoolFee.lean:46 — for every uint256 amount: no revert, returns
    ///         amount * 3 / 9997 (computed exactly, 512-bit), world unchanged. (semantics changed by the 0.03% trade
    ///         fee; Lean statement needs updating: was amount * 3 / 997.)
    function testFuzz_calculatePoolFee_ok(uint24 f, uint256 a) public {
        vm.record();
        (bool ok, bytes memory ret) = _call(f, a);
        assertTrue(ok);
        assertEq(abi.decode(ret, (uint256)), FullMath.mulDiv(a, 3, 9997));
        _assertNoHookWrites();
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapCalculatePoolFee.lean:53 — the fee never exceeds the amount.
    function testFuzz_calculatePoolFee_le(uint24 f, uint256 a) public {
        vm.record();
        uint256 r = hook.calculatePoolFee(f, a);
        assertLe(r, a);
        _assertNoHookWrites();
    }

    /// @notice Edge values for the three theorems above.
    function test_calculatePoolFee_ok_edges() public view {
        uint256[7] memory xs = [uint256(0), 1, 3_332, 3_333, 9_996, 9_997, type(uint256).max];
        for (uint256 i; i < xs.length; ++i) {
            assertEq(hook.calculatePoolFee(0, xs[i]), FullMath.mulDiv(xs[i], 3, 9997));
        }
    }
}
