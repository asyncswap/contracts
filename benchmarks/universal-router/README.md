# Universal Router and v4 periphery capacity

Measured on 2026-11-05: **244–250 independent swaps in the first
30,000,000-gas local block**, through released Universal Router 2.2.0,
its pinned v4 periphery and Permit2. This extends the earlier
[plain v4 test-adapter baseline](../uniswap-v4/README.md).

## Results

| Standing Permit2 allowance | Direction | First-block transactions | Mean receipt gas | Blocks for 500 swaps |
|---|---|---:|---:|---:|
| Finite, exact input | Buy asset | 244 | 122,297.2 | 3 |
| Finite, exact input | Sell asset | 244 | 122,517.2 | 3 |
| Unlimited | Buy asset | 250 | 119,312.2 | 2 |
| Unlimited | Sell asset | 250 | 119,532.2 | 2 |

All **2,000 swaps succeeded** across four workloads. Each queued 500 transactions
from unique actors before mining, so each first block filled with more work
pending. A transaction here is one single-hop v4 swap through the router.
These are observed workload counts under the documented gas-limit policy,
not a fixed protocol capacity or transactions-per-second figure.

| Workload under the same 30-million-gas budget | First-block transactions |
|---|---:|
| Plain v4 via minimal core test adapter | 288 |
| Plain v4 via checked core test adapter | 250 |
| Universal Router + v4 periphery + Permit2 | 244–250 |
| Async Swap creating and matching one maker | 44–51 |
| Async Swap creating and matching eight makers | 10–12 |

The router path averages roughly 119.3k–122.5k gas, versus roughly 103.7k
for the minimal core adapter. Async Swap also creates order and bid state,
updates the book and settles maker/taker claims. Its matched pairs and the
baseline's AMM swaps perform different work; the counts do not establish
identical pricing, liquidity or user outcomes. Claim withdrawal remains
outside Async Swap's crossing measurements, while these swaps deliver tokens.

## Actual route and checks

The measured call is `UniversalRouter.execute(commands, inputs, deadline)`:

1. `V4_SWAP` dispatches to the released v4 periphery implementation.
2. `SWAP_EXACT_IN_SINGLE` executes a no-hook, single-hop pool swap.
3. `SETTLE_ALL` pulls the input from the user through Permit2 into PoolManager.
4. `TAKE_ALL` sends output tokens to the user.

A deadline and nonzero minimum output are enabled. Fixture tests confirm that
expired deadlines and insufficient output revert with the expected errors.
The input amounts and minimums are one asset / 990 quote tokens for sells,
and 1,000 quote tokens / 0.99 asset for buys. The starting pool reference price
is approximately 1,000 quote tokens per asset; this is not a guarantee of equal
net value after fees and price movement. The optional per-hop relative-price
field is zero; the absolute output minimum remains enforced.

Receipt checks verify exactly one expected-pool swap, exact input, output,
configured fee and active liquidity, every user's final balances, aggregate
pool token conservation, zero router and Permit2 token balances, the final
Permit2 allowance/expiry/nonce, and all block gas totals. Finite approvals end
at zero; unlimited approvals remain unlimited. Four fixture exports and all
2,000 independent transaction checks pass.

## Build and scope

- Universal Router tag **2.2.0**, commit
  `64027f3372aa235734207c4e05667204f6f927e1`; v4 periphery commit
  `a7af5b345b479b05fde9182d7e40913a73b3e18f`; Permit2 commit
  `cc56ad0f3439c502c246fc5cfcc3db92bb8b7219`.
- The router is built using its release settings: solc 0.8.26, via IR,
  optimizer 1 run, Cancun, 23,233 runtime bytes. Permit2 uses its own pinned
  build settings: solc 0.8.17, via IR, 1,000,000 optimizer runs, London,
  9,152 runtime bytes. Both execute on Cancun Anvil. PoolManager and the fixture
  retain the earlier benchmark's solc 0.8.26 / 10,000-run settings. We do not
  force the router into that optimizer profile or claim exact live-deployment costs.
- The same PoolManager dependency, deep full-range pool, 0.3% LP fee,
  18/6-decimal mock ERC-20s and prefunded nonzero output balances as the core
  baseline. No hook or initialized-tick crossings, no multihop, ETH wrapping,
  bridge, migration, or permissioned-token route. Unused integration constructor
  addresses, including the permission-adapter factory, are zero.
- ERC-20-to-Permit2 approvals and Permit2-to-router allowances are established
  during setup. **Approval transactions and in-transaction permit signatures
  are excluded.** Finite and unlimited standing allowances are separate cases.
- Same block budget and FIFO policy as the crossing benchmark. Each workload's
  declared transaction gas limit is 120% of its first estimate, rounded up to
  1,000. Reserved headroom affects block packing. Receipt gas includes intrinsic
  gas and refunds. Setup, deployments, LP funding and approvals are excluded.

The [official Universal Router 2.2.0 release](https://github.com/Uniswap/universal-router/releases/tag/2.2.0)
and [pinned v4 router integration](https://github.com/Uniswap/universal-router/blob/64027f3372aa235734207c4e05667204f6f927e1/contracts/modules/uniswap/v4/V4SwapRouter.sol)
identify the source path; the numbers above come from the local receipts.
This is a production-source router benchmark for one controlled route, not
live-network throughput or every routing configuration.

## Reproduce

Requires Foundry, Python 3, Node/npm and GitHub CLI. Preparation fetches pinned
official sources into ignored `.local/` directories and installs only three
pinned Solidity npm dependencies with installation scripts disabled. It verifies
source revisions and compiler/runtime sizes before copying artifacts into the
ignored `deployments/` directory. No wallet key or public broadcast is used.

```sh
python3 benchmarks/universal-router/prepare.py
python3 benchmarks/universal-router/run.py
```

`results/build.json` records compiler settings, pins and creation-bytecode hashes.
`results/summary.json` contains per-workload blocks, gas, assumptions and checks.
`results/<workload>.json.gz` retains all full receipts and logs. Production
Async Swap sources and deployment scripts remain unchanged; its unmet
100-crossing-transactions-per-block target remains open.
