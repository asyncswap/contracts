// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {SetupHook} from "../SetupHook.t.sol";
import {AsyncSwap} from "@async-swap/AsyncSwap.sol";
import {AsyncFiller} from "@async-swap/libraries/AsyncFiller.sol";
import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";
import {MockERC20} from "../utils/MockERC20.sol";

/// @notice Pins down what revoking the Router does to a maker's live orders, and that filling needs no
///         grant from the filler. An EOA maker that revokes the Router can neither cancel nor have its
///         orders filled until it re-grants, yet the book still matches those orders.
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

    function test_RevertWhen_EoaCancelsThroughRevokedRouter() public {
        AsyncOrder memory ask = _order(alice, true, 1 ether, 1 ether);
        _submit(ask);
        _revoke(alice);

        vm.prank(alice);
        vm.expectRevert(); // NotAuthorizedExecutor, wrapped by the PoolManager
        router.cancelOrder(ask);
        assertEq(hook.asyncOrder(poolId, _id(ask)), 1 ether, "input stays escrowed");
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

    /// The owner raising a pool's minimum blocks reprices of orders that were valid when placed.
    function test_RevertWhen_OwnerRaisesMinimumAboveLiveOrder() public {
        AsyncOrder memory ask = _order(alice, true, 5 ether, 5 ether);
        _submit(ask);

        hook.setMinOrder(key, 10 ether);
        vm.prank(alice);
        vm.expectRevert(AsyncFiller.BelowMinimumOrder.selector);
        hook.updatePrice(ask, 6 ether);
    }
}
