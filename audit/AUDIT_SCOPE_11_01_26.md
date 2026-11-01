# Audit scope: Async Swap (2026-11-01)

Supersedes [`AUDIT_SCOPE_10_23_26.md`](AUDIT_SCOPE_10_23_26.md), which froze the code at `830cd9e`.

- **Repository:** <https://github.com/asyncswap/contracts>
- **Code frozen at:** `fdfdf65ac44219ef3a77fdc95d2de3016732c10b` on `main` (2026-11-01). `src/` and `script/` are
  identical to `c13cd5a`, the commit deployed to the testnets below; later commits change only tests, audit notes
  and deployment records.
- **Compiler:** solc 0.8.26, optimizer on (`optimizer_runs = 10_000`); see `foundry.toml`.
- **Chain:** Unichain (130) first; any EVM chain with Uniswap v4 later.
- **Builds on:** Uniswap v4 `PoolManager` (hooks, ERC-6909 claims, dynamic LP fee), Permit2 for signed orders,
  OpenZeppelin `SafeERC20`, `EIP712`, `SignatureChecker` and `Multicall`.

## What it is

Async Swap is a Uniswap v4 hook that turns swaps into limit orders. Makers escrow their input in the hook and set a
minimum output. Every pool pairs an asset with USDC (the numeraire). Orders are filled by matching against each
other, by permissionless fillers, or against the pool's own liquidity.

- **Pools.** Anyone can create a pool: the hook accepts one that pairs the configured USDC with an asset that has
  code and uses the dynamic-fee flag. The owner cannot open, close or configure pools.
- **Book.** Orders sit at price levels on v4 ticks (`TickPrice`: the floor tick of the exact limit, 0.01% apart).
  Within a level they rank by exact limit, then escrowed priority bid, then arrival (`EligiblePrice`); exact
  rational limits decide crossing. New orders and any crossed backlog share one book-wide selection, at most eight
  pairs per call.
- **Venue choice.** A new order goes to the better venue first (`TickPrice.poolBeatsLevel`). If the pool's price
  beats the best opposite level (inside the dynamic-fee window, counting the fee a fill back toward the reference
  would pay), the pool goes first, limited one tick short of that level and inside v4's price range, and the book
  matches the rest. Otherwise the book goes first and the pool must take all of any remainder. A pool fill that
  would leave no active liquidity reverts.
- **Fees.** Book matches and filler fills take 0.02% from what each side receives. Pool fills pay active LPs 0.02%
  and the protocol 0.01%, plus a dynamic fee (`DynamicFeeOrdering`) on a fill that moves the price back toward the
  first pool fill's starting tick within 2 blocks: half the gap it closes, half to LPs and half to `FeeVault`.
- **Settlement.** Book matches credit both sides, and any remainder left below the pool minimum, as PoolManager
  ERC-6909 claims, batched per call (`ClaimTransfers`). Holders redeem them through `TokenClaims` (ERC-20),
  `NativeClaims` (ETH) or `Router.withdrawClaims`. Filler fills and full pool fills pay ERC-20 output directly; native
  output, and a pool fill that leaves part of the order on the book, are credited as claims.
- **Priority bids.** Paid in USDC and escrowed when the order is created. Each fill settles its proportional share
  and the rest settles when the order closes. Every settled bid goes to `FeeVault`, never to LPs.
- **Minimums.** Fixed at deployment, no setter: a minimum order in USDC (`minOrder`, from a dollar amount and the
  numeraire's decimals) and an asset floor per pool (`minAssetAmount`, 10^(decimals − 4), so 0.0001 of a token).
  The $0.10 bid cap is derived from the numeraire's decimals too.
- **Signed actions.** Permit2 order witnesses (`swapWithSig`), `SetExecutor`, `UpdatePrice` (binds the order's
  `createdSequence` and its `reprices` count; a reprice that lands after partial matches applies its signed price
  to the remainder) and `CancelOrder` (no order size: covers whatever remains). All use unordered nonces in one space.
- **Router.** The single trusted entry for order creation. `multicall` batches actions as the caller (not payable).
  Order creation and fills pay an MEV tax of the transaction's priority fee times `MEV_TAX_GAS` (per chain, fixed at
  deployment: 20,000,000 on Unichain Sepolia, 0 elsewhere), in `msg.value` on top of any native deposit, credited to
  `FeeVault` as native claims. The Router can cancel for a maker without an executor grant.

