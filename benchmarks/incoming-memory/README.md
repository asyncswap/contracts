# Incoming order memory implementation

Keeping crossing arrivals in memory reduces mean transaction gas by **28.9–55.7%** across the existing ten workloads. All **1,000 transactions / 5,200 matched pairs** pass the receipt, selection and accounting checks. Validation passed **1,061 local regression tests**, one additional deterministic deployment test, three Unichain fork tests, and the extended reference suite at **2,048 fuzz runs**.

This implementation is on `mmsaki/incoming-memory`, based on benchmark commit `94400ce97b3260140d5449cbd26a3e7cdd832821`. Source SHA-256 hashes in `results/comparison.json` identify the code measured before the implementation commit; the recorded parent commit alone does not. Existing deployments and the v1.3.0 release do not contain this change.

## What changed

`IncomingMatching.stage` checks the opposite price level's **exact root summary**, avoiding a fee/FIFO tree traversal merely to decide whether a cross exists. Noncrossing arrivals and pools with active LP liquidity retain ordinary persistent admission.

For a potentially crossing arrival without active LP liquidity:

1. Validate amount and fee rules, escrow the priority bid, reserve the original queue/maker sequence, and retain the eleven order fields in transaction-scoped storage. The existing hook still escrows the input and emits the creation event.
2. The trusted Router pays input and priority fee before calling the existing handoff.
3. Load the candidate into memory. Recheck active liquidity; if a funding callback added liquidity, persist the candidate and use the established LP-routing path.
4. Select the globally best bid and ask from the union of the memory candidate and stored book. Exact price, funded fee and queue age decide priority. Re-evaluate after every fill, including when a partial fill shrinks the candidate's fee bid. Continue clearing backlog after the candidate closes, within the same eight-pair budget.
5. Preserve maker-price settlement, proportional ceiling-rounded minima, original maker age, dust refunds, trade fees and priority-fee events. Persist and index only a remaining candidate; flush the existing batched claim credits.

The new helper deliberately reuses the existing settlement and stored-order reduction routines. `_matchAmounts` accepts memory records and uses one maker/taker sizing branch for both directions, retaining the original affordability cap and ceiling rounding. Small source comments explain the transient bridge, exact-summary prefilter, priority reselection and sell-before-buy sequence ordering.

**Observable boundary:** a crossing candidate is absent from persistent order getters while its token funding callback is executing. It cannot be repriced, topped up or matched as a stored order during that unpaid interval. The funded post-handoff state and lifecycle events are checked against the reference model. Native and LP paths retain their existing settlement behavior; the LP path has not been optimized here.

## Crossing receipt benchmarks

Same fixed 18/6-decimal tokens, funded bids, distinct users, 30 million gas Anvil blocks, Cancun and solc 0.8.26 with 10,000 optimizer runs. Setup, approvals and resting-order placement are excluded. Receipt gas includes intrinsic gas and applied refunds. Every workload has 100 independently submitted Router transactions; eight-fill profiles have eight matched pairs per transaction.

| Workload | Baseline mean gas | Implementation mean gas | Reduction | First block tx, before → after |
| --- | ---: | ---: | ---: | ---: |
| buy_eight_distinct | 2,441,439 | 1,081,974 | 55.7% | 11 → 27 |
| buy_eight_levels | 2,648,223 | 1,304,861 | 50.7% | 10 → 22 |
| buy_eight_same | 2,246,111 | 1,157,832 | 48.5% | 12 → 24 |
| buy_one_distinct | 642,064 | 385,321 | 40.0% | 46 → 77 |
| buy_one_same | 561,756 | 399,598 | 28.9% | 51 → 73 |
| sell_eight_distinct | 2,468,227 | 1,108,756 | 55.1% | 11 → 26 |
| sell_eight_levels | 2,673,894 | 1,317,668 | 50.7% | 10 → 22 |
| sell_eight_same | 2,272,698 | 1,171,614 | 48.4% | 12 → 24 |
| sell_one_distinct | 667,659 | 397,455 | 40.5% | 44 → 74 |
| sell_one_same | 587,304 | 411,633 | 29.9% | 49 → 71 |

