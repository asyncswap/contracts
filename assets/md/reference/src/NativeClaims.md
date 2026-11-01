# NativeClaims

[Git Source](https://github.com/asyncswap/contracts/blob/2047394fa89cda4ed8f617b9d3c53de5e873ac09/src/NativeClaims.sol)

Redeems the caller's PoolManager native ETH claims to a chosen recipient.

<i>
  Approve this contract for native claim ID 0 on PoolManager before redeeming.
  Claim ownership and allowances are enforced by PoolManager.burn. No hook escrow is accessible.
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

<a id="nonreentrant" />

### nonReentrant

```solidity
modifier nonReentrant();
```

<a id="constructor-ipoolmanager" />

### constructor

```solidity
constructor(IPoolManager manager);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| manager | `IPoolManager` |  |

<a id="redeem-address-uint256" />

### redeem

```solidity
function redeem(address recipient, uint256 amount) external nonReentrant;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| recipient | `address` |  |
| amount | `uint256` |  |

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

### NativeRedeemed

```solidity
event NativeRedeemed(address indexed owner, address indexed recipient, uint256 amount);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| owner | `address` |  |
| recipient | `address` |  |
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