## In scope: 3,815 nSLOC

nSLOC counts non-blank lines outside comments (the same method reproduces every count in the 10-23 scope).
"Since `830cd9e`" is the diff against the previous freeze.

### Contracts (`src/`): 2,700 nSLOC, 19 files

| File | nSLOC | Since `830cd9e` | Notes |
|---|---:|---|---|
| `src/AsyncSwap.sol` | 527 | **changed (+98)** | The hook: pool admission, order creation in `beforeSwap`, venue choice, fills, cancels, signed actions, immutable minimums |
| `src/libraries/AsyncMatching.sol` | 456 | **changed (+84)** | Book-wide pair selection, match amounts, reductions, claim payouts, pool fills (full and partial), dust closes |
| `src/libraries/AsyncFiller.sol` | 357 | changed (+9) | Order storage, escrow, fills, cancels, priority levels, bid settlement, minimum and asset-floor checks |
| `src/Router.sol` | 324 | **changed (+68)** | Entry points: swap, signed swap (Permit2), fill, cancel, signed cancel, multicall, claim withdrawal, MEV tax |
| `src/MatchingEngine.sol` | 188 | unchanged | Standalone matching benchmark harness; holds no tokens and is not deployed |
| `src/BaseHook.sol` | 171 | unchanged | Uniswap v4 hook base |
| `src/libraries/RadixPriceTree.sol` | 136 | unchanged | Patricia index of price levels and priority keys, with node-id reuse |
| `src/libraries/OrderSignatures.sol` | 110 | changed (+6) | EIP-712 types: order witness, cancel, executor, reprice |
| `src/libraries/EligiblePrice.sol` | 81 | unchanged | Exact subtree price summaries over the priority tree; eligible-order search |
| `src/libraries/DynamicFeeOrdering.sol` | 71 | **new** | Backrun fee on pool fills inside a 2-block window |
| `src/libraries/TickPrice.sol` | 59 | **new** | Price keys on v4 ticks; pool-versus-book comparison and the pool-first limit |
| `src/libraries/ClaimTransfers.sol` | 37 | **new** | Batches claim credits for one matching call (34 entries) |
| `src/FeeVault.sol` | 34 | unchanged | Holds protocol fees, bids and MEV tax as claims; owner collects |
| `src/TokenClaims.sol` | 33 | unchanged | Redeems a holder's ERC-20 PoolManager claims to any recipient |
| `src/NativeClaims.sol` | 32 | unchanged | Redeems a holder's native-ETH claims to any recipient |
| `src/libraries/CurrencySettler.sol` | 26 | unchanged | Settle/take helpers |
| `src/interfaces/ISignatureTransfer.sol` | 24 | unchanged | Permit2 interface |
| `src/types/AsyncOrder.sol` | 21 | changed (comments) | Order struct and id |
| `src/ImmutableState.sol` | 13 | unchanged | PoolManager reference |

`AsyncMatching`, `TickPrice` and `DynamicFeeOrdering` are linked libraries deployed by CREATE2 at the same address
on every chain; library calls run in the hook's context.

### Scripts (`script/`): 1,115 nSLOC, 19 files

