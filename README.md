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
- [Priority-fee top-ups](docs/priority-fee-top-ups.md): maker authorization, funding, queue updates, and agent calls.
- [Contract call sequences](docs/contract-call-sequences.md): calls, callbacks, responses, and withdrawals.
- [Price-key crossing](docs/price-key-crossing.md): price comparisons and rounding.
- [Dynamic fee ordering](docs/dynamic-fee-ordering.md): the dynamic fee on pool fills that backrun a price move, and who receives it. Open question: does charging half the price gap capture enough of a backrun's MEV for LPs and the protocol, or should the right to backrun a pool fill be auctioned through USDC priority bids, the way book matching already auctions ordering?

## Build and deployment

v1.3.0 is deployed on **Unichain Sepolia** (test USDC) and **Robinhood Chain testnet** (test USDG). See [addresses and previous deployments](docs/deployments.md) and [live top-up validation](benchmarks/releases/README.md). All nine release modules on each network have exact source matches on Sourcify. Mainnet remains subject to [audit and readiness checks](MAINNET_READINESS.md).

`AsyncMatching` is an external Solidity library linked into the hook. The deployment wrapper deploys and links `TickPrice`, `DynamicFeeOrdering`, `TickBitmap`, `EligiblePrice`, and `PriorityFeeUpdates` first. The fee-amendment library links to `EligiblePrice`. `script/deploy.sh <chain-key> [dry-run|broadcast|verify]` deploys the libraries through the shared CREATE2 deployer, links the hook bytecode, mines the hook salt, deploys the hook and Router, and records the addresses under `deployments/<chainId>/`. `verify` publishes sources through Sourcify, tries Blockscout, and writes standard JSON inputs for manual upload. An `ASYNC_MATCHING_LIBRARY_ADDRESS` override must match this build's predicted address. Foundry links the libraries automatically in tests.

The bitmap changes the order-book storage layout and requires a new hook deployment. Existing radix state cannot be reused as bitmap state. The default compiler remains solc 0.8.26.

Install dependencies and run the contract suite with:

```sh
forge soldeer install
FOUNDRY_INVARIANT_RUNS=64 FOUNDRY_INVARIANT_DEPTH=64 forge test
```

## Benchmarks

Measured on 2026-11-05 through the actual Router/hook settlement path, comparing the radix baseline with the bitmap implementation at `1389863`, before the fee top-up endpoint. The fixture has 256 distinct resting ask levels and distinct owners, with no LP liquidity. Each operation starts from the same committed state on local Anvil using Cancun rules and a 30M gas block limit.

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

Fee top-ups measured separately use **186,710–235,267 gas** across four local fixtures, including an initially zero-bid order and a crowded price level. See [the top-up receipt benchmark](benchmarks/topups/README.md) for per-case results and reproduction instructions.

[Local stress validation](benchmarks/stress/README.md) covers matching, liquidity fills,
claim withdrawals and sustained API reads. The [public-testnet ingestion/read soak](benchmarks/soak/README.md)
passed a 10-minute 26-second run on both testnets: 98 transactions, all 96 lifecycle
events reconciled through REST/WebSocket, and 10,016 reads with zero failures
(p95 76.69 ms). This bounded run does not establish maximum capacity or multi-hour resilience.

[Crossing-heavy block tests](benchmarks/crossing/README.md) settled all 1,000
transactions and 5,200 matched pairs correctly. Under a 30-million-gas local
block budget, the first blocks held 44–51 single-fill transactions or 10–12
eight-fill transactions with the documented gas limits. The target of 100
crossing transactions in one block was not met.

For context, a [plain Uniswap v4 comparison](benchmarks/uniswap-v4/README.md)
fit 250–288 single-hop swaps in the first block under the same budget and gas-limit
policy. This uses official core test adapters, deep liquidity and no hook or
initialized-tick crossings; it is not Universal Router or live-network throughput.
The subsequent [Universal Router and periphery benchmark](benchmarks/universal-router/README.md)
fit 244–250 swaps in the first block through released router 2.2.0 and Permit2,
with deadline/minimum-output checks and standing token allowances. Approval
setup and permit signatures are excluded; the route remains single-hop with no hook.

## Priority fees and future matching work

An order's USDC priority bid breaks ties between equal exact limit prices. This is separate from the transaction's gas priority fee. Zero bids are allowed; for a nonzero bid, the required minimum is 0.1% of the order's USDC notional, rounded down and capped at $0.10 with the default six-decimal numeraire configuration. Users may bid more than that minimum.

Makers can call `Router.topUpPriorityFee(order, addedFee)` to escrow additional USDC on an open order. The Router requires the maker's approval and caller identity; the amount is added to the **remaining** bid without changing the order's input budget or limit price. The resulting bid must meet the minimum for the remaining order. A top-up resets time priority within its new fee tier and preserves the original maker age used for settlement pricing. It does not trigger matching; an agent can combine it with `matchBook(key, maxMatches)` through `Router.multicall` in one atomic transaction. See [the top-up API and agent example](docs/priority-fee-top-ups.md).

Priority bids, including top-ups, are non-refundable: they are spent proportionally on fills, with the remainder transferred to the FeeVault on cancellation or dust closure. They improve priority among equal exact-price orders without creating liquidity or guaranteeing execution. They are not direct keeper rewards. This feature is available on the v1.3.0 testnet hooks and Routers. Earlier deployments do not acquire it automatically; existing orders stay on their original hook.

The current matcher already processes up to eight pairs per call and combines claim transfers. A uniform-price batch auction would additionally change when orders clear and which price they receive. It remains a separate research direction; no batch-auction gas or execution-quality improvement has been demonstrated for these contracts. See [the research notes](benchmarks/orderbook/research.md).
