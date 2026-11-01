# AsyncFiller

[Git Source](https://github.com/asyncswap/contracts/blob/9fddf384806296d86e2066f735c36f956d6e9f73/src/libraries/AsyncFiller.sol)

**Title:** AsyncFiller

**Author:** @msakiart

Stores open async orders and settles fills against them.

<i>
  Authorization model: the maker authorizes a Router/executor at order-creation time
  (`setExecutor[owner][executor] = true`). All subsequent fill / cancel / updatePrice
  calls on the hook must come from that registered executor. The hook forwards its
  immediate caller (`msg.sender`) and the resolved end-actor address (filler / canceller)
  into this library; the executor is checked here, and PM settlement targets the actor.
</i>

## Constants

### MAX_PRIORITY_FEE

```solidity
uint64 internal constant MAX_PRIORITY_FEE = type(uint64).max;
```

### MIN_PRIORITY_FEE

<i>
  Default $0.10 cap for six-decimal numeraires. A pool may override this for other decimals.
</i>

```solidity
uint64 internal constant MIN_PRIORITY_FEE = 100_000;
```

### PRIORITY_FEE_BPS

<i>
  Below a $100 order the least bid is 10 bps of the order instead: min($0.10, 0.1% of it).
</i>

```solidity
uint256 internal constant PRIORITY_FEE_BPS = 10;
```

### TRADE_FEE_BPS

<i>
  Protocol fee on what each side of a book match or filler fill receives: 0.02%.
</i>

```solidity
uint256 internal constant TRADE_FEE_BPS = 2;
```

## Functions

<a id="addorder-state-book-bytes32-address-uint256-uint256-bool-bool-uint256" />

### addOrder

```solidity
function addOrder(
        State storage self,
        Book storage book,
        bytes32 id,
        address owner,
        uint256 amountIn,
        uint256 amountOutMin,
        bool isBuy,
        bool zeroForOne,
        uint256 priorityFee
    ) internal;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `State` |  |
| book | `Book` |  |
| id | `bytes32` |  |
| owner | `address` |  |
| amountIn | `uint256` |  |
| amountOutMin | `uint256` |  |
| isBuy | `bool` |  |
| zeroForOne | `bool` |  |
| priorityFee | `uint256` |  |

<a id="tradefee-uint256" />

### tradeFee

The protocol's 0.02% of a payment, rounded up. Each side of a trade receives its
proceeds less this fee, so a maker receives at least `amountOutMin` minus 0.02%.

```solidity
function tradeFee(uint256 amount) internal pure returns (uint256);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount | `uint256` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `uint256` |  |

<a id="minpriorityfee-uint256" />

### minPriorityFee

The least bid for an order worth `notional` numeraire units: $0.10, or 0.1% of the
order when that is less (orders under $100).

```solidity
function minPriorityFee(uint256 notional) internal pure returns (uint256);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| notional | `uint256` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `uint256` |  |

<a id="minpriorityfee-uint256-uint64" />

### minPriorityFee

```solidity
function minPriorityFee(uint256 notional, uint64 cap) internal pure returns (uint256);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| notional | `uint256` |  |
| cap | `uint64` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `uint256` |  |

<a id="checkminimum-book-bool-uint256-uint256" />

### checkMinimum

Reverts unless the order's numeraire leg is at least the pool's minimum (a buy's input, a
sell's minimum output) and its asset leg at least the pool's asset floor (a sell's input, a buy's minimum
output). Neither reads the pool price, which whoever initializes the pool sets.

```solidity
function checkMinimum(Book storage book, bool isBuy, uint256 amountIn, uint256 amountOutMin) internal view;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| book | `Book` |  |
| isBuy | `bool` |  |
| amountIn | `uint256` |  |
| amountOutMin | `uint256` |  |

<a id="settlepriorityfee-state-poolkey-bytes32-address-uint256-address" />

### settlePriorityFee

```solidity
function settlePriorityFee(
        State storage self,
        PoolKey memory key,
        bytes32 id,
        address maker,
        uint256 amount,
        address hook
    ) internal;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `State` |  |
| key | `PoolKey` |  |
| id | `bytes32` |  |
| maker | `address` |  |
| amount | `uint256` |  |
| hook | `address` |  |

<a id="bestorder-state-book-bool" />

### bestOrder

```solidity
function bestOrder(State storage self, Book storage book, bool isBuy)
        internal
        view
        returns (bool found, uint128 price, bytes32 orderId, address owner);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `State` |  |
| book | `Book` |  |
| isBuy | `bool` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| found | `bool` |  |
| price | `uint128` |  |
| orderId | `bytes32` |  |
| owner | `address` |  |

<a id="level-book-bool-uint128" />

### level

```solidity
function level(Book storage book, bool isBuy, uint128 price)
        internal
        view
        returns (bytes32 head, bytes32 tail, uint32 orderCount);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| book | `Book` |  |
| isBuy | `bool` |  |
| price | `uint128` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| head | `bytes32` |  |
| tail | `bytes32` |  |
| orderCount | `uint32` |  |

<a id="bestatprice-book-bool-uint128" />

### bestAtPrice

```solidity
function bestAtPrice(Book storage book, bool isBuy, uint128 price) internal view returns (bytes32 id);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| book | `Book` |  |
| isBuy | `bool` |  |
| price | `uint128` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| id | `bytes32` |  |

<a id="updateprice-state-book-asyncorder-bytes32-uint256-address" />

### updatePrice

Maker-only price update: `caller` must equal `order.owner` (the maker directly, or the
owner whose signature `updatePriceWithSig` verified). No executor is involved.

```solidity
function updatePrice(
        State storage self,
        Book storage book,
        AsyncOrder memory order,
        bytes32 id,
        uint256 newAmountOutMin,
        address caller
    ) internal;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `State` |  |
| book | `Book` |  |
| order | `AsyncOrder` |  |
| id | `bytes32` |  |
| newAmountOutMin | `uint256` |  |
| caller | `address` |  |

<a id="fill-state-book-asyncorder-bytes32-address-address-address-address-uint256" />

### fill

Full-fill. The caller (the hook contract) must be an authorized executor of the
order owner; `filler` is the actual end-user paying the output and receiving the
input. Must be invoked from inside an `IPoolManager.unlock` context.

<i>
  Settle gross output (native only; ERC20 is pre-settled), pay the signed minimum less the trade fee to the
  maker, and mint fee claims to the vault. Burn input claims and pay the input less the trade fee to the
  filler. Both currency deltas net to zero. A failed fill reverts all legs.
</i>

```solidity
function fill(
        State storage self,
        Book storage book,
        AsyncOrder memory order,
        bytes32 id,
        address hook,
        address executor,
        address filler,
        address feeVault,
        uint256 fee
    ) internal;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `State` |  |
| book | `Book` |  |
| order | `AsyncOrder` |  |
| id | `bytes32` |  |
| hook | `address` |  |
| executor | `address` |  |
| filler | `address` |  |
| feeVault | `address` |  |
| fee | `uint256` |  |

<a id="_payfiller-state-currency-address-address-address-uint256" />

### \_payFiller

<i>
  Burn the order's input claims and pay the filler all but the trade fee, which goes to the vault.
</i>

```solidity
function _payFiller(
        State storage self,
        Currency input,
        address hook,
        address filler,
        address feeVault,
        uint256 amountIn
    ) private returns (uint256 tradeFeeIn);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `State` |  |
| input | `Currency` |  |
| hook | `address` |  |
| filler | `address` |  |
| feeVault | `address` |  |
| amountIn | `uint256` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| tradeFeeIn | `uint256` |  |

<a id="_closeorder-state-book-poolkey-bytes32-address" />

### \_closeOrder

<i>
  Remove and delete an order, then settle its bid.
</i>

```solidity
function _closeOrder(State storage self, Book storage book, PoolKey memory key, bytes32 id, address hook) private;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `State` |  |
| book | `Book` |  |
| key | `PoolKey` |  |
| id | `bytes32` |  |
| hook | `address` |  |

<a id="settleorderpriorityfee-state-poolkey-bytes32-address" />

### settleOrderPriorityFee

```solidity
function settleOrderPriorityFee(State storage self, PoolKey memory key, bytes32 id, address hook) internal;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `State` |  |
| key | `PoolKey` |  |
| id | `bytes32` |  |
| hook | `address` |  |

<a id="cancel-state-book-asyncorder-bytes32-address-address" />

### cancel

Cancel an unfilled order. Must be called inside an unlock context. Auth: `executor`
must be either the order owner themselves (smart-contract makers calling the hook
directly from their own unlock) or an executor the maker authorised via
`setExecutor`. Funds always return to `order.owner`.

```solidity
function cancel(
        State storage self,
        Book storage book,
        AsyncOrder memory order,
        bytes32 id,
        address hook,
        address executor
    ) internal;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `State` |  |
| book | `Book` |  |
| order | `AsyncOrder` |  |
| id | `bytes32` |  |
| hook | `address` |  |
| executor | `address` |  |

<a id="_append-state-book-bytes32" />

### \_append

```solidity
function _append(State storage self, Book storage book, bytes32 id) internal;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `State` |  |
| book | `Book` |  |
| id | `bytes32` |  |

<a id="_remove-state-book-bytes32" />

### \_remove

```solidity
function _remove(State storage self, Book storage book, bytes32 id) internal;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `State` |  |
| book | `Book` |  |
| id | `bytes32` |  |

<a id="_prioritykey-uint64-uint64" />

### \_priorityKey

```solidity
function _priorityKey(uint64 priorityFee, uint64 sequence) private pure returns (uint128);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| priorityFee | `uint64` |  |
| sequence | `uint64` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `uint128` |  |

<a id="refreshexactprice-state-book-bytes32" />

### refreshExactPrice

<i>
  Refresh even when a partial fill changes neither the price key nor remaining bid.
</i>

```solidity
function refreshExactPrice(State storage self, Book storage book, bytes32 id) internal;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `State` |  |
| book | `Book` |  |
| id | `bytes32` |  |

<a id="exactprice-orderinfo" />

### exactPrice

```solidity
function exactPrice(OrderInfo storage order) internal view returns (EligiblePrice.Ratio memory);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `OrderInfo` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `EligiblePrice.Ratio` |  |

<a id="eligibleatprice-book-bool-uint128-eligibleprice-ratio" />

### eligibleAtPrice

```solidity
function eligibleAtPrice(Book storage book, bool isBuy, uint128 price, EligiblePrice.Ratio memory limit)
        internal
        view
        returns (bytes32);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| book | `Book` |  |
| isBuy | `bool` |  |
| price | `uint128` |  |
| limit | `EligiblePrice.Ratio` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `bytes32` |  |

<a id="mostpermissiveatprice-book-bool-uint128" />

### mostPermissiveAtPrice

```solidity
function mostPermissiveAtPrice(Book storage book, bool isBuy, uint128 price)
        internal
        view
        returns (EligiblePrice.Ratio memory);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| book | `Book` |  |
| isBuy | `bool` |  |
| price | `uint128` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `EligiblePrice.Ratio` |  |

<a id="_pricekey-bool-bool-uint256-uint256" />

### \_priceKey

<i>
  The order's book level: the v4 tick of its exact limit, ordered by numeraire per asset
  (see `TickPrice.key`). The exact limit is kept on the order and decides crossing.
</i>

```solidity
function _priceKey(bool isBuy, bool zeroForOne, uint256 amountIn, uint256 amountOut)
        internal
        pure
        returns (uint128);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| isBuy | `bool` |  |
| zeroForOne | `bool` |  |
| amountIn | `uint256` |  |
| amountOut | `uint256` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `uint128` |  |

## Events

### AsyncOrderCreated

```solidity
event AsyncOrderCreated(
        PoolId indexed poolId,
        bytes32 indexed orderId,
        address indexed owner,
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOutMin,
        bytes32 salt
    );
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| poolId | `PoolId` |  |
| orderId | `bytes32` |  |
| owner | `address` |  |
| zeroForOne | `bool` |  |
| amountIn | `uint256` |  |
| amountOutMin | `uint256` |  |
| salt | `bytes32` |  |

### AsyncOrderPriceUpdated

```solidity
event AsyncOrderPriceUpdated(
        PoolId indexed poolId, bytes32 indexed orderId, uint256 oldAmountOutMin, uint256 newAmountOutMin
    );
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| poolId | `PoolId` |  |
| orderId | `bytes32` |  |
| oldAmountOutMin | `uint256` |  |
| newAmountOutMin | `uint256` |  |

### AsyncOrderFilled

```solidity
event AsyncOrderFilled(
        PoolId indexed poolId, bytes32 indexed orderId, address indexed filler, uint256 amountIn, uint256 amountOutMin
    );
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| poolId | `PoolId` |  |
| orderId | `bytes32` |  |
| filler | `address` |  |
| amountIn | `uint256` |  |
| amountOutMin | `uint256` |  |

### AsyncOrderCancelled

```solidity
event AsyncOrderCancelled(PoolId indexed poolId, bytes32 indexed orderId, address indexed owner, uint256 amountIn);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| poolId | `PoolId` |  |
| orderId | `bytes32` |  |
| owner | `address` |  |
| amountIn | `uint256` |  |

### OrderFeeAccrued

```solidity
event OrderFeeAccrued(PoolId indexed poolId, bytes32 indexed orderId, Currency indexed currency, uint256 amount);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| poolId | `PoolId` |  |
| orderId | `bytes32` |  |
| currency | `Currency` |  |
| amount | `uint256` |  |

### PriorityFeeDonated

```solidity
event PriorityFeeDonated(PoolId indexed poolId, bytes32 indexed orderId, address indexed maker, uint256 amount);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| poolId | `PoolId` |  |
| orderId | `bytes32` |  |
| maker | `address` |  |
| amount | `uint256` |  |

### PriorityFeeForfeited

```solidity
event PriorityFeeForfeited(PoolId indexed poolId, bytes32 indexed orderId, address indexed maker, uint256 amount);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| poolId | `PoolId` |  |
| orderId | `bytes32` |  |
| maker | `address` |  |
| amount | `uint256` |  |

## Errors

### OrderAlreadyExists

```solidity
error OrderAlreadyExists();
```

### OrderNotFound

```solidity
error OrderNotFound();
```

### NotOrderOwner

```solidity
error NotOrderOwner();
```

### NotAuthorizedExecutor

```solidity
error NotAuthorizedExecutor();
```

### ZeroAmount

```solidity
error ZeroAmount();
```

### PriorityFeeTooLarge

```solidity
error PriorityFeeTooLarge();
```

### PriorityFeeTooSmall

```solidity
error PriorityFeeTooSmall();
```

### BelowMinimumOrder

```solidity
error BelowMinimumOrder();
```

### BelowMinimumAssetAmount

```solidity
error BelowMinimumAssetAmount();
```

## Structs

### OrderInfo

Open-order record. Filler fills are full-order; direct matches can reduce it
partially while keeping the remaining input in escrow.

```solidity
struct OrderInfo {
        address owner;
        uint256 amountIn;
        uint256 amountOutMin;
        uint128 price;
        bool isBuy;
        bool zeroForOne;
        uint64 sequence;
        /// @dev The bid, escrowed as hook claims since the order was created.
        uint64 priorityFee;
        uint128 priorityKey;
        /// @dev Immutable settlement age; repricing only resets queue sequence.
        uint64 createdSequence;
    }
```

**Properties**

| Name | Type | Description |
| ---- | ---- | ----------- |
| owner | `address` |  |
| amountIn | `uint256` |  |
| amountOutMin | `uint256` |  |
| price | `uint128` |  |
| isBuy | `bool` |  |
| zeroForOne | `bool` |  |
| sequence | `uint64` |  |
| priorityFee | `uint64` |  |
| priorityKey | `uint128` |  |
| createdSequence | `uint64` |  |

### PriceLevel

<i>
  Orders at one price, highest bid first, then earliest.
</i>

```solidity
struct PriceLevel {
        uint32 orderCount;
        RadixPriceTree.Tree priorityOrders;
        mapping(uint128 priorityKey => bytes32 orderId) priorityOrderIds;
        mapping(uint32 nodeId => EligiblePrice.Ratio) exactBounds;
    }
```

**Properties**

| Name | Type | Description |
| ---- | ---- | ----------- |
| orderCount | `uint32` |  |
| priorityOrders | `RadixPriceTree.Tree` |  |
| priorityOrderIds | `mapping(uint128 priorityKey => bytes32 orderId)` |  |
| exactBounds | `mapping(uint32 nodeId => EligiblePrice.Ratio)` |  |

### MatchAmounts

```solidity
struct MatchAmounts {
        uint256 assetAmount;
        uint256 quoteAmount;
    }
```

**Properties**

| Name | Type | Description |
| ---- | ---- | ----------- |
| assetAmount | `uint256` |  |
| quoteAmount | `uint256` |  |

### NewOrder

```solidity
struct NewOrder {
        bytes32 id;
        address owner;
        uint256 amountIn;
        uint256 amountOutMin;
        bool isBuy;
        bool zeroForOne;
        uint256 priorityFee;
        PoolId poolId;
    }
```

**Properties**

| Name | Type | Description |
| ---- | ---- | ----------- |
| id | `bytes32` |  |
| owner | `address` |  |
| amountIn | `uint256` |  |
| amountOutMin | `uint256` |  |
| isBuy | `bool` |  |
| zeroForOne | `bool` |  |
| priorityFee | `uint256` |  |
| poolId | `PoolId` |  |

### State

```solidity
struct State {
        IPoolManager poolManager;
        Currency numeraire;
        address feeVault;
        mapping(bytes32 orderId => OrderInfo) orders;
        mapping(address owner => mapping(address executor => bool)) isExecutor;
        /// @dev Pool tick before the first pool fill of the current backrun window, and that fill's block.
        int24 refTick;
        uint64 refBlock;
    }
```

**Properties**

| Name | Type | Description |
| ---- | ---- | ----------- |
| poolManager | `IPoolManager` |  |
| numeraire | `Currency` |  |
| feeVault | `address` |  |
| orders | `mapping(bytes32 orderId => OrderInfo)` |  |
| isExecutor | `mapping(address owner => mapping(address executor => bool))` |  |
| refTick | `int24` |  |
| refBlock | `uint64` |  |

### Book

```solidity
struct Book {
        uint64 nextSequence;
        uint64 openOrderCount;
        /// @dev $0.10 in this pool's numeraire base units. Zero uses the six-decimal default.
        uint64 priorityFeeCap;
        RadixPriceTree.Tree bids;
        RadixPriceTree.Tree asks;
        mapping(uint128 price => PriceLevel) bidLevels;
        mapping(uint128 price => PriceLevel) askLevels;
        /// @dev Least order size in numeraire base units (0: none); see `checkMinimum`.
        uint256 minOrder;
        /// @dev Least asset amount an order may trade, from the asset's decimals and the hook's precision.
        uint256 minAssetAmount;
    }
```

**Properties**

| Name | Type | Description |
| ---- | ---- | ----------- |
| nextSequence | `uint64` |  |
| openOrderCount | `uint64` |  |
| priorityFeeCap | `uint64` |  |
| bids | `RadixPriceTree.Tree` |  |
| asks | `RadixPriceTree.Tree` |  |
| bidLevels | `mapping(uint128 price => PriceLevel)` |  |
| askLevels | `mapping(uint128 price => PriceLevel)` |  |
| minOrder | `uint256` |  |
| minAssetAmount | `uint256` |  |
