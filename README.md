![Async Swap](docs/assets/async-swap-banner.png)

# Async Swap

Async Swap is a continuous on-chain order book and matching engine built as a Uniswap v4 hook focused on large swaps in volatile pairs, where AMM price impact can be high. Traders set a limit price for assets paired with USDC, and orders are good till cancelled (GTC): there is no expiry, so an order rests until it fills or the maker cancels it. Anyone can permissionlessly fill orders, and anyone can open a USDC pool on the hook.

## How it works

1. A maker swaps through the Router with an exact input and a minimum output. The hook takes the swap off the pool's curve and records it as an order.
2. The order is matched immediately against the best opposite orders on the book, at the resting order's price.
3. Any remainder rests on the book. It can later match a new order, fill from the pool's own liquidity when that beats the book, be taken by any filler who pays the maker's price, be repriced, or be cancelled.

Fills depend on available liquidity and counterparties. The minimum order, the cap on the required nonzero priority bid, and the asset floor are fixed when the hook is deployed, so the owner cannot change pool rules under live orders.

## Built on Uniswap v4 accounting

Async Swap uses v4's two accounting primitives together: custom accounting decides how an order executes, and flash accounting makes every step of its life settle as net deltas inside one PoolManager unlock.

### Custom accounting

The hook enables `beforeSwapReturnDelta`. In `beforeSwap` it takes the full exact input as ERC-6909 claims and returns `toBeforeSwapDelta(-amountSpecified, 0)`, so the PoolManager treats the whole swap as consumed by the hook. The pool's curve is never touched by order creation. The hook, not the AMM, decides execution: the order rests on the book, matches opposite orders, fills from pool liquidity through a guarded self-call, or is taken by a filler. `afterSwapReturnDelta` is not used.

### Flash accounting

Every Router action runs inside a single `PoolManager.unlock`: `swap`, `swapWithSig`, `fillOrder`, `matchBook`, `fillFromPoolLiquidity`, `cancelOrder`, `cancelWithSig`, `cancelAndWithdraw`, `withdrawClaims` and `topUpPriorityFee`. Within the unlock, balances are running deltas. Escrow, matching of up to eight pairs, protocol fees, LP donations and maker payouts move through `take`, `settle`, `mint`, `burn` and `donate`, and only net amounts settle when the unlock closes. If any operation leaves a nonzero delta, the whole transaction reverts.

### Custody and claims

Maker escrow stays in the PoolManager as ERC-6909 claims owned by the hook, and protocol fees are claims owned by the FeeVault. Matched makers receive ERC-20 output directly or native output as claims they redeem through `NativeClaims`, `TokenClaims` or `Router.withdrawClaims`. There is no separate vault or custody contract.

### Hook permissions

| Permission | Use |
| --- | --- |
| `beforeInitialize` | Requires a USDC (numeraire) side and the dynamic-fee flag, and seeds the pool's book settings. |
| `beforeAddLiquidity` | Allows LP positions, which supply the inventory for pool fills. |
| `beforeSwap` | Validates the order and the Router's executor authorization, and records the order. |
| `beforeSwapReturnDelta` | Custom accounting: hands the full input to the hook instead of the curve. |

No after-hooks are used.

## Matching engine

Book matching prioritizes price, with higher escrowed USDC bids breaking same-price ties and earlier submissions breaking equal-bid ties. Price levels sit on Uniswap v4 ticks and are found through a three-level occupancy bitmap; within a level, a radix tree ranks orders by priority bid and arrival, with exact-limit summaries so the best crossing order is found in one walk. Matching processes up to eight pairs per call and combines claim transfers; `matchBook(key, maxMatches)` lets anyone continue it.

## Fees

- Each side of a book match or filler fill receives its proceeds less a 0.02% protocol fee, so a maker receives at least its minimum output minus 0.02%.
- Fills against pool liquidity pay active LPs 0.02% and the protocol 0.01%.
- Dynamic fee ordering: a pool fill that moves the price back toward where it stood before that pool's first fill of a 2-block window pays a dynamic fee of about half the backrun's profit, split between LPs and the protocol (tracked per pool).
- MEV tax: order creation and fills pay a tax on the transaction's priority fee, credited to the protocol, so a transaction sent with no priority fee pays nothing and searchers racing for position pay most of their bids to the protocol.

## Priority fees