| File | nSLOC | Since `830cd9e` | Notes |
|---|---:|---|---|
| `script/FFIHelper.sol` | 146 | changed | FFI helpers; minimum priority bid, approvals, reading an order's assigned salt |
| `script/Trade.s.sol` | 122 | unchanged | End-to-end trading flows on a deployment |
| `script/01_DeployHook.s.sol` | 116 | changed | Router then hook (CREATE2 salt, owner, numeraire, minimums, per-chain MEV tax gas), post-deploy checks |
| `script/config/UniswapAddresses.sol` | 100 | changed | Per-chain PoolManager, Permit2 and USDC addresses |
| `script/03_Swap.s.sol` | 84 | changed | Place an order through the Router |
| `script/lib/Deployments.sol` | 70 | unchanged | Reading and writing deployment records |
| `script/InitPool.s.sol` | 66 | unchanged | Pool initialization with real tokens (Unichain) |
| `script/local/Smoke.s.sol` | 58 | **new** | Local smoke flow on Anvil |
| `script/local/LocalMarket.s.sol` | 53 | **new** | Local market setup on Anvil |
| `script/02_InitializePool.s.sol` | 46 | unchanged | Pool initialization with a mock asset |
| `script/05_ExecuteOrder.s.sol` | 40 | changed | Fill an order at its live amounts |
| `script/00_DeployDynamicFeeOrdering.s.sol` | 35 | **new** | Deploy `DynamicFeeOrdering` (CREATE2) |
| `script/00_DeployMatchingLibrary.s.sol` | 35 | unchanged | Deploy and link `AsyncMatching` |
| `script/00_DeployPoolManager.s.sol` | 34 | unchanged | Local PoolManager for testing |
| `script/00_DeployTickPrice.s.sol` | 34 | **new** | Deploy `TickPrice` (CREATE2) |
| `script/DeployWithdrawalRouter.s.sol` | 26 | **new** | Testnet-only second Router for claims |
| `script/04_CancelOrder.s.sol` | 22 | unchanged | Cancel an order |
| `script/DeployNativeClaims.s.sol` | 14 | unchanged | Deploy `NativeClaims` |
| `script/DeployTokenClaims.s.sol` | 14 | unchanged | Deploy `TokenClaims` |

Supporting deployment tooling (not Solidity; review for correctness of what gets deployed, not counted in nSLOC):
`script/deploy.sh` and its per-chain wrappers (`deploy-unichain.sh`, `deploy-arc.sh`, and the testnet ones),
`script/deploy-standalone-testnet.sh`, `script/deploy-withdrawal-router.sh`, `script/mine-hook-salt.ts`,
`script/price.ts`, `script/sync-deployment-record.py`, `script/sync-poolmanager-receipt.py`,
`script/check-contract-sizes.py`, `script/check-mainnet-readiness.sh`, `script/config/chains.json` (per-chain
addresses, transaction ordering and `mevTaxGas`; `deploy.sh` refuses a chain with no `mevTaxGas`, or a nonzero one on
a chain not ordered by priority fee).

For the scripts, the questions are: does the hook get deployed with the intended owner, numeraire, flags, minimums,
Router and linked libraries; does the Router get the intended MEV tax gas for its chain; are the per-chain addresses
right; can a deployment be front-run or left half-configured.

Out of scope: `test/`, `dependencies/`, `docs/`, `site/`, `formal/`.

## Where to look hardest

