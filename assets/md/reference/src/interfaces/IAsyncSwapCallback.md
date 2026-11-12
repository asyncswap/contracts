# IAsyncSwapCallback

[Git Source](https://github.com/asyncswap/contracts/blob/d4dd306239445175911ee1e7a9b5f0cf55ee69df/src/interfaces/IAsyncSwapCallback.sol)

**Title:** IAsyncSwapCallback

The Router's callback fill surface: `fillOrderWithCallback` opens a fill and calls the filler back
(`IAsyncSwapFlashFiller.asyncSwapFlashFill`); the `...InCallback` functions are the only Router calls
accepted while that callback runs, and only from its filler. Every other Router entry point reverts
`FlashFillActive` until the callback returns.

## Functions

<a id="fillorderwithcallback-asyncorder-uint256-bytes" />

### fillOrderWithCallback

Fill `order` with no inventory: input first as claims, callback, then the owed output as claims.

```solidity
function fillOrderWithCallback(AsyncOrder calldata order, uint256 maxPrice, bytes calldata data) external payable;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |
| maxPrice | `uint256` |  |
| data | `bytes` |  |

<a id="fillorderincallback-asyncorder-uint256" />

### fillOrderInCallback

Inside the callback: fill another open order, paying its output and receiving its input as claims.

```solidity
function fillOrderInCallback(AsyncOrder calldata order, uint256 maxPrice) external;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |
| maxPrice | `uint256` |  |

<a id="matchbookincallback-poolkey-uint8" />

### matchBookInCallback

Inside the callback: continue a crossed book.

```solidity
function matchBookInCallback(PoolKey calldata key, uint8 maxMatches) external returns (uint8);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| key | `PoolKey` |  |
| maxMatches | `uint8` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `uint8` |  |
