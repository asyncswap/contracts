![Async Swap](docs/assets/async-swap-banner.png)

# Async Swap v2

Async Swap is an on-chain order book and matching engine built as a Uniswap v4 hook. Traders set a limit price for assets paired with USDC. Orders can match with other traders or available pool liquidity. Anyone can permissionlessly fill orders.

Book matching prioritizes price, with higher escrowed USDC bids breaking same-price ties and earlier submissions breaking equal-bid ties. Liquidity providers earn a 0.30% fee on fills against their active positions. Unfilled amounts remain open for later execution, repricing, or cancellation; fills depend on available liquidity and counterparties.

## Documentation

Published at **[docs.asyncswap.org](https://docs.asyncswap.org)**: these guides, the audit status and a contract
reference generated from the NatSpec in `src/`. The site (`site/`, built with [vocs](https://vocs.dev)) rebuilds on
every push to `main` that touches them; preview it locally with `cd site && bun install && bun run dev`.

- [Protocol overview](docs/protocol.md): components, custody, order placement, authorization, and deployment.
- [Order lifecycle and priority bids](docs/order-lifecycle.md): matching, fills, cancellation, and bid settlement.
- [Contract call sequences](docs/contract-call-sequences.md): calls, callbacks, responses, and withdrawals.
- [Price-key crossing](docs/price-key-crossing.md): price comparisons and rounding.

## Build and deployment

`AsyncMatching` is an external Solidity library linked into the hook. `script/deploy.sh <chain-key> [dry-run|broadcast|verify]` (wrapped by `script/deploy-arc.sh` and `script/deploy-unichain.sh`) deploys it deterministically through the shared CREATE2 deployer (`script/00_DeployMatchingLibrary.s.sol`), links that address into the hook bytecode, mines the hook salt, deploys the hook and Router, and records everything under `deployments/<chainId>/`. `verify` publishes sources through Sourcify, tries the chain's Blockscout API, and writes standard JSON inputs for manual upload. Set `ASYNC_MATCHING_LIBRARY_ADDRESS` in `.env.deploy` only to link a library deployed another way. The Foundry test runner links the library automatically.

Install dependencies and run the contract suite with:

```sh
forge soldeer install
FOUNDRY_INVARIANT_RUNS=64 FOUNDRY_INVARIANT_DEPTH=64 forge test
```

Run the local block-packing and adversarial gas benchmark with:

```sh
./script/stress-matching-engine.sh
```

The benchmark starts a fresh local Anvil chain with a 30M gas block limit. A run on 2026-10-14 measured:

| Workload | Transactions included | Block gas used |
| --- | ---: | ---: |
| 100 distinct ordinary prices | 100 | 22.29M / 30M |
| Adversarial high-bit radix paths | 83, then 17 next block | 29.04M / 30M, then 8.89M |
| 100 orders, each filling eight makers | 100 | 26.14M / 30M |

These are local measurements, not production-chain guarantees. The adversarial orders stayed pending for the next block instead of reverting; the stress script reproduces all three scenarios.
