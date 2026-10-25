// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;
import {IERC6909Claims} from "v4-core/interfaces/external/IERC6909Claims.sol";

import {FormalMatchD} from "./FormalMatchD.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/types/Currency.sol";

/// @notice Runtime checks for direct ERC-6909 claim settlement, event order, and failure rollback.
contract AsyncSwapSettleTransfersFormalTest is FormalMatchD {
    function _reason(uint256 tag) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("MockedPoolManagerCall(uint256)", tag);
    }

    /// @dev `inputOf key order`: currency0 when it sells token 0.
    function _inputOf(Case memory c, bool zeroForOne) internal pure returns (Currency) {
        return zeroForOne ? c.k.currency0 : c.k.currency1;
    }

    /// @notice Check the direct claim-transfer path and its observable result.
    function testFuzz_settleTransfers_run(uint256[6] memory s, uint8 flags) public {
        Case memory c = _mkCase(s, flags);
        Run memory r = _exec(c);
        if (r.matched == 0) return;
        Trace memory t = _newTrace();
        _escrowLeg(t, _inputOf(c, r.sell0.zeroForOne), r.buy0.owner, r.asset);
        _escrowLeg(t, _inputOf(c, r.buy0.zeroForOne), r.sell0.owner, r.quote);
        _assertOps(_legsOf(r.ops), _done(t));
        assertEq(r.buy0.owner, bob);
        assertEq(r.sell0.owner, alice);
    }

    /// @notice Check the direct claim-transfer path and its observable result.
    function testFuzz_settleTransfers_reverts_iff(uint256[6] memory s, uint8 flags, uint8 mode, uint256 tag) public {
        Case memory c = _mkCase(s, flags);
        (bool matches, uint256 asset, uint256 quote) = _pre(c);
        if (!matches) return;
        mode %= 5; // 0 none; 1/2 asset leg burn/payout; 3/4 quote leg burn/payout
        _mockLeg(c, asset, quote, mode, _reason(tag));
        if (mode == 0) {
            bytes[] memory res = _runR(_matchCalls(c.k));
            assertEq(abi.decode(res[0], (uint8)), 1, "both legs succeed: no revert");
        } else {
            vm.expectRevert(_reason(tag));
            _run(_matchCalls(c.k));
        }
    }

    /// @notice Check the direct claim-transfer path and its observable result.
    function testFuzz_settleTransfers_ok(uint256[6] memory s, uint8 flags) public {
        Case memory c = _mkCase(s, flags);
        Run memory r = _exec(c);
        if (r.matched == 0) return;
        Op[] memory legs = _legsOf(r.ops);
        assertEq(legs.length, 2);
        assertEq(legs[0].kind, OP_TRANSFER);
        assertEq(legs[1].kind, OP_TRANSFER);
        assertEq(legs[0].cur, _inputOf(c, true).toId());
        assertEq(legs[1].cur, _inputOf(c, false).toId());
        assertEq(legs[0].amount, r.asset);
        assertEq(legs[1].amount, r.quote);
        assertEq(legs[0].who, bob);
        assertEq(legs[1].who, alice);
        Trace memory t = _newTrace();
        _escrowLeg(t, c.k.currency0, bob, r.asset);
        _escrowLeg(t, c.k.currency1, alice, r.quote);
        _assertOps(legs, _done(t));
    }

    /// @notice Check the direct claim-transfer path and its observable result.
    function testFuzz_settleTransfers_ok_same_manager(uint256[6] memory s, uint8 flags) public {
        Case memory c = _mkCase(s, flags);
        (bool matches, uint256 asset, uint256 quote) = _pre(c);
        if (!matches) return;
        (IPoolManager pm0,,) = hook.asyncOrders(c.pid);
        assertEq(address(pm0), address(manager));
        // Both claim transfers use the configured PoolManager.
        vm.expectCall(address(manager), abi.encodeCall(IERC6909Claims.transfer, (bob, c.k.currency0.toId(), asset)));
        vm.expectCall(address(manager), abi.encodeCall(IERC6909Claims.transfer, (alice, c.k.currency1.toId(), quote)));
        Run memory r = _exec(c);
        assertEq(r.matched, 1);
        (IPoolManager pm1,,) = hook.asyncOrders(c.pid);
        assertEq(address(pm1), address(pm0), "poolManager unchanged");
    }
}
