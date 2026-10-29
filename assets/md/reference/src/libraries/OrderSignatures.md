# OrderSignatures

[Git Source](https://github.com/asyncswap/contracts/blob/9e8cf35f5e2c6a55c344fd3f18722f08518bf9f4/src/libraries/OrderSignatures.sol)

**Title:** OrderSignatures

**Author:** @msakiart

EIP-712 types for signed AsyncSwap actions. Every type spells out the maker, both tokens
and the amounts so wallets render a readable message instead of opaque calldata.

* `AsyncOrder` is the Permit2 witness for `Router.swapWithSig` (Permit2 domain).
* `SetExecutor` and `UpdatePrice` are verified by the hook (AsyncSwap domain).
* `CancelOrder` is verified by the Router (AsyncSwap Router domain).

## Constants

### POOL_KEY_TYPE

```solidity
bytes internal constant POOL_KEY_TYPE =
        "PoolKey(address currency0,address currency1,uint24 fee,int24 tickSpacing,address hooks)";
```

### ASYNC_ORDER_TYPE

```solidity
bytes internal constant ASYNC_ORDER_TYPE =
        "AsyncOrder(address maker,address tokenIn,address tokenOut,uint256 amountIn,uint256 amountOutMin,uint256 priorityFee,PoolKey pool)";
```

### POOL_KEY_TYPEHASH

```solidity
bytes32 internal constant POOL_KEY_TYPEHASH = keccak256(POOL_KEY_TYPE);
```

### ASYNC_ORDER_TYPEHASH

```solidity
bytes32 internal constant ASYNC_ORDER_TYPEHASH = keccak256(abi.encodePacked(ASYNC_ORDER_TYPE, POOL_KEY_TYPE));
```

### PERMIT2_WITNESS_TYPE

Witness type string appended by Permit2 to `PermitWitnessTransferFrom(...)`.
Referenced types are sorted alphabetically per EIP-712.

```solidity
string internal constant PERMIT2_WITNESS_TYPE = string(
        abi.encodePacked(
            "AsyncOrder witness)", ASYNC_ORDER_TYPE, POOL_KEY_TYPE, "TokenPermissions(address token,uint256 amount)"
        )
    );
```

### SET_EXECUTOR_TYPEHASH

```solidity
bytes32 internal constant SET_EXECUTOR_TYPEHASH = keccak256(
        abi.encodePacked(
            "SetExecutor(address maker,address executor,bool allow,PoolKey pool,uint256 nonce,uint256 deadline)",
            POOL_KEY_TYPE
        )
    );
```

### UPDATE_PRICE_TYPEHASH

```solidity
bytes32 internal constant UPDATE_PRICE_TYPEHASH = keccak256(
        "UpdatePrice(address maker,address tokenIn,address tokenOut,uint256 amountIn,uint256 newAmountOutMin,bytes32 orderId,uint64 sequence,uint256 nonce,uint256 deadline)"
    );
```

### CANCEL_ORDER_TYPEHASH

```solidity
bytes32 internal constant CANCEL_ORDER_TYPEHASH = keccak256(
        "CancelOrder(address maker,address tokenIn,address tokenOut,uint256 amountIn,bytes32 orderId,uint64 createdSequence,uint256 nonce,uint256 deadline)"
    );
```

## Functions

<a id="tokens-asyncorder" />

### tokens

```solidity
function tokens(AsyncOrder memory order) internal pure returns (address tokenIn, address tokenOut);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| tokenIn | `address` |  |
| tokenOut | `address` |  |

<a id="hashpoolkey-poolkey" />

### hashPoolKey

```solidity
function hashPoolKey(PoolKey memory key) internal pure returns (bytes32);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| key | `PoolKey` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `bytes32` |  |

<a id="hashorder-asyncorder" />

### hashOrder

Struct hash of the order a maker signs as the Permit2 witness. Covers everything that
defines the order; `sqrtPrice` is excluded (the hook consumes the whole swap, so v4
never reads the price limit) and `salt` is assigned by the hook at create time.

```solidity
function hashOrder(AsyncOrder memory order) internal pure returns (bytes32);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `bytes32` |  |

<a id="hashsetexecutor-poolkey-address-address-bool-uint256-uint256" />

### hashSetExecutor

```solidity
function hashSetExecutor(
        PoolKey memory key,
        address maker,
        address executor,
        bool allow,
        uint256 nonce,
        uint256 deadline
    ) internal pure returns (bytes32);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| key | `PoolKey` |  |
| maker | `address` |  |
| executor | `address` |  |
| allow | `bool` |  |
| nonce | `uint256` |  |
| deadline | `uint256` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `bytes32` |  |

<a id="hashupdateprice-asyncorder-bytes32-uint256-uint256-uint64-uint256-uint256" />

### hashUpdatePrice

```solidity
function hashUpdatePrice(
        AsyncOrder memory order,
        bytes32 orderId,
        uint256 amountIn,
        uint256 newAmountOutMin,
        uint64 sequence,
        uint256 nonce,
        uint256 deadline
    ) internal pure returns (bytes32);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |
| orderId | `bytes32` |  |
| amountIn | `uint256` | the order's stored input, so the maker sees the size of the order they reprice. |
| newAmountOutMin | `uint256` |  |
| sequence | `uint64` | The order's queue sequence, which every reprice and every recreation moves on, so a<br />signature can neither undo a later reprice nor apply to an identical replacement. |
| nonce | `uint256` |  |
| deadline | `uint256` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `bytes32` |  |

<a id="hashcancel-asyncorder-bytes32-uint256-uint64-uint256-uint256" />

### hashCancel

<i>
  Carries a nonce: order ids can recur (identical order re-placed in the same block after a
  cancel), so order deletion alone does not stop a signed cancel from being replayed.
</i>

```solidity
function hashCancel(
        AsyncOrder memory order,
        bytes32 orderId,
        uint256 amountIn,
        uint64 createdSequence,
        uint256 nonce,
        uint256 deadline
    ) internal pure returns (bytes32);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |
| orderId | `bytes32` |  |
| amountIn | `uint256` |  |
| createdSequence | `uint64` |  |
| nonce | `uint256` |  |
| deadline | `uint256` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `bytes32` |  |
