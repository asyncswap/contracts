# FM-01: Best-price routing sends the whole order through the pool past better book liquidity

| | |
|---|---|
| Severity | Medium |
| Status | ✅ Fixed in this branch |
| Found by | Formal Mind swarm (assistant, Pashov lenses), confirmed by hand |
| Location | `src/AsyncSwap.sol` `matchNewOrder` and `_poolBeatsBook`; `src/libraries/AsyncMatching.sol` `_swapAgainstPool` |
| PoC | `test/formal/RoutingPoolImpact.t.sol` |

## Summary

`matchNewOrder` picks which venue fills a new order first with `_poolBeatsBook`, which compares only the pool's
**spot** tick with the best resting order on the other side. When the spot is better by even one tick, the whole
order is swapped through the pool, and that swap's only price limit is the maker's own `amountOutMin`. The pool fill
is all-or-nothing, so its price impact can take the order's average price far past a resting order that would have
filled it, and that resting order is never touched.

## Impact

A taker gets a much worse fill than the book offers, while a maker whose order sits at the better price is skipped.
Nothing is stolen, and the taker's `amountOutMin` bounds the loss, but routing is the protocol's promise ("best of
pool and book"), and a loose minimum is common. In the PoC, Bob buys with 10 USDC against a thin pool (10 ether of
full-range liquidity) at spot 1.0 while Alice asks 10 asset for 10.02 USDC: the pool is one-tick better at spot, so
Bob gets about **5** asset instead of the **9.98** Alice's ask gives, and Alice's ask stays untouched.

## Root cause

```solidity
bool poolFirst = _poolBeatsBook(order.key, state.orders[id].isBuy); // spot tick vs best level only
...
try this.fillOrderFromPoolLiquidity(order, id) {} catch {}          // swap limit: MIN/MAX_SQRT_PRICE
```

`_swapAgainstPool` swapped with `zeroForOne ? MIN_SQRT_PRICE + 1 : MAX_SQRT_PRICE - 1`, so nothing stopped the pool
swap at the book's price.

## Fix

When the pool goes first, its swap is limited at the best book level:

- `_poolBeatsBook` also returns that level as a sqrt price, mapping the book key back to a pool tick (the inverse of
  the mapping it already uses) and taking `TickMath.getSqrtPriceAtTick`.
- `matchNewOrder` calls a new self-only `fillOrderFromPoolLiquidityWithin(order, id, sqrtPriceLimitX96)`, which
  passes the limit through `AsyncMatching.fillFromPoolLiquidity` to `_swapAgainstPool` (0 keeps the old MIN/MAX
  limit).
- A swap that reaches the limit stops short and reverts as `PartialLiquidityFill` (the pool fill stays
  all-or-nothing). `matchNewOrder` already catches it, so the book matches the order instead.

`fillOrderFromPoolLiquidity(order, id)` keeps its signature and behaviour for the Router's and executors' retries. So
does the pool-second path, which runs only after the book has taken what it can.

## Residual

The limit bounds the pool's marginal price before its LP fee, so a pool-first fill can still end a fee's width worse
than the book level. Splitting an order between the pool (up to the level) and the book would be the full answer, but
it needs a partial pool fill, which this change deliberately leaves out.

## Tests

- `test_poolSpotBetterNoLongerTakesWholeOrderPastTheBook`: the PoC's scenario. Before the fix Bob got under 5.1 asset
  and the ask was untouched; now he gets over 9.9 and the ask takes the order.
- `test_poolStillTakesAnOrderItFillsBeforeTheBookLevel`: a small buy that moves the pool only a few ticks is still
  filled by the pool, and the ask is left alone.
- `forge test`: 885 passed, 0 failed.

The Lean spec of `_poolBeatsBook` (`formal/Proofs/Swarm/AsyncSwapPoolBeatsBook.lean`) proves the old return type;
the swarm re-proves it from the new source on its next run.
