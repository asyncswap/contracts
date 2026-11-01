# Unichain mainnet readiness

Status: **WAITING FOR AUDIT.** The contracts are ready for independent security review. No mainnet
deployment has been broadcast, and none will be until the audit is complete and its findings are resolved.

## Audit

- **Scope:** [`audit/AUDIT_SCOPE_10_23_26.md`](audit/AUDIT_SCOPE_10_23_26.md). It freezes the code at
  `830cd9e` (2026-10-23): 3,156 nSLOC across `src/` and `script/`. It supersedes
  [`audit/AUDIT_SCOPE_10_19_26.md`](audit/AUDIT_SCOPE_10_19_26.md) (`dc8042d`). If `src/` or `script/`
  changes before the audit starts, re-freeze in a new dated scope file.
- **Automated review:** every finding of the Nethermind AuditAgent report is fixed or acknowledged, each
  fix with a regression test that fails on the audited commit; see
  [`audit/auditagent_report_1_status.md`](audit/auditagent_report_1_status.md).
- **Previous audits** (Lee, 33 Labs, the H-05 follow-up) covered the earlier
  [asyncswap/protocol](https://github.com/asyncswap/protocol) code; see [`audit/README.md`](audit/README.md).

## Settlement model

- **Book matches** credit both sides, and any remainder returned below the pool minimum, as PoolManager
  ERC-6909 claims in every currency. Matching makes no token transfers and calls no recipient code, so a
  recipient that a token refuses (for example a USDC-blocklisted address) or that rejects ETH cannot block
  the book.
- **Filler fills and pool-liquidity fills** pay ERC-20 output directly to the maker; native output is
  credited as claims. The order is closed before any payout, and a failed pool fill reverts only its own
  attempt, leaving the order resting.
- **Cancellations** return ERC-20 input directly and native input as claims.
- **Redemption:** `TokenClaims.redeem(currency, recipient, amount)` (ERC-20) and
  `NativeClaims.redeem(recipient, amount)` (ETH) redeem only the caller's claims, after a PoolManager
  approval for that claim id, to any nonzero recipient. A failed transfer restores claims and allowance
  atomically; re-entry is blocked.
- **Priority bids** are escrowed as hook claims at order creation and always settle to the FeeVault,
  never to LPs.

## Evidence collected

- **Full suite:** 833 passed, 0 failed, 1 skipped (2026-10-23, `main` at `e62a183`). The skipped suite is
  the Unichain fork test, which runs when its RPC variables are set.
- **Invariants:** 10 invariants across `MatchingInvariantTest`, `PriorityMatchingInvariantTest` and
  `LpMatchingInvariantTest`, 64 runs × depth 64 (4,096 calls) each with fail-on-revert: escrow equals
  outstanding obligations, asset conservation, best prices against a linear scan, and the hook holds no
  USDC beyond escrow.
- **Regression suites:** `test/security/` (exact-price eligibility, minimum order, priority fees, native
  settlement, reentrancy, fee claims, order windows and more), `test/nethermind_auditagent/` (one test per
  AuditAgent finding) and `test/TokenClaims.t.sol`.
- **Bytecode checks:** `test/formal/` runs single-call property checks of the compiled contracts.
- **Coverage of `src/`:** 99.9% lines, 99.4% statements, 98.8% branches, 100% functions. The uncovered
  branches are unreachable guards.
- **Unichain fork:** `UnichainForkTest`, 3 tests against block 61279110 with the real PoolManager and USDC:
  native/USDC fills, residual cancellation, non-refundable priority fees without LPs, and continuation
  after the eight-match bound. Last run 2026-10-15; re-run on the audited commit.
- **Local CREATE2 deployment** with the indexed frontend settled 0.4 ETH for 1,000 USDC and 0.6 ETH for
  1,500 USDC, with recipient balances reflecting both fills.

```sh
forge test                                   # full suite
UNICHAIN_FORK_RPC_URL=https://mainnet.unichain.org UNICHAIN_FORK_BLOCK=61279110 forge test --match-contract UnichainForkTest -vv
forge coverage --skip 'test/formal/AsyncSwapBeforeSwap.t.sol' --report summary --no-match-coverage '(test|script|dependencies)/'
```

The fork fixture installs hook code for tests. It is not a rehearsal of the production deployment
script. The local demo deploys a new mock-USDC market; it is not a mainnet liquidity simulation.

## Deployment constraints

- Chain: Unichain 130.
- PoolManager: `0x1F98400000000000000000000000000000000004`.
  Source: <https://developers.uniswap.org/docs/protocols/v4/deployments>
- USDC: `0x078D782b760474a361dDA0AF3839290b0EF57AD6`. Revalidate issuer address and decimals in the final
  rehearsal.
- Runtime sizes (`forge build --sizes`, `optimizer_runs = 10_000`, 2026-11-01, after the M-01, L-02 and M-02
  fixes): AsyncSwap 22,988 bytes, AsyncMatching 23,866, Router 22,130, FeeVault 2,320, TokenClaims 2,110,
  NativeClaims 1,964. All under the 24,576-byte EIP-170 limit, but the margins are thin: AsyncMatching has
  only 710 bytes left, the hook 1,588 and the Router 2,446. Budget audit
  fixes against those margins, prefer moving logic into linked libraries over growing the hook, and
  recheck after every change.
- The deployment wrapper checks library code presence, not exact runtime identity. Pin and verify the
  final library and hook runtime hashes.
- `AsyncMatching` deploys through CREATE2 with the salt `keccak256("asyncswap.v2.AsyncMatching")`, which
  fixes its address across chains. Keep it unless a new address is intended.
- Owner in the current script: `0xb1F0982E02f9F71E60512fd47471d76610CcB556`. Confirm the final owner,
  operational permissions and funding before broadcast. The owner can transfer ownership, `sweep` the
  hook's stranded raw balance and collect FeeVault fees. It cannot open or close pools or change pool
  parameters.
- Pool parameters are constructor arguments with no setter: `DEPLOY_MIN_ORDER_USD` (default $10) and an
  asset precision of 4 (0.0001 token). The constructor derives the $0.10 bid cap and the base-unit
  minimum from USDC's decimals. Confirm both values before broadcast; changing them means a new hook.
- The Router's MEV tax gas is a constructor argument with no setter, set per chain in
  `script/config/chains.json` (`deployment.mevTaxGas`, with `deployment.ordering`): 20,000,000 on Unichain,
  whose blocks are ordered by priority fee, and 0 where ordering is by arrival, by builders or unconfirmed.
  `deploy.sh` refuses a chain without a value, or with a nonzero value on a chain not ordered by priority fee.
  Confirm Unichain's ordering and typical wallet priority fees before broadcast, and have the frontend send
  orders with a zero priority fee.

## Before the audit starts

- If `src/` or `script/` changes after `830cd9e`, add a new dated scope file frozen at the commit to be
  audited (see [Audit](#audit)).

## After the audit

- Fix or acknowledge every finding, each fix with a regression test, and re-run the full suite, the
  invariants and the fork tests on the final commit.
- Stress the integrated custody path at 100 transactions per block with adversarial dust, cancellation and
  priority cases. The standalone matching benchmarks (`script/stress-matching-engine.sh`) do not establish
  integrated throughput.
- Rehearse the pinned deployment script on a Unichain fork, then verify the final bytecode and publish
  sources.
- Decide on executor revocation: revoking the Router strands an EOA maker's live orders until it grants
  the Router again (see `test/security/ExecutorRevocation.t.sol`). Either block revocation while orders
  are live or let the Router cancel for the owner regardless.
- Deploy the claim redeemers with the core contracts: `script/DeployTokenClaims.s.sol` and
  `script/DeployNativeClaims.s.sol` (not broadcast yet).
- Ship the claim experience in the indexer and frontend before launch: match proceeds and native proceeds
  are claim balances, which users redeem by approving the claim id on the PoolManager and calling
  `TokenClaims.redeem` or `NativeClaims.redeem`. Approval is for claims, not ERC-20 or hook executor
  permissions. Confirm the production indexer and frontend understand all events and order states; the
  local matching lab uses a separate SQLite indexer.

`script/check-mainnet-readiness.sh` runs the native rejecting-recipient test and deliberately exits
non-zero, keeping release blocked until the audit and the remaining work are complete.
