// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AsyncFiller} from "@async-swap/libraries/AsyncFiller.sol";
import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";

/// @title DutchAuction
/// @author @msakiart
/// @notice Linked module for Dutch auction orders. The order rests in the book at the maker's minimum output (the
///         floor) the whole time. An auction adds a premium on top that only flash fillers pay: it starts at
///         `startAmountOutMin - floor` and falls in a straight line to zero over `duration` blocks. After that the order
///         is a plain good-till-cancelled order at the floor, with nothing to step and no keeper.
/// @dev Book matches and pool fills during an auction pay the floor, the maker's own limit. Plain filler fills are
///      refused while a premium is live (`requireNoPremium`), so a filler cannot skip it. A maker reprice or a partial
///      match ends the premium: `premium` sees a reprice count or a minimum it did not record.
///      Public library calls use DELEGATECALL, so the auctions stay in the hook.
library DutchAuction {
    /// @notice Longest auction, in blocks.
    uint32 internal constant MAX_DURATION = 50_000;

    struct Auction {
        uint256 startAmountOutMin;
        /// @dev The order's minimum output when the auction started. The premium is measured above it.
        uint256 floorAmountOutMin;
        uint64 startBlock;
        uint32 duration;
        /// @dev The order's reprice count when the auction started.
        uint32 reprices;
    }

    event AuctionStarted(
        bytes32 indexed orderId,
        uint256 startAmountOutMin,
        uint256 floorAmountOutMin,
        uint64 startBlock,
        uint32 duration
    );

    error InvalidAuction();
    /// @notice A plain fill was tried while the order's auction premium is live. Fill it with a flash fill, which pays
    ///         the premium, or after the auction.
    error AuctionRunning(uint256 premium);

    /// @notice Start an auction on a resting order. Maker only. The order's current minimum output is the floor, and
    ///         `startAmountOutMin` (above it) is what a flash filler pays at the start block.
    function start(
        AsyncFiller.State storage self,
        mapping(bytes32 => Auction) storage auctions,
        AsyncOrder calldata order,
        bytes32 id,
        uint256 startAmountOutMin,
        uint32 duration,
        address caller
    ) public {
        if (caller != order.owner) revert AsyncFiller.NotOrderOwner();
        AsyncFiller.OrderInfo storage info = self.orders[id];
        if (info.amountIn == 0) revert AsyncFiller.OrderNotFound();
        uint256 floor = info.amountOutMin;
        if (duration == 0 || duration > MAX_DURATION || startAmountOutMin <= floor) revert InvalidAuction();
        auctions[id] = Auction({
            startAmountOutMin: startAmountOutMin,
            floorAmountOutMin: floor,
            startBlock: uint64(block.number),
            duration: duration,
            reprices: info.reprices
        });
        emit AuctionStarted(id, startAmountOutMin, floor, uint64(block.number), duration);
    }

    /// @notice The auction premium a flash filler pays on top of the order's minimum output now. Zero for an order with
    ///         no auction, after the duration, or once the maker repriced or the order was partly matched.
    function premium(AsyncFiller.State storage self, mapping(bytes32 => Auction) storage auctions, bytes32 id)
        public
        view
        returns (uint256)
    {
        Auction storage auction = auctions[id];
        uint256 duration = auction.duration;
        if (duration == 0) return 0;
        uint256 elapsed = block.number - auction.startBlock;
        if (elapsed >= duration) return 0;
        AsyncFiller.OrderInfo storage info = self.orders[id];
        uint256 floor = auction.floorAmountOutMin;
        if (info.amountIn == 0 || info.reprices != auction.reprices || info.amountOutMin != floor) return 0;
        uint256 range = auction.startAmountOutMin - floor;
        // The schedule rounds in the maker's favour: the premium falls by whole steps, rounded down.
        return range - range * elapsed / duration;
    }

    /// @notice Revert while the order's premium is live, so plain fills cannot skip it.
    function requireNoPremium(AsyncFiller.State storage self, mapping(bytes32 => Auction) storage auctions, bytes32 id)
        public
        view
    {
        uint256 live = premium(self, auctions, id);
        if (live != 0) revert AuctionRunning(live);
    }
}