An order's USDC priority bid breaks ties between equal exact limit prices. This is separate from the transaction's gas priority fee. Zero bids are allowed; for a nonzero bid, the required minimum is 0.1% of the order's USDC notional, rounded down and capped at $0.10 with the default six-decimal numeraire configuration. Users may bid more than that minimum.

Makers can call `Router.topUpPriorityFee(order, addedFee)` to escrow additional USDC on an open order. The Router requires the maker's approval and caller identity; the amount is added to the **remaining** bid without changing the order's input budget or limit price. The resulting bid must meet the minimum for the remaining order. A top-up resets time priority within its new fee tier and preserves the original maker age used for settlement pricing. It does not trigger matching; an agent can combine it with `matchBook(key, maxMatches)` through `Router.multicall` in one atomic transaction. See [the top-up API and agent example](docs/priority-fee-top-ups.md).

Priority bids, including top-ups, are non-refundable: they are spent proportionally on fills, with the remainder transferred to the FeeVault on cancellation or dust closure. They improve priority among equal exact-price orders without creating liquidity or guaranteeing execution. They are not direct keeper rewards. This feature is available on the v1.3.0 testnet hooks and Routers. Earlier deployments do not acquire it automatically; existing orders stay on their original hook.

### Application-specific sequencing

Applications can schedule their own submissions, cancellations, and top-ups, but the shared book still ranks by price, USDC priority bid, then arrival time. `Router.multicall` can bundle actions; application-side scheduling does not guarantee execution.

## Documentation

Published at **[docs.asyncswap.org](https://docs.asyncswap.org)**: these guides, the audit status and a contract
reference generated from the NatSpec in `src/`. The site (`site/`, built with [vocs](https://vocs.dev)) rebuilds on
every push to `main` that touches them; preview it locally with `cd site && bun install && bun run dev`.

- [Protocol overview](docs/protocol.md): components, custody, order placement, authorization, and deployment.
- [Order lifecycle and priority bids](docs/order-lifecycle.md): matching, fills, cancellation, and bid settlement.
- [Priority-fee top-ups](docs/priority-fee-top-ups.md): maker authorization, funding, queue updates, and agent calls.
- [Dutch auction orders](docs/dutch-auction.md): a minimum output that falls to a floor, steps, and fills.
- [Contract call sequences](docs/contract-call-sequences.md): calls, callbacks, responses, and withdrawals.
- [Price-key crossing](docs/price-key-crossing.md): price comparisons and rounding.
- [Large-swap research series](https://x.com/asyncswap/article/2120701882377060839): three articles on large-swap costs, opposite-side flow, and Uniswap v4 hooks.
- [Dynamic fee ordering](docs/dynamic-fee-ordering.md): how pool-fill backruns pay LPs and the protocol.

## Build and deployment

v1.3.0 is deployed on **Unichain Sepolia** (test USDC) and **Robinhood Chain testnet** (test USDG). **Elysium testnet** (test USDC, native HYPE) runs a later build of the same protocol. See [addresses and previous deployments](docs/deployments.md). All nine release modules on each network have exact source matches on Sourcify. Mainnet remains subject to [audit and readiness checks](MAINNET_READINESS.md).

`AsyncMatching` is an external Solidity library linked into the hook. The deployment wrapper deploys and links `TickPrice`, `DynamicFeeOrdering`, `TickBitmap`, `EligiblePrice`, and `PriorityFeeUpdates` first. The fee-amendment library links to `EligiblePrice`. `script/deploy.sh <chain-key> [dry-run|broadcast|verify]` deploys the libraries through the shared CREATE2 deployer, links the hook bytecode, mines the hook salt, deploys the hook and Router, and records the addresses under `deployments/<chainId>/`. `verify` publishes sources through Sourcify, tries Blockscout, and writes standard JSON inputs for manual upload. An `ASYNC_MATCHING_LIBRARY_ADDRESS` override must match this build's predicted address. Foundry links the libraries automatically in tests.

The bitmap changes the order-book storage layout and requires a new hook deployment. Existing radix state cannot be reused as bitmap state. The default compiler remains solc 0.8.26.

Install dependencies and run the contract suite with:

```sh
forge soldeer install
FOUNDRY_INVARIANT_RUNS=64 FOUNDRY_INVARIANT_DEPTH=64 forge test --use solar
```
