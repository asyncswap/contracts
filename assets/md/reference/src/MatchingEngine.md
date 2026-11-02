# MatchingEngine

[Git Source](https://github.com/asyncswap/contracts/blob/bae26ef1448faa2347a1fb13d45436a67057695f/src/MatchingEngine.sol)

**Title:** MatchingEngine

Standalone price-time matching harness. It maintains a radix-indexed
limit book and emits deterministic fill instructions.

<i>
  Algorithm and gas benchmark only: it does not custody or settle tokens.
  Live orders settle through the AsyncSwap hook and AsyncMatching.
</i>

## Constants

### PRICE_SCALE

```solidity
uint128 public constant PRICE_SCALE = 1e18;
```

### MAX_MATCHES_PER_CALL

```solidity
uint8 public constant MAX_MATCHES_PER_CALL = 8;
```

## State Variables

### books

```solidity
mapping(bytes32 market => Book) private books;
```

### entered

```solidity
bool private entered;
```

## Functions

<a id="nonreentrant" />

### nonReentrant

```solidity
modifier nonReentrant();
```

<a id="placeorder-bytes32-bool-uint128-uint128" />

### placeOrder

Submit a limit order. Crossing orders match immediately, up to
eight fills; any remainder rests at its limit price.

```solidity
function placeOrder(bytes32 market, bool isBuy, uint128 amount, uint128 price)
        external
        nonReentrant
        returns (uint64 orderId);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| market | `bytes32` | Identifier for a pair and settlement domain chosen by the caller. |
| isBuy | `bool` | True for a bid, false for an ask. |
| amount | `uint128` | Base quantity in the engine's fixed-point units. |
| price | `uint128` | Quote per base, scaled by 1e18. |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| orderId | `uint64` |  |

<a id="matchbook-bytes32-uint8" />

### matchBook

Continue clearing a crossed book after an order hit its per-call
fill cap. Work is bounded by `maxMatches` and anyone may call it.

```solidity
function matchBook(bytes32 market, uint8 maxMatches) external nonReentrant returns (uint8 matched);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| market | `bytes32` |  |
| maxMatches | `uint8` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| matched | `uint8` |  |

<a id="cancelorder-bytes32-uint64" />

### cancelOrder

```solidity
function cancelOrder(bytes32 market, uint64 orderId) external nonReentrant;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| market | `bytes32` |  |
| orderId | `uint64` |  |

<a id="getorder-bytes32-uint64" />

### getOrder

```solidity
function getOrder(bytes32 market, uint64 orderId) external view returns (Order memory);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| market | `bytes32` |  |
| orderId | `uint64` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `Order` |  |

<a id="bestprice-bytes32-bool" />

### bestPrice

```solidity
function bestPrice(bytes32 market, bool isBuy) external view returns (bool found, uint128 price);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| market | `bytes32` |  |
| isBuy | `bool` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| found | `bool` |  |
| price | `uint128` |  |

<a id="levelordercount-bytes32-bool-uint128" />

### levelOrderCount

```solidity
function levelOrderCount(bytes32 market, bool isBuy, uint128 price) external view returns (uint32);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| market | `bytes32` |  |
| isBuy | `bool` |  |
| price | `uint128` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `uint32` |  |

<a id="_matchincoming-book-bytes32-uint64" />

### \_matchIncoming

```solidity
function _matchIncoming(Book storage book, bytes32 market, uint64 incomingId) private returns (uint8 matched);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| book | `Book` |  |
| market | `bytes32` |  |
| incomingId | `uint64` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| matched | `uint8` |  |

<a id="_fill-book-bytes32-uint64-uint64-uint128-uint128" />

### \_fill

```solidity
function _fill(Book storage book, bytes32 market, uint64 makerId, uint64 takerId, uint128 quantity, uint128 price)
        private;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| book | `Book` |  |
| market | `bytes32` |  |
| makerId | `uint64` |  |
| takerId | `uint64` |  |
| quantity | `uint128` |  |
| price | `uint128` |  |

<a id="_clearbestpair-book-bytes32" />

### \_clearBestPair

```solidity
function _clearBestPair(Book storage book, bytes32 market) private returns (bool);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| book | `Book` |  |
| market | `bytes32` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `bool` |  |

<a id="_clearorders-book-bytes32-uint64-uint64" />

### \_clearOrders

```solidity
function _clearOrders(Book storage book, bytes32 market, uint64 bidId, uint64 askId) private;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| book | `Book` |  |
| market | `bytes32` |  |
| bidId | `uint64` |  |
| askId | `uint64` |  |

<a id="_append-book-uint64" />

### \_append

```solidity
function _append(Book storage book, uint64 orderId) private;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| book | `Book` |  |
| orderId | `uint64` |  |

<a id="_remove-book-uint64" />

### \_remove

```solidity
function _remove(Book storage book, uint64 orderId) private;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| book | `Book` |  |
| orderId | `uint64` |  |

## Events

### OrderPlaced

```solidity
event OrderPlaced(
        bytes32 indexed market,
        uint64 indexed orderId,
        address indexed owner,
        bool isBuy,
        uint128 amount,
        uint128 price,
        uint64 sequence
    );
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| market | `bytes32` |  |
| orderId | `uint64` |  |
| owner | `address` |  |
| isBuy | `bool` |  |
| amount | `uint128` |  |
| price | `uint128` |  |
| sequence | `uint64` |  |

### OrderCancelled

```solidity
event OrderCancelled(bytes32 indexed market, uint64 indexed orderId, address indexed owner);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| market | `bytes32` |  |
| orderId | `uint64` |  |
| owner | `address` |  |

### OrderFilled

```solidity
event OrderFilled(
        bytes32 indexed market,
        uint64 indexed makerOrderId,
        uint64 indexed takerOrderId,
        uint128 amount,
        uint128 price,
        uint256 quoteAmount
    );
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| market | `bytes32` |  |
| makerOrderId | `uint64` |  |
| takerOrderId | `uint64` |  |
| amount | `uint128` |  |
| price | `uint128` |  |
| quoteAmount | `uint256` |  |

## Errors

### ZeroAmount

```solidity
error ZeroAmount();
```

### ZeroPrice

```solidity
error ZeroPrice();
```

### InvalidMatchBound

```solidity
error InvalidMatchBound();
```

### NotOrderOwner

```solidity
error NotOrderOwner();
```

### OrderNotFound

```solidity
error OrderNotFound();
```

### ReentrantCall

```solidity
error ReentrantCall();
```

## Structs

### Order

```solidity
struct Order {
        address owner;
        uint128 price;
        uint128 remaining;
        uint64 sequence;
        uint64 previous;
        uint64 next;
        bool isBuy;
        bool active;
    }
```

**Properties**

| Name | Type | Description |
| ---- | ---- | ----------- |
| owner | `address` |  |
| price | `uint128` |  |
| remaining | `uint128` |  |
| sequence | `uint64` |  |
| previous | `uint64` |  |
| next | `uint64` |  |
| isBuy | `bool` |  |
| active | `bool` |  |

### Level

```solidity
struct Level {
        uint64 head;
        uint64 tail;
        uint32 orderCount;
    }
```

**Properties**

| Name | Type | Description |
| ---- | ---- | ----------- |
| head | `uint64` |  |
| tail | `uint64` |  |
| orderCount | `uint32` |  |

### Book

```solidity
struct Book {
        uint64 nextOrderId;
        uint64 nextSequence;
        RadixPriceTree.Tree bids;
        RadixPriceTree.Tree asks;
        mapping(uint128 price => Level) bidLevels;
        mapping(uint128 price => Level) askLevels;
        mapping(uint64 orderId => Order) orders;
    }
```

**Properties**

| Name | Type | Description |
| ---- | ---- | ----------- |
| nextOrderId | `uint64` |  |
| nextSequence | `uint64` |  |
| bids | `RadixPriceTree.Tree` |  |
| asks | `RadixPriceTree.Tree` |  |
| bidLevels | `mapping(uint128 price => Level)` |  |
| askLevels | `mapping(uint128 price => Level)` |  |
| orders | `mapping(uint64 orderId => Order)` |  |
