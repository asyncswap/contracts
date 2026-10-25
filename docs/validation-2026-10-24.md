# Validation of the second audit fixes

The resolved findings are described in [the audit status](../audit/auditagent_report_2_status.md).

The final run passed **859 Solidity tests** (one RPC-dependent fork test skipped), **42 Python
tests**, all **10 Python–Solidity differential suites**, and the focused Lean build. All five
generated contract models reproduce byte-for-byte.

## Reproducing the checks

```sh
forge test
forge build --skip test --skip script --sizes
EXPORT_GAS_FIXTURE=true forge test --match-contract EligibleGasTest -vv
```

Use Solidity 0.8.26 with **43,690 optimizer runs**. TickPrice is linked separately; the deployment
wrapper deploys it before linking AsyncMatching. The protocol-only size check excludes the concrete
upstream PoolManager development fixture, which exceeds EIP-170 at this optimizer setting. The
protocol uses an existing PoolManager; these measurements do not certify deploying a new PoolManager
from the development fixture with this configuration.

From `/Users/meek/developer/mmsaki/uv4`:

```sh
uv run pytest tests/priority_protocol -q
uv run python examples/export_priority_vectors.py /Users/meek/developer/asyncswap/contracts
uv run python examples/export_eligible_vectors.py /Users/meek/developer/asyncswap/contracts
uv run python examples/check_priority_source.py /Users/meek/developer/asyncswap/contracts
```

The reference model compares exact Fraction prices and uses sorting instead of the Solidity radix
index. Eight stateful differential campaigns include 514 operations, 128 matches, and 8,109 order
state checks, plus independent wallet and claim checks. They include cancellation, partial fills,
repricing (including rejected bid-floor increases), ordinary and end levels, and matched identities.
The 100 pairwise arithmetic vectors and signature hash comparisons are separate tests.

## Gas receipts

| Matches in one Router transaction | Receipt gas |
| ---: | ---: |
| 1 | 490,024 |
| 2 | 626,378 |
| 4 | 943,316 |
| 8 | 1,631,254 |

These are actual successful Router receipts on isolated Anvil, not `gasleft()` estimates. Every
transaction starts from the same exported state with 128 blockers, 32 crossing pairs, standard
ERC-20s and no LPs. Receipt gas includes intrinsic gas and storage refunds. Matched proceeds are
claims; later withdrawals are separate transactions and are excluded. The prior recorded fixture
used 500,583 / 636,940 / 955,580 / 1,652,381 gas for the same batch sizes at 43,690 runs. Accounting,
selection and linked code have changed, so the measurements describe the complete revision rather
than isolating one optimization. These samples establish neither a global minimum nor a worst-case
transaction bound. The full event receipts and compiler settings are in
`audit/validation/matching-receipts-2026-10-24.json`.

## Proof location and boundaries

Commit `f243b0b` deliberately retired the Lean project. Its parent's historical source is recovered
under `/Users/meek/developer/asyncswap/contracts-validation-proofs/formal`. The historical proofs
are archived and do not describe current contracts.

`/Users/meek/developer/asyncswap/contracts-validation-proofs/current` contains freshly regenerated
models and focused proofs for current claim settlement, FeeVault routing, exact-extremum lookup,
callback authorization, cancellation expiry, and capped-fill arithmetic. Run `generate.sh`, then
`lake build` there. Their external/helper assumptions remain explicit; this is not a complete
cross-contract refinement. The Solidity and differential tests exercise these boundaries.

## Runtime sizes

| Protocol component | Bytes | EIP-170 headroom |
| --- | ---: | ---: |
| AsyncMatching | 22,924 | 1,652 |
| AsyncSwap | 22,229 | 2,347 |
| Router | 20,609 | 3,967 |
| TickPrice | 3,331 | 21,245 |
| TokenClaims | 2,110 | 22,466 |

The machine-readable validation record identifies the exact source hashes and final test counts.
No network broadcast is included in this validation.
