// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {FormalMatchD} from "./FormalMatchD.sol";

/// @notice Runtime checks for direct ERC-6909 claim settlement, event order, and failure rollback.
contract AsyncSwapTransferEscrowFormalTest is FormalMatchD {
    function _reason(uint256 tag) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("MockedPoolManagerCall(uint256)", tag);
    }

    /// @notice Check the direct claim-transfer path and its observable result.
    function testFuzz_transferEscrow_run(uint256[6] memory s, uint8 flags) public {
        Case memory c = _mkCase(s, flags);
        Run memory r = _exec(c);
        if (r.matched == 0) return;
        _assertOps(_legsOf(r.ops), _legOps(c, r));
    }

    /// @notice Check the direct claim-transfer path and its observable result.
    function testFuzz_transferEscrow_claim_transfer_reverts(
        uint256[6] memory s,
        uint8 flags,
        bool quoteLeg,
        uint256 tag
    ) public {
        Case memory c = _mkCase(s, flags);
        (bool matches, uint256 asset, uint256 quote) = _pre(c);
        if (!matches) return;
        _mockLeg(c, asset, quote, quoteLeg ? 3 : 1, _reason(tag));
        uint256 bobBefore = _claims(bob, c.k.currency0);
        vm.expectRevert(_reason(tag));
        _run(_matchCalls(c.k));
        assertEq(_claims(bob, c.k.currency0), bobBefore, "earlier claim credit rolled back");
    }

    /// @notice Check the direct claim-transfer path and its observable result.
    function testFuzz_transferEscrow_native(uint256[6] memory s, uint8 flags, bool failTransfer, uint256 tag) public {
        Case memory c = _mkCase(s, flags | 2);
        (bool matches, uint256 asset, uint256 quote) = _pre(c);
        if (!matches) return;
        if (failTransfer) {
            _mockLeg(c, asset, quote, 2, _reason(tag)); // transfer native claims to the buyer
            vm.expectRevert(_reason(tag));
            _run(_matchCalls(c.k));
        } else {
            Run memory r = _exec(c);
            assertEq(r.matched, 1);
            Op[] memory legs = _legsOf(r.ops);
            _assertOp(legs[0], Op(OP_TRANSFER, bob, 0, asset, 0, 0, 0), "native claim transfer");
        }
    }

    /// @notice Check the direct claim-transfer path and its observable result.
    function testFuzz_transferEscrow_erc20(
        uint256[6] memory s,
        uint8 flags,
        bool quoteLeg,
        bool failTransfer,
        uint256 tag
    ) public {
        Case memory c = _mkCase(s, flags & ~uint8(2));
        (bool matches, uint256 asset, uint256 quote) = _pre(c);
        if (!matches) return;
        if (failTransfer) {
            _mockLeg(c, asset, quote, quoteLeg ? 4 : 2, _reason(tag));
            vm.expectRevert(_reason(tag));
            _run(_matchCalls(c.k));
        } else {
            Op[] memory legs = _legsOf(_exec(c).ops);
            uint256 i = quoteLeg ? 1 : 0;
            (address token, address to, uint256 amount) =
                quoteLeg ? (address(token1), alice, quote) : (address(token0), bob, asset);
            _assertOp(legs[i], Op(OP_TRANSFER, to, uint256(uint160(token)), amount, 0, 0, 0), "claim transfer");
        }
    }

    /// @notice Check the direct claim-transfer path and its observable result.
    function testFuzz_transferEscrow_ok(uint256[6] memory s, uint8 flags) public {
        Case memory c = _mkCase(s, flags);
        Run memory r = _exec(c);
        if (r.matched == 0) return;
        Op[] memory legs = _legsOf(r.ops);
        assertEq(legs.length, 2);
        for (uint256 leg; leg < 2; ++leg) {
            assertEq(legs[leg].kind, OP_TRANSFER);
        }
        _assertOps(legs, _legOps(c, r));
    }

    /// @notice Check the direct claim-transfer path and its observable result.
    function testFuzz_transferEscrow_reverts_iff(uint256[6] memory s, uint8 flags, uint8 mode, uint256 tag) public {
        Case memory c = _mkCase(s, flags);
        (bool matches, uint256 asset, uint256 quote) = _pre(c);
        if (!matches) return;
        mode %= 5; // 0: neither call reverts; 1/3: the burn of a leg; 2/4: its payout
        _mockLeg(c, asset, quote, mode, _reason(tag));
        if (mode == 0) {
            bytes[] memory res = _runR(_matchCalls(c.k));
            assertEq(abi.decode(res[0], (uint8)), 1, "no revert");
        } else {
            vm.expectRevert(_reason(tag));
            _run(_matchCalls(c.k));
        }
    }
}
