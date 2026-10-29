# BatchCancels

[Git Source](https://github.com/asyncswap/contracts/blob/e578e5b3753d37bfd6053629c8aed4ad3d31df45/src/BatchCancels.sol)

Cancels several orders owned by the caller in one PoolManager unlock.

<i>
  Makers must authorize this contract as an executor for each order's pool.
</i>

## Constants

### poolManager

```solidity
IPoolManager public immutable poolManager;
```

### hook

```solidity
AsyncSwap public immutable hook;
```

## State Variables

### cancellingOwner

```solidity
address private cancellingOwner;
```

## Functions

<a id="constructor-ipoolmanager-asyncswap" />

### constructor

```solidity
constructor(IPoolManager manager, AsyncSwap orderHook);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| manager | `IPoolManager` |  |
| orderHook | `AsyncSwap` |  |

<a id="cancelorders-asyncorder" />

### cancelOrders

```solidity
function cancelOrders(AsyncOrder[] calldata orders) external;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| orders | `AsyncOrder[]` |  |

<a id="unlockcallback-bytes" />

### unlockCallback

```solidity
function unlockCallback(bytes calldata data) external returns (bytes memory);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| data | `bytes` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `bytes` |  |

## Errors

### InvalidBatch

```solidity
error InvalidBatch();
```

### NotOwner

```solidity
error NotOwner();
```

### OnlyPoolManager

```solidity
error OnlyPoolManager();
```
