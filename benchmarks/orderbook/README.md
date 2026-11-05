# Order-book optimization and validation

Async Swap uses a three-level bitmap for occupied tick levels and retains the radix tree within each level for exact-price/priority selection. Parent bits summarize nonempty child words. Inserts and removals update ancestors only when a word becomes empty or nonempty; minimum/maximum lookup follows three occupied bits instead of walking radix branches.

The outer domain is 1..1,774,545. The inner fee/sequence keys remain uint128. Exact rational price, remaining priority fee, queue sequence, original maker age, and the eight-pair matching bound retain their existing meanings. This change does not add fee top-ups or change the auction mechanism.

## Gas results

Local Cancun Anvil receipts, 256 distinct resting ask levels, distinct owners, no LP liquidity. Operations start from independent copies of the same committed fixture. Placement and repricing create new levels; the incoming buy fills eight makers. Intrinsic gas and applied refunds are included; setup and approvals are excluded.

| Operation | Radix baseline | Bitmap with linking | Reduction |
| --- | ---: | ---: | ---: |
| Place | 584,885 | 486,702 | 16.79% |
| Cancel | 246,336 | 191,955 | 22.08% |
| Reprice | 377,954 | 309,336 | 18.16% |
| Incoming order filling eight makers | 2,962,260 | 2,793,022 | 5.71% |

These initial validation measurements are archived in [receipts.json](results/receipts.json), with the full validation record in [validation.json](results/validation.json). The baseline is `abf374271c3378a4f461841fd7dac3867f3f5158`. [results.json](results/results.json) records the rerun against the integrated PR sources; it reproduced the receipt values above.

All 38 public-API state comparisons matched, covering 32/256/1,024-order same-price and distinct-price ask books, mirrored bid books, mixed exact prices sharing a tick, and both LP-routing directions. Gross call measurements are in [coverage.csv](results/coverage.csv). They have different accounting from receipts and should not be compared directly with the table above.

Savings depend on workload. In the initial validation, the linked candidate cost 2.09% more for appending at an existing crowded tick, 1.27% more to cancel there, 1.53% more to reprice within it, and 0.51% more for eight fills there. Mirrored distinct-price books improved; LP buy/sell fixtures improved about 4.7%/4.4% in gross call measurements.

## Correctness checks

- [MatchingReference.t.sol](../../test/MatchingReference.t.sol) keeps an independent array of orders and scans exact rational limits, then fee and queue age. Its generic maker/taker calculation checks match IDs, execution amounts, partial-fill remainders, fees, claims and escrow after each operation. It covers cancellation, repricing, price improvement, dust refunds, and a backlog cleared in 8 + 8 + 4 matches.
- The reference shares only `TickPrice.key` for detecting tick changes that reset queue age. Its bounded arithmetic and currency1-USDC book model are not a formal proof or an independent test of tick conversion or LP pricing.
- [TickBitmap.t.sol](../../test/TickBitmap.t.sol) compares full-domain mutations against a linear scan and radix tree, exercises boundary/invalid keys and duplicate insertion, and empties/reuses all 28 groups.
- Representation-specific tests were ported rather than excluded: Book offsets, valid synthetic tick keys, a bit-by-bit outer scan, bounded traversal/missing-child checks, and exact three-word write footprints replace outer radix-pointer expectations. Inner radix checks remain. These ports do not re-prove the historical Lean model.

The original isolated candidate passed 1,015 tests at 128 fuzz runs and invariant settings of 64 runs × 64 depth, excluding the live fork and intentionally excluded `_finding_` tests. That total includes benchmark fixtures now kept outside the normal test directory. Use the PR's CI results for the integrated suite's current total.

## Linking and deployment

The first bitmap prototype fit in the hook but exceeded the runtime limit in its matching library (24,931 bytes). The revised implementation links `TickBitmap.best` and `EligiblePrice.refresh/remove`; Solidity library delegatecalls operate on the hook's existing storage context.

At Solidity 0.8.26 / 10,000 optimizer runs, the measured runtimes are 23,849 bytes for AsyncSwap and 24,225 for AsyncMatching, leaving 727 and 351 bytes respectively. TickBitmap is 696 bytes and EligiblePrice is 1,966 bytes. The production size check requires both new library artifacts and checks all production contracts, not only the hook.

**This is a new-deployment storage layout.** Each outer tree shrinks from four words to three and subsequent Book members move. Existing radix state cannot be interpreted as bitmap state. The deployment wrapper deploys and links both libraries before the matcher/hook and refuses a matcher override that differs from this build's deterministic address. The deployment and verification paths include the new libraries. No chain deployment is part of the benchmark.

## Reproduce

Requirements: Python 3.12+, Foundry/Anvil, initialized repository dependencies, and the baseline Git commit available locally. The measurements above used Foundry 1.9.0; repository CI retains its existing pinned toolchain. The default compiler remains solc 0.8.26.

```sh
python3 benchmarks/orderbook/run.py --output /tmp/async-swap-book-benchmark
```

Choose a new output directory outside the checkout. The runner exports the pinned baseline from Git, copies the current candidate into a second isolated directory, uses the same fixtures for both, runs the reference-model tests, compares 38 state digests, checks all linked runtime sizes, and measures actual local transactions. Source hashes must remain unchanged throughout the run. Full logs and machine-readable results stay in the output directory.

The 1,024-order fixtures need a high aggregate Foundry test gas limit to fund many actors and execute repeated snapshots. This does not change the local receipt block limit of 30 million. Heavy benchmarks are kept out of default CI tests.

```sh
forge test --match-contract MatchingReferenceTest
forge test --match-contract TickBitmapTest
forge build
python3 script/check-contract-sizes.py
```

## Solar experiment

Solar was tested separately on the **radix baseline**, using `forge build --use solar` and the seven reference-model tests (128 fuzz runs). All seven passed. Solar `0.3.0-dev+commit.a2b44354`, reporting Solidity compatibility 0.8.38, produced 14,200 bytes of hook runtime versus the solc baseline's 23,669 bytes. It warned about exact 0.8.26 pragmas. This is a limited compiler experiment, not a full Solar validation, a production-compiler switch, or a gas result for the bitmap candidate. [Solar documentation](https://github.com/paradigmxyz/solar#binary-usage).

See [research notes](research.md) for the CLOB comparison and paper-specific scope.
