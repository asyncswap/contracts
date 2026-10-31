// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {NativeAsyncSwapTest} from "./NativeAsyncSwap.t.sol";
import {AsyncOrder} from "src/types/AsyncOrder.sol";
import {AsyncSwap} from "src/AsyncSwap.sol";
import {Router} from "src/Router.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {ISignatureTransfer} from "src/interfaces/ISignatureTransfer.sol";

contract RejectRouterETH {
    receive() external payable {
        revert("Reject ETH");
    }
}

contract ReenterRouterETH {
    Router public router;
    bool public blocked;

    constructor(Router target) {
        router = target;
    }

    receive() external payable {
        Currency[] memory currencies = new Currency[](1);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;
        try router.withdrawClaims(currencies, amounts) {}
        catch {
            blocked = true;
        }
    }
}

contract RouterClaimsTest is NativeAsyncSwapTest {
    function _openNative() private returns (AsyncOrder memory order) {
        order = _order(alice, true, 1 ether, 1 ether);
        vm.prank(alice);
        router.swap{value: 1 ether}(order, abi.encode(AsyncSwap.UserParams(alice, address(router), 1 ether, 100_000)));
        order = _withAssignedSalt(order);
    }

    function test_cancelAndWithdrawReturnsETHWithoutConsumingExistingClaims() public {
        AsyncOrder memory first = _openNative();
        vm.prank(alice);
        router.cancelOrder(first);
        vm.roll(block.number + 1);
        AsyncOrder memory second = _openNative();
        uint256 beforeETH = alice.balance;
        vm.startPrank(alice);
        manager.approve(address(router), 0, 1 ether);
        second.amountIn = 999 ether; // Caller-supplied sizes do not control the refund.
        router.cancelAndWithdraw(second);
        vm.stopPrank();
        assertEq(alice.balance, beforeETH + 1 ether);
        assertEq(manager.balanceOf(alice, 0), 1 ether);
        assertEq(manager.allowance(alice, address(router), 0), 0);
        assertEq(hook.asyncOrder(poolId, _orderIdFor(alice, true, second.salt)), 0);
    }

    function test_missingClaimApprovalRollsBackCancellation() public {
        AsyncOrder memory order = _openNative();
        vm.prank(alice);
        vm.expectRevert();
        router.cancelAndWithdraw(order);
        assertEq(hook.asyncOrder(poolId, _orderIdFor(alice, true, order.salt)), 1 ether);
        assertEq(manager.balanceOf(alice, 0), 0);
    }

    function test_otherWalletCannotCancelAndWithdraw() public {
        AsyncOrder memory order = _openNative();
        vm.prank(bob);
        vm.expectRevert("Only owner can cancel");
        router.cancelAndWithdraw(order);
    }

    function test_updatedRouterCancelsExistingHookOrdersAfterExecutorGrant() public {
        AsyncOrder memory order = _openNative();
        Router updated = new Router(manager, hook, ISignatureTransfer(address(0)));
        uint256 beforeETH = alice.balance;
        vm.startPrank(alice);
        manager.approve(address(updated), 0, 1 ether);
        vm.expectRevert();
        updated.cancelAndWithdraw(order);
        hook.setExecutor(poolId, address(updated), true);
        updated.cancelAndWithdraw(order);
        vm.stopPrank();
        assertEq(alice.balance, beforeETH + 1 ether);
        assertEq(hook.router(), address(router));
    }

    function test_erc20CancellationReturnsTokensWithoutClaimApproval() public {
        AsyncOrder memory order = _order(alice, false, 1 ether, 1 ether);
        vm.prank(alice);
        router.swap(order, abi.encode(AsyncSwap.UserParams(alice, address(router), 1 ether, 100_000)));
        order = _withAssignedSalt(order);
        uint256 beforeTokens = erc20.balanceOf(alice);
        vm.prank(alice);
        router.cancelAndWithdraw(order);
        assertEq(erc20.balanceOf(alice), beforeTokens + 1 ether);
    }

    function test_withdrawClaimsToOwnerAndRejectDoubleSpend() public {
        AsyncOrder memory order = _openNative();
        vm.startPrank(alice);
        router.cancelOrder(order);
        Currency[] memory currencies = new Currency[](1);
        currencies[0] = currency0;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0.4 ether;
        manager.approve(address(router), 0, 0.4 ether);
        uint256 beforeETH = alice.balance;
        router.withdrawClaims(currencies, amounts);
        assertEq(alice.balance, beforeETH + 0.4 ether);
        assertEq(manager.balanceOf(alice, 0), 0.6 ether);
        vm.expectRevert();
        router.withdrawClaims(currencies, amounts);
        vm.stopPrank();
        vm.prank(bob);
        vm.expectRevert();
        router.withdrawClaims(currencies, amounts);
    }

    function test_rejectedETHRollsBackClaimsAndAllowance() public {
        AsyncOrder memory order = _openNative();
        vm.prank(alice);
        router.cancelOrder(order);
        RejectRouterETH recipient = new RejectRouterETH();
        vm.prank(alice);
        manager.transfer(address(recipient), 0, 1 ether);
        Currency[] memory currencies = new Currency[](1);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;
        vm.startPrank(address(recipient));
        manager.approve(address(router), 0, 1 ether);
        vm.expectRevert();
        router.withdrawClaims(currencies, amounts);
        vm.stopPrank();
        assertEq(manager.balanceOf(address(recipient), 0), 1 ether);
        assertEq(manager.allowance(address(recipient), address(router), 0), 1 ether);
    }

    function test_partialFillCancelsAndWithdrawsOnlyLiveRemainder() public {
        AsyncOrder memory order = _openNative();
        AsyncOrder memory buy = _order(bob, false, 0.4 ether, 0.4 ether);
        vm.startPrank(bob);
        hook.setExecutor(poolId, address(router), true);
        router.swap(buy, abi.encode(AsyncSwap.UserParams(bob, address(router), 0.4 ether, 100_000)));
        vm.stopPrank();
        uint256 remaining = hook.asyncOrder(poolId, _orderIdFor(alice, true, order.salt));
        assertGt(remaining, 0);
        assertLt(remaining, 1 ether);
        uint256 beforeETH = alice.balance;
        vm.startPrank(alice);
        manager.approve(address(router), 0, remaining);
        router.cancelAndWithdraw(order);
        vm.stopPrank();
        assertEq(alice.balance, beforeETH + remaining);
        assertEq(manager.balanceOf(alice, 0), 0);
    }

    function test_laterBatchFailureRollsBackEarlierWithdrawal() public {
        AsyncOrder memory order = _openNative();
        vm.startPrank(alice);
        router.cancelOrder(order);
        manager.approve(address(router), 0, 1 ether);
        Currency[] memory currencies = new Currency[](2);
        currencies[1] = currency1;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1 ether;
        amounts[1] = 1;
        uint256 beforeETH = alice.balance;
        vm.expectRevert();
        router.withdrawClaims(currencies, amounts);
        vm.stopPrank();
        assertEq(alice.balance, beforeETH);
        assertEq(manager.balanceOf(alice, 0), 1 ether);
        assertEq(manager.allowance(alice, address(router), 0), 1 ether);
    }

    function test_nativeReceiverCannotReenterWithdraw() public {
        AsyncOrder memory order = _openNative();
        vm.prank(alice);
        router.cancelOrder(order);
        ReenterRouterETH receiver = new ReenterRouterETH(router);
        vm.prank(alice);
        manager.transfer(address(receiver), 0, 1 ether);
        Currency[] memory currencies = new Currency[](1);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;
        vm.startPrank(address(receiver));
        manager.approve(address(router), 0, 1 ether);
        router.withdrawClaims(currencies, amounts);
        vm.stopPrank();
        assertTrue(receiver.blocked());
        assertEq(address(receiver).balance, 1 ether);
        assertEq(manager.balanceOf(address(receiver), 0), 0);
    }

    function test_invalidWithdrawalBatchesRevert() public {
        Currency[] memory currencies = new Currency[](2);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;
        vm.expectRevert("Duplicate currency");
        router.withdrawClaims(currencies, amounts);
        amounts[0] = 0;
        vm.expectRevert("Zero claim");
        router.withdrawClaims(currencies, amounts);
        vm.expectRevert("Invalid claims");
        router.withdrawClaims(new Currency[](0), new uint256[](0));
    }
}
