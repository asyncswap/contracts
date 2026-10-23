// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {SetupHook} from "../SetupHook.t.sol";
import {AsyncSwap} from "@async-swap/AsyncSwap.sol";
import {AsyncFiller} from "@async-swap/libraries/AsyncFiller.sol";
import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";
import {MockERC20} from "../utils/MockERC20.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {PoolIdLibrary, PoolKey} from "v4-core/types/PoolKey.sol";

/// @notice Every order is worth at least the pool's minimum, in numeraire (token1) base units: a buy's
///         input, a sell's minimum output, and a sell's input at the pool's current price. A partial
///         match that leaves less than the minimum refunds the remainder. In PriorityFee mode the
///         least bid is min($0.10, 0.1% of the order).
contract MinimumOrderTest is SetupHook {
    using PoolIdLibrary for PoolKey;

    uint256 constant MIN = 10 ether; // "$10" for this 18-decimal numeraire

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public override {
        super.setUp();
        topUp(alice, 1_000 ether);
        topUp(bob, 1_000 ether);
    }

    function _order(address maker, bool zeroForOne, uint256 amountIn, uint256 amountOutMin, uint256 fee)
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
            priorityFee: fee,
            sqrtPrice: 2 ** 96,
            salt: keccak256(
                abi.encode(block.timestamp, block.number, address(manager), maker, amountIn, amountOutMin, fee)
            )
        });
    }

    /// @dev Asks sell token0 (zeroForOne); bids spend token1, the numeraire.
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

    /* ------------------------------------------------------------------ admission */

    function test_RevertWhen_BuyBelowMinimum() public {
        hook.setMinOrder(key, MIN);
        AsyncOrder memory bid = _order(bob, false, MIN - 1, MIN, 100_000);
        vm.expectRevert(); // the hook's revert is wrapped by the PoolManager
        this.submitExternal(bid);
    }

    function test_buyAtMinimum_rests() public {
        hook.setMinOrder(key, MIN);
        AsyncOrder memory bid = _order(bob, false, MIN, MIN, 100_000);
        _submit(bid);
        assertEq(hook.asyncOrder(poolId, _id(bid)), MIN);
    }

    function test_RevertWhen_SellAsksBelowMinimum() public {
        hook.setMinOrder(key, MIN);
        AsyncOrder memory ask = _order(alice, true, 100 ether, MIN - 1, 100_000);
        vm.expectRevert();
        this.submitExternal(ask);
    }

    /// A sell asking for plenty but offering almost nothing, at the pool's 1:1 price, is below the minimum.
    function test_RevertWhen_SellInputWorthLessThanMinimum() public {
        hook.setMinOrder(key, MIN);
        AsyncOrder memory ask = _order(alice, true, 1, 100 ether, 100_000);
        vm.expectRevert();
        this.submitExternal(ask);
    }

    function test_sellAtMinimum_rests() public {
        hook.setMinOrder(key, MIN);
        AsyncOrder memory ask = _order(alice, true, MIN, MIN, 100_000);
        _submit(ask);
        assertEq(hook.asyncOrder(poolId, _id(ask)), MIN);
    }

    function test_RevertWhen_UpdatePriceBelowMinimum() public {
        hook.setMinOrder(key, MIN);
        AsyncOrder memory ask = _order(alice, true, 20 ether, 20 ether, 100_000);
        _submit(ask);
        vm.prank(alice);
        vm.expectRevert(AsyncFiller.BelowMinimumOrder.selector);
        hook.updatePrice(ask, MIN - 1);
    }

    /* ------------------------------------------------------------------ remainders */

    /// The ask is matched down to 5, below the minimum of 10: the order closes and the 5 return to alice.
    function test_partialMatchRemainderBelowMinimum_refunded() public {
        hook.setMinOrder(key, MIN);
        AsyncOrder memory ask = _order(alice, true, 15 ether, 15 ether, 100_000);
        uint256 aliceToken0Before = token0.balanceOf(alice);
        _submit(ask);
        _submit(_order(bob, false, MIN, MIN, 100_000));

        assertEq(hook.asyncOrder(poolId, _id(ask)), 0, "remainder below the minimum closes the order");
        assertEq(token0.balanceOf(alice), aliceToken0Before - 15 ether, "the full input was escrowed");
        assertEq(manager.balanceOf(alice, currency0.toId()), 5 ether, "the unmatched 5 are refunded as claims");
    }

    /* ------------------------------------------------------------------ configuration */

    function test_newPoolsTakeTheDefaultMinimum() public {
        hook.setDefaultMinOrder(MIN);
        PoolKey memory key2 = PoolKey({
            currency0: currency0, currency1: currency1, fee: LPFeeLibrary.DYNAMIC_FEE_FLAG, tickSpacing: 2, hooks: hook
        });
        manager.initialize(key2, 2 ** 96);
        vm.prank(bob);
        hook.setExecutor(key2.toId(), address(router), true);

        AsyncOrder memory bid = _order(bob, false, MIN - 1, MIN, 100_000);
        bid.key = key2;
        vm.expectRevert();
        this.submitExternal(bid);
    }

    function test_RevertWhen_NonOwnerSetsMinimum() public {
        vm.startPrank(alice);
        vm.expectRevert(AsyncSwap.NotOwner.selector);
        hook.setMinOrder(key, MIN);
        vm.expectRevert(AsyncSwap.NotOwner.selector);
        hook.setDefaultMinOrder(MIN);
        vm.stopPrank();
    }

    /* ------------------------------------------------------------------ tiered bid */

    /// A $50 order (6-decimal amounts) needs a bid of 0.1%, $0.05, not the full $0.10.
    function test_priorityFee_smallOrderPaysTenBps() public {
        AsyncOrder memory bid = _order(bob, false, 50e6, 50e6, 50_000);
        _submit(bid);
        assertEq(hook.asyncOrder(poolId, _id(bid)), 50e6);
    }

    function test_RevertWhen_priorityFee_smallOrderBelowTenBps() public {
        AsyncOrder memory bid = _order(bob, false, 50e6, 50e6, 49_999);
        vm.expectRevert();
        this.submitExternal(bid);
    }

    /// @dev External hop so `vm.expectRevert` sees the Router call as one call.
    function submitExternal(AsyncOrder memory order) external {
        _submit(order);
    }
}
