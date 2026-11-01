# AsyncMatching

[Git Source](https://github.com/asyncswap/contracts/blob/7d09cfaccb98252068945596ea6058dffa186a9a/src/libraries/AsyncMatching.sol)

Linked matching module operating on the hook's order and radix-book storage.

<i>
  Public library calls use DELEGATECALL, so ERC-6909 escrow remains owned by Async Swap.
</i>

## Constants

### MAX_MATCHES_PER_CALL

```solidity
uint8 public constant MAX_MATCHES_PER_CALL = 8;
```

### POOL_LIQUIDITY_FILL_FEE

<i>
  LP fee on a pool-liquidity fill, in v4 pips: 0.02%.
</i>

```solidity
uint24 private constant POOL_LIQUIDITY_FILL_FEE = 200;
```

## Functions

<a id="addorder-asyncfiller-state-asyncfiller-book-asyncfiller-neworder" />

### addOrder

```solidity
function addOrder(AsyncFiller.State storage self, AsyncFiller.Book storage book, AsyncFiller.NewOrder memory order)
        public;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| book | `AsyncFiller.Book` |  |
| order | `AsyncFiller.NewOrder` |  |

<a id="bestorder-asyncfiller-state-asyncfiller-book-bool" />

### bestOrder

```solidity
function bestOrder(AsyncFiller.State storage self, AsyncFiller.Book storage book, bool isBuy)
        public
        view
        returns (bool found, uint128 price, bytes32 orderId, address owner);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| book | `AsyncFiller.Book` |  |
| isBuy | `bool` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| found | `bool` |  |
| price | `uint128` |  |
| orderId | `bytes32` |  |
| owner | `address` |  |

<a id="fill-asyncfiller-state-asyncfiller-book-fillparams" />

### fill

```solidity
function fill(AsyncFiller.State storage self, AsyncFiller.Book storage book, FillParams memory params) public;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| book | `AsyncFiller.Book` |  |
| params | `FillParams` |  |

<a id="cancel-asyncfiller-state-asyncfiller-book-cancelparams" />

### cancel

```solidity
function cancel(AsyncFiller.State storage self, AsyncFiller.Book storage book, CancelParams memory params) public;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| book | `AsyncFiller.Book` |  |
| params | `CancelParams` |  |

<a id="updateprice-asyncfiller-state-asyncfiller-book-updateparams" />

### updatePrice

```solidity
function updatePrice(AsyncFiller.State storage self, AsyncFiller.Book storage book, UpdateParams memory params)
        public;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| book | `AsyncFiller.Book` |  |
| params | `UpdateParams` |  |

<a id="matchincoming-asyncfiller-state-asyncfiller-book-poolkey-bytes32-address" />

### matchIncoming

```solidity
function matchIncoming(
        AsyncFiller.State storage self,
        AsyncFiller.Book storage book,
        PoolKey calldata key,
        bytes32 incomingId,
        address hook
    ) public returns (uint8 matched);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| book | `AsyncFiller.Book` |  |
| key | `PoolKey` |  |
| incomingId | `bytes32` |  |
| hook | `address` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| matched | `uint8` |  |

<a id="matchbook-asyncfiller-state-asyncfiller-book-poolkey-uint8-address" />

### matchBook

```solidity
function matchBook(
        AsyncFiller.State storage self,
        AsyncFiller.Book storage book,
        PoolKey calldata key,
        uint8 maxMatches,
        address hook
    ) public returns (uint8 matched);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| book | `AsyncFiller.Book` |  |
| key | `PoolKey` |  |
| maxMatches | `uint8` |  |
| hook | `address` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| matched | `uint8` |  |

<a id="_bookpair-asyncfiller-state-asyncfiller-book" />

### \_bookPair

```solidity
function _bookPair(AsyncFiller.State storage self, AsyncFiller.Book storage book)
        private
        view
        returns (bytes32 bidId, bytes32 askId);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| book | `AsyncFiller.Book` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| bidId | `bytes32` |  |
| askId | `bytes32` |  |

<a id="fillfrompoolliquidity-asyncfiller-state-asyncfiller-book-poolkey-bytes32-address-uint160" />

### fillFromPoolLiquidity

Execute an order against active v4 LP positions if they meet the signed minimum.

<i>
  Reverts atomically on insufficient liquidity or output; the caller catches this across a self-call so
  the resting order is preserved. Without a price limit the whole order must fill. With one (the best
  book level, when the pool goes first) the swap may stop there: the filled part must meet the maker's
  limit pro rata, and the rest stays on the book with the maker's own limit for the book to match.
</i>

```solidity
function fillFromPoolLiquidity(
        AsyncFiller.State storage self,
        AsyncFiller.Book storage book,
        PoolKey calldata key,
        bytes32 id,
        address hook,
        uint160 sqrtPriceLimitX96
    ) public;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| book | `AsyncFiller.Book` |  |
| key | `PoolKey` |  |
| id | `bytes32` |  |
| hook | `address` |  |
| sqrtPriceLimitX96 | `uint160` |  |

<a id="_reduceafterpoolfill-asyncfiller-state-asyncfiller-book-poolkey-bytes32-uint256" />

### \_reduceAfterPoolFill

```solidity
function _reduceAfterPoolFill(
        AsyncFiller.State storage self,
        AsyncFiller.Book storage book,
        PoolKey calldata key,
        bytes32 id,
        uint256 consumed
    ) private;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| book | `AsyncFiller.Book` |  |
| key | `PoolKey` |  |
| id | `bytes32` |  |
| consumed | `uint256` |  |

<a id="closebelowminimum-asyncfiller-state-asyncfiller-book-poolkey-bytes32" />

### closeBelowMinimum

Close a live order left below the pool minimum and return its input as claims; its unfilled
priority bid is spent, as for a book match that leaves dust.

```solidity
function closeBelowMinimum(
        AsyncFiller.State storage self,
        AsyncFiller.Book storage book,
        PoolKey calldata key,
        bytes32 id
    ) public;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| book | `AsyncFiller.Book` |  |
| key | `PoolKey` |  |
| id | `bytes32` |  |

<a id="_poolfillnet-asyncfiller-state-poolkey-bytes32-address-uint160" />

### \_poolFillNet

<i>
  Swap the order's input less the protocol's 0.01% (rounded up, paid to the vault), then take the dynamic
  fee (`DynamicFeeOrdering`) from the output. A swap stopped short at `sqrtPriceLimitX96` pays the 0.01% on
  what it swapped. Returns the input swapped, the input used including the 0.01%, and the net output,
  reverting unless the output meets the maker's limit on the input used.
</i>

```solidity
function _poolFillNet(
        AsyncFiller.State storage self,
        PoolKey calldata key,
        bytes32 id,
        address hook,
        uint160 sqrtPriceLimitX96
    ) private returns (uint256 swapped, uint256 consumed, uint256 amountOut);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| key | `PoolKey` |  |
| id | `bytes32` |  |
| hook | `address` |  |
| sqrtPriceLimitX96 | `uint160` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| swapped | `uint256` |  |
| consumed | `uint256` |  |
| amountOut | `uint256` |  |

<a id="_chargefees-asyncfiller-state-poolkey-bytes32-uint256-int24-uint256" />

### \_chargeFees

<i>
  Pay the 0.01% from the input's escrow to the vault and charge the dynamic fee on the output; returns
  the dynamic fee.
</i>

```solidity
function _chargeFees(
        AsyncFiller.State storage self,
        PoolKey calldata key,
        bytes32 id,
        uint256 protocolFee,
        int24 tickBefore,
        uint256 amountOut
    ) private returns (uint256);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| key | `PoolKey` |  |
| id | `bytes32` |  |
| protocolFee | `uint256` |  |
| tickBefore | `int24` |  |
| amountOut | `uint256` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `uint256` |  |

<a id="_swapagainstpool-ipoolmanager-poolkey-bool-uint256-address-uint160" />

### \_swapAgainstPool

```solidity
function _swapAgainstPool(
        IPoolManager manager,
        PoolKey calldata key,
        bool zeroForOne,
        uint256 amountIn,
        address hook,
        uint160 sqrtPriceLimitX96
    ) private returns (uint256 swapped, uint256 amountOut, int24 tickBefore);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| manager | `IPoolManager` |  |
| key | `PoolKey` |  |
| zeroForOne | `bool` |  |
| amountIn | `uint256` |  |
| hook | `address` |  |
| sqrtPriceLimitX96 | `uint160` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| swapped | `uint256` |  |
| amountOut | `uint256` |  |
| tickBefore | `int24` |  |

<a id="_matchpair-asyncfiller-state-asyncfiller-book-poolkey-bytes32-bytes32-claimtransfers-batch" />

### \_matchPair

<i>
  `buyId` comes from the bid tree and `sellId` from the ask tree (`_bookPair`), so their
  sides are fixed by construction.
</i>

```solidity
function _matchPair(
        AsyncFiller.State storage self,
        AsyncFiller.Book storage book,
        PoolKey calldata key,
        bytes32 buyId,
        bytes32 sellId,
        ClaimTransfers.Batch memory batch
    ) private returns (bool);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| book | `AsyncFiller.Book` |  |
| key | `PoolKey` |  |
| buyId | `bytes32` |  |
| sellId | `bytes32` |  |
| batch | `ClaimTransfers.Batch` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `bool` |  |

<a id="_matchamounts-asyncfiller-orderinfo-asyncfiller-orderinfo-bool" />

### \_matchAmounts

```solidity
function _matchAmounts(AsyncFiller.OrderInfo storage sell, AsyncFiller.OrderInfo storage buy, bool restingBuy)
        private
        view
        returns (AsyncFiller.MatchAmounts memory amounts);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| sell | `AsyncFiller.OrderInfo` |  |
| buy | `AsyncFiller.OrderInfo` |  |
| restingBuy | `bool` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| amounts | `AsyncFiller.MatchAmounts` |  |

<a id="_payouts-asyncfiller-state-poolkey-bytes32-bytes32" />

### \_payouts

```solidity
function _payouts(AsyncFiller.State storage self, PoolKey calldata key, bytes32 buyId, bytes32 sellId)
        private
        view
        returns (Payouts memory payouts);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| key | `PoolKey` |  |
| buyId | `bytes32` |  |
| sellId | `bytes32` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| payouts | `Payouts` |  |

<a id="_settletransfers-ipoolmanager-address-payouts-asyncfiller-matchamounts-claimtransfers-batch" />

### \_settleTransfers

<i>
  Each side receives its proceeds less the 0.02% trade fee, which goes to the vault.
</i>

```solidity
function _settleTransfers(
        IPoolManager manager,
        address feeVault,
        Payouts memory payouts,
        AsyncFiller.MatchAmounts memory amounts,
        ClaimTransfers.Batch memory batch
    ) private;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| manager | `IPoolManager` |  |
| feeVault | `address` |  |
| payouts | `Payouts` |  |
| amounts | `AsyncFiller.MatchAmounts` |  |
| batch | `ClaimTransfers.Batch` |  |

<a id="_reducematchedorders-asyncfiller-state-asyncfiller-book-poolkey-bytes32-bytes32-asyncfiller-matchamounts-claimtransfers-batch" />

### \_reduceMatchedOrders

```solidity
function _reduceMatchedOrders(
        AsyncFiller.State storage self,
        AsyncFiller.Book storage book,
        PoolKey calldata key,
        bytes32 buyId,
        bytes32 sellId,
        AsyncFiller.MatchAmounts memory amounts,
        ClaimTransfers.Batch memory batch
    ) private returns (uint256 sellRefund, uint256 buyRefund);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| book | `AsyncFiller.Book` |  |
| key | `PoolKey` |  |
| buyId | `bytes32` |  |
| sellId | `bytes32` |  |
| amounts | `AsyncFiller.MatchAmounts` |  |
| batch | `ClaimTransfers.Batch` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| sellRefund | `uint256` |  |
| buyRefund | `uint256` |  |

<a id="_transferescrow-ipoolmanager-currency-address-uint256-claimtransfers-batch" />

### \_transferEscrow

```solidity
function _transferEscrow(
        IPoolManager manager,
        Currency currency,
        address recipient,
        uint256 amount,
        ClaimTransfers.Batch memory batch
    ) private;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| manager | `IPoolManager` |  |
| currency | `Currency` |  |
| recipient | `address` |  |
| amount | `uint256` |  |
| batch | `ClaimTransfers.Batch` |  |

<a id="_reduceaftermatch-asyncfiller-state-asyncfiller-book-poolkey-reductionparams-claimtransfers-batch-bool" />

### \_reduceAfterMatch

```solidity
function _reduceAfterMatch(
        AsyncFiller.State storage self,
        AsyncFiller.Book storage book,
        PoolKey calldata key,
        ReductionParams memory params,
        ClaimTransfers.Batch memory batch,
        bool closeDust
    ) private returns (uint256);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| book | `AsyncFiller.Book` |  |
| key | `PoolKey` |  |
| params | `ReductionParams` |  |
| batch | `ClaimTransfers.Batch` |  |
| closeDust | `bool` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `uint256` |  |

<a id="_settlematchedpriorityfee-asyncfiller-state-poolkey-bytes32-uint256-uint256-claimtransfers-batch" />

### \_settleMatchedPriorityFee

```solidity
function _settleMatchedPriorityFee(
        AsyncFiller.State storage self,
        PoolKey calldata key,
        bytes32 id,
        uint256 inputUsed,
        uint256 oldInput,
        ClaimTransfers.Batch memory batch
    ) private returns (uint256 unfilledPriorityFee);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| key | `PoolKey` |  |
| id | `bytes32` |  |
| inputUsed | `uint256` |  |
| oldInput | `uint256` |  |
| batch | `ClaimTransfers.Batch` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| unfilledPriorityFee | `uint256` |  |

<a id="_creditpriorityfee-asyncfiller-state-poolkey-bytes32-address-uint256-claimtransfers-batch" />

### \_creditPriorityFee

```solidity
function _creditPriorityFee(
        AsyncFiller.State storage self,
        PoolKey calldata key,
        bytes32 id,
        address maker,
        uint256 amount,
        ClaimTransfers.Batch memory batch
    ) private;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| key | `PoolKey` |  |
| id | `bytes32` |  |
| maker | `address` |  |
| amount | `uint256` |  |
| batch | `ClaimTransfers.Batch` |  |

<a id="_crosses-uint128-uint128-asyncfiller-orderinfo-asyncfiller-orderinfo" />

### \_crosses

Decide whether a buy and a sell order cross, i.e. a price exists that satisfies both
makers' limits.

<i>
  Keys are the floor ticks of the exact limits, ordered by numeraire per asset, so two
  distinct prices can share a key. Strictly ordered keys decide the result directly,
  since a monotone key cannot invert a strict inequality. Equal keys are decided by a
  full-precision cross-multiply:
</i>

cross  \<=>  buyIn/buyOut >= sellOut/sellIn  \<=>  buyIn*sellIn >= sellOut*buyOut
\<=>  floor(buyIn\*sellIn / sellOut) >= buyOut   (sellOut, buyOut are nonzero).

An exact tie counts as a cross. With equal keys the quotient is on the order of
`buyOut`, so the `mulDiv` cannot overflow for escrowable amounts.

```solidity
function _crosses(
        uint128 buyKey,
        uint128 sellKey,
        AsyncFiller.OrderInfo storage buy,
        AsyncFiller.OrderInfo storage sell
    ) internal view returns (bool);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| buyKey | `uint128` |  |
| sellKey | `uint128` |  |
| buy | `AsyncFiller.OrderInfo` |  |
| sell | `AsyncFiller.OrderInfo` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `bool` |  |

## Events

### AsyncOrdersMatched

```solidity
event AsyncOrdersMatched(
        PoolId indexed poolId,
        bytes32 indexed sellOrderId,
        bytes32 indexed buyOrderId,
        uint256 assetAmount,
        uint256 numeraireAmount
    );
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| poolId | `PoolId` |  |
| sellOrderId | `bytes32` |  |
| buyOrderId | `bytes32` |  |
| assetAmount | `uint256` |  |
| numeraireAmount | `uint256` |  |

### AsyncOrderLiquidityFilled

```solidity
event AsyncOrderLiquidityFilled(
        PoolId indexed poolId, bytes32 indexed orderId, address indexed maker, uint256 amountIn, uint256 amountOut
    );
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| poolId | `PoolId` |  |
| orderId | `bytes32` |  |
| maker | `address` |  |
| amountIn | `uint256` |  |
| amountOut | `uint256` |  |

## Errors

### InvalidMatchBound

```solidity
error InvalidMatchBound();
```

### PartialLiquidityFill

```solidity
error PartialLiquidityFill();
```

### LimitPriceNotMet

```solidity
error LimitPriceNotMet();
```

### NoActiveLiquidity

```solidity
error NoActiveLiquidity();
```

## Structs

### ReductionParams

```solidity
struct ReductionParams {
        bytes32 id;
        uint256 inputUsed;
        uint256 outputReceived;
    }
```

**Properties**

| Name | Type | Description |
| ---- | ---- | ----------- |
| id | `bytes32` |  |
| inputUsed | `uint256` |  |
| outputReceived | `uint256` |  |

### Payouts

<i>
  Who receives each leg of a match, read before the matched orders are reduced.
</i>

```solidity
struct Payouts {
        address sellOwner;
        address buyOwner;
        Currency sellInput;
        Currency buyInput;
        uint256 sellRefund; // input returned to an order left below the pool minimum
        uint256 buyRefund;
    }
```

**Properties**

| Name | Type | Description |
| ---- | ---- | ----------- |
| sellOwner | `address` |  |
| buyOwner | `address` |  |
| sellInput | `Currency` |  |
| buyInput | `Currency` |  |
| sellRefund | `uint256` |  |
| buyRefund | `uint256` |  |

### FillParams

```solidity
struct FillParams {
        AsyncOrder order;
        bytes32 id;
        address hook;
        address executor;
        address filler;
        address feeVault;
        uint256 fee;
    }
```

**Properties**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |
| id | `bytes32` |  |
| hook | `address` |  |
| executor | `address` |  |
| filler | `address` |  |
| feeVault | `address` |  |
| fee | `uint256` |  |

### CancelParams

```solidity
struct CancelParams {
        AsyncOrder order;
        bytes32 id;
        address hook;
        address executor;
    }
```

**Properties**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |
| id | `bytes32` |  |
| hook | `address` |  |
| executor | `address` |  |

### UpdateParams

```solidity
struct UpdateParams {
        AsyncOrder order;
        bytes32 id;
        uint256 newAmountOutMin;
        address caller;
    }
```

**Properties**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |
| id | `bytes32` |  |
| newAmountOutMin | `uint256` |  |
| caller | `address` |  |
