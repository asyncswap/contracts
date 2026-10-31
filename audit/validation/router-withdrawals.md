# Router withdrawals validation — 2026-10-31

The updated Router adds `cancelAndWithdraw` and `withdrawClaims` alongside the
existing immutable hooks. The original creation Router remains trusted for
creation and signed nonce handling. Direct cancellation instead requires the
maker to authorize the new Router as an executor; claim redemption requires
ERC-6909 allowances on PoolManager. Existing orders and balances stay in place.

## Results

- Full Foundry suite: **914 passed, 0 failed, 0 skipped** (153 suites).
- Full interface suite: **159 passed, 0 failed**. Typecheck and production build passed.
- Concolity optimized Router coverage: **149/149 lines (100%)**, **190/722 JUMPI
  branch sides (26.32%)**. These are bytecode branch sides, not Solidity statements.
- Concolity: 907 passing test entries and 18 skipped entries, zero compilation
  errors, zero unsupported cheatcodes, zero non-varying missing-code bindings,
  and **zero verdict disagreements with Foundry**.
- Skipped Concolity entries: 14 invariants, three fork tests, and one deliberately
  excluded finding test. Foundry runs the invariant and fork cases separately;
  the finding test is excluded by the repository's default profile.
- Targeted concolic exploration: seven runs, ten solver calls, zero findings,
  zero model mismatches, zero malformed or stale solutions, and no pinned ops.
  The two new fuzz harnesses did not reach 476 remaining branch targets; 56 were
  outside the influence of their inputs. This does not establish whole-Router
  path completeness or prove the absence of bugs.
- Mutation campaign: **29/29 selected, compiling mutations detected** by the
  22-test `RouterClaimsTest` suite. Gambit v1.0.6 generated 24 mutations; five
  additional mutations targeted cancellation, pre-existing balances, claim burns,
  recipients, and batch iteration. This is a selected campaign, not an exhaustive
  mutation score for the repository.

## Gaps closed

The first mutation run detected 18 of 24 mutations. Six survived: two removed the
PoolManager caller guard and four broke valid batch processing. Added an explicit
unauthorized-callback regression and a successful ETH-plus-ERC20 batch withdrawal.
All six then failed the tests. Added fuzz cases for maker identity, executor
permission, exact claim allowance, withdrawal amount, and stale caller-supplied
order size, plus mismatched and oversized batch checks.

The contract implementation did not change during this campaign. Tests also cover
preserved existing claims, partial-fill refunds, recipient rejection, atomic batch
rollback, other-wallet rejection, and reentrant withdrawal attempts.

## Deployment checks

All four withdrawal Router runtime bytecodes, constructor arguments, successful
receipts, and unchanged hook creation-Router pointers were checked. A Unichain
Sepolia fork simulated an order through the original Router, cancellation through
the new Router after executor approval, and redemption of the existing owner's
native claims. No owner withdrawal was broadcast during verification.

Sepolia's RPC estimated about 33.3 million deployment gas. Two earlier transactions
reverted at lower locally estimated limits; the final deployment succeeded with
a 37.1 million limit. The registry records only the successful deployment.

## Reproduction

```sh
forge test --json > forge-results.json
concolity coverage . --include src/Router.sol --against-forge forge-results.json --json
concolity explore . --only RouterClaimsTest --include src/Router.sol \
  --runs-per-test 24 --flips-per-run 8 --timeout-ms 2000 --json
```

Concolity source and Formal Mind dependency revisions are pinned in the local
`~/.concolity/versions.json`; `~/.concolity/build.sh` rebuilds the installed tool.
Raw coverage, exploration and comparison reports are in `~/.concolity/reports/`.
The exact mutation diffs, individual outcomes, and initial/final counts are in
[router-withdrawals-mutations.json](./router-withdrawals-mutations.json).
