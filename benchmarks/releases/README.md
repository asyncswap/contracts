# v1.3.0 testnet validation

Protocol source: `c9372ff9577ba3950fa321090a7bfb559fc964a4` (bitmap optimization and funded maker fee top-ups).
Deployed on 2026-11-05 through Olive's `new-deployer` account, authorized with Touch ID.

| Check | Unichain Sepolia (1301) | Robinhood testnet (46630) |
| --- | --- | --- |
| Numeraire | Test USDC | Test USDG |
| Source verification | 9/9 Sourcify exact matches | 9/9 Sourcify exact matches |
| Create → top-up → cancel | Passed | Passed |
| Top-up receipt gas | 200,740 | 203,261 |
| Top-up amount | 0.001 USDC | 0.001 USDG |
| Input returned on cancellation | 1 USDC | 1 USDG |
| Remaining ERC-20 approval | 0 | 0 |

The smoke test checks the live bid and update event, unchanged order input/minimum output and original maker age,
closure after cancellation, full input refund, and FeeVault's claim increase by exactly the top-up.
Each transaction has a successful receipt. ETH/numeraire pools are initialized on both new hooks, with the
previous pool's reference price and no added LP liquidity. These measurements are individual smoke transactions;
they do not establish throughput, worst-case matching gas, or 100 transactions per block.

Evidence:

- [Unichain configuration, code and source verification](../../deployments/1301/1301-v1.3.0-validation.json)
- [Unichain smoke receipts](../../deployments/1301/1301-v1.3.0-smoke.json)
- [Robinhood configuration, code and source verification](../../deployments/46630/46630-v1.3.0-validation.json)
- [Robinhood smoke receipts](../../deployments/46630/46630-v1.3.0-smoke.json)

Executable runtime was compared with local artifacts, excluding constructor immutables and compiler metadata;
configuration and Router constructor arguments were checked separately. Sourcify subsequently reported exact
matches including metadata for all nine modules. Supply the complete hook library-link settings when verifying
Router and FeeVault too: those settings are included in their deployment build's metadata.
Uniscan's Blockscout endpoint did not accept submissions; use the recorded Sourcify verification links.
Robinhood's Blockscout submissions were accepted; Sourcify is the confirmed source-verification evidence.

## Smoke runner

`testnet_smoke.py` is the release-specific broadcast harness, restricted to these two testnets and the named
account. It persists each transaction hash before waiting and never automatically resends a top-up. It permits
resuming only the setup stages used in this release; inspect other interrupted runs before doing anything else.
Completed evidence makes it skip the corresponding network. It is not a general-purpose load generator.

```bash
olive exec new-deployer -- python3 benchmarks/releases/testnet_smoke.py --broadcast
```

The run required two setup corrections: explicit nonces for load-balanced RPCs and an explicit Router executor
grant before order creation. Robinhood RPC reads use Foundry because direct Python HTTP requests returned 403.
No failed order or top-up transaction was broadcast during those corrections.

The frozen protocol previously passed 1,024 tests in 184 suites, including fork, invariant, independent-model,
and callback tests. This release also passed contract-size enforcement and the documentation production build.
The refreshed audit scope and remaining mainnet gates are in [mainnet readiness](../../MAINNET_READINESS.md).
