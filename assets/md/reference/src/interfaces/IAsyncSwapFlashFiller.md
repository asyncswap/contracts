# IAsyncSwapFlashFiller

[Git Source](https://github.com/asyncswap/contracts/blob/db503f7f95d5ccf59d6e7fcbb0e4507dab24c838/src/interfaces/IAsyncSwapFlashFiller.sol)

**Title:** IAsyncSwapFlashFiller

Callback a filler contract implements to use `Router.flashFill`.

## Functions

<a id="asyncswapflashfill-asyncorder-uint256-uint256-bytes" />

### asyncSwapFlashFill

Called by the Router inside its PoolManager unlock, after the order was closed and its input,
less the 0.02% trade fee, credited to the filler as ERC-6909 claims (`amountIn` of the input
currency, id 0 for native ETH).

<i>
  Before returning, the filler must hold `amountOwed` claims of the order's output currency and allow
  the Router to transfer them (`PoolManager.approve(router, id, amountOwed)` or an operator grant). Inside
  the callback it may swap on any v4 pool, `burn`/`mint`/`take`/`settle`, and fill other Async Swap orders
  through `IAsyncSwapCallback.fillOrderInCallback` and `matchBookInCallback`. Every delta it opens must be zero
  when the Router's unlock ends.
</i>

```solidity
function asyncSwapFlashFill(AsyncOrder calldata order, uint256 amountIn, uint256 amountOwed, bytes calldata data)
        external;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |
| amountIn | `uint256` |  |
| amountOwed | `uint256` |  |
| data | `bytes` |  |
