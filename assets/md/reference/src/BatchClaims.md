# BatchClaims

[Git Source](https://github.com/asyncswap/contracts/blob/2047394fa89cda4ed8f617b9d3c53de5e873ac09/src/BatchClaims.sol)

Atomically redeems a caller's PoolManager ERC-6909 claims for several currencies.

<i>
  The caller must first make this contract an operator on PoolManager. The operator
  permission is used only for claims owned by msg.sender and paid to their recipient.
</i>

## Constants

### poolManager

```solidity
IPoolManager public immutable poolManager;
```

## State Variables

### \_redeeming

```solidity
bool private _redeeming;
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

<a id="nonreentrant" />

### nonReentrant

```solidity
modifier nonReentrant();
```

<a id="redeem-currency-address-uint256" />

### redeem

```solidity
function redeem(Currency[] calldata currencies, address recipient, uint256[] calldata amounts)
        external
        nonReentrant;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| currencies | `Currency[]` |  |
| recipient | `address` |  |
| amounts | `uint256[]` |  |

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

## Events

### ClaimRedeemed

```solidity
event ClaimRedeemed(address indexed owner, address indexed recipient, Currency indexed currency, uint256 amount);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| owner | `address` |  |
| recipient | `address` |  |
| currency | `Currency` |  |
| amount | `uint256` |  |

## Errors

### OnlyPoolManager

```solidity
error OnlyPoolManager();
```

### InvalidRedemption

```solidity
error InvalidRedemption();
```

### ReentrantRedemption

```solidity
error ReentrantRedemption();
```
