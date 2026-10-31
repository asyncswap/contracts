# BatchActions

[Git Source](https://github.com/asyncswap/contracts/blob/ffcca30f5d858d6f9a022187cceed4cdfe76b79a/src/BatchActions.sol)

Cancels the caller's orders and redeems the caller's ERC-6909 PoolManager claims
atomically in one PoolManager unlock.

<i>
  Before cancelling, the maker must authorize this contract as an executor on the hook
  for each order's pool. Before redeeming, the maker must authorize this contract as a
  PoolManager operator. Either action can be omitted by passing an empty array.
</i>

## Constants

### poolManager

```solidity
IPoolManager public immutable poolManager;
```

### hook

```solidity
AsyncSwap public immutable hook;
```

## State Variables

### activeOwner

```solidity
address private activeOwner;
```

## Functions

<a id="constructor-ipoolmanager-asyncswap" />

### constructor

```solidity
constructor(IPoolManager manager, AsyncSwap orderHook);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| manager | `IPoolManager` |  |
| orderHook | `AsyncSwap` |  |

<a id="execute-asyncorder-currency-uint256-address" />

### execute

Perform either or both actions. All operations succeed or the transaction reverts.

```solidity
function execute(
        AsyncOrder[] calldata orders,
        Currency[] calldata currencies,
        uint256[] calldata amounts,
        address recipient
    ) external;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| orders | `AsyncOrder[]` | Open orders owned by msg.sender to cancel (maximum 50). |
| currencies | `Currency[]` | Claim currencies to redeem; address(0) denotes native ETH (maximum 16). |
| amounts | `uint256[]` | Raw claim amounts corresponding to currencies. |
| recipient | `address` | Address receiving redeemed ETH/ERC20 tokens. |

<a id="unlockcallback-bytes" />

### unlockCallback

<i>
  PoolManager calls this only during execute. Cancels first so newly returned claims
  can be redeemed in the same unlock if the caller included their amounts.
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

### InvalidBatch

```solidity
error InvalidBatch();
```

### NotOwner

```solidity
error NotOwner();
```

### WrongHook

```solidity
error WrongHook();
```

### OnlyPoolManager

```solidity
error OnlyPoolManager();
```
