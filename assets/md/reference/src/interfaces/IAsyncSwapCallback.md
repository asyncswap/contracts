# IAsyncSwapCallback

[Git Source](https://github.com/asyncswap/contracts/blob/84f3d45a9d5fd5044b514fe8372b641bb2c45527/src/interfaces/IAsyncSwapCallback.sol)

**Title:** IAsyncSwapCallback

The Router's callback fill surface: `fillOrderWithCallback` opens a fill and calls the filler back
(`IAsyncSwapFlashFiller.asyncSwapFlashFill`); the `...InCallback` functions are the only Router calls
accepted while that callback runs, and only from its filler. Every other Router entry point reverts
`FlashFillActive` until the callback returns.

## Functions

<a id="fillorderwithcallback-asyncorder-uint256-bytes" />

### fillOrderWithCallback

Fill `order` with no inventory: input first as claims, callback, then the owed output as claims.
Every fill in the callback (this one and each `fillOrderInCallback`) owes the MEV tax, paid to the
FeeVault when the fill runs. `msg.value` prepays it, any amount; the filler may also pay inside its
callback with `PoolManager.settleFor(router)`. A surplus is returned to the filler in ETH and a
shortfall reverts `MevTaxUnpaid`.

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
The filler pays the order's minimum output plus any live Dutch auction premium (`auctionPremium` on the
hook), and approves the Router for both; `maxPrice` bounds the total.

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

<a id="mevtaxfor-uint256" />

### mevTaxFor

MEV tax for `fills` fills at this transaction's priority fee. Off chain, simulate with the gas price
you will send (`eth_call` with `gasPrice`); on chain it is exact for the running transaction.

```solidity
function mevTaxFor(uint256 fills) external view returns (uint256);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| fills | `uint256` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `uint256` |  |

<a id="mevtaxowed" />

### mevTaxOwed

Inside the callback: the MEV tax the Router still owes for this flash fill, every fill charged so far
less what was paid. Settle exactly this with `PoolManager.settleFor(router)` before returning.

```solidity
function mevTaxOwed() external view returns (uint256);
```

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `uint256` |  |
