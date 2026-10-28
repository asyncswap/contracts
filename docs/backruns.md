# Backruns and the backrun premium

A large order that fills against pool liquidity moves the pool price. Whoever trades the price back
earns the difference: a **backrun**. Without a charge, that profit goes entirely to the backrunner,
and the LPs whose liquidity absorbed both trades lose it. Since v1.1.0 the hook charges a **backrun
premium** on pool fills that move the price back, and splits it between the LPs and the protocol.

The premium applies only to pool fills (`fillFromPoolLiquidity`, including the pool attempt when a new
order arrives). Book matches and filler fills settle at the orders' signed limits, move no pool price
and pay no premium.

## How it works

The logic is in [`BackrunPremium.sol`](../src/libraries/BackrunPremium.sol), a linked library that
`AsyncMatching` calls after every pool fill.

1. **Reference.** Each pool stores a reference tick and the block it was set in
   (`AsyncFiller.State.refTick`, `refBlock`). The first pool fill after the window has expired records
   the pool's tick from *before* that fill as the new reference, and pays no premium.
2. **Window.** The reference holds for `BACKRUN_WINDOW` = 2 blocks after the block that set it. A pool
   fill after that starts a new window.
3. **Premium.** A pool fill inside the window that ends closer to the reference than it started pays

   ```text
   premium = min(amountOut × (gapBefore + gapAfter) / 40_000, amountOut / 2)
   ```

   where `gapBefore` and `gapAfter` are the distances, in ticks, from the reference to the pool's tick
   before and after the fill. If the fill crosses the reference, `gapAfter` is 0: the part past the
   reference closes no gap. One tick is about 0.01%, so `(gapBefore + gapAfter) / 2` is the average
   price gap over the fill in basis points, and the premium is **half the price gap the fill closes**.
4. **No premium** for a fill that moves the price further from the reference, or doesn't move it.
5. **Split.** Half the premium is donated to in-range LPs (`PoolManager.donate`). The other half, plus
   any rounding, is credited to the FeeVault as ERC-6909 claims. If no liquidity is in range after the
   fill, all of it goes to the FeeVault.
6. **Maker protection.** The premium is taken from the fill's output before the maker is paid, and the
   output that remains must still meet the order's minimum. Otherwise the pool fill reverts, and the
   order goes to the book or rests, exactly as when a pool fill misses its limit for any other reason.

The 0.01% protocol fee on the input and the 0.02% LP fee still apply to every pool fill; the premium
is on top of them.

## Example

From [`test/BackrunCapture.t.sol`](../test/BackrunCapture.t.sol), a pool at 1 USDC per asset with deep
liquidity:

| | Before v1.1.0 | v1.1.0 |
|---|---|---|
| Alice sells 2,000 asset into the pool | price drops | price drops; reference set |
| Bob buys back with the USDC Alice received, same block | | pays the premium |
| Bob's profit, valued at the pre-sell price | 3.39 USDC | 1.34 USDC |
| LPs and FeeVault capture from Bob's backrun | about 0.6 USDC (fees only) | 2.65 USDC |

Bob still profits, so pools keep getting brought back to the market price, but most of the gap now
stays with the LPs and the protocol.

## Splitting a backrun

A premium charged per swap invites splitting: several small backruns each pay a lower rate. Here the
premium depends on the gap at each fill's start and end, not on how many fills there are. Splitting
one backrun into several orders pays roughly the same total, because each piece pays on the part of
the gap it closes. In the test, five orders earn 1.38 USDC against 1.34 for one; the small difference
comes from averaging the gap linearly in ticks while the pool's price curve is not linear.

## What it doesn't cover

- **The premium is in the output currency.** A backrun that buys the asset pays its premium in the
  asset; one that sells the asset pays in USDC. Valued at the reference price, the two are the same.
- **Only within the window.** A backrun that lands more than 2 blocks after the fill that set the
  reference pays nothing. On chains with short block times, such as Unichain, that's a few seconds.
- **One reference per window.** If several large fills happen in one window, they're all measured
  against the price before the first one.
- **It's an estimate.** The gap is measured in ticks against the pool's own earlier price, not against
  an outside market price. A fill that moves the pool back after the outside market really moved
  still pays within the window.
- **Not yet in the Lean proofs.** The Foundry tests and the uv4 Python model cover it.

## Deployment

`BackrunPremium` is linked into `AsyncMatching`, which is linked into the hook. `script/deploy.sh`
deploys it through the shared CREATE2 deployer (`script/00_DeployBackrunPremium.s.sol`, salt
`asyncswap.v2.BackrunPremium`) before `AsyncMatching`, and records it in `deployments/<chainId>/`.
