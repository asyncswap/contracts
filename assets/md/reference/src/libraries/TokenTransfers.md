# TokenTransfers

[Git Source](https://github.com/asyncswap/contracts/blob/cc20ad373bc4ca8ed8dd664a6393434575cb1bd8/src/libraries/TokenTransfers.sol)

Require full ERC-20 delivery without charging extra to the sender; token-reported success is insufficient.

## Functions

<a id="snapshot-address-address-address" />

### snapshot

```solidity
function snapshot(address token, address from, address to) internal view returns (Balances memory balances);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| token | `address` |  |
| from | `address` |  |
| to | `address` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| balances | `Balances` |  |

<a id="verify-address-address-address-uint256-balances" />

### verify

```solidity
function verify(address token, address from, address to, uint256 amount, Balances memory before) internal view;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| token | `address` |  |
| from | `address` |  |
| to | `address` |  |
| amount | `uint256` |  |
| before | `Balances` |  |

<a id="transferfrom-address-address-address-uint256" />

### transferFrom

```solidity
function transferFrom(address token, address from, address to, uint256 amount) internal;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| token | `address` |  |
| from | `address` |  |
| to | `address` |  |
| amount | `uint256` |  |

<a id="verifydebit-address-address-uint256-uint256" />

### verifyDebit

<i>
  PoolManager verifies deposit credit at settlement. Preserve CurrencyNotSettled for short deposits.
</i>

```solidity
function verifyDebit(address token, address from, uint256 amount, uint256 before) internal view;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| token | `address` |  |
| from | `address` |  |
| amount | `uint256` |  |
| before | `uint256` |  |

<a id="transfer-address-address-uint256" />

### transfer

```solidity
function transfer(address token, address to, uint256 amount) internal;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| token | `address` |  |
| to | `address` |  |
| amount | `uint256` |  |

<a id="bubbleunsupported-bytes" />

### bubbleUnsupported

<i>
  A liquidity miss may leave an order resting; an unsupported token must fail the caller explicitly.
</i>

```solidity
function bubbleUnsupported(bytes memory reason) internal pure;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| reason | `bytes` |  |

<a id="take-ipoolmanager-currency-address-uint256" />

### take

```solidity
function take(IPoolManager manager, Currency currency, address to, uint256 amount) internal;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| manager | `IPoolManager` |  |
| currency | `Currency` |  |
| to | `address` |  |
| amount | `uint256` |  |

## Errors

### TokenNotSupported

```solidity
error TokenNotSupported(address token);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| token | `address` |  |

## Structs

### Balances

```solidity
struct Balances {
        uint256 from;
        uint256 to;
    }
```

**Properties**

| Name | Type | Description |
| ---- | ---- | ----------- |
| from | `uint256` |  |
| to | `uint256` |  |
