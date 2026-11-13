// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {FlashFillTest} from "./FlashFill.t.sol";
import {AsyncFiller} from "@async-swap/libraries/AsyncFiller.sol";
import {DutchAuction} from "@async-swap/libraries/DutchAuction.sol";
import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";
import {PoolIdLibrary, PoolKey} from "v4-core/types/PoolKey.sol";

/// @notice Dutch auction orders: the order rests at its floor (the maker's minimum output), and a flash filler pays a
///         premium on top that falls in a straight line to zero. Plain fills wait for it; nothing needs stepping.
contract DutchAuctionTest is FlashFillTest {
    using PoolIdLibrary for PoolKey;

    /// @dev Alice sells 1 ETH for TOKEN with a floor of 90 TOKEN; the auction starts at 100 TOKEN and lasts 100 blocks.
    ///      Bob bids for ETH and Carol asks TOKEN, so a flash filler can route 1 ETH into about 99.98 TOKEN.
    function _auction() internal returns (AsyncOrder memory a, AsyncOrder memory b, AsyncOrder memory c) {
        b = _place(bob, ethUsdc, USDC, 2970 ether, 0.99 ether);
        c = _place(carol, tokenUsdc, TOKEN, 100 ether, 2000 ether);
        a = _place(alice, ethToken, ETH, 1 ether, 90 ether);
        vm.prank(alice);
        hook.startAuction(a, 100 ether, 100);
    }

    function _minOut(AsyncOrder memory order) internal view returns (uint256 amountOutMin) {
        bytes32 id = keccak256(abi.encode(block.chainid, order.key.toId(), order.owner, order.zeroForOne, order.salt));
        (, amountOutMin) = hook.asyncOrderInfo(order.key.toId(), id);
    }

    function test_auction_premiumFallsToZero() public {
        (AsyncOrder memory a,,) = _auction();
        assertEq(hook.auctionPremium(a), 10 ether, "full premium in the start block");
        vm.roll(block.number + 25);
        assertEq(hook.auctionPremium(a), 7.5 ether);
        vm.roll(block.number + 25);
        assertEq(hook.auctionPremium(a), 5 ether);
        vm.roll(block.number + 50);
        assertEq(hook.auctionPremium(a), 0, "none after the duration");
    }

    function test_auction_bookKeepsTheFloor() public {
        (AsyncOrder memory a,,) = _auction();
        assertEq(_minOut(a), 90 ether, "the order rests at the floor from the start");
        vm.roll(block.number + 500);
        assertEq(_minOut(a), 90 ether, "and after the auction, with nothing stepped");
    }

    function test_auction_noAuctionNoPremium() public {
        AsyncOrder memory a = _place(alice, ethToken, ETH, 1 ether, 90 ether);
        assertEq(hook.auctionPremium(a), 0);
    }

    function test_auction_makerRepriceEndsPremium() public {
        (AsyncOrder memory a,,) = _auction();
        vm.prank(alice);
        hook.updatePrice(a, 91 ether);
        assertEq(hook.auctionPremium(a), 0);
    }

    function test_auction_startMakerOnly() public {
        AsyncOrder memory a = _place(alice, ethToken, ETH, 1 ether, 90 ether);
        vm.prank(bob);
        vm.expectRevert(AsyncFiller.NotOrderOwner.selector);
        hook.startAuction(a, 100 ether, 100);
    }

    function test_auction_startChecksBounds() public {
        AsyncOrder memory a = _place(alice, ethToken, ETH, 1 ether, 90 ether);
        vm.startPrank(alice);
        vm.expectRevert(DutchAuction.InvalidAuction.selector);
        hook.startAuction(a, 90 ether, 100); // start not above the floor
        vm.expectRevert(DutchAuction.InvalidAuction.selector);
        hook.startAuction(a, 100 ether, 0);
        vm.expectRevert(DutchAuction.InvalidAuction.selector);
        hook.startAuction(a, 100 ether, DutchAuction.MAX_DURATION + 1);
        vm.stopPrank();
    }

    function test_auction_startNeedsLiveOrder() public {
        AsyncOrder memory a = _place(alice, ethToken, ETH, 1 ether, 90 ether);
        a.salt = keccak256("missing");
        vm.prank(alice);
        vm.expectRevert(AsyncFiller.OrderNotFound.selector);
        hook.startAuction(a, 100 ether, 100);
    }

    /// @notice At the start the books cannot pay floor plus premium (100 TOKEN). Halfway the filler owes 95: the hook
    ///         gets the 90 floor and Alice gets the 5 premium on top, in tokens and with no trade fee on it.
    function test_auction_flashFillPaysFloorPlusPremium() public {
        (AsyncOrder memory a, AsyncOrder memory b, AsyncOrder memory c) = _auction();

        vm.expectRevert();
        filler.run(a, 100 ether, _steps2(_fillStep(b), _fillStep(c)), 0);

        vm.roll(block.number + 50);
        uint256 aliceToken = token.balanceOf(alice);
        filler.run(a, 95 ether, _steps2(_fillStep(b), _fillStep(c)), 0);

        assertEq(
            token.balanceOf(alice) - aliceToken, 90 ether - _fee(90 ether) + 5 ether, "floor less fee, plus premium"
        );
        assertEq(_live(a), 0);
    }

    /// @notice The filler's maxPrice bounds floor plus premium.
    function test_auction_flashFillMaxPriceCoversPremium() public {
        (AsyncOrder memory a, AsyncOrder memory b, AsyncOrder memory c) = _auction();
        vm.roll(block.number + 50); // floor 90 + premium 5
        vm.expectRevert("Price exceeds maxPrice");
        filler.run(a, 94 ether, _steps2(_fillStep(b), _fillStep(c)), 0);
    }

    /// @notice A plain fill cannot skip the premium; once the auction ends it fills at the floor.
    function test_auction_plainFillWaitsForTheAuction() public {
        (AsyncOrder memory a,,) = _auction();
        token.mint(bob, 100 ether);
        vm.prank(bob);
        vm.expectRevert();
        router.fillOrder(a, 90 ether, "");

        vm.roll(block.number + 100);
        uint256 aliceToken = token.balanceOf(alice);
        vm.prank(bob);
        router.fillOrder(a, 90 ether, "");
        assertEq(token.balanceOf(alice) - aliceToken, 90 ether - _fee(90 ether), "floor less fee");
        assertEq(_live(a), 0);
    }

    function testFuzz_auction_premiumWithinRange(uint256 elapsed) public {
        (AsyncOrder memory a,,) = _auction();
        elapsed = bound(elapsed, 0, 200);
        vm.roll(block.number + elapsed);
        uint256 got = hook.auctionPremium(a);
        assertLe(got, 10 ether);
        if (elapsed >= 100) assertEq(got, 0);
        else assertEq(got, 10 ether - (10 ether * elapsed) / 100);
    }
}
