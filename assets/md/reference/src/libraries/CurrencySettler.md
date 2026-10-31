# CurrencySettler

[Git Source](https://github.com/asyncswap/contracts/blob/ffcca30f5d858d6f9a022187cceed4cdfe76b79a/src/libraries/CurrencySettler.sol)

**Title:** CurrencySettler

Production copy of v4-core's test-only `CurrencySettler`, using safe transfers so tokens
that return no data from `transfer` / `transferFrom` (e.g. USDT) settle correctly.

## Functions

<a id="settle-currency-ipoolmanager-address-uint256-bool" />

### settle

Settle (pay) a currency to the PoolManager.

```solidity
function settle(Currency currency, IPoolManager manager, address payer, uint256 amount, bool burn) internal;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| currency | `Currency` |  |
| manager | `IPoolManager` |  |
| payer | `address` |  |
| amount | `uint256` |  |
| burn | `bool` | If true, burn the payer's ERC-6909 claims instead of transferring tokens. |

<a id="take-currency-ipoolmanager-address-uint256-bool" />

### take

Take (receive) a currency from the PoolManager.

```solidity
function take(Currency currency, IPoolManager manager, address recipient, uint256 amount, bool claims) internal;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| currency | `Currency` |  |
| manager | `IPoolManager` |  |
| recipient | `address` |  |
| amount | `uint256` |  |
| claims | `bool` | If true, mint ERC-6909 claims instead of transferring tokens. |
