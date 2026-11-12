# IncomingMatching

[Git Source](https://github.com/asyncswap/contracts/blob/245c06bce0aea780bf783eff9b5e05cd627266fc/src/libraries/IncomingMatching.sol)

Fund a crossing arrival, match it in memory, then index only its remainder.

<i>
  Active LP pools retain the existing storage path. Pending orders cannot match before funding.
</i>

## Constants

### STAGE

```solidity
bytes32 private constant STAGE = keccak256("asyncswap.incoming.record");
```

### POOL

```solidity
bytes32 private constant POOL = keccak256("asyncswap.incoming.pool");
```

### ID

```solidity
bytes32 private constant ID = keccak256("asyncswap.incoming.id");
```

## Functions

<a id="pending-poolid" />

### pending

```solidity
function pending(PoolId poolId) public view returns (bool result);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| poolId | `PoolId` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| result | `bool` |  |

<a id="addorder-asyncfiller-state-asyncfiller-book-asyncfiller-neworder" />

### addOrder

<i>
  Shared stored-admission wrapper. Keeping it here avoids duplicating admission
  bytecode in AsyncMatching, which only needs reductions and settlement for existing orders.
</i>

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

<a id="stage-asyncfiller-state-asyncfiller-book-asyncfiller-neworder" />

### stage

```solidity
function stage(AsyncFiller.State storage self, AsyncFiller.Book storage book, AsyncFiller.NewOrder memory order)
        public;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| book | `AsyncFiller.Book` |  |
| order | `AsyncFiller.NewOrder` |  |

<a id="_cancross-asyncfiller-book-asyncfiller-neworder" />

### \_canCross

<i>
  Resting-only arrivals keep ordinary admission. The memory bridge pays off when
  an opposite order crosses; repeat full selection after funding because callbacks can reprice.
</i>

```solidity
function _canCross(AsyncFiller.Book storage book, AsyncFiller.NewOrder memory order) private view returns (bool);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| book | `AsyncFiller.Book` |  |
| order | `AsyncFiller.NewOrder` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `bool` |  |

<a id="matchneworder-asyncfiller-state-asyncfiller-book-asyncorder-bytes32" />

### matchNewOrder

<i>
  Delegatecall keeps escrow and the LP self-call in the hook context, while moving
  venue orchestration out of the hook's size-constrained runtime. Funding/auth stay in the Router/hook.
</i>

```solidity
function matchNewOrder(
        AsyncFiller.State storage self,
        AsyncFiller.Book storage book,
        AsyncOrder calldata order,
        bytes32 id
    ) public returns (uint8 matched);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| book | `AsyncFiller.Book` |  |
| order | `AsyncOrder` |  |
| id | `bytes32` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| matched | `uint8` |  |

<a id="_poolbeatsbook-asyncfiller-state-asyncfiller-book-poolkey-bool" />

### \_poolBeatsBook

<i>
  The pool goes first only while its adjusted price beats the best opposite level.
  An equal level or empty opposite side leaves the book first; the existing LP limit is unchanged.
</i>

```solidity
function _poolBeatsBook(
        AsyncFiller.State storage self,
        AsyncFiller.Book storage book,
        PoolKey calldata key,
        bool isBuy
    ) private view returns (bool, uint160);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| book | `AsyncFiller.Book` |  |
| key | `PoolKey` |  |
| isBuy | `bool` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `bool` |  |
| \<none> | `uint160` |  |

<a id="_matchpending-asyncfiller-state-asyncfiller-book-poolkey-bytes32-address" />

### \_matchPending

```solidity
function _matchPending(
        AsyncFiller.State storage self,
        AsyncFiller.Book storage book,
        PoolKey calldata key,
        bytes32 id,
        address owner
    ) private returns (bool handled, uint8 matched);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| book | `AsyncFiller.Book` |  |
| key | `PoolKey` |  |
| id | `bytes32` |  |
| owner | `address` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| handled | `bool` |  |
| matched | `uint8` |  |

<a id="_load-bytes32-address" />

### \_load

```solidity
function _load(bytes32 id, address owner) private returns (AsyncFiller.OrderInfo memory incoming);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| id | `bytes32` |  |
| owner | `address` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| incoming | `AsyncFiller.OrderInfo` |  |

<a id="_crosses-asyncfiller-state-asyncfiller-orderinfo-bytes32-bytes32-bytes32" />

### \_crosses

```solidity
function _crosses(
        AsyncFiller.State storage self,
        AsyncFiller.OrderInfo memory incoming,
        bytes32 id,
        bytes32 bid,
        bytes32 ask
    ) private view returns (bool);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| incoming | `AsyncFiller.OrderInfo` |  |
| id | `bytes32` |  |
| bid | `bytes32` |  |
| ask | `bytes32` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `bool` |  |

<a id="_persist-asyncfiller-state-asyncfiller-book-bytes32-asyncfiller-orderinfo" />

### \_persist

```solidity
function _persist(
        AsyncFiller.State storage self,
        AsyncFiller.Book storage book,
        bytes32 id,
        AsyncFiller.OrderInfo memory info
    ) private;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| book | `AsyncFiller.Book` |  |
| id | `bytes32` |  |
| info | `AsyncFiller.OrderInfo` |  |

<a id="_best-asyncfiller-state-asyncfiller-book-asyncfiller-orderinfo-bytes32-bool" />

### \_best

```solidity
function _best(
        AsyncFiller.State storage self,
        AsyncFiller.Book storage book,
        AsyncFiller.OrderInfo memory incoming,
        bytes32 id,
        bool buy
    ) private view returns (bytes32);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| book | `AsyncFiller.Book` |  |
| incoming | `AsyncFiller.OrderInfo` |  |
| id | `bytes32` |  |
| buy | `bool` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `bytes32` |  |

<a id="_match-asyncfiller-state-asyncfiller-book-poolkey-bytes32-asyncfiller-orderinfo-bytes32-bytes32-claimtransfers-batch" />

### \_match

```solidity
function _match(
        AsyncFiller.State storage self,
        AsyncFiller.Book storage book,
        PoolKey calldata key,
        bytes32 id,
        AsyncFiller.OrderInfo memory incoming,
        bytes32 bid,
        bytes32 ask,
        ClaimTransfers.Batch memory batch
    ) private returns (bool);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| book | `AsyncFiller.Book` |  |
| key | `PoolKey` |  |
| id | `bytes32` |  |
| incoming | `AsyncFiller.OrderInfo` |  |
| bid | `bytes32` |  |
| ask | `bytes32` |  |
| batch | `ClaimTransfers.Batch` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `bool` |  |

<a id="_reduce-asyncfiller-state-asyncfiller-book-poolkey-bytes32-asyncfiller-orderinfo-uint256-claimtransfers-batch" />

### \_reduce

```solidity
function _reduce(
        AsyncFiller.State storage self,
        AsyncFiller.Book storage book,
        PoolKey calldata key,
        bytes32 id,
        AsyncFiller.OrderInfo memory info,
        uint256 consumed,
        ClaimTransfers.Batch memory batch
    ) private returns (uint256 refund);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| book | `AsyncFiller.Book` |  |
| key | `PoolKey` |  |
| id | `bytes32` |  |
| info | `AsyncFiller.OrderInfo` |  |
| consumed | `uint256` |  |
| batch | `ClaimTransfers.Batch` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| refund | `uint256` |  |
