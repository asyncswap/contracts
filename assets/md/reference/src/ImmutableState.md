# ImmutableState

[Git Source](https://github.com/asyncswap/contracts/blob/7cc0f3471ba542b534750d8031a5ccf41b883551/src/ImmutableState.sol)

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
