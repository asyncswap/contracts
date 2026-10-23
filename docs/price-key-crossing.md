# Price keys and crossing

## Price keys

Every resting order is indexed on its pool's book by a `uint128` price key computed in
`AsyncFiller._priceKey`:

| Side | Key |
|---|---|
| Buy (`isBuy`, maker escrows the numeraire) | `floor(amountIn * 1e18 / amountOutMin)` |
| Sell | `floor(amountOutMin * 1e18 / amountIn)` |

A ratio that rounds to zero maps to `1`, and a ratio above `type(uint128).max` saturates at the
maximum. The key is a truncated WAD ratio, so two orders with different exact prices can share a key.
Keys order the radix tree; they do not by themselves decide whether two orders trade.

## Crossing rule

`AsyncMatching._crosses(buyKey, sellKey, buy, sell)` decides whether a buy and a sell can trade:

- `buyKey > sellKey` is a cross and `buyKey < sellKey` is not. Truncation is monotone, so a strict
  ordering of keys always reflects a strict ordering of exact prices.
- Equal keys are decided at full precision:

```
cross  <=>  buyIn / buyOut >= sellOut / sellIn
       <=>  buyIn * sellIn >= sellOut * buyOut
       <=>  floor(buyIn * sellIn / sellOut) >= buyOut      (sellOut and buyOut are nonzero)
```

implemented as `Math.mulDiv(buy.amountIn, sell.amountIn, sell.amountOutMin) >= buy.amountOutMin`.
Orders cannot be created or updated with a zero minimum, so the divisor is never zero. With equal
keys the quotient is on the order of `buyOut`, so the division cannot overflow for escrowable
amounts.

An exact tie (`buyIn * sellIn == sellOut * buyOut`) counts as a cross and executes.

## Consequences

- Equal-key noncrossing heads no longer terminate selection when another pair is eligible.
  Each priority subtree stores its minimum exact ask or maximum exact bid. The search chooses
  the higher-priority child if its summary admits a crossing order, otherwise the other child.
  Each lookup traverses at most 128 branches without scanning or persistent cursors.
- Incoming matching chooses the highest-priority eligible opposing order at the best bucket.
  Resting-book matching chooses the highest-priority buy crossing any ask in the boundary
  bucket, then the highest-priority ask crossing that buy. This buy-first lexicographic policy
  retains fee/sequence priority among feasible pairs; it does not optimize global volume.
- Every genuine cross, including the tie, produces a non-zero match in `_matchAmounts` that pays
  each maker at least their signed minimum for the input consumed. This was checked exhaustively
  for small amounts and on randomized large near-tie pairs.
- Direct order-to-order matches swap the two escrowed inputs with no protocol fee, so rounding never
  moves value to or from the protocol.

Example of equal keys without a cross:

| Order | `amountIn` | `amountOutMin` | Key |
|---|---:|---:|---|
| Buy | `3e18 + 1` | `1e18` | `3000000000000000001` |
| Sell | `1e18 - 1` | `3e18 - 2` | `3000000000000000001` |

`buyIn * sellIn` is one unit below `sellOut * buyOut`, so the pair does not cross and rests.

## Tests

`test/security/PriceKeyCrossing.t.sol`:

- `test_equalKeyNonCrossingPairDoesNotBlockMatching`
- `test_matchBookMakesNoFalseMatch`
- `test_exactTieExecutes`

## Saturation

Distinct extreme ratios collapse onto the boundary keys `1` and `type(uint128).max`. The exact
equal-key test still decides crossing correctly for them, but priority among different saturated
prices follows priority bid and then sequence rather than exact price. The ordinary bucket-width
bound does not apply to the saturated upper bucket; key `1` merges the zero and one bins.

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

For ordinary buckets, human price width is `10^(assetDecimals - usdcDecimals - 18)` USDC/asset:
**0.000001 USDC/asset** for 18/6 decimals. That bounds price separation, not delay or backlog.
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
the bound even if neither the coarse key nor the remaining fee changes. New storage is appended
to each price level; existing live trees would need their summaries initialized before using this
code. These local changes have not been deployed.

The protocol-controlled index work is O(128 M) for M matches. Eight is the existing per-call cap,
not a per-transaction cap. Token code and external settlement costs are outside this structural
bound. `EligibleGas.t.sol` measures composed batches through a real unlock; no numerical
worst-case gas certificate or universally optimal batch size is claimed.

The updated whitepaper is in the local `asyncswap/whitepaper` checkout. Its new section contains
integer safety and search arguments, gas curves, and the constrained parameter objective.
