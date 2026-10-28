# ImmutableState

[Git Source](https://github.com/asyncswap/contracts/blob/996c1e5bc0203720c76f3ad0406a08db4650f3b5/src/ImmutableState.sol)

**Title:** Immutable State

A collection of immutable state variables, commonly used across multiple contracts

## Constants

### poolManager

```solidity
IPoolManager public immutable poolManager;
```

## Functions

<a id="onlypoolmanager" />

### onlyPoolManager

Only allow calls from the PoolManager contract

```solidity
modifier onlyPoolManager();
```

<a id="constructor-ipoolmanager" />

### constructor

```solidity
constructor(IPoolManager _poolManager);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \_poolManager | `IPoolManager` |  |

## Errors

### NotPoolManager

Thrown when the caller is not PoolManager

```solidity
error NotPoolManager();
```
