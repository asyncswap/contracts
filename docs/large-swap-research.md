# Large-swap research

Async Swap focuses on large swaps in volatile pairs, where executing against an AMM curve can make price impact a material part of the cost. This research asks whether opposite-direction flow often arrives soon enough to meet a resting order instead.

## What the studies found

- **One Uniswap v3 ETH/USDC pool, October 2026:** $100,000–$1 million swaps averaged 26.5 bps in fees and price impact, versus 5.5 bps for swaps under $10,000. Opposite flow covered 82% of large-swap volume within five minutes and 99% within an hour. The study estimated $651,000–$768,000 in potential savings for that month and pool. ([Part 1](https://x.com/asyncswap/article/2120701882377060839))
- **Eight major Uniswap v3 pools, November 2025–October 2026:** $100,000–$1 million swaps incurred $59.7 million in pool fees and price impact. Matching opposite flow was estimated to avoid $22.7–$40.7 million of that cost. Matchable flow varied by pool; stablecoin flow was less two-sided than deep ETH and BTC pools. ([Part 2](https://x.com/asyncswap/article/2120704799087714634))
- **Uniswap v4, November 2025–October 2026:** Specialized hooks made some targeted markets cheap (1.3–2.2 bps), while no-hook ETH pools still cost 24.0–38.7 bps for large swaps. Opposite flow covered 49–67% of large-swap volume in five minutes and 85–88% within an hour in those ETH pools. ([Part 3](https://x.com/asyncswap/article/2120713673639436417))

## What this means for Async Swap

The research points to a timing gap, not a universal lack of liquidity: large volatile-pair trades may pay to move the AMM price now even when opposite-direction flow appears later. Stablecoin pools and specialized hooks can already make some markets cheap. The remaining opportunity is volatile pairs without a hook built for that market.

Async Swap lets a maker name a price and leave a good-till-cancelled order on-chain. Opposing orders can meet at the resting price as they arrive; pool liquidity can fill the order when it offers better value. The goal is to let large orders meet over time instead of requiring every trade to sweep the curve immediately.

## Limits of the estimates

The potential savings are upper bounds from historical flow, not realized Async Swap results. They assume opposite-direction trades wait and match at the pre-swap pool price; some observed opposite flow may be arbitrage that would not rest. Actual execution depends on order behavior, counterparties, market movement, and fees. The analysis does not guarantee fills, lower costs, or future fee revenue.

For how Async Swap redirects some ordering and backrun MEV, see [dynamic fee ordering](/protocol/dynamic-fee-ordering).
