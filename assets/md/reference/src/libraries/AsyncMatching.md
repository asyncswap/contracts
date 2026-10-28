# AsyncMatching

[Git Source](https://github.com/asyncswap/contracts/blob/996c1e5bc0203720c76f3ad0406a08db4650f3b5/src/libraries/AsyncMatching.sol)

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

```solidity
uint24 private constant POOL_LIQUIDITY_FILL_FEE = 3_000;
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

<a id="setminorder-asyncfiller-book-poolid-uint256" />

### setMinOrder

```solidity
function setMinOrder(AsyncFiller.Book storage book, PoolId poolId, uint256 minimum) public;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| book | `AsyncFiller.Book` |  |
| poolId | `PoolId` |  |
| minimum | `uint256` |  |

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

<a id="level-asyncfiller-book-bool-uint128" />

### level

```solidity
function level(AsyncFiller.Book storage book, bool isBuy, uint128 price)
        public
        view
        returns (bytes32 head, bytes32 tail, uint32 orderCount);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| book | `AsyncFiller.Book` |  |
| isBuy | `bool` |  |
| price | `uint128` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| head | `bytes32` |  |
| tail | `bytes32` |  |
| orderCount | `uint32` |  |

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

<a id="fillfrompoolliquidity-asyncfiller-state-asyncfiller-book-poolkey-bytes32-address-address" />

### fillFromPoolLiquidity

Execute an order against active v4 LP positions if they meet the signed minimum.

<i>
  Reverts atomically on insufficient liquidity/output or partial execution. The caller
  catches this across a self-call so the resting order is preserved.
</i>

```solidity
function fillFromPoolLiquidity(
        AsyncFiller.State storage self,
        AsyncFiller.Book storage book,
        PoolKey calldata key,
        bytes32 id,
        address maker,
        address hook
    ) public;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| book | `AsyncFiller.Book` |  |
| key | `PoolKey` |  |
| id | `bytes32` |  |
| maker | `address` |  |
| hook | `address` |  |

<a id="_swapagainstpool-ipoolmanager-poolkey-bool-uint256-uint256-address" />

### \_swapAgainstPool

```solidity
function _swapAgainstPool(
        IPoolManager manager,
        PoolKey calldata key,
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOutMin,
        address hook
    ) private returns (uint256 amountOut);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| manager | `IPoolManager` |  |
| key | `PoolKey` |  |
| zeroForOne | `bool` |  |
| amountIn | `uint256` |  |
| amountOutMin | `uint256` |  |
| hook | `address` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| amountOut | `uint256` |  |

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

<a id="_settletransfers-ipoolmanager-payouts-asyncfiller-matchamounts-claimtransfers-batch" />

### \_settleTransfers

```solidity
function _settleTransfers(
        IPoolManager manager,
        Payouts memory payouts,
        AsyncFiller.MatchAmounts memory amounts,
        ClaimTransfers.Batch memory batch
    ) private;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| manager | `IPoolManager` |  |
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

<a id="_reduceaftermatch-asyncfiller-state-asyncfiller-book-poolkey-reductionparams-claimtransfers-batch" />

### \_reduceAfterMatch

```solidity
function _reduceAfterMatch(
        AsyncFiller.State storage self,
        AsyncFiller.Book storage book,
        PoolKey calldata key,
        ReductionParams memory params,
        ClaimTransfers.Batch memory batch
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