Block admission uses the existing policy: declared gas limit = 120% of the first estimate, rounded up to 1,000. These are measured first-block counts under that policy, not universal maximum throughput or wall-clock TPS. The 100-crossing-transactions-per-block target is still unmet.

The existing Universal Router baseline is roughly 119–123k gas for a single-hop AMM swap without initialized tick crossings. The implementation's eight-fill averages normalize to approximately **135–165k gas per matched pair**, while one-fill arrivals still cost roughly **385–411k**. This does not make the workloads equivalent: Async Swap changes individual order/claim states, and later claim withdrawals remain excluded.

`results/crossing/` retains all receipts and validation assertions. The baseline archives in `benchmarks/crossing/results/` remain intact.

## Storage evidence and resting-order cost

Replayed opcode traces exactly reproduce the first two saved receipts in each selected profile. The representative second transaction uses **30 SSTORE operations** for one match, **149** for eight matches at a crowded level, and **133** for eight distinct levels. Counts include repeated writes to a slot; the compact traces are in `results/crossing-traces/`.

Four additional noncrossing transactions measure the cost of the admission prefilter:

| Control | Baseline | Implementation | Increase |
| --- | ---: | ---: | ---: |
| First buy | 533,406 | 550,034 | 3.12% |
| Second buy | 519,358 | 536,010 | 3.21% |
| First sell | 586,222 | 602,965 | 2.86% |
| Second sell | 537,994 | 554,761 | 3.12% |

These controls double the minimum output in both Router ABI copies, check that no match event occurs, and verify that the complete input and new minimum remain stored. They are four samples, not a broad resting-order distribution. An earlier always-staged version cost 10–15% more for noncrossing admission; the final version uses the summarized eligibility check and ordinary admission when it cannot cross.

## Validation and fixture changes

- Baseline local suite: **1,047 passed**, excluding the external Unichain fork suite.
- Local suite: **1,061 passed, zero failed**, with the same exclusion. The subsequently added deterministic deployment/idempotency test passed separately.
- Read-only Unichain mainnet fork: **3 passed** at block **61,709,000**, using a local hook fixture against the real PoolManager and USDC. This is not a test of a publicly deployed new hook.
- Extended memory reference/funding/transition suite: **14 passed**, including **2,048 fuzz cases × 64 mixed operations**, plus bounded draining. The oracle scans orders independently and checks selection, fill amounts, fee/minimum remainders, queue and maker ages, claims and total escrow.
- New deterministic reference cases check fee-priority yielding after a partial fill, backlog continuing after the arrival closes, and backlog exhausting the shared match budget before the arrival is selected. Existing top-up, repricing, cancellation, dust and LP tests pass.
- New token-callback tests check both input and bid funding, prohibit matching a pending candidate, and verify that failed funding rolls back the candidate and permits a retry.
- Added transition cases cover active liquidity appearing during funding, cancellation and repricing of an opposite order during funding, currency0 as the numeraire, and sequential swaps in one transaction. Assertions cover residuals, queue/maker ages, claims, fee-vault balances and escrow.
- Matching conservation invariant: **64 runs × 64 calls, zero handler reverts**; other existing invariant suites also pass.

Some stored-book unit fixtures used raw `beforeSwap` and intentionally omitted the Router's handoff to arrange crossed resting orders. The memory path correctly stopped materializing those crossing arrivals, so those fixtures initially failed before reaching their matching assertions. `FormalMatchD` and `HookHelpersB` now temporarily select the persisted admission branch while arranging their book, restoring the exact liquidity storage word before the operation under test. No LP swap runs during that arrangement and their outcome assertions are retained. The separate reference/funding suites exercise the real memory path.

The raw `beforeSwap` outcome model now accounts for the liquidity read requiring initialized per-pool state; real `PoolManager.swap` already requires an initialized pool. These runtime-test changes are not a regeneration or proof of the Lean model for the new module. The incoming-memory state machine needs its own formal/audit coverage before release.

## Huff experiment

The local `v2-raff` experiment is on `mmsaki/incoming-math-kernel`, based on `be294742cf76ab60f2c5c82ec46b7a96508c987b`. Its old full hook is incompatible with current global matching, original maker age, proportional remainder minima, fee top-ups, indexes, LP routing and ABI. It has not been presented as a replacement hook.