- **Venue choice and pool-first fills** (`TickPrice.poolBeatsLevel`, `AsyncSwap.matchNewOrder`,
  `AsyncMatching._poolFillNet` / `_swapAgainstPool` / `_reduceAfterPoolFill`, `closeBelowMinimum`): the pool-first
  limit (one tick toward the incoming order for a swap that lowers the tick, clamped inside v4's range), the
  fee-window adjustment, partial pool fills that leave the rest for the book (pro-rata limit, pro-rata 0.01%, input
  minted back), and the post-swap liquidity check. This code changed most since the last freeze and was the source
  of most findings in the reviews below.
- **Dynamic fee** (`DynamicFeeOrdering.charge`): reference and window handling, the fee base for a fill that crosses
  the reference, the 50% cap, and who can choose when a resting order pays it.
- **Exact eligibility** (`EligiblePrice.sol`, `AsyncMatching._bookPair`, `AsyncFiller` append/remove/refresh):
  subtree summaries must stay exact through insertion, removal, repricing, node-id reuse and every partial fill.
- **Escrow conservation**: every path (match, filler fill, full and partial pool fill, cancel, dust close, bid
  settlement) must burn or move exactly what it pays; the hook's claims per currency equal open input plus open
  bids. Claims are fungible across pools, so one pool must never pay out another pool's escrow.
- **Minimums and the asset floor** (`checkMinimum`, `_minAssetAmount`, pool admission with arbitrary assets and their
  `decimals()`): both legs at creation and reprice; remainders are closed by the USDC leg only.
- **Signed actions**: reprice scaling to a remainder (`_verifyReprice`), the `reprices` counter, nonce burning, the
  Router's grant-free cancel and Router-only `useNonce`, and `swapWithSig` skipping a grant whose nonce is spent.
- **MEV tax** (`Router._chargeMevTax` / `_payMevTax`): the transient slot, exact `msg.value`, native settlement to
  `FeeVault`, and interaction with native deposits in `swap` and `fillOrder`.
- **Ordering of state changes and external calls** in `fill`, `fillFromPoolLiquidity`, the Router's fill path
  (`_requireUnchanged` after the ERC-20 pull), and token callbacks during order creation.

## Trust assumptions

- **Owner** (two-step `transferOwnership` / `acceptOwnership`): sweeps tokens sent to the hook by mistake (`sweep`;
  escrow lives in PoolManager claims, not the hook's balance) and collects fees, bids and MEV tax from `FeeVault`.
  It cannot open, close or configure pools or change minimums. Must not be able to take makers' escrow.
- **Router**: the hook trusts its immutable `router` as the only order-creation path, for grant-free cancels on a
  maker's behalf (the Router checks the owner or a signature), and for burning cancel nonces.
- **Executors**: a maker authorizes executors per pool (`setExecutor` or `setExecutorWithSig`); the Router is the
  usual one. An executor can only act on that maker's orders.
- **Fillers / matchers / keepers**: anyone; permissionless.
- **Pool creators**: anyone, for any asset with code. A malicious asset must only be able to affect its own pool.
- **Tokens**: USDC plus standard ERC-20s and native ETH. Fee-on-transfer and rebasing tokens are not supported.

## Known issues (do not report)

From the reviews below, acknowledged:

- **Ways to race without the MEV tax** (Pashov 4, 5, 6, 9): a searcher can reprice its own resting order with
  `updatePrice` and settle it with `matchBook` (on the Router or directly on the hook, which needs no unlock), or
  pool-fill its own order through `tryFillOrderFromPoolLiquidity` with its own contract as executor. No user loses
  funds; the tax covers Router creation and fills only.
- **A partly matched order can fall behind an equal-priced order** (Pashov 7): the remainder's minimum rounds up, so
  its exact limit is one unit worse than the maker signed and its bid buys no priority. Pinned by
  `test_knownIssue_partlyMatchedOrderFallsBehindAnEqualOrder`.
- **Fees round to zero on dust orders** (LSP I-01): only with minimums off.
- **The MEV tax needs an exact `msg.value`**: the deposit plus `priority fee × MEV_TAX_GAS`. Wallets should send taxed
  calls with no priority fee; the app does.

By design:

- **Priority bids are non-refundable.** All of a bid goes to `FeeVault`, including on cancellation or a dust close.
- **Tokens with recipient callbacks (e.g. ERC-777)** are not supported. Matching pays only claims and runs no
  recipient code; filler fills and full pool fills transfer ERC-20 output after the order is closed.
- **Proceeds are claims.** Recipients redeem through `TokenClaims`, `NativeClaims` or `Router.withdrawClaims`.
- **`DeployWithdrawalRouter`** deploys a testnet-only second Router for claims; the hook trusts only its own Router,
  so cancels through the second one fail.
- `MatchingEngine.sol` is a benchmark harness, not deployed (AuditAgent finding 8, acknowledged).
- Release items in `MAINNET_READINESS.md` (deployment rehearsal, bytecode pinning, throughput stress, deploying the
  claim redeemers) are operational, not code findings.

The 29 leads in [`pashov_security_review_2026-11-01.md`](pashov_security_review_2026-11-01.md) and the leads in
[`lsp_security_review_2026-11-01.md`](lsp_security_review_2026-11-01.md) are unconfirmed trails, not known issues:
confirming or ruling out any of them is in scope.

## Previous audits

| Report | Scope | Result |
|---|---|---|
| Lee, 33 Labs (2026-05-08) | Earlier design, never launched (`asyncswap/protocol`) | C-01, H-01..H-04, L-02, L-03, I-01 fixed; L-01 works as intended |
| H-05 follow-up (2026-08-08) | Earlier design | H-05 fixed; native reentrancy hardening |
| AI-assisted review (2026-10-10) | Earlier design at `760699a` | M-01, M-02, L-01..L-03, I-01, I-03 fixed; I-02 acknowledged |
| Pre-freeze review (2026-10-19) | Matching engine | Unpaid priority bid could freeze a pool: fixed in #9 |
| Nethermind AuditAgent (scan `ae602e60`) | `e04668e` | All 12 findings and 2 related issues fixed or acknowledged; see [`auditagent_report_1_status.md`](auditagent_report_1_status.md) |
| Formal Mind swarm, FM-01 | Routing | Best-price routing bypassed better book liquidity: fixed; see [`FM-01-routing-pool-impact.md`](FM-01-routing-pool-impact.md) |
| LSP security review (2026-11-01) | `81ba6b8` | M-01, M-02, L-01, L-02 fixed; I-01 acknowledged; see [`lsp_security_review_2026-11-01.md`](lsp_security_review_2026-11-01.md) |
| Pashov `solidity-auditor` (2026-11-01, 3 passes) | `7d09cfa` | Findings 1, 2, 3, 8, 10, 11 fixed; 4, 5, 6, 7, 9 acknowledged; see [`pashov_security_review_2026-11-01.md`](pashov_security_review_2026-11-01.md) |

Status of every finding: [`README.md`](README.md). Every fix has a regression test, in `test/security/` (including
`test/security/poc/` and `test/security/PashovFindings.t.sol`) or `test/nethermind_auditagent/`.

## Testing

At the freeze commit:

- `forge test`: 971 passing, 0 failing, 0 skipped. The Unichain fork suite (`UnichainForkTest`, 3 tests) runs
  against the `unichain` RPC alias at block 61,709,000 unless `UNICHAIN_FORK_RPC_URL` and `UNICHAIN_FORK_BLOCK` are set.
- 14 invariant runs across `MatchingInvariantTest`, `PriorityMatchingInvariantTest`, `LpMatchingInvariantTest` and
  `ExactPriorityInvariantTest` (64 runs × depth 64, fail-on-revert): escrow equals outstanding obligations, asset
  conservation, best prices against a linear scan, the best order is exact limit then bid then age, and the hook
  holds no USDC beyond escrow.
- Regression suites in `test/security/` and `test/nethermind_auditagent/`; Python reference vectors for exact
  eligibility and priority; single-call bytecode property checks in `test/formal/`. The Lean specifications in
  `formal/` predate several changes and have not been regenerated.
- Coverage of `src/`: 99.82% lines, 98.94% statements, 96.63% branches, 100% functions. The lowest branch coverage is
  `TickPrice` at 78.57% (the clamps at v4's price limits and the fee-window guard) and `DynamicFeeOrdering` at
  91.67%.
- Runtime sizes (EIP-170 limit 24,576): AsyncSwap 23,428 bytes, AsyncMatching 24,135, Router 22,131, TickPrice
  5,204, FeeVault 2,320, TokenClaims 2,110, NativeClaims 1,964.

```sh
forge test
forge coverage --skip 'test/formal/AsyncSwapBeforeSwap.t.sol' --report summary --no-match-coverage '(test|script|dependencies)/'
```

## Deployments

`c13cd5a` is deployed and verified on Sourcify on Unichain Sepolia (1301), Sepolia (11155111), Arc testnet
(5042002), Robinhood Chain testnet (46630) and MegaETH testnet (6343); addresses are in `deployments/<chainId>/`.
No mainnet deployment exists; see [`../MAINNET_READINESS.md`](../MAINNET_READINESS.md).
