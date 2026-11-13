# IAsyncSwapFlashFiller

[Git Source](https://github.com/asyncswap/contracts/blob/6aa19f681f6dcda07dbe32d621088bdd4be8da99/src/interfaces/IAsyncSwapFlashFiller.sol)

**Title:** IAsyncSwapFlashFiller

Callback a filler contract implements to use `Router.flashFill`.

## Functions

<a id="asyncswapflashfill-asyncorder-uint256-uint256-bytes" />

### asyncSwapFlashFill

Called by the Router inside its PoolManager unlock, after the order was closed and its input,
less the 0.02% trade fee, credited to the filler as ERC-6909 claims (`amountIn` of the input
currency, id 0 for native ETH).

<i>
  `amountOwed` is the order's minimum output plus any live Dutch auction premium; the Router pays the minimum
  to the hook and the premium to the maker. Before returning, the filler must hold `amountOwed` claims of the
  order's output currency and allow the Router to transfer them (`PoolManager.approve(router, id, amountOwed)` or an operator grant). Inside
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
