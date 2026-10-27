// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {SetupHook} from "./SetupHook.t.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {BatchActions} from "src/BatchActions.sol";
import {AsyncSwap} from "src/AsyncSwap.sol";
import {AsyncOrder} from "src/types/AsyncOrder.sol";
import {Currency} from "v4-core/types/Currency.sol";

contract BatchActionsTest is SetupHook {
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address recipient = makeAddr("recipient");
    BatchActions actions;

    function setUp() public override {
        super.setUp();
        topUp(alice, 100 ether);
        topUp(bob, 100 ether);
        vm.prank(alice);
        token0.approve(address(router), type(uint256).max);
        vm.prank(bob);
        token0.approve(address(router), type(uint256).max);
        actions = new BatchActions(manager, hook);
        vm.prank(alice);
        hook.setExecutor(poolId, address(actions), true);
    }

    function _open(uint256 amount) private returns (AsyncOrder memory order) {
        order = AsyncOrder(key, alice, true, amount, amount * 2, 100_000, 2 ** 96, 0);
        vm.prank(alice);
        router.swap(order, abi.encode(AsyncSwap.UserParams(alice, address(router), amount * 2, 100_000)));
        order.salt = _expectedSalt(alice, amount, amount * 2);
    }

    function _emptyOrders() private pure returns (AsyncOrder[] memory) {
        return new AsyncOrder[](0);
    }

    function _emptyCurrencies() private pure returns (Currency[] memory) {
        return new Currency[](0);
    }

    function _emptyAmounts() private pure returns (uint256[] memory) {
        return new uint256[](0);
    }

    /// @dev The deposit whose input after the maker's 0.03% fee is exactly `net`.
    function _gross(uint256 net) private pure returns (uint256) {
        return Math.mulDiv(net, 10_000, 9_997, Math.Rounding.Ceil);
    }

    function _creditBoth() private {
        AsyncOrder memory order;
        order = AsyncOrder(key, alice, true, _gross(10 ether), 10 ether, 100_000, 2 ** 96, 0);
        vm.prank(alice);
        router.swap(order, abi.encode(AsyncSwap.UserParams(alice, address(router), 10 ether, 100_000)));
        order = AsyncOrder(key, bob, false, _gross(10 ether), 10 ether, 100_000, 2 ** 96, 0);
        vm.prank(bob);
        router.swap(order, abi.encode(AsyncSwap.UserParams(bob, address(router), 10 ether, 100_000)));
        order = AsyncOrder(key, bob, true, _gross(5 ether), 5 ether, 100_000, 2 ** 96, 0);
        vm.prank(bob);
        router.swap(order, abi.encode(AsyncSwap.UserParams(bob, address(router), 5 ether, 100_000)));
        order = AsyncOrder(key, alice, false, _gross(5 ether), 5 ether, 100_000, 2 ** 96, 0);
        vm.prank(alice);
        router.swap(order, abi.encode(AsyncSwap.UserParams(alice, address(router), 5 ether, 100_000)));
        assertEq(manager.balanceOf(alice, uint160(Currency.unwrap(currency0))), 5 ether);
        assertEq(manager.balanceOf(alice, uint160(Currency.unwrap(currency1))), 10 ether);
    }

    function test_cancelTwoOrdersInOneUnlock() public {
        AsyncOrder[] memory orders = new AsyncOrder[](2);
        orders[0] = _open(1 ether);
        orders[1] = _open(2 ether);

        vm.prank(alice);
        actions.execute(orders, _emptyCurrencies(), _emptyAmounts(), address(0));

        assertEq(hook.asyncOrder(poolId, _orderIdFor(alice, true, orders[0].salt)), 0);
        assertEq(hook.asyncOrder(poolId, _orderIdFor(alice, true, orders[1].salt)), 0);
        assertEq(token0.balanceOf(alice), 100 ether);
    }

    function test_redeemTwoClaimsInOneUnlock() public {
        _creditBoth();
        Currency[] memory currencies = new Currency[](2);
        currencies[0] = currency0;
        currencies[1] = currency1;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 5 ether;
        amounts[1] = 10 ether;

        vm.prank(alice);
        vm.expectRevert();
        actions.execute(_emptyOrders(), currencies, amounts, recipient);

        vm.prank(alice);
        manager.setOperator(address(actions), true);
        uint256 before0 = token0.balanceOf(recipient);
        uint256 before1 = token1.balanceOf(recipient);
        vm.prank(alice);
        actions.execute(_emptyOrders(), currencies, amounts, recipient);

        assertEq(manager.balanceOf(alice, uint160(Currency.unwrap(currency0))), 0);
        assertEq(manager.balanceOf(alice, uint160(Currency.unwrap(currency1))), 0);
        assertEq(token0.balanceOf(recipient) - before0, 5 ether);
        assertEq(token1.balanceOf(recipient) - before1, 10 ether);
    }

    function test_cancelAndRedeemInOneUnlock() public {
        _creditBoth();
        AsyncOrder[] memory orders = new AsyncOrder[](1);
        orders[0] = _open(1 ether);
        Currency[] memory currencies = new Currency[](1);
        currencies[0] = currency0;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 5 ether;
        vm.prank(alice);
        manager.setOperator(address(actions), true);

        uint256 beforeBalance = token0.balanceOf(recipient);
        vm.prank(alice);
        actions.execute(orders, currencies, amounts, recipient);

        assertEq(hook.asyncOrder(poolId, _orderIdFor(alice, true, orders[0].salt)), 0);
        assertEq(manager.balanceOf(alice, uint160(Currency.unwrap(currency0))), 0);
        assertEq(token0.balanceOf(recipient) - beforeBalance, 5 ether);
    }

    function test_rejectsOtherMakersOrders() public {
        AsyncOrder[] memory orders = new AsyncOrder[](1);
        orders[0] = _open(1 ether);
        vm.prank(bob);
        vm.expectRevert(BatchActions.NotOwner.selector);
        actions.execute(orders, _emptyCurrencies(), _emptyAmounts(), address(0));
        assertGt(hook.asyncOrder(poolId, _orderIdFor(alice, true, orders[0].salt)), 0);
    }

    function test_atomicWhenClaimFailsAfterCancel() public {
        AsyncOrder[] memory orders = new AsyncOrder[](1);
        orders[0] = _open(1 ether);
        Currency[] memory currencies = new Currency[](1);
        currencies[0] = currency1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;
        vm.prank(alice);
        manager.setOperator(address(actions), true);

        vm.prank(alice);
        vm.expectRevert();
        actions.execute(orders, currencies, amounts, recipient);
        assertGt(hook.asyncOrder(poolId, _orderIdFor(alice, true, orders[0].salt)), 0);
    }

    function test_rejectsInvalidInputsAndDirectCallback() public {
        vm.expectRevert(BatchActions.InvalidBatch.selector);
        actions.execute(_emptyOrders(), _emptyCurrencies(), _emptyAmounts(), address(0));
        Currency[] memory currencies = new Currency[](2);
        currencies[0] = currency0;
        currencies[1] = currency0;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;
        vm.expectRevert(BatchActions.InvalidBatch.selector);
        actions.execute(_emptyOrders(), currencies, amounts, recipient);
        vm.expectRevert(BatchActions.OnlyPoolManager.selector);
        actions.unlockCallback("");
    }
}
