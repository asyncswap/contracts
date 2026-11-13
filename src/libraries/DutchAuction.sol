// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AsyncFiller} from "@async-swap/libraries/AsyncFiller.sol";
import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";
import {PoolIdLibrary, PoolKey} from "v4-core/types/PoolKey.sol";

/// @title DutchAuction
/// @author @msakiart
/// @notice Linked module for Dutch auction orders. The maker of a resting order sets a floor and a duration in blocks,
///         and the order's minimum output then falls in a straight line from its price at start to the floor. Anyone
///         may call `step` to write the scheduled minimum into the order, by the same reprice path a maker uses, so
///         the book always holds a real price. The Router steps the order before every filler fill.
/// @dev Between steps the stored minimum is at or above the schedule, so the maker never receives less than the
///      schedule gives. A maker reprice stops the auction: `step` sees a reprice count it did not write.
///      Public library calls use DELEGATECALL, so the auctions and books stay in the hook.
library DutchAuction {
    using AsyncFiller for AsyncFiller.State;
    using PoolIdLibrary for PoolKey;

    /// @notice Longest auction, in blocks.
    uint32 internal constant MAX_DURATION = 50_000;

    struct Auction {
        uint256 startAmountOutMin;
        uint256 floorAmountOutMin;
        uint64 startBlock;
        uint32 duration;
        /// @dev The order's reprice count after the last write by this auction.
        uint32 reprices;
    }

    event AuctionStarted(
        bytes32 indexed orderId, uint256 startAmountOutMin, uint256 floorAmountOutMin, uint64 startBlock, uint32 duration
    );

    error InvalidAuction();

    /// @notice Start an auction on a resting order. Maker only. The order's current minimum is the start price.
    function start(
        AsyncFiller.State storage self,
        AsyncFiller.Book storage book,
        mapping(bytes32 => Auction) storage auctions,
        AsyncOrder calldata order,
        bytes32 id,
        uint256 floorAmountOutMin,
        uint32 duration,
        address caller
    ) public {
        if (caller != order.owner) revert AsyncFiller.NotOrderOwner();
        AsyncFiller.OrderInfo storage info = self.orders[id];
        if (info.amountIn == 0) revert AsyncFiller.OrderNotFound();
        if (
            duration == 0 || duration > MAX_DURATION || floorAmountOutMin == 0
                || floorAmountOutMin >= info.amountOutMin
        ) revert InvalidAuction();
        AsyncFiller.checkMinimum(book, info.isBuy, info.amountIn, floorAmountOutMin);
        auctions[id] = Auction({
            startAmountOutMin: info.amountOutMin,
            floorAmountOutMin: floorAmountOutMin,
            startBlock: uint64(block.number),
            duration: duration,
            reprices: info.reprices
        });
        emit AuctionStarted(id, info.amountOutMin, floorAmountOutMin, uint64(block.number), duration);
    }

    /// @notice Write the scheduled minimum into the order when it is below the stored one. Anyone may call it.
    ///         Does nothing for an order with no running auction. Returns the order's minimum output after the step.
    function step(
        AsyncFiller.State storage self,
        AsyncFiller.Book storage book,
        mapping(bytes32 => Auction) storage auctions,
        AsyncOrder calldata order,
        bytes32 id
    ) public returns (uint256) {
        Auction storage auction = auctions[id];
        AsyncFiller.OrderInfo storage info = self.orders[id];
        uint256 stored = info.amountOutMin;
        if (auction.duration == 0) return stored;
        if (info.amountIn == 0 || info.reprices != auction.reprices) {
            delete auctions[id];
            return stored;
        }
        uint256 scheduled = amountOutMinAt(auction, block.number);
        if (scheduled < stored) {
            self.updatePrice(book, order, id, scheduled, order.owner);
            auction.reprices = info.reprices;
        }
        if (block.number >= auction.startBlock + auction.duration) delete auctions[id];
        return info.amountOutMin;
    }

    /// @notice The scheduled minimum output at `blockNumber`, rounded up for the maker.
    function amountOutMinAt(Auction memory auction, uint256 blockNumber) internal pure returns (uint256) {
        uint256 elapsed = blockNumber - auction.startBlock;
        if (elapsed >= auction.duration) return auction.floorAmountOutMin;
        uint256 drop = (auction.startAmountOutMin - auction.floorAmountOutMin) * elapsed / auction.duration;
        return auction.startAmountOutMin - drop;
    }
}
