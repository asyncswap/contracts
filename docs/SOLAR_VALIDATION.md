# Solar compiler validation

`forge test --use solar` originally failed 15 constructor/EIP-712 checks in `RouterConstructor.t.sol` and `SpecEip712.t.sol`. All failed at `FormalImmutablesC`'s comparison of deployed code with the artifact after masking immutables.

The helper assumed every immutable occupied a zero-filled `PUSH32` operand. Solar also emits narrower operands: the Router artifact declares 20-byte address ranges and one-byte integer ranges. The old scanner left these bytes unmasked. A minimal contract with `address` and `uint8` immutables reproduced the failure while both public getters returned the correct values.

The helper now reads `deployedBytecode.immutableReferences`, validates each range, normalizes its big-endian value and masks only its declared bytes. The original code-length, remaining-bytecode, immutable-value and behavioral assertions are unchanged. Read permission is limited to the standard and isolated Solar artifact directories.

This is a test-helper portability fix. The reproduction does not establish a Solar or Foundry bug, so no upstream bug report was filed.

All 24 tests in the affected suites pass under both solc 0.8.26 and Solar after the fix, at 256 cases per fuzz test.

## Reproduce

Run from the Solidity repository root.

```sh
forge test --use solar --out out-solar --cache-path cache-solar -vvv
```

Use the pinned fork settings to include the three live-state tests:

```sh
UNICHAIN_FORK_RPC_URL=https://mainnet.unichain.org \
UNICHAIN_FORK_BLOCK=61709000 \
FOUNDRY_INVARIANT_RUNS=64 \
FOUNDRY_INVARIANT_DEPTH=64 \
forge test --use solar --out out-solar --cache-path cache-solar -j 2 -vvv
```

The isolated paths preserve the canonical build artifacts. `out-solar/` and `cache-solar/` are ignored by Git.

## Toolchains

Release validation uses Forge 1.8.6 and solc 0.8.26. The Solar comparison uses Forge 1.9.0 (`6056c584`) and Solar `0.3.0-dev+commit.a2b44354`, which reports Solidity compatibility version 0.8.38. Solar emits version warnings for the exact 0.8.26 pragmas; no source pragmas or assertions were changed to suppress them.

Solar remains an experimental comparison. The release compiler setting stays at solc 0.8.26. Smaller Solar artifacts do not establish lower execution gas; they need their own receipt benchmarks.

## Coverage and stale metadata

With Forge 1.9.0, `forge coverage --use solar` compiles an unoptimized build in memory but can leave artifacts from a previous optimized solc build on disk. The immutable-layout helper obtains bytecode through a cheatcode and reads immutable ranges from an artifact file. Mixing those builds reproduced 15 failures with `immutable placeholder is not zero`; ordinary Solar tests and the token-delivery coverage tests passed.

Build matching Solar artifacts before coverage. The wrapper isolates them from normal builds and preserves all existing assertions:

```sh
./script/coverage-solar.sh --no-match-path '**/UnichainFork.t.sol'
```

Additional arguments select tests or fuzz settings. The wrapper owns the report options: it filters LCOV records to `src/`, saves `coverage/solar-src.lcov`, and prints a table with totals calculated only from those records. Tests, deployment scripts and dependencies remain available to the test run but do not contribute to coverage totals. `FORGE_BIN` can select a Forge installation with Solar support. The script builds with `--optimize false --ast`, then runs coverage against the same `out-solar-coverage/` directory. Its read permission is declared in `foundry.toml`.

The fork exclusion makes this an offline run. To include the three live-state tests, configure the pinned Unichain RPC/block above and omit `--no-match-path`. Solar still reports source-anchor warnings with this toolchain; passing tests do not establish that every coverage percentage is accurate. This workaround addresses mismatched artifact metadata and does not suppress those warnings.

Validation of this workflow: all **1,085 offline tests passed**, including the 15 previously failing immutable checks. Four Python checks verify source-path filtering, weighted totals and rejection of empty/duplicate/invalid input. The generated LCOV contains only repository-relative `src/` records. Run the filter checks with `python3 -m unittest discover -s script/tests -p test_coverage_src.py`.
