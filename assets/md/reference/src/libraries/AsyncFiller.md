# AsyncFiller

[Git Source](https://github.com/asyncswap/contracts/blob/e31f7066f60bba1d310850060188cecf69bae54c/src/libraries/AsyncFiller.sol)

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

### PRICE_SCALE

```solidity
uint256 private constant PRICE_SCALE = 1e18;
```

### MAX_PRIORITY_FEE

```solidity
uint64 internal constant MAX_PRIORITY_FEE = type(uint64).max;
```

### MIN_PRIORITY_FEE

<i>
  $0.10 in six-decimal USDC base units. Async Swap pools are configured with USDC as numeraire.
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

<a id="checkminimum-state-book-poolid-bool-bool-uint256-uint256" />

### checkMinimum

Reverts unless the order is worth at least the pool's minimum in the numeraire: a buy's
input; a sell's minimum output and its input at the pool's current price. The price
check keeps out sells that ask for the minimum but offer almost nothing.

```solidity
function checkMinimum(
        State storage self,
        Book storage book,
        PoolId poolId,
        bool isBuy,
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOutMin
    ) internal view;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `State` |  |
| book | `Book` |  |
| poolId | `PoolId` |  |
| isBuy | `bool` |  |
| zeroForOne | `bool` |  |
| amountIn | `uint256` |  |
| amountOutMin | `uint256` |  |

<a id="setminorder-book-poolid-uint256" />

### setMinOrder

```solidity
function setMinOrder(Book storage book, PoolId poolId, uint256 minimum) internal;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| book | `Book` |  |
| poolId | `PoolId` |  |
| minimum | `uint256` |  |

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

Maker-only price update. The executor (router) is required to be authorized by
the maker, AND `caller` must equal `order.owner` — both checked here.

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
  Settle gross output (native only; ERC20 is pre-settled), pay the signed net minimum to the maker, and mint fee
  claims to the vault. Burn input claims and pay the full input to the filler.
  Both currency deltas net to zero. A failed fill reverts all legs.
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

<a id="_pricekey-bool-uint256-uint256" />

### \_priceKey

<i>
  WAD-scaled price ratio bounded to the radix key range: a ratio that rounds to zero
  maps to 1 and a ratio above uint128 saturates at the maximum.
</i>

```solidity
function _priceKey(bool isBuy, uint256 amountIn, uint256 amountOut) private pure returns (uint128);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| isBuy | `bool` |  |
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
event OrderFeeAccrued(bytes32 indexed orderId, Currency indexed currency, uint256 amount);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
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

### MinOrderSet

```solidity
event MinOrderSet(PoolId indexed poolId, uint256 minOrder);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| poolId | `PoolId` |  |
| minOrder | `uint256` |  |

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

### Book

```solidity
struct Book {
        uint64 nextSequence;
        uint64 openOrderCount;
        RadixPriceTree.Tree bids;
        RadixPriceTree.Tree asks;
        mapping(uint128 price => PriceLevel) bidLevels;
        mapping(uint128 price => PriceLevel) askLevels;
        /// @dev Least order size in numeraire base units (0: none); see `checkMinimum`.
        uint256 minOrder;
    }
```

**Properties**

| Name | Type | Description |
| ---- | ---- | ----------- |
| nextSequence | `uint64` |  |
| openOrderCount | `uint64` |  |
| bids | `RadixPriceTree.Tree` |  |
| asks | `RadixPriceTree.Tree` |  |
| bidLevels | `mapping(uint128 price => PriceLevel)` |  |
| askLevels | `mapping(uint128 price => PriceLevel)` |  |
| minOrder | `uint256` |  |
