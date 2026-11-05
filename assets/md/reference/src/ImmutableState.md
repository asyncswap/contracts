# ImmutableState

[Git Source](https://github.com/asyncswap/contracts/blob/1389863a5546dee090eb3cb462f95789363b47fe/src/ImmutableState.sol)

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
