// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AsyncFiller} from "@async-swap/libraries/AsyncFiller.sol";
import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";
import {CurrencySettler} from "@async-swap/libraries/CurrencySettler.sol";
import {IPoolManager, SwapParams} from "v4-core/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {PoolIdLibrary, PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/types/BalanceDelta.sol";
import {SafeCast} from "v4-core/libraries/SafeCast.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {RadixPriceTree} from "@async-swap/libraries/RadixPriceTree.sol";
import {EligiblePrice} from "@async-swap/libraries/EligiblePrice.sol";

/// @notice Linked matching module operating on the hook's order and radix-book storage.
/// @dev Public library calls use DELEGATECALL, so ERC-6909 escrow remains owned by Async Swap.
library AsyncMatching {
    using CurrencySettler for Currency;
    using AsyncFiller for AsyncFiller.Book;
    using AsyncFiller for AsyncFiller.State;
    using PoolIdLibrary for PoolKey;
    using RadixPriceTree for RadixPriceTree.Tree;
    using BalanceDeltaLibrary for BalanceDelta;
    using SafeCast for *;
    using StateLibrary for IPoolManager;

    uint256 private constant PRICE_SCALE = 1e18;
    uint8 public constant MAX_MATCHES_PER_CALL = 8;

    struct ReductionParams {
        bytes32 id;
        uint256 inputUsed;
        uint256 outputReceived;
    }

    /// @dev Who receives each leg of a match, read before the matched orders are reduced.
    struct Payouts {
        address sellOwner;
        address buyOwner;
        Currency sellInput;
        Currency buyInput;
        uint256 sellRefund; // input returned to an order left below the pool minimum
        uint256 buyRefund;
    }

    struct FillParams {
        AsyncOrder order;
        bytes32 id;
        address hook;
        address executor;
        address filler;
        address feeVault;
        uint256 fee;
    }

    struct CancelParams {
        AsyncOrder order;
        bytes32 id;
        address hook;
        address executor;
    }

    struct UpdateParams {
        AsyncOrder order;
        bytes32 id;
        uint256 newAmountOutMin;
        address caller;
    }

    event AsyncOrdersMatched(
        PoolId indexed poolId,
        bytes32 indexed sellOrderId,
        bytes32 indexed buyOrderId,
        uint256 assetAmount,
        uint256 numeraireAmount
    );

    error InvalidMatchBound();
    error PartialLiquidityFill();
    error LimitPriceNotMet();
    error NoActiveLiquidity();

    uint24 private constant POOL_LIQUIDITY_FILL_FEE = 3_000;

    event AsyncOrderLiquidityFilled(
        PoolId indexed poolId, bytes32 indexed orderId, address indexed maker, uint256 amountIn, uint256 amountOut
    );

    function addOrder(AsyncFiller.State storage self, AsyncFiller.Book storage book, AsyncFiller.NewOrder memory order)
        public
    {
        self.checkMinimum(book, order.poolId, order.isBuy, order.zeroForOne, order.amountIn, order.amountOutMin);
        self.addOrder(
            book,
            order.id,
            order.owner,
            order.amountIn,
            order.amountOutMin,
            order.isBuy,
            order.zeroForOne,
            order.priorityFee
        );
    }

    function setMinOrder(AsyncFiller.Book storage book, PoolId poolId, uint256 minimum) public {
        book.setMinOrder(poolId, minimum);
    }

    function bestOrder(AsyncFiller.State storage self, AsyncFiller.Book storage book, bool isBuy)
        public
        view
        returns (bool found, uint128 price, bytes32 orderId, address owner)
    {
        return self.bestOrder(book, isBuy);
    }

    function level(AsyncFiller.Book storage book, bool isBuy, uint128 price)
        public
        view
        returns (bytes32 head, bytes32 tail, uint32 orderCount)
    {
        return book.level(isBuy, price);
    }

    function fill(AsyncFiller.State storage self, AsyncFiller.Book storage book, FillParams memory params) public {
        self.fill(
            book, params.order, params.id, params.hook, params.executor, params.filler, params.feeVault, params.fee
        );
    }

    function cancel(AsyncFiller.State storage self, AsyncFiller.Book storage book, CancelParams memory params) public {
        self.cancel(book, params.order, params.id, params.hook, params.executor);
    }

    function updatePrice(AsyncFiller.State storage self, AsyncFiller.Book storage book, UpdateParams memory params)
        public
    {
        self.updatePrice(book, params.order, params.id, params.newAmountOutMin, params.caller);
    }

    function matchIncoming(
        AsyncFiller.State storage self,
        AsyncFiller.Book storage book,
        PoolKey calldata key,
        bytes32 incomingId,
        address hook
    ) public returns (uint8 matched) {
        if (self.orders[incomingId].amountIn == 0) revert AsyncFiller.OrderNotFound();
        // Admission has already inserted and funded the order. Use the same book-wide
        // priority rule for arrivals and backlog, sharing one bounded match budget.
        return matchBook(self, book, key, MAX_MATCHES_PER_CALL, hook);
    }

    function matchBook(
        AsyncFiller.State storage self,
        AsyncFiller.Book storage book,
        PoolKey calldata key,
        uint8 maxMatches,
        address hook
    ) public returns (uint8 matched) {
        if (maxMatches == 0 || maxMatches > MAX_MATCHES_PER_CALL) revert InvalidMatchBound();
        while (matched < maxMatches) {
            (bytes32 bidId, bytes32 askId) = _bookPair(self, book);
            if (bidId == bytes32(0)) break;
            if (!_matchPair(self, book, key, bidId, askId, hook)) break;
            unchecked {
                ++matched;
            }
        }
    }

    function _bookPair(AsyncFiller.State storage self, AsyncFiller.Book storage book)
        private
        view
        returns (bytes32 bidId, bytes32 askId)
    {
        (bool hasBid, uint128 bidPrice) = book.bids.best(true);
        (bool hasAsk, uint128 askPrice) = book.asks.best(false);
        if (!hasBid || !hasAsk || bidPrice < askPrice) return (bytes32(0), bytes32(0));
        bidId = book.bestAtPrice(true, bidPrice);
        askId = book.bestAtPrice(false, askPrice);
        if (_crosses(bidPrice, askPrice, self.orders[bidId], self.orders[askId])) return (bidId, askId);
        // The only ambiguous boundary is a shared bucket. Maximize buy priority among
        // buys crossing any ask, then sell priority conditional on that selected buy.
        EligiblePrice.Ratio memory cheapestAsk = book.mostPermissiveAtPrice(false, askPrice);
        // The head bid is already the highest priority. If it crosses any ask,
        // retain it rather than traversing its priority tree a second time.
        if (!EligiblePrice.le(cheapestAsk, AsyncFiller.exactPrice(self.orders[bidId]))) {
            bidId = book.eligibleAtPrice(true, bidPrice, cheapestAsk);
            if (bidId == bytes32(0)) return (bytes32(0), bytes32(0));
        }
        askId = book.eligibleAtPrice(false, askPrice, AsyncFiller.exactPrice(self.orders[bidId]));
        // A feasible bid has an eligible ask by the summary invariant. The
        // match-pair guard also rejects an empty record before any settlement.
    }

    /// @notice Execute an order against active v4 LP positions if they meet the signed minimum.
    /// @dev Reverts atomically on insufficient liquidity/output or partial execution. The caller
    ///      catches this across a self-call so the resting order is preserved.
    function fillFromPoolLiquidity(
        AsyncFiller.State storage self,
        AsyncFiller.Book storage book,
        PoolKey calldata key,
        bytes32 id,
        address maker,
        address hook
    ) public {
        AsyncFiller.OrderInfo storage info = self.orders[id];
        uint256 amountIn = info.amountIn;
        uint256 amountOutMin = info.amountOutMin;
        if (amountIn == 0) revert AsyncFiller.OrderNotFound();
        bool zeroForOne = info.zeroForOne;
        uint256 priorityFee = info.priorityFee;
        // Close the order before the maker's payout, which can run recipient code.
        AsyncFiller._remove(self, book, id);
        delete self.orders[id];
        uint256 amountOut = _swapAgainstPool(self.poolManager, key, zeroForOne, amountIn, amountOutMin, hook);
        Currency output = zeroForOne ? key.currency1 : key.currency0;
        output.take(self.poolManager, maker, amountOut, output.isAddressZero());
        AsyncFiller.settlePriorityFee(self, key, id, maker, priorityFee, hook);
        emit AsyncOrderLiquidityFilled(key.toId(), id, maker, amountIn, amountOut);
    }

    function _swapAgainstPool(
        IPoolManager manager,
        PoolKey calldata key,
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOutMin,
        address hook
    ) private returns (uint256 amountOut) {
        if (manager.getLiquidity(key.toId()) == 0) revert NoActiveLiquidity();
        Currency input = zeroForOne ? key.currency0 : key.currency1;
        input.settle(manager, hook, amountIn, true);
        (,,, uint24 previousFee) = manager.getSlot0(key.toId());
        manager.updateDynamicLPFee(key, POOL_LIQUIDITY_FILL_FEE);
        BalanceDelta delta = manager.swap(
            key,
            SwapParams(
                zeroForOne, -amountIn.toInt256(), zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            ),
            ""
        );
        manager.updateDynamicLPFee(key, previousFee);
        int128 inputDelta = zeroForOne ? delta.amount0() : delta.amount1();
        int128 outputDelta = zeroForOne ? delta.amount1() : delta.amount0();
        if (inputDelta != -amountIn.toInt128()) revert PartialLiquidityFill();
        if (outputDelta <= 0 || uint256(uint128(outputDelta)) < amountOutMin) revert LimitPriceNotMet();
        return uint256(uint128(outputDelta));
    }

    /// @dev `buyId` comes from the bid tree and `sellId` from the ask tree (`_bookPair`), so their
    ///      sides are fixed by construction.
    function _matchPair(
        AsyncFiller.State storage self,
        AsyncFiller.Book storage book,
        PoolKey calldata key,
        bytes32 buyId,
        bytes32 sellId,
        address hook
    ) private returns (bool) {
        AsyncFiller.OrderInfo storage buy = self.orders[buyId];
        AsyncFiller.OrderInfo storage sell = self.orders[sellId];
        if (buy.amountIn == 0 || sell.amountIn == 0) return false;
        // The older order is the maker and sets the price.
        bool makerBuy = buy.createdSequence < sell.createdSequence;
        AsyncFiller.MatchAmounts memory amounts = _matchAmounts(sell, buy, makerBuy);
        if (amounts.assetAmount == 0 || amounts.quoteAmount == 0) return false;

        // Read who is paid, then reduce both orders before any payout: an ERC20 transfer can run
        // recipient code, which must find both records already settled.
        Payouts memory payouts = _payouts(self, key, buyId, sellId);
        (payouts.sellRefund, payouts.buyRefund) = _reduceMatchedOrders(self, book, key, buyId, sellId, amounts, hook);
        _settleTransfers(self.poolManager, payouts, amounts, hook);
        emit AsyncOrdersMatched(key.toId(), sellId, buyId, amounts.assetAmount, amounts.quoteAmount);
        return true;
    }

    function _matchAmounts(AsyncFiller.OrderInfo storage sell, AsyncFiller.OrderInfo storage buy, bool restingBuy)
        private
        view
        returns (AsyncFiller.MatchAmounts memory amounts)
    {
        if (restingBuy) {
            amounts.quoteAmount = Math.mulDiv(sell.amountIn, buy.amountIn, buy.amountOutMin);
            if (amounts.quoteAmount > buy.amountIn) amounts.quoteAmount = buy.amountIn;
            if (amounts.quoteAmount == 0) return amounts;
            amounts.assetAmount = Math.mulDiv(amounts.quoteAmount, buy.amountOutMin, buy.amountIn, Math.Rounding.Ceil);
            if (amounts.assetAmount > sell.amountIn) return AsyncFiller.MatchAmounts(0, 0);
            uint256 sellerMinimum =
                Math.mulDiv(amounts.assetAmount, sell.amountOutMin, sell.amountIn, Math.Rounding.Ceil);
            if (amounts.quoteAmount < sellerMinimum) return AsyncFiller.MatchAmounts(0, 0);
        } else {
            amounts.assetAmount = Math.mulDiv(buy.amountIn, sell.amountIn, sell.amountOutMin);
            if (amounts.assetAmount > sell.amountIn) amounts.assetAmount = sell.amountIn;
            if (amounts.assetAmount == 0) return amounts;
            amounts.quoteAmount = Math.mulDiv(amounts.assetAmount, sell.amountOutMin, sell.amountIn, Math.Rounding.Ceil);
            if (amounts.quoteAmount > buy.amountIn) return AsyncFiller.MatchAmounts(0, 0);
            uint256 buyerMinimum = Math.mulDiv(amounts.quoteAmount, buy.amountOutMin, buy.amountIn, Math.Rounding.Ceil);
            if (amounts.assetAmount < buyerMinimum) return AsyncFiller.MatchAmounts(0, 0);
        }
    }

    function _payouts(AsyncFiller.State storage self, PoolKey calldata key, bytes32 buyId, bytes32 sellId)
        private
        view
        returns (Payouts memory payouts)
    {
        AsyncFiller.OrderInfo storage buy = self.orders[buyId];
        AsyncFiller.OrderInfo storage sell = self.orders[sellId];
        payouts.sellInput = sell.zeroForOne ? key.currency0 : key.currency1;
        payouts.buyInput = buy.zeroForOne ? key.currency0 : key.currency1;
        payouts.sellOwner = sell.owner;
        payouts.buyOwner = buy.owner;
    }

    function _settleTransfers(
        IPoolManager manager,
        Payouts memory payouts,
        AsyncFiller.MatchAmounts memory amounts,
        address hook
    ) private {
        _transferEscrow(manager, payouts.sellInput, payouts.buyOwner, amounts.assetAmount, hook);
        _transferEscrow(manager, payouts.buyInput, payouts.sellOwner, amounts.quoteAmount, hook);
        if (payouts.sellRefund != 0) {
            _transferEscrow(manager, payouts.sellInput, payouts.sellOwner, payouts.sellRefund, hook);
        }
        if (payouts.buyRefund != 0) {
            _transferEscrow(manager, payouts.buyInput, payouts.buyOwner, payouts.buyRefund, hook);
        }
    }

    function _reduceMatchedOrders(
        AsyncFiller.State storage self,
        AsyncFiller.Book storage book,
        PoolKey calldata key,
        bytes32 buyId,
        bytes32 sellId,
        AsyncFiller.MatchAmounts memory amounts,
        address hook
    ) private returns (uint256 sellRefund, uint256 buyRefund) {
        sellRefund = _reduceAfterMatch(
            self, book, key, ReductionParams(sellId, amounts.assetAmount, amounts.quoteAmount), hook
        );
        buyRefund =
            _reduceAfterMatch(self, book, key, ReductionParams(buyId, amounts.quoteAmount, amounts.assetAmount), hook);
    }

    function _transferEscrow(IPoolManager manager, Currency currency, address recipient, uint256 amount, address hook)
        private
    {
        currency.settle(manager, hook, amount, true);
        // Matching and dust refunds credit claims in every currency. Redemption is
        // separate, so a token rejection cannot stall other orders in the book.
        currency.take(manager, recipient, amount, true);
    }

    function _reduceAfterMatch(
        AsyncFiller.State storage self,
        AsyncFiller.Book storage book,
        PoolKey calldata key,
        ReductionParams memory params,
        address hook
    ) private returns (uint256) {
        AsyncFiller.OrderInfo storage info = self.orders[params.id];
        uint256 oldInput = info.amountIn;
        uint256 remainingInput = oldInput - params.inputUsed;
        uint256 oldPriorityFee = info.priorityFee;
        uint256 unfilledPriorityFee = _settleMatchedPriorityFee(self, key, params.id, params.inputUsed, oldInput, hook);
        // The unfilled input keeps the maker's own limit: price improvement on the filled part is
        // not credited against it. Rounding up never asks less than that limit, and leaves a
        // nonzero minimum for any nonzero remainder.
        uint256 remainingMinimum = Math.mulDiv(info.amountOutMin, remainingInput, oldInput, Math.Rounding.Ceil);

        // The order closes when its input is used up, or when what is left is worth less than the
        // pool minimum by the order's own terms (no pool price involved); the caller then returns
        // the remaining input after both reductions. Settling the unfilled bid calls no maker code.
        if (remainingInput == 0 || (info.isBuy ? remainingInput : remainingMinimum) < book.minOrder) {
            AsyncFiller.settlePriorityFee(self, key, params.id, info.owner, unfilledPriorityFee, hook);
            AsyncFiller._remove(self, book, params.id);
            delete self.orders[params.id];
            return remainingInput;
        }

        info.amountIn = remainingInput;
        info.amountOutMin = remainingMinimum;
        info.priorityFee = uint64(unfilledPriorityFee);
        uint128 updatedPrice = _priceKey(info.isBuy, remainingInput, remainingMinimum);
        bool priceChanged = updatedPrice != info.price;
        if (priceChanged || unfilledPriorityFee != oldPriorityFee) {
            AsyncFiller._remove(self, book, params.id);
            info.price = updatedPrice;
            if (priceChanged) info.sequence = ++book.nextSequence;
            AsyncFiller._append(self, book, params.id);
        } else {
            AsyncFiller.refreshExactPrice(self, book, params.id);
        }
        return 0;
    }

    function _settleMatchedPriorityFee(
        AsyncFiller.State storage self,
        PoolKey calldata key,
        bytes32 id,
        uint256 inputUsed,
        uint256 oldInput,
        address hook
    ) private returns (uint256 unfilledPriorityFee) {
        AsyncFiller.OrderInfo storage info = self.orders[id];
        // Every stored bid is escrowed; a zero remainder needs no settlement.
        uint256 oldPriorityFee = info.priorityFee;
        if (oldPriorityFee == 0) return 0;
        uint256 filledPriorityFee = Math.mulDiv(oldPriorityFee, inputUsed, oldInput);
        unfilledPriorityFee = oldPriorityFee - filledPriorityFee;
        // A proportional share is earned only for the input that actually filled. The
        // donation is in this unlock, so a failed fill reverts the bid settlement too.
        AsyncFiller.settlePriorityFee(self, key, id, info.owner, filledPriorityFee, hook);
    }

    function _priceKey(bool isBuy, uint256 amountIn, uint256 amountOut) private pure returns (uint128) {
        uint256 price =
            isBuy ? Math.mulDiv(amountIn, PRICE_SCALE, amountOut) : Math.mulDiv(amountOut, PRICE_SCALE, amountIn);
        if (price == 0) return 1;
        if (price > type(uint128).max) return type(uint128).max;
        return uint128(price);
    }

    /// @notice Decide whether a buy and a sell order cross, i.e. a price exists that satisfies both
    ///         makers' limits.
    /// @dev The `uint128` price keys on the book are truncated WAD ratios, so two distinct prices
    ///      can share a key. Strictly ordered keys decide the result directly, since truncation
    ///      cannot invert a strict inequality. Equal keys are decided by a full-precision
    ///      cross-multiply:
    ///
    ///      cross  <=>  buyIn/buyOut >= sellOut/sellIn  <=>  buyIn*sellIn >= sellOut*buyOut
    ///             <=>  floor(buyIn*sellIn / sellOut) >= buyOut   (sellOut, buyOut are nonzero).
    ///
    ///      An exact tie counts as a cross. With equal keys the quotient is on the order of
    ///      `buyOut`, so the `mulDiv` cannot overflow for escrowable amounts.
    function _crosses(
        uint128 buyKey,
        uint128 sellKey,
        AsyncFiller.OrderInfo storage buy,
        AsyncFiller.OrderInfo storage sell
    ) internal view returns (bool) {
        if (buyKey != sellKey) return buyKey > sellKey;
        return Math.mulDiv(buy.amountIn, sell.amountIn, sell.amountOutMin) >= buy.amountOutMin;
    }
}
