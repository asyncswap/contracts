![Async Swap](docs/assets/async-swap-banner.png)

# Async Swap v2

Async Swap is an on-chain order book and matching engine built as a Uniswap v4 hook. Traders set a limit price for assets paired with USDC. Orders can match with other traders, available pool liquidity, or independent fillers who keep funds in their wallets until they choose to fill.

Book matching prioritizes price, with FIFO or USDC bids breaking same-price ties. Liquidity providers earn a 0.30% fee on fills against their active positions. Unfilled amounts remain open for later execution, repricing, or cancellation; fills depend on available liquidity and counterparties.

## Documentation

- [Protocol overview](docs/protocol.md): components, custody, order placement, authorization, and deployment.
- [Order lifecycle and priority bids](docs/order-lifecycle.md): matching, fills, cancellation, and bid settlement.
- [Contract call sequences](docs/contract-call-sequences.md): calls, callbacks, responses, and withdrawals.
- [Price-key crossing](docs/price-key-crossing.md): price comparisons and rounding.

## Build and deployment

`AsyncMatching` is an external Solidity library linked into the hook. Deploy it once on each target chain with `forge create src/libraries/AsyncMatching.sol:AsyncMatching --rpc-url "$RPC_URL" --broadcast --account "$DEPLOYER_ACCOUNT"`, set the returned address as `ASYNC_MATCHING_LIBRARY_ADDRESS` in `.env.deploy`, then run `script/deploy-unichain.sh`; the wrapper verifies the library code and links that address into the CREATE2 hook bytecode. The Foundry test runner links the library automatically.

Install dependencies and run the contract suite with:

```sh
forge soldeer install
forge test
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
