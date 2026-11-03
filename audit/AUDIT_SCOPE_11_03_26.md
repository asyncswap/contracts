# Audit scope: Async Swap (2026-11-03)

Supersedes the 2026-11-01 scope, which froze the code at `fdfdf65`. Earlier scopes and every previous report are kept
at [`2739d6c/audit/`](https://github.com/asyncswap/contracts/tree/2739d6c/audit); this file carries over what an
auditor needs from them: the known issues and the status of every finding.

- **Repository:** [asyncswap/contracts](https://github.com/asyncswap/contracts)
- **Code frozen at:** `2739d6cfd07154c275144a313cf1168b485c1327` on `main` (2026-11-03). Later commits change only
  this scope, docs and tests.
- **Compiler:** solc 0.8.26, optimizer on (`optimizer_runs = 10_000`); see `foundry.toml`.
- **Chain:** Unichain (130) first; any EVM chain with Uniswap v4 later.
- **Builds on:** Uniswap v4 `PoolManager` (hooks, ERC-6909 claims, dynamic LP fee), Permit2 for signed orders,
  OpenZeppelin `SafeERC20`, `EIP712`, `SignatureChecker` and `Multicall`.

## Changes since the last freeze (`fdfdf65`)

- **The trusted Router can't be revoked** (`src/AsyncSwap.sol`, +4 nSLOC). `setExecutor` and `setExecutorWithSig`
  revert `CannotRevokeTrustedRouter` when a maker sets `allow = false` for the hook's immutable `router`; in the
  signed path the check runs after the deadline, nonce and signature checks. Revoking the Router used to strand a
  maker's live orders: `Router.cancelOrder`, `cancelWithSig`, `fillOrder` and `fillFromPoolLiquidity` all need the
  grant, and an EOA can't cancel from its own unlock. Any other executor can still be granted and revoked.
- **No dollar minimum by default** (`script/01_DeployHook.s.sol`): `DEPLOY_MIN_ORDER_USD` defaults to 0, so the
  asset floor (10^(decimals − 4) of each pool's asset) is the order minimum unless a deployment sets one.
- **Fewer deployment targets:** the Sepolia, Arc testnet, MegaETH testnet and HyperEVM testnet wrappers, the
  standalone testnet script and their `chains.json` entries were removed.

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
- **Priority bids.** Optional, paid in USDC and escrowed when the order is created. Each fill settles its
  proportional share and the rest settles when the order closes. Every settled bid goes to `FeeVault`, never to LPs.
- **Minimums.** Fixed at deployment, no setter: an optional minimum order in USDC (`minOrder`, from a dollar amount
  and the numeraire's decimals; 0 by default) and an asset floor per pool (`minAssetAmount`, 10^(decimals − 4), so
  0.0001 of a token). The $0.10 bid cap is derived from the numeraire's decimals too.
- **Signed actions.** Permit2 order witnesses (`swapWithSig`), `SetExecutor`, `UpdatePrice` (binds the order's
  `createdSequence` and its `reprices` count; a reprice that lands after partial matches applies its signed price
  to the remainder) and `CancelOrder` (no order size: covers whatever remains). All use unordered nonces in one space.
- **Router.** The single trusted entry for order creation, and an executor makers can't revoke. `multicall` batches
  actions as the caller (not payable). Order creation and fills pay an MEV tax of the transaction's priority fee
  times `MEV_TAX_GAS` (per chain, fixed at deployment: 20,000,000 on Unichain and Unichain Sepolia, which order by
  priority fee), in `msg.value` on top of any native deposit, credited to `FeeVault` as native claims. The Router can
  cancel for a maker without an executor grant.

## In scope: 3,819 nSLOC

nSLOC counts non-blank lines outside comments (the same method reproduces every count in the previous scopes).
"Since `fdfdf65`" is the diff against the previous freeze.

### Contracts (`src/`): 2,704 nSLOC, 19 files

| File | nSLOC | Since `fdfdf65` | Notes |
|---|---:|---|---|
| `src/AsyncSwap.sol` | 531 | **changed (+4)** | The hook: pool admission, order creation in `beforeSwap`, venue choice, fills, cancels, signed actions, executor grants, immutable minimums |
| `src/libraries/AsyncMatching.sol` | 456 | unchanged | Book-wide pair selection, match amounts, reductions, claim payouts, pool fills (full and partial), dust closes |
| `src/libraries/AsyncFiller.sol` | 357 | unchanged | Order storage, escrow, fills, cancels, priority levels, bid settlement, minimum and asset-floor checks |
| `src/Router.sol` | 324 | unchanged | Entry points: swap, signed swap (Permit2), fill, cancel, signed cancel, multicall, claim withdrawal, MEV tax |
| `src/MatchingEngine.sol` | 188 | unchanged | Standalone matching benchmark harness; holds no tokens and is not deployed |
| `src/BaseHook.sol` | 171 | unchanged | Uniswap v4 hook base |
| `src/libraries/RadixPriceTree.sol` | 136 | unchanged | Patricia index of price levels and priority keys, with node-id reuse |
| `src/libraries/OrderSignatures.sol` | 110 | unchanged | EIP-712 types: order witness, cancel, executor, reprice |
| `src/libraries/EligiblePrice.sol` | 81 | unchanged | Exact subtree price summaries over the priority tree; eligible-order search |
| `src/libraries/DynamicFeeOrdering.sol` | 71 | unchanged | Backrun fee on pool fills inside a 2-block window |
| `src/libraries/TickPrice.sol` | 59 | unchanged | Price keys on v4 ticks; pool-versus-book comparison and the pool-first limit |
| `src/libraries/ClaimTransfers.sol` | 37 | unchanged | Batches claim credits for one matching call (34 entries) |
| `src/FeeVault.sol` | 34 | unchanged | Holds protocol fees, bids and MEV tax as claims; owner collects |
| `src/TokenClaims.sol` | 33 | unchanged | Redeems a holder's ERC-20 PoolManager claims to any recipient |
| `src/NativeClaims.sol` | 32 | unchanged | Redeems a holder's native-ETH claims to any recipient |
| `src/libraries/CurrencySettler.sol` | 26 | unchanged | Settle/take helpers |
| `src/interfaces/ISignatureTransfer.sol` | 24 | unchanged | Permit2 interface |
| `src/types/AsyncOrder.sol` | 21 | unchanged | Order struct and id |
| `src/ImmutableState.sol` | 13 | unchanged | PoolManager reference |

`AsyncMatching`, `TickPrice` and `DynamicFeeOrdering` are linked libraries deployed by CREATE2 at the same address
on every chain; library calls run in the hook's context.

### Scripts (`script/`): 1,115 nSLOC, 19 files

| File | nSLOC | Since `fdfdf65` | Notes |
|---|---:|---|---|
| `script/FFIHelper.sol` | 146 | unchanged | FFI helpers; minimum priority bid, approvals, reading an order's assigned salt |
| `script/Trade.s.sol` | 122 | unchanged | End-to-end trading flows on a deployment |
| `script/01_DeployHook.s.sol` | 116 | changed (default) | Router then hook (CREATE2 salt, owner, numeraire, minimums, per-chain MEV tax gas), post-deploy checks; `DEPLOY_MIN_ORDER_USD` now defaults to 0 |
| `script/config/UniswapAddresses.sol` | 100 | unchanged | Per-chain PoolManager, Permit2 and USDC addresses |
| `script/03_Swap.s.sol` | 84 | unchanged | Place an order through the Router |
| `script/lib/Deployments.sol` | 70 | unchanged | Reading and writing deployment records |
| `script/InitPool.s.sol` | 66 | unchanged | Pool initialization with real tokens (Unichain) |
| `script/local/Smoke.s.sol` | 58 | unchanged | Local smoke flow on Anvil |
| `script/local/LocalMarket.s.sol` | 53 | unchanged | Local market setup on Anvil |
| `script/02_InitializePool.s.sol` | 46 | unchanged | Pool initialization with a mock asset |
| `script/05_ExecuteOrder.s.sol` | 40 | unchanged | Fill an order at its live amounts |
| `script/00_DeployDynamicFeeOrdering.s.sol` | 35 | unchanged | Deploy `DynamicFeeOrdering` (CREATE2) |
| `script/00_DeployMatchingLibrary.s.sol` | 35 | unchanged | Deploy and link `AsyncMatching` |
| `script/00_DeployPoolManager.s.sol` | 34 | unchanged | Local PoolManager for testing |
| `script/00_DeployTickPrice.s.sol` | 34 | unchanged | Deploy `TickPrice` (CREATE2) |
| `script/DeployWithdrawalRouter.s.sol` | 26 | unchanged | Testnet-only second Router for claims |
| `script/04_CancelOrder.s.sol` | 22 | unchanged | Cancel an order |
| `script/DeployNativeClaims.s.sol` | 14 | unchanged | Deploy `NativeClaims` |
| `script/DeployTokenClaims.s.sol` | 14 | unchanged | Deploy `TokenClaims` |

Supporting deployment tooling (not Solidity; review for correctness of what gets deployed, not counted in nSLOC):
`script/deploy.sh` and its per-chain wrappers (`deploy-unichain.sh`, `deploy-unichain-sepolia.sh`,
`deploy-robinhood-testnet.sh`, `deploy-arc.sh`), `script/deploy-withdrawal-router.sh`, `script/mine-hook-salt.ts`,
`script/price.ts`, `script/sync-deployment-record.py`, `script/sync-poolmanager-receipt.py`,
`script/check-contract-sizes.py`, `script/check-mainnet-readiness.sh`, `script/config/chains.json` (per-chain
addresses, transaction ordering and `mevTaxGas`; `deploy.sh` refuses a chain with no `mevTaxGas`, or a nonzero one on
a chain not ordered by priority fee).

For the scripts, the questions are: does the hook get deployed with the intended owner, numeraire, flags, minimums,
Router and linked libraries; does the Router get the intended MEV tax gas for its chain; are the per-chain addresses
right; can a deployment be front-run or left half-configured.

Out of scope: `test/`, `dependencies/`, `docs/`, `site/`, and the helper scripts `script/formal-index.py`,
`script/formal-mind-report.py` and `script/stress-matching-engine.sh`.

## Where to look hardest

- **Venue choice and pool-first fills** (`TickPrice.poolBeatsLevel`, `AsyncSwap.matchNewOrder`,
  `AsyncMatching._poolFillNet` / `_swapAgainstPool` / `_reduceAfterPoolFill`, `closeBelowMinimum`): the pool-first
  limit (one tick toward the incoming order for a swap that lowers the tick, clamped inside v4's range), the
  fee-window adjustment, partial pool fills that leave the rest for the book (pro-rata limit, pro-rata 0.01%, input
  minted back), and the post-swap liquidity check. This code was the source of most findings in the reviews below.
- **Dynamic fee** (`DynamicFeeOrdering.charge`): reference and window handling, the fee base for a fill that crosses
  the reference, the 50% cap, and who can choose when a resting order pays it.
- **Exact eligibility** (`EligiblePrice.sol`, `AsyncMatching._bookPair`, `AsyncFiller` append/remove/refresh):
  subtree summaries must stay exact through insertion, removal, repricing, node-id reuse and every partial fill.
- **Escrow conservation**: every path (match, filler fill, full and partial pool fill, cancel, dust close, bid
  settlement) must burn or move exactly what it pays; the hook's claims per currency equal open input plus open
  bids. Claims are fungible across pools, so one pool must never pay out another pool's escrow.
- **Minimums and the asset floor** (`checkMinimum`, `_minAssetAmount`, pool admission with arbitrary assets and their
  `decimals()`): both legs at creation and reprice; remainders are closed by the USDC leg only. With `minOrder` 0 the
  asset floor is the only minimum.
- **Executor grants and signed actions**: the Router can't be revoked through either path, while other executors
  can; reprice scaling to a remainder (`_verifyReprice`), the `reprices` counter, nonce burning, the Router's
  grant-free cancel and Router-only `useNonce`, and `swapWithSig` skipping a grant whose nonce is spent.
- **MEV tax** (`Router._chargeMevTax` / `_payMevTax`): the transient slot, exact `msg.value`, native settlement to
  `FeeVault`, and interaction with native deposits in `swap` and `fillOrder`.
- **Ordering of state changes and external calls** in `fill`, `fillFromPoolLiquidity`, the Router's fill path
  (`_requireUnchanged` after the ERC-20 pull), and token callbacks during order creation.

## Trust assumptions

- **Owner** (two-step `transferOwnership` / `acceptOwnership`): sweeps tokens sent to the hook by mistake (`sweep`;
  escrow lives in PoolManager claims, not the hook's balance) and collects fees, bids and MEV tax from `FeeVault`.
  It cannot open, close or configure pools or change minimums. Must not be able to take makers' escrow.
- **Router**: the hook trusts its immutable `router` as the only order-creation path, as an executor no maker can
  revoke, for grant-free cancels on a maker's behalf (the Router checks the owner or a signature), and for burning
  cancel nonces.
- **Executors**: a maker authorizes executors per pool (`setExecutor` or `setExecutorWithSig`) and can revoke any of
  them except the Router. An executor can only act on that maker's orders.
- **Fillers / matchers / keepers**: anyone; permissionless.
- **Pool creators**: anyone, for any asset with code. A malicious asset must only be able to affect its own pool.
- **Tokens**: USDC plus standard ERC-20s and native ETH. Fee-on-transfer and rebasing tokens are not supported.

## Known issues (do not report)

Acknowledged in the reviews below:

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

- **Makers can't revoke the Router.** A maker who wants out cancels its orders (through the Router, by signature,
  or directly from its own unlock); the Router acts for a maker only when that maker calls it or signs.
- **Priority bids are non-refundable.** All of a bid goes to `FeeVault`, including on cancellation or a dust close.
- **Tokens with recipient callbacks (e.g. ERC-777)** are not supported. Matching pays only claims and runs no
  recipient code; filler fills and full pool fills transfer ERC-20 output after the order is closed.
- **Proceeds are claims.** Recipients redeem through `TokenClaims`, `NativeClaims` or `Router.withdrawClaims`.
- **`DeployWithdrawalRouter`** deploys a testnet-only second Router for claims; the hook trusts only its own Router,
  so cancels through the second one fail.
- `MatchingEngine.sol` is a benchmark harness, not deployed (AuditAgent finding 8, acknowledged).
- Release items in `MAINNET_READINESS.md` (deployment rehearsal, bytecode pinning, throughput stress, deploying the
  claim redeemers) are operational, not code findings.

The 29 leads in the Pashov review and the leads in the LSP review are unconfirmed trails, not known issues:
confirming or ruling out any of them is in scope.

## Previous reviews

Reports are linked at `2739d6c`, the last commit that tracks them. Every fix has a regression test, in
`test/security/` (including `test/security/poc/` and `test/security/PashovFindings.t.sol`),
`test/nethermind_auditagent/` or `test/formal/RoutingPoolImpact.t.sol`.

| Report | Scope | Result |
|---|---|---|
| Lee, 33 Labs (2026-05-08) | Earlier design, never launched (`asyncswap/protocol`) | C-01, H-01..H-04, L-02, L-03, I-01 fixed; L-01 works as intended |
| H-05 follow-up (2026-08-08) | Earlier design | H-05 fixed; native reentrancy hardening |
| AI-assisted review (2026-10-10) | Earlier design at `760699a` | M-01, M-02, L-01..L-03, I-01, I-03 fixed; I-02 acknowledged |
| Pre-freeze review (2026-10-19) | Matching engine | Unpaid priority bid could freeze a pool: fixed in #9 |
| [Nethermind AuditAgent 1](https://github.com/asyncswap/contracts/blob/2739d6c/audit/auditagent_report_1_ae602e60-d592-45ec-92ef-891968f087f0.md) (scan `ae602e60`) | `e04668e` | 12 findings and 2 related issues: all fixed except 8, acknowledged for the harness and fixed live; [status](https://github.com/asyncswap/contracts/blob/2739d6c/audit/auditagent_report_1_status.md) |
| [Nethermind AuditAgent 2](https://github.com/asyncswap/contracts/blob/2739d6c/audit/auditagent_report_2_e73aa801-4ee2-4796-9bf6-5ee08d526d36.md) (scan `e73aa801`) | Exact pricing, repricing, cancels | 3 findings fixed; [status](https://github.com/asyncswap/contracts/blob/2739d6c/audit/auditagent_report_2_status.md) |
| [Formal Mind swarm](https://github.com/asyncswap/contracts/blob/2739d6c/audit/formal-mind.md) | Routing | FM-01 (Medium): best-price routing bypassed better book liquidity; fixed in `550b463` ([report](https://github.com/asyncswap/contracts/blob/2739d6c/audit/FM-01-routing-pool-impact.md)) |
| [LSP security review](https://github.com/asyncswap/contracts/blob/2739d6c/audit/lsp_security_review_2026-11-01.md) (2026-11-01) | `81ba6b8` | M-01, M-02, L-01, L-02 fixed; I-01 acknowledged |
| [Pashov `solidity-auditor`](https://github.com/asyncswap/contracts/blob/2739d6c/audit/pashov_security_review_2026-11-01.md) (2026-11-01, 3 passes) | `7d09cfa` | 1, 2, 3, 8, 10, 11 fixed; 4, 5, 6, 7, 9 acknowledged |

The findings of the last three reviews, in full:

| Review | ID | Severity | Finding | Status |
|---|---|---|---|---|
| Formal Mind | FM-01 | Medium | Best-price routing compares only the pool spot tick, then swaps the whole order through the pool | Fixed |
| LSP | M-01 | Medium | A leftover signed `SetExecutor` grant from `swapWithSig` can undo a maker's revocation | Fixed |
| LSP | M-02 | Medium | A front-run ask can force a new order onto the book at a worse price than the pool | Fixed |
| LSP | L-01 | Low | A small partial match voids a maker's relayed cancel or reprice | Fixed |
| LSP | L-02 | Low | Pool squatting before a token is deployed disables its asset floor | Fixed |
| LSP | I-01 | Info | Fee rounding on dust remainders (only with minimums off) | Acknowledged |
| Pashov | 1 | 90 | The backrun fee charges the whole output of a fill that crosses the reference tick | Fixed |
| Pashov | 2 | 90 | A dust order at the end key turns off pool fills for the other side | Fixed |
| Pashov | 3 | 85 | The venue choice ignores the dynamic fee | Fixed |
| Pashov | 4 | 85 | A maker that sets itself as executor fills from the pool with no MEV tax | Acknowledged |
| Pashov | 5 | 85 | A direct `updatePrice` makes an old order cross with no MEV tax | Acknowledged |
| Pashov | 6 | 85 | Reprice plus `matchBook` pays no MEV tax | Acknowledged |
| Pashov | 7 | 75 | Ceil rounding on a partial match makes the remainder's limit worse | Acknowledged |
| Pashov | 8 | 75 | A pool-first fill parks the price in an empty range and freezes pool fills | Fixed |
| Pashov | 9 | 75 | Any caller runs the hook's `matchBook` with no unlock and no Router | Acknowledged |
| Pashov | 10 | 75 | A copied executor grant submitted first reverts the relayer's `swapWithSig` | Fixed |
| Pashov | 11 | 75 | The pool-first limit stops one tick past the best resting price | Fixed |

Pashov's column is the reviewer's confidence, not a severity.

## Testing

At the freeze commit:

- `forge test`: 987 passing, 0 failing, 0 skipped, in 177 suites. The Unichain fork suite (`UnichainForkTest`, 3 tests) runs against the `unichain`
  RPC alias at block 61,709,000 unless `UNICHAIN_FORK_RPC_URL` and `UNICHAIN_FORK_BLOCK` are set.
- 14 invariant runs across `MatchingInvariantTest`, `PriorityMatchingInvariantTest`, `LpMatchingInvariantTest` and
  `ExactPriorityInvariantTest` (64 runs × depth 64, fail-on-revert): escrow equals outstanding obligations, asset
  conservation, best prices against a linear scan, the best order is exact limit then bid then age, and the hook
  holds no USDC beyond escrow.
- Regression suites in `test/security/` and `test/nethermind_auditagent/`; Python reference vectors for exact
  eligibility and priority; single-call bytecode property checks in `test/formal/`. The Lean models those checks were
  written from are not maintained and are not part of this repository.
- Coverage of `src/`: 99.82% lines, 99.10% statements, 97.61% branches, 100% functions. Three branches are defensive
  and unreachable, so they stay uncovered: the clamp at v4's minimum price in `TickPrice.poolBeatsLevel` (a swap that
  lowers the tick has its limit moved one tick up, so it never lands on `MIN_TICK`), the zero floor of the fee-window
  subtraction (the pool's key always exceeds half its gap to the reference), and the no-liquidity case of
  `DynamicFeeOrdering._pay` (a pool fill that leaves no active liquidity reverts first).
- Runtime sizes (EIP-170 limit 24,576): AsyncSwap 23,669 bytes, AsyncMatching 24,135, Router 22,131, TickPrice
  5,204, FeeVault 2,320, TokenClaims 2,110, NativeClaims 1,964.

```sh
forge test
forge coverage --skip 'test/formal/AsyncSwapBeforeSwap.t.sol' --report summary --no-match-coverage '(test|script|dependencies)/'
```

## Deployments

The testnets run `bc95df4`: Unichain Sepolia (1301) and Robinhood Chain testnet (46630), with `minOrder` 0 and the
asset floor; addresses are in `deployments/<chainId>/` and [`docs/deployments.md`](../docs/deployments.md). Its
`src/` is the same as `fdfdf65`, so it **does not** include the Router rule above: on those hooks a maker can still
revoke the Router. No mainnet deployment exists; see [`../MAINNET_READINESS.md`](../MAINNET_READINESS.md).
