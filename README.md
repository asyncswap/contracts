![Async Swap](docs/assets/async-swap-banner.png)

# Async Swap

Async Swap is an on-chain order book and matching engine built as a Uniswap v4 hook. Traders set a limit price for assets paired with USDC. Orders can match with other traders or available pool liquidity. Anyone can permissionlessly fill orders, and anyone can open a USDC pool on the hook. The minimum order, the cap on the required nonzero priority bid, and the asset floor are fixed when the hook is deployed, so the owner cannot change pool rules under live orders.

Book matching prioritizes price, with higher escrowed USDC bids breaking same-price ties and earlier submissions breaking equal-bid ties. Each side of a book match or filler fill receives its proceeds less a 0.02% protocol fee, so a maker receives at least its minimum output minus 0.02%; fills against pool liquidity pay active LPs 0.02% and the protocol 0.01%, and a pool fill that moves the price back toward where it stood before that pool's first fill of a 2-block window pays a dynamic fee of about half the backrun's profit, split between LPs and the protocol (dynamic fee ordering; tracked per pool). Order creation and fills also pay an MEV tax on the transaction's priority fee, credited to the protocol, so a transaction sent with no priority fee pays nothing and searchers racing for position pay most of their bids to the protocol. Unfilled amounts remain open for later execution, repricing, or cancellation; fills depend on available liquidity and counterparties.

## Documentation

Published at **[docs.asyncswap.org](https://docs.asyncswap.org)**: these guides, the audit status and a contract
reference generated from the NatSpec in `src/`. The site (`site/`, built with [vocs](https://vocs.dev)) rebuilds on
every push to `main` that touches them; preview it locally with `cd site && bun install && bun run dev`.

- [Protocol overview](docs/protocol.md): components, custody, order placement, authorization, and deployment.
- [Order lifecycle and priority bids](docs/order-lifecycle.md): matching, fills, cancellation, and bid settlement.
- [Contract call sequences](docs/contract-call-sequences.md): calls, callbacks, responses, and withdrawals.
- [Price-key crossing](docs/price-key-crossing.md): price comparisons and rounding.
- [Dynamic fee ordering](docs/dynamic-fee-ordering.md): the dynamic fee on pool fills that backrun a price move, and who receives it. Open question: does charging half the price gap capture enough of a backrun's MEV for LPs and the protocol, or should the right to backrun a pool fill be auctioned through USDC priority bids, the way book matching already auctions ordering?

## Build and deployment

`AsyncMatching` is an external Solidity library linked into the hook. The deployment wrapper deploys and links `TickPrice`, `DynamicFeeOrdering`, `TickBitmap`, and `EligiblePrice` first. `script/deploy.sh <chain-key> [dry-run|broadcast|verify]` deploys the libraries through the shared CREATE2 deployer, links the hook bytecode, mines the hook salt, deploys the hook and Router, and records the addresses under `deployments/<chainId>/`. `verify` publishes sources through Sourcify, tries Blockscout, and writes standard JSON inputs for manual upload. An `ASYNC_MATCHING_LIBRARY_ADDRESS` override must match this build's predicted address. Foundry links the libraries automatically in tests.

The bitmap changes the order-book storage layout and requires a new hook deployment. Existing radix state cannot be reused as bitmap state. The default compiler remains solc 0.8.26.

Install dependencies and run the contract suite with:

```sh
forge soldeer install
FOUNDRY_INVARIANT_RUNS=64 FOUNDRY_INVARIANT_DEPTH=64 forge test
```

## Benchmarks

Measured on 2026-11-05 through the actual Router/hook settlement path, comparing the radix baseline with the bitmap implementation. The fixture has 256 distinct resting ask levels and distinct owners, with no LP liquidity. Each operation starts from the same committed state on local Anvil using Cancun rules and a 30M gas block limit.

| Operation | Radix baseline gas | Bitmap gas | Reduction |
| --- | ---: | ---: | ---: |
| Place at a new price level | 584,885 | 486,702 | 16.79% |
| Cancel | 246,336 | 191,955 | 22.08% |
| Reprice to a new level | 377,954 | 309,336 | 18.16% |
| Incoming order filling eight makers | 2,962,260 | 2,793,022 | 5.71% |

Transaction receipts include intrinsic gas and applied refunds; setup and approvals are excluded. All 38 public-API state comparisons matched across different book sizes, both trading directions, crowded ticks and LP-routing fixtures. Savings depend on the workload: crowded-tick operations used approximately 0.5–2.1% more gas in the separate gross-call measurements. These are local gas measurements, not production throughput guarantees.

Reproduce the comparison with Python 3.12+, Foundry/Anvil and the repository dependencies installed. Choose a new output directory outside the checkout:

```sh
python3 benchmarks/orderbook/run.py --output /tmp/async-swap-book-benchmark
```

See [methodology and validation](benchmarks/orderbook/README.md), [receipt data](benchmarks/orderbook/results/receipts.json), and [all workload results](benchmarks/orderbook/results/coverage.csv). The earlier standalone matching-harness block-packing numbers are not used to describe the Router/hook's performance.

## Priority fees and future matching work

An order's USDC priority bid breaks ties between equal exact limit prices. This is separate from the transaction's gas priority fee. Zero bids are allowed; for a nonzero bid, the required minimum is 0.1% of the order's USDC notional, rounded down and capped at $0.10 with the default six-decimal numeraire configuration. Users may bid more than that minimum.

**Fee top-ups are proposed, not implemented.** A maker-authorized top-up could escrow additional USDC and update the order's priority entry without changing its input budget or limit price. It would improve queue position among equal-price orders; it would not create liquidity or guarantee execution. Existing priority bids are spent proportionally on fills, with the remainder forfeited on cancellation or dust closure to the FeeVault. They are not a direct keeper reward, so a top-up alone would not solve backlog-clearing incentives. Funding, amendment authorization and tie-priority rules need their own implementation and tests.

The current matcher already processes up to eight pairs per call and combines claim transfers. A uniform-price batch auction would additionally change when orders clear and which price they receive. It remains a separate research direction; no batch-auction gas or execution-quality improvement has been demonstrated for these contracts. See [the research notes](benchmarks/orderbook/research.md).
