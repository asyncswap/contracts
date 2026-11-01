# FeeVault

[Git Source](https://github.com/asyncswap/contracts/blob/c13cd5a3947c45e1887698ad62cbb0175b5bf594/src/FeeVault.sol)

Holds and redeems protocol fee claims, never maker escrow.

## Constants

### poolManager

```solidity
IPoolManager public immutable poolManager;
```

### hook

```solidity
IFeeOwner public immutable hook;
```

## Functions

<a id="constructor-ipoolmanager" />

### constructor

```solidity
constructor(IPoolManager manager);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| manager | `IPoolManager` |  |

<a id="collect-currency-address" />

### collect

The current protocol owner may redeem all fees of one currency.

```solidity
function collect(Currency currency, address recipient) external;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| currency | `Currency` |  |
| recipient | `address` |  |

<a id="unlockcallback-bytes" />

### unlockCallback

<i>
  PoolManager only calls this vault back during its own collection unlock.
</i>

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

## Events

### FeesCollected

```solidity
event FeesCollected(Currency indexed currency, address indexed recipient, uint256 amount);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| currency | `Currency` |  |
| recipient | `address` |  |
| amount | `uint256` |  |

## Errors

### Unauthorized

```solidity
error Unauthorized();
```

### ZeroAddress

```solidity
error ZeroAddress();
```
