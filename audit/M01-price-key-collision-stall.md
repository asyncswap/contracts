# M01 — Price-key collision wedges the matching engine

| | |
|---|---|
| **Severity** | Medium |
| **Status** | Fixed |
| **Component** | `src/libraries/AsyncMatching.sol` (`matchIncoming`, `matchBook`), `src/libraries/AsyncFiller.sol` (`_priceKey`) |
| **Impact** | Liveness / griefing on the automatic matching engine. No loss of funds. |
| **Regression test** | `test/audit/M01_PriceKeyCollisionStall.t.sol` |

## Summary

Order crossing was decided by comparing two `uint128` WAD price keys, each produced by a
truncating `mulDiv` in `AsyncFiller._priceKey`. Two orders can round to the **same** key while, at
full precision, they do **not** cross. When that happens `AsyncMatching._matchAmounts` correctly
refuses the trade and returns `(0,0)`, so `_matchPair` returns `false`. Both `matchIncoming` and
`matchBook` responded to a `false` result with `break`.

Because the offending pair sits at the **best bid and the best ask**, every later `matchBook` call
broke immediately and every new order crossing that top pair failed to match and simply rested. The
permissionless matching engine — the protocol's core mechanism — could be wedged at the top of book.

## Root cause

A truncated `uint128` key cannot represent the exact ratio `amountOutMin / amountIn`. Two distinct
ratios can floor to the same key. The crossing test compared those lossy keys directly, so a pair
that only *appears* to cross (an artifact of truncation) entered the match attempt, failed the exact
arithmetic in `_matchAmounts`, and triggered a `break` that the engine never recovered from.

### Concrete witness

| Order | `amountIn` | `amountOutMin` | WAD key |
|---|---:|---:|---|
| Buy (`zeroForOne = false`) | `3e18 + 1` | `1e18` | `3000000000000000001` |
| Sell (`zeroForOne = true`) | `1e18 - 1` | `3e18 - 2` | `3000000000000000001` |

The keys are equal, so the old code saw a cross. The exact test is false by one unit:

```
buyIn * sellIn  = 2999999999999999997999999999999999999
sellOut * buyOut = 2999999999999999998000000000000000000   (larger -> no real cross)
```

An attacker controls both of their own orders' amounts, so the colliding pair is crafted
deliberately. The capital is fully refundable via cancel, so the cost is essentially gas.

## Impact

No funds can be stolen, and individual orders can still be filled through `fillOrder` (external
filler) or `fillFromPoolLiquidity`. What breaks is the promise that crossing orders settle
automatically: the permissionless `matchBook` progress can be halted at the top of book cheaply and
repeatably, and non-clearing crossed orders accumulate there. Rated **Medium** (liveness/griefing).

## Fix

`AsyncMatching._crosses` trusts the keys only when they are **strictly ordered** — truncation can
never invert a strict inequality, so `buyKey > sellKey` always implies a genuine cross and
`buyKey < sellKey` always implies no cross. The only ambiguous case is **equal keys**, which is
decided with a full-precision cross-multiply:

```
cross  <=>  buyIn/buyOut >= sellOut/sellIn
       <=>  buyIn * sellIn >= sellOut * buyOut
       <=>  floor(buyIn * sellIn / sellOut) >= buyOut      (sellOut, buyOut are nonzero)
```

implemented as `Math.mulDiv(buy.amountIn, sell.amountIn, sell.amountOutMin) >= buy.amountOutMin`.
When the keys are equal the quotient is on the order of `buyOut`, so the `mulDiv` cannot overflow
for any realistic escrowed amount, and the exact check runs only on that boundary — the common,
strictly-ordered path keeps the cheap key comparison.

**House-always-wins rounding.** The exact tie `buyIn * sellIn == sellOut * buyOut` is treated as a
cross (`>=`), so the protocol always executes an available trade rather than leaving value resting in
a crossed book. Exhaustive search over all small integers plus ~1,000,000 randomized large crossing
pairs and the tightest-cross boundary confirms that **every** genuine cross (including the tie)
produces a non-zero, minimum-respecting match in `_matchAmounts` — so no stall remains, and each
maker is always paid at least their signed limit for the input consumed. Direct order-to-order
matches are a pure swap of the two escrowed inputs (zero protocol fee, exact conservation), so the
protocol is never the party that loses a rounding sub-unit.

## Tests

`test/audit/M01_PriceKeyCollisionStall.t.sol`:

- `test_M01_keyCollisionDoesNotWedgeBook` — a key-colliding non-crossing pair at the top of book
  does not prevent a genuinely crossing order from matching.
- `test_M01_matchBookMakesNoFalseMatch` — `matchBook` on a book holding only the colliding pair
  returns `0` and leaves both orders intact (correct: they do not cross), never fabricating a trade.
- `test_M01_exactTieExecutes` — an exact tie at equal keys executes instead of resting.

Full suite after the fix: **144 passing** (141 original + 3 new), including the matching invariants
at 64 runs / depth 64 with fail-on-revert.

## Related (not fixed here)

`_priceKey` saturates extreme ratios to `1` or `type(uint128).max`. Distinct extreme-ratio orders
therefore collapse onto the same boundary key. The exact-cross tie-break above neutralizes the
resulting false crossings for matching, but mis-prioritization among genuinely different saturated
prices remains possible. Consider rejecting orders whose true ratio falls outside the representable
range rather than silently saturating. Tracked separately as **L-series**.
