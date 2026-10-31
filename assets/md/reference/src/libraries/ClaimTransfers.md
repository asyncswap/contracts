# ClaimTransfers

[Git Source](https://github.com/asyncswap/contracts/blob/97cbdf27bf322f5109418f442275172e22ad8711/src/libraries/ClaimTransfers.sol)

<i>
  At most 16 makers and the FeeVault can each receive two currencies in eight matches.
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
        Credit[34] credits;
        uint256 count;
    }
```

**Properties**

| Name | Type | Description |
| ---- | ---- | ----------- |
| credits | `Credit[34]` |  |
| count | `uint256` |  |