The new isolated Huff kernel implements current match sizing and proportional remainder arithmetic. Its combined legacy/kernel suite passes **176 tests**, with one RPC-dependent suite skipped. The kernel has **8,192 differential fuzz cases**, **1,024 boundary matches** and **192 boundary reductions**, including exact overflow/revert checks.

A second fixture in this Solidity checkout directly compares the Huff kernel with the **actual `AsyncMatching._matchAmounts` helper**: **2,048 full-width fuzz cases plus 1,250 boundary comparisons pass**, checking exact return and revert bytes. This tests arithmetic compatibility, not a full Huff matching engine.

Measured callee-only savings against the standalone Solidity specification are **370–530 gas per kernel call**. They cannot be subtracted directly from full-swap receipt gas. The useful lessons are early affordability capping and preserving the original proportional remainder; current Solidity already uses those rules. Storage lifecycle changes produce the much larger measured gain here. See the portable `huff-experiment.patch`, `results/huff-kernel-results.json` and `results/huff-production-parity.json`. No Huff code is linked into the production hook.

## Bytecode reduction and deployment

| Module | Before review | Implementation | EIP-170 headroom |
| --- | ---: | ---: | ---: |
| AsyncSwap | 24,550 | 23,044 | 1,532 |
| AsyncMatching | 24,514 | 23,033 | 1,543 |
| IncomingMatching | 18,804 | 21,060 | 3,516 |

All production runtime and creation sizes pass the deployment-limit check. The compiler settings remain solc 0.8.26, optimizer 10,000, Cancun. Venue orchestration moved into the linked incoming-order library; the stored-admission wrapper is shared there, and symmetric match sizing uses a single maker/taker branch. The hook retains the authenticated funding handoff. Small comments explain these techniques in source.

Compared with the initial memory prototype, this refactor adds **0.094–0.1424%** mean crossing gas, preserves every measured first-block count, and reduces the resting controls by **2,250 gas each**. `results/prototype-before-review.json` preserves the earlier measurements.

`script/00_DeployIncomingMatching.s.sol` deploys the new linked library deterministically after AsyncMatching and before the hook. The deployment, verification and local-stack scripts supply its link address, and the size checker requires its artifact. A local CREATE2 test checks the predicted address and idempotent rerun. A new hook deployment must use the new library linkage; existing immutable hooks cannot acquire this path in place.

The [focused source review](REVIEW.md) found no confirmed unresolved defect in the examined path. This is not an external audit or a Lean proof. Before release, extend formal/audit scope to the new module, quantify LP and broader resting-workload overhead, and repeat public-testnet soak on newly deployed contracts. Deployment registries, frontend addresses, audit-scope artifacts and release tags remain unchanged.

## Reproduce

From this implementation checkout, with the pinned dependencies and tools available:

```sh
forge test --no-match-contract UnichainForkTest
forge test --match-contract UnichainForkTest
forge build && python3 script/check-contract-sizes.py
forge test --match-contract 'IncomingMemory(Funding|Reference|Transitions|QuoteZero)Test' --fuzz-runs 2048
python3 benchmarks/crossing/run.py --output-dir benchmarks/incoming-memory/results/crossing
python3 benchmarks/incoming-memory/profile.py
python3 benchmarks/incoming-memory/controls.py . benchmarks/incoming-memory/results/resting-prototype
# Optional arithmetic experiment: clone v2-raff at the base above and apply huff-experiment.patch.
python3 benchmarks/incoming-memory/prepare-huff.py ../v2-raff
FOUNDRY_TEST=benchmarks/incoming-memory/fixtures FOUNDRY_OUT=.local/huff-parity/out \
FOUNDRY_CACHE_PATH=.local/huff-parity/cache forge test \
  --match-contract HuffProductionParityTest --fuzz-runs 2048
```

Regression/fuzz/fork validation uses CI-pinned Foundry **v1.8.6**. Receipt benchmarks and traces use Forge/Anvil **v1.9.0**, with the same solc and EVM settings; exact versions are recorded in the crossing summary.

The baseline resting controls use the same controls script with the baseline repository path and an independent output directory. Both repositories need their crossing fixture exports first. All benchmark broadcasts are to disposable loopback Anvil instances; no signer or public transaction is used.
