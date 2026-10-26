// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {SetupHook} from "./SetupHook.t.sol";
import {BatchCancels} from "src/BatchCancels.sol";
import {AsyncSwap} from "src/AsyncSwap.sol";
import {AsyncOrder} from "src/types/AsyncOrder.sol";

contract BatchCancelsTest is SetupHook {
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    BatchCancels cancels;

    function setUp() public override {
        super.setUp();
        topUp(alice, 100 ether);
        topUp(bob, 100 ether);
        vm.prank(alice);
        token0.approve(address(router), type(uint256).max);
        cancels = new BatchCancels(manager, hook);
        vm.prank(alice);
        hook.setExecutor(poolId, address(cancels), true);
    }

    function _open(uint256 amount) private returns (AsyncOrder memory order) {
        order = AsyncOrder(key, alice, true, amount, amount * 2, 100_000, 2 ** 96, 0);
        vm.prank(alice);
        router.swap(order, abi.encode(AsyncSwap.UserParams(alice, address(router), amount * 2, 100_000)));
        order.salt = _expectedSalt(alice, amount, amount * 2);
    }

    function test_cancelTwoOrdersInOneTransaction() public {
        AsyncOrder[] memory orders = new AsyncOrder[](2);
        orders[0] = _open(1 ether);
        orders[1] = _open(2 ether);
        vm.prank(alice);
        cancels.cancelOrders(orders);
        assertEq(hook.asyncOrder(poolId, _orderIdFor(alice, true, orders[0].salt)), 0);
        assertEq(hook.asyncOrder(poolId, _orderIdFor(alice, true, orders[1].salt)), 0);
        assertEq(token0.balanceOf(alice), 100 ether);
    }

    function test_rejectsOtherOwnerAndDirectCallback() public {
        AsyncOrder[] memory orders = new AsyncOrder[](1);
        orders[0] = _open(1 ether);
        vm.prank(bob);
        vm.expectRevert(BatchCancels.NotOwner.selector);
        cancels.cancelOrders(orders);
        vm.expectRevert(BatchCancels.OnlyPoolManager.selector);
        cancels.unlockCallback("");
        assertGt(hook.asyncOrder(poolId, _orderIdFor(alice, true, orders[0].salt)), 0);
    }

    function test_atomicWhenAnOrderIsAlreadyClosed() public {
        AsyncOrder[] memory orders = new AsyncOrder[](2);
        orders[0] = _open(1 ether);
        orders[1] = _open(2 ether);
        vm.prank(alice);
        router.cancelOrder(orders[1]);
        vm.prank(alice);
        vm.expectRevert();
        cancels.cancelOrders(orders);
        assertGt(hook.asyncOrder(poolId, _orderIdFor(alice, true, orders[0].salt)), 0);
    }
}
