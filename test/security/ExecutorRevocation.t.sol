// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {SetupHook} from "../SetupHook.t.sol";
import {AsyncSwap} from "@async-swap/AsyncSwap.sol";
import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";
import {AsyncFiller} from "@async-swap/libraries/AsyncFiller.sol";
import {MockERC20} from "../utils/MockERC20.sol";

/// @notice Pins down what revoking the Router does to a maker's live orders, and that filling needs no
///         grant from the filler. A maker that revokes the Router can still cancel through it (the Router
///         cancels only for the owner or with the owner's signature), but its orders cannot be filled through
///         it until it re-grants. The book still matches those orders.
contract ExecutorRevocationTest is SetupHook {
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public override {
        super.setUp();
        topUp(alice, 1_000 ether);
        topUp(bob, 1_000 ether);
    }

    function _order(address maker, bool zeroForOne, uint256 amountIn, uint256 amountOutMin)
        internal
        view
        returns (AsyncOrder memory)
    {
        return AsyncOrder({
            key: key,
            owner: maker,
            zeroForOne: zeroForOne,
            amountIn: amountIn,
            amountOutMin: amountOutMin,
            priorityFee: 100_000,
            sqrtPrice: 2 ** 96,
            salt: keccak256(
                abi.encode(block.timestamp, block.number, address(manager), maker, amountIn, amountOutMin, 100_000)
            )
        });
    }

    function _submit(AsyncOrder memory order) internal {
        MockERC20 input = order.zeroForOne ? token0 : token1;
        vm.startPrank(order.owner);
        input.approve(address(router), order.amountIn);
        token1.approve(address(router), order.amountIn + order.priorityFee);
        router.swap(
            order,
            abi.encode(
                AsyncSwap.UserParams({
                    user: order.owner,
                    executor: address(router),
                    amountOutMin: order.amountOutMin,
                    priorityFee: order.priorityFee
                })
            )
        );
        vm.stopPrank();
    }

    function _id(AsyncOrder memory order) internal view returns (bytes32) {
        return _orderIdFor(order.owner, order.zeroForOne, order.salt);
    }

    function _revoke(address maker) internal {
        vm.prank(maker);
        hook.setExecutor(poolId, address(router), false);
    }

    function test_eoaCancelsThroughRevokedRouter() public {
        AsyncOrder memory ask = _order(alice, true, 1 ether, 1 ether);
        uint256 before = token0.balanceOf(alice);
        _submit(ask);
        _revoke(alice);

        vm.prank(alice);
        router.cancelOrder(ask);
        assertEq(hook.asyncOrder(poolId, _id(ask)), 0, "order cancelled");
        assertEq(token0.balanceOf(alice), before, "input refunded");
    }

    /// The Router still checks ownership: revoking it does not let anyone else cancel.
    function test_RevertWhen_NonOwnerCancelsThroughRevokedRouter() public {
        AsyncOrder memory ask = _order(alice, true, 1 ether, 1 ether);
        _submit(ask);
        _revoke(alice);

        vm.prank(bob);
        vm.expectRevert(bytes("Only owner can cancel"));
        router.cancelOrder(ask);
    }

    /// Another executor the maker revoked still cannot cancel: only the trusted Router needs no grant.
    function test_RevertWhen_RevokedOtherExecutorCancels() public {
        AsyncOrder memory ask = _order(alice, true, 1 ether, 1 ether);
        _submit(ask);
        vm.prank(alice);
        hook.setExecutor(poolId, bob, false);

        vm.prank(bob);
        vm.expectRevert(AsyncFiller.NotAuthorizedExecutor.selector);
        hook.cancelOrder(ask);
    }

    function test_RevertWhen_FillingOrderOfMakerWhoRevokedRouter() public {
        AsyncOrder memory ask = _order(alice, true, 1 ether, 1 ether);
        _submit(ask);
        _revoke(alice);

        vm.prank(bob);
        vm.expectRevert(); // NotAuthorizedExecutor, wrapped by the PoolManager
        router.fillOrder(ask, type(uint256).max, "");
        assertEq(hook.asyncOrder(poolId, _id(ask)), 1 ether, "order untouched");
    }

    /// Matching never checks the resting maker's grant, so a revoked maker's order still trades.
    function test_matchingConsumesOrderOfMakerWhoRevokedRouter() public {
        AsyncOrder memory ask = _order(alice, true, 1 ether, 1 ether);
        _submit(ask);
        _revoke(alice);

        _submit(_order(bob, false, 1 ether, 1 ether));
        assertEq(hook.asyncOrder(poolId, _id(ask)), 0, "ask matched despite the revoked grant");
    }

    function test_regrantRestoresCancel() public {
        AsyncOrder memory ask = _order(alice, true, 1 ether, 1 ether);
        uint256 aliceToken0Before = token0.balanceOf(alice);
        _submit(ask);
        _revoke(alice);

        vm.startPrank(alice);
        hook.setExecutor(poolId, address(router), true);
        router.cancelOrder(ask);
        vm.stopPrank();
        assertEq(hook.asyncOrder(poolId, _id(ask)), 0, "order cancelled");
        assertEq(token0.balanceOf(alice), aliceToken0Before, "input refunded");
    }

    /// Fillers need no grant of their own: the check is on the maker's grant to the Router.
    function test_fillerWithoutAnyGrantCanFill() public {
        AsyncOrder memory ask = _order(alice, true, 1 ether, 1 ether);
        _submit(ask);

        address carol = makeAddr("carol");
        token1.mint(carol, 2 ether);
        assertFalse(hook.isExecutor(poolId, carol, address(router)), "carol never granted anything");

        vm.startPrank(carol);
        token1.approve(address(router), type(uint256).max);
        router.fillOrder(ask, type(uint256).max, "");
        vm.stopPrank();
        assertEq(hook.asyncOrder(poolId, _id(ask)), 0, "carol filled");
        assertGt(token0.balanceOf(carol), 0, "carol received the maker's input");
    }
}
