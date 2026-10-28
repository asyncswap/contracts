# Price keys and crossing

## Price keys

Every resting order is indexed on its pool's book by a `uint128` price key computed in
`AsyncFiller._priceKey` (`TickPrice.key`): the Uniswap v4 tick of the order's exact limit.

1. Take the order's currency1/currency0 ratio: `amountOutMin / amountIn` when it sells currency0,
   `amountIn / amountOutMin` when it sells currency1.
2. Take its floor tick: the largest tick `t` (spacing 1, price `1.0001^t`) priced at or below the
   ratio (`TickPrice.floorTick`, via `TickMath.getTickAtSqrtPrice`).
3. Order ticks by numeraire per asset: `t - MIN_TICK + 1` when the numeraire is currency1,
   `MAX_TICK - t + 1` when it is currency0.

Keys run from `1` to `2 * MAX_TICK + 1`. Ratios outside the v4 price range (about `2^-128` to
`2^128`) share the end keys. Each level is 0.01% wide at any price and for any token decimals,
so two orders sharing a nonclamped key are within approximately 0.01% of each other.
The end levels do not have this spread bound. The exact limit stays on the order:
keys order the radix tree; they do not by themselves decide whether two orders trade.

## Crossing rule

`AsyncMatching._crosses(buyKey, sellKey, buy, sell)` decides whether a buy and a sell can trade:

* `buyKey > sellKey` is a cross and `buyKey < sellKey` is not. The key is monotone in the exact
  price, so a strict ordering of keys always reflects a strict ordering of exact prices.
* Equal keys are decided at full precision:

```
cross  <=>  buyIn / buyOut >= sellOut / sellIn
       <=>  buyIn * sellIn >= sellOut * buyOut
       <=>  floor(buyIn * sellIn / sellOut) >= buyOut      (sellOut and buyOut are nonzero)
```

implemented as `Math.mulDiv(buy.amountIn, sell.amountIn, sell.amountOutMin) >= buy.amountOutMin`.
Orders cannot be created or updated with a zero minimum, so the divisor is never zero. Both escrowed inputs are bounded by signed 128-bit settlement amounts, so their product and
its quotient by a positive minimum fit in 256 bits, including at clamped end levels.

An exact tie (`buyIn * sellIn == sellOut * buyOut`) counts as a cross and executes.

## Consequences

* Equal-key noncrossing heads no longer terminate selection when another pair is eligible.
  Each priority subtree stores its minimum exact ask or maximum exact bid. The search chooses
  the higher-priority child if its summary admits a crossing order, otherwise the other child.
  Each lookup traverses at most 128 branches without scanning or persistent cursors.
* Automatic arrivals and resting-book matching use the same selection rule: the exact highest
  bid and exact lowest ask in their best levels. The subtree extremum is the eligibility threshold,
  so only orders at that exact extremum qualify; remaining fee and sequence break exact-price ties.
  If these extrema do not cross, no pair at the boundary crosses. Prices grouped in the same level
  never let a worse exact price jump ahead by paying more.
* Every genuine cross, including the tie, produces a non-zero match in `_matchAmounts` that pays
  each maker at least their signed minimum for the input consumed. This was checked exhaustively
  for small amounts and on randomized large near-tie pairs.
* Matching compares the signed minimums, not the post-fee proceeds, so the 0.02% trade fee (taken
  from each side's proceeds afterwards, rounded up) never changes which orders cross.

Example of equal keys without a cross: a sell asking `1000.05` and a buy offering `1000.02`
USDC per asset sit on the same tick, but the buy is below the ask, so the pair rests.

## Tests

`test/security/PriceKeyCrossing.t.sol`:

* `test_equalKeyNonCrossingPairDoesNotBlockMatching`
* `test_matchBookMakesNoFalseMatch`
* `test_exactTieExecutes`

## Level width and the price-priority bound

Within one tick, priority is bid then sequence, not exact price, so a higher-bid order can trade
ahead of one priced up to 0.01% better. Across ticks, price always comes first. Under the earlier
WAD-ratio key a level was `10^(assetDecimals - usdcDecimals - 18)` USDC/asset wide, which is
about 10% of the price for an 18-decimal asset at $0.00001, and the clamped keys `1` and
`type(uint128).max` merged arbitrarily distant prices (audit 2026-10-23, finding 1). Ticks remove
both: the width is relative and fixed, and only prices outside the v4 range share the end keys.

## Historical counterexample and repaired regression

`test/security/CoarsePriceBlocking.t.sol` creates a pool with an 18-decimal asset and 6-decimal
USDC fixture at 1,000 USDC/asset, minimum order 1 USDC, and no active LP liquidity. A sell
offering `2e15 - 1` asset base units for `2_000_000` USDC base units has the same key as a
1,000 USDC/asset order, but a slightly higher exact ask. Its `100_001`-unit bid outranks the
`100_000`-unit bids of 20 honest sells. Under the previous head-only policy, twenty matching buys stopped at that blocker, and 100
retries made no progress. The Python `legacy_matching=True` mode preserves that baseline.

With exact eligibility, the same twenty buys execute against the honest sells without cancelling
or outbidding the blocker. The blocker remains open, preserving its escrow and bid. The updated
`CoarsePriceBlockingTest` asserts that outcome through the real Router/hook/PoolManager, and tests
the mirrored incoming-sell case. Generated `EligiblePythonVectors.t.sol` exercises normal prices,
both clamps, blockers on both sides, mutations, partial fills, balances and fee claims.

With tick keys the blocker above is one level worse than the honest asks, so it cannot outrank
them at all. A level is 0.01% of the price wide. That bounds price separation, not delay or backlog.
The repaired selector guarantees finding a crossing pair in a valid book when one exists;
successful settlement and transaction submission remain required. It does not guarantee that
every low-priority order eventually fills under continuing higher-priority arrivals.

The companion model is in the local uv4 checkout under `src/uv4/priority_protocol/`, with results
and explicit modeling boundaries in `docs/priority_protocol/`. `PriorityPythonVectors.t.sol` checks
100 independently generated Python matching cases against the real matcher;
`PriorityPythonHashes.t.sol` checks order identities and signature struct hashes.

## Maintenance, gas, and verification boundaries

`EligiblePrice.sol` compares full 512-bit cross products and stores two-word exact bounds at
priority-tree nodes. Append/remove repair the affected ancestor path. Every partial fill refreshes
the bound even if neither the tick key nor the remaining fee changes. New storage is appended
to each price level; existing live trees would need their summaries initialized before using this
code. These local changes have not been deployed.

The protocol-controlled index work is O(128 M) for M matches. Eight is the existing per-call cap,
not a per-transaction cap. Token code and external settlement costs are outside this structural
bound. `EligibleGas.t.sol` measures composed batches through a real unlock; no numerical
worst-case gas certificate or universally optimal batch size is claimed.

The updated whitepaper is in the local `asyncswap/whitepaper` checkout. Its new section contains
integer safety and search arguments, gas curves, and the constrained parameter objective.
