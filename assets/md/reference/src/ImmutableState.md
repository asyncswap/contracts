# ImmutableState

[Git Source](https://github.com/asyncswap/contracts/blob/d2dedce1007d645b3f34f1db1ddd883a354ea298/src/ImmutableState.sol)

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
