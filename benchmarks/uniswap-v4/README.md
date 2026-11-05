# Plain Uniswap v4 swap capacity comparison

Measured on 2026-11-05 using the same **30,000,000-gas local block budget**,
Cancun rules, compiler and transaction gas-limit policy as the
[Async Swap crossing tests](../crossing/README.md).

The simple v4 pool fit **250–288 swaps in its first block**, compared with
**44–51 Async Swap single-fill transactions** or **10–12 eight-fill transactions**.
These are observed local workloads, not a fixed capacity or TPS limit for either
protocol. Async Swap itself uses v4; this compares a plain AMM pool with the
additional work performed by the order-book hook.

## Measured baseline

| Core test adapter | Direction | First-block swaps | Mean receipt gas | First 100 swaps' gas |
|---|---|---:|---:|---:|
| PoolSwapTest | Buy asset | 250 | 119,366.2 | 11,950,300 |
| PoolSwapTest | Sell asset | 250 | 119,371.2 | 11,950,800 |
| SwapRouterNoChecks | Buy asset | 288 | 103,714.2 | 10,385,100 |
| SwapRouterNoChecks | Sell asset | 288 | 103,739.2 | 10,387,600 |

All **2,000 independently submitted swaps** succeeded across four workloads.
Each workload queued 500 swaps before mining, so the first block was filled
while additional transactions remained pending. Every workload drained in two
blocks; all 100 of its first swaps fit in the first block.

The first transaction uses 17,100 more gas than subsequent swaps in this fixture.
Per-swap receipt gas ranges from 103,680 to 120,805 for the minimal adapter and
119,332 to 136,437 for the checked adapter. The table reports means over all 500
transactions, not just a favorable sample.

## What differs

| Workload | Work per transaction | First-block transactions |
|---|---|---:|
| Plain v4 baseline | One single-hop AMM swap, input/output ERC-20 settlement | 250–288 |
| Async Swap single fill | Create an order, escrow its bid, match one maker, settle claims and fees | 44–51 |
| Async Swap eight fills | Create an order, escrow its bid, match eight makers, update the book and settle claims/fees | 10–12 |

Twelve eight-fill transactions settle 96 pairs. That is still twelve
transactions, and a matched order pair does not perform identical work to an
AMM swap. These results show that the extra order-book work has a measurable
cost; they do not establish equal execution prices, liquidity, or trade quality.

Uniswap describes v4's singleton PoolManager and flash accounting in its
[official architecture documentation](https://developers.uniswap.org/docs/protocols/v4/concepts/architecture)
and [flash-accounting documentation](https://developers.uniswap.org/docs/protocols/v4/concepts/flash-accounting).
Those design descriptions are not the source of these capacity numbers; the
numbers come from the retained local receipts.

## Scope and controls

- Same PoolManager dependency used by the Async Swap fixture, pinned to v4-core
  commit `46c6834698c48bc4a463a86d8420f4eb1d7f3b75`. Compile with solc 0.8.26,
  optimizer 10,000 runs and Cancun, rather than claiming deployed-mainnet bytecode costs.
- No hook, one pool, one hop, 0.3% LP fee, deep full-range liquidity. Initial price
  is approximately 1,000 quote tokens (six decimals) per asset token (18 decimals). Each sell
  inputs one asset; each buy inputs 1,000 quote tokens. This is a reference notional,
  not a claim of identical net value after fees and price movement.
- No initialized liquidity ticks are crossed. Tick changes within the range are
  not initialized-tick crossings. Tick-heavy swaps, hooks and multihop routes are
  unmeasured and can change the gas costs.
- 500 unique users per workload, all prefunded with both mock ERC-20s. Existing
  nonzero output balances avoid first-time balance initialization costs.
  Setup, LP funding and approvals are excluded from the measured swaps.
- Automining disabled; FIFO queue; fixed transaction gas limit equal to 120% of
  the first gas estimate, rounded up to 1,000. This is the same policy as the
  crossing benchmark. Gas-limit reservations affect packing, so these are not
  mathematically maximal block counts. Receipt gas includes intrinsic gas and refunds.
- The two adapters are the official core repository's
  [`SwapRouterNoChecks`](https://github.com/Uniswap/v4-core/blob/46c6834698c48bc4a463a86d8420f4eb1d7f3b75/src/test/SwapRouterNoChecks.sol)
  and [`PoolSwapTest`](https://github.com/Uniswap/v4-core/blob/46c6834698c48bc4a463a86d8420f4eb1d7f3b75/src/test/PoolSwapTest.sol).
  **Neither is Universal Router.** The minimal adapter lacks production
  minimum-output/deadline checks; the checked adapter adds test-only balance
  assertions. These are core baselines, not the Uniswap app's transaction costs.
- Plain swaps transfer ERC-20 outputs immediately. Async Swap book matches issue
  claims whose later withdrawal is excluded from its crossing measurements.
  Therefore this is a workload comparison, not identical end-to-end user flows.

## Verification and reproduction

Each receipt must succeed and contain exactly one expected-pool Swap event.
Checks verify exact input, positive plausible output, unchanged active liquidity,
configured fee, all wallet balances, aggregate pool token conservation, zero
adapter token balances, and every block's enforced gas limit.

```sh
python3 benchmarks/uniswap-v4/run.py
```

Requires Python 3, Foundry and the existing repository dependencies. It starts
only disposable loopback Anvil nodes, uses no wallet keys, and broadcasts no
public-chain transactions. Four fixture exports pass before measurements.

`results/summary.json` records the versions, assumptions, gas limits, blocks
and validation outcomes. `results/<workload>.json.gz` retains all full receipts
and logs. Production contract sources are unchanged. This comparison does not
close Async Swap's unmet 100-crossing-transactions-per-block target.
