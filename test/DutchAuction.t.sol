// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {FlashFillTest} from "./FlashFill.t.sol";
import {AsyncFiller} from "@async-swap/libraries/AsyncFiller.sol";
import {DutchAuction} from "@async-swap/libraries/DutchAuction.sol";
import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";
import {PoolIdLibrary, PoolKey} from "v4-core/types/PoolKey.sol";

/// @notice Dutch auction orders: the minimum output falls in a straight line from start to floor, `stepAuction` writes
///         it into the book, and a flash fill steps the order first so the filler pays the scheduled price.
contract DutchAuctionTest is FlashFillTest {
    using PoolIdLibrary for PoolKey;

    /// @dev Alice sells 1 ETH for TOKEN: 100 TOKEN at start, 90 TOKEN after 100 blocks.
    function _auction() internal returns (AsyncOrder memory a, AsyncOrder memory b, AsyncOrder memory c) {
        b = _place(bob, ethUsdc, USDC, 2970 ether, 0.99 ether);
        c = _place(carol, tokenUsdc, TOKEN, 100 ether, 2000 ether);
        a = _place(alice, ethToken, ETH, 1 ether, 100 ether);
        vm.prank(alice);
        hook.startAuction(a, 90 ether, 100);
    }

    function _minOut(AsyncOrder memory order) internal view returns (uint256 amountOutMin) {
        bytes32 id = keccak256(abi.encode(block.chainid, order.key.toId(), order.owner, order.zeroForOne, order.salt));
        (, amountOutMin) = hook.asyncOrderInfo(order.key.toId(), id);
    }

    function _bookMinOut(AsyncOrder memory order) internal view returns (uint256 amountOutMin) {
        bytes32 id = keccak256(abi.encode(block.chainid, order.key.toId(), order.owner, order.zeroForOne, order.salt));
        (,, amountOutMin,,,,) = hook.orderBookOrder(order.key.toId(), id);
    }

    function test_auction_stepFollowsSchedule() public {
        (AsyncOrder memory a,,) = _auction();
        assertEq(hook.stepAuction(a), 100 ether, "no drop in the start block");

        vm.roll(block.number + 25);
        assertEq(hook.stepAuction(a), 97.5 ether);
        assertEq(_bookMinOut(a), 97.5 ether, "book holds the stepped price");

        vm.roll(block.number + 25);
        assertEq(hook.stepAuction(a), 95 ether);
        assertEq(_minOut(a), 95 ether);
    }

    function test_auction_endsAtFloor() public {
        (AsyncOrder memory a,,) = _auction();
        vm.roll(block.number + 500);
        assertEq(hook.stepAuction(a), 90 ether);
        // The auction is finished: the order now rests as a plain limit order at the floor.
        vm.prank(alice);
        hook.updatePrice(a, 92 ether);
        assertEq(hook.stepAuction(a), 92 ether);
    }

    function test_auction_stepIsPermissionless() public {
        (AsyncOrder memory a,,) = _auction();
        vm.roll(block.number + 50);
        vm.prank(makeAddr("anyone"));
        assertEq(hook.stepAuction(a), 95 ether);
    }

    function test_auction_stepWithoutAuctionDoesNothing() public {
        AsyncOrder memory a = _place(alice, ethToken, ETH, 1 ether, 100 ether);
        vm.roll(block.number + 50);
        vm.recordLogs();
        assertEq(hook.stepAuction(a), 100 ether);
        assertEq(vm.getRecordedLogs().length, 0, "no reprice");
    }

    function test_auction_makerRepriceStopsIt() public {
        (AsyncOrder memory a,,) = _auction();
        vm.roll(block.number + 10);
        vm.prank(alice);
        hook.updatePrice(a, 99.5 ether);
        vm.roll(block.number + 50);
        assertEq(hook.stepAuction(a), 99.5 ether, "maker's price stands");
    }

    function test_auction_startMakerOnly() public {
        AsyncOrder memory a = _place(alice, ethToken, ETH, 1 ether, 100 ether);
        vm.prank(bob);
        vm.expectRevert(AsyncFiller.NotOrderOwner.selector);
        hook.startAuction(a, 90 ether, 100);
    }

    function test_auction_startChecksBounds() public {
        AsyncOrder memory a = _place(alice, ethToken, ETH, 1 ether, 100 ether);
        vm.startPrank(alice);
        vm.expectRevert(DutchAuction.InvalidAuction.selector);
        hook.startAuction(a, 100 ether, 100); // floor not below the start
        vm.expectRevert(DutchAuction.InvalidAuction.selector);
        hook.startAuction(a, 0, 100);
        vm.expectRevert(DutchAuction.InvalidAuction.selector);
        hook.startAuction(a, 90 ether, 0);
        vm.expectRevert(DutchAuction.InvalidAuction.selector);
        hook.startAuction(a, 90 ether, DutchAuction.MAX_DURATION + 1);
        vm.stopPrank();
    }

    function test_auction_startNeedsLiveOrder() public {
        AsyncOrder memory a = _place(alice, ethToken, ETH, 1 ether, 100 ether);
        a.salt = keccak256("missing");
        vm.prank(alice);
        vm.expectRevert(AsyncFiller.OrderNotFound.selector);
        hook.startAuction(a, 90 ether, 100);
    }

    /// @notice At start nobody can pay 100 TOKEN through the books. Halfway the schedule asks 95, and a flash fill
    ///         steps the order itself, so the filler fills at 95 with no separate step call.
    function test_auction_flashFillPaysScheduledPrice() public {
        (AsyncOrder memory a, AsyncOrder memory b, AsyncOrder memory c) = _auction();

        vm.expectRevert();
        filler.run(a, 95 ether, _steps2(_fillStep(b), _fillStep(c)), 0);

        vm.roll(block.number + 50);
        uint256 aliceToken = token.balanceOf(alice);
        filler.run(a, 95 ether, _steps2(_fillStep(b), _fillStep(c)), 0);

        assertEq(token.balanceOf(alice) - aliceToken, 95 ether - _fee(95 ether), "alice paid the schedule");
        assertEq(_live(a), 0);
    }

    /// @notice The filler's maxPrice still binds: the schedule is above it, so the fill reverts.
    function test_auction_flashFillRespectsMaxPrice() public {
        (AsyncOrder memory a, AsyncOrder memory b, AsyncOrder memory c) = _auction();
        vm.roll(block.number + 20); // schedule: 98
        vm.expectRevert("Price exceeds maxPrice");
        filler.run(a, 95 ether, _steps2(_fillStep(b), _fillStep(c)), 0);
    }

    function testFuzz_auction_scheduleBetweenFloorAndStart(uint256 elapsed) public {
        (AsyncOrder memory a,,) = _auction();
        elapsed = bound(elapsed, 0, 200);
        vm.roll(block.number + elapsed);
        uint256 got = hook.stepAuction(a);
        assertLe(got, 100 ether);
        assertGe(got, 90 ether);
        if (elapsed >= 100) assertEq(got, 90 ether);
        else assertEq(got, 100 ether - (10 ether * elapsed) / 100);
    }
}
