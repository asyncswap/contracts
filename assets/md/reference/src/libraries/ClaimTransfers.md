# ClaimTransfers

[Git Source](https://github.com/asyncswap/contracts/blob/d2f73e537656f99998496fd813462294fa8cd4c8/src/libraries/ClaimTransfers.sol)

<i>
  At most 16 makers can receive two currencies, plus one FeeVault, in eight matches.
</i>

## Functions

<a id="credit-batch-ipoolmanager-currency-address-uint256" />

### credit

```solidity
function credit(Batch memory batch, IPoolManager manager, Currency currency, address recipient, uint256 amount)
        internal;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| batch | `Batch` |  |
| manager | `IPoolManager` |  |
| currency | `Currency` |  |
| recipient | `address` |  |
| amount | `uint256` |  |

<a id="flush-batch-ipoolmanager" />

### flush

```solidity
function flush(Batch memory batch, IPoolManager manager) internal;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| batch | `Batch` |  |
| manager | `IPoolManager` |  |

## Structs

### Credit

```solidity
struct Credit {
        Currency currency;
        address recipient;
        uint256 amount;
    }
```

**Properties**

| Name | Type | Description |
| ---- | ---- | ----------- |
| currency | `Currency` |  |
| recipient | `address` |  |
| amount | `uint256` |  |

### Batch

```solidity
struct Batch {
        Credit[33] credits;
        uint256 count;
    }
```

**Properties**

| Name | Type | Description |
| ---- | ---- | ----------- |
| credits | `Credit[33]` |  |
| count | `uint256` |  |
