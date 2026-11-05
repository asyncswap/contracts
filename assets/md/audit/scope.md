# Audit scope: Async Swap (2026-11-05)

Supersedes the [2026-11-03 scope](https://github.com/asyncswap/contracts/blob/c9372ff/audit/AUDIT_SCOPE_11_03_26.md),
which froze protocol code at `2739d6c`. The prior findings and their dispositions are carried forward below;
passing tests are validation evidence, not a new security audit.

* **Repository:** [asyncswap/contracts](https://github.com/asyncswap/contracts)
* **Protocol and production deployment code frozen at:** `c9372ff9577ba3950fa321090a7bfb559fc964a4` on `main`.
  This includes the bitmap optimization (#77) and funded fee top-ups (#78). Check out this exact commit for
  the protocol review. Later release evidence and integration work do not change this frozen source.
* **Compiler:** solc 0.8.26, optimizer on (`optimizer_runs = 10_000`); see `foundry.toml`.
* **Chain:** Unichain (130) first; any EVM chain with Uniswap v4 later.
* **Builds on:** Uniswap v4 `PoolManager` (hooks, ERC-6909 claims, dynamic LP fee), Permit2 for signed orders,
  OpenZeppelin `SafeERC20`, `EIP712`, `SignatureChecker` and `Multicall`.

## Changes since the last freeze (`2739d6c`)

* **Bounded outer tick bitmap.** `TickBitmap` replaces the outer radix price index in `AsyncFiller.Book`;
  the inner Patricia priority tree remains. Check tick boundaries, empty levels, best-price selection and
  count consistency. This changes storage layout and requires a new deployment; no in-place migration exists.
* **Linked exact-price updates.** `EligiblePrice.refresh/remove` are now public linked-library calls to
  keep matching bytecode deployable. Verify caller storage layout, link addresses and summary repair.
* **Funded fee top-ups.** `Router.topUpPriorityFee(order, addedFee)` authenticates the maker, transfers the
  delta in the numeraire and credits the hook before `PriorityFeeUpdates` rekeys the inner queue and mints
  claims. The resulting remaining bid must meet the current minimum and fit uint64. Only the trusted Router
  can enter the hook endpoint. Price, input budget, original maker age and signed-reprice version stay intact;
  fee-tier FIFO age resets. Top-ups are non-refundable, untaxed by the Router's native MEV tax and do not
  invoke matching. Makers can batch a bounded matching call with multicall.
* **Payment callbacks and signatures.** The amendment reads live state after payment. A partial fill during
  payment changes the remainder to which the delta is added; closure reverts the entire transaction.
  Existing signed reprices and cancellations remain valid unless their own validity conditions change.
* **Deployment links.** Production and local deployment wrappers now link `TickBitmap`, `EligiblePrice`,
  and `PriorityFeeUpdates`, in dependency order. A supplied matcher override must match this build's
  predicted address; having code alone is insufficient.
* **Validation.** Independent linear-scan matching-model tests, bitmap boundary/property tests, funding
  and callback regressions, mixed top-up invariants, and public-Router gas measurements accompany the changes.

## What it is

Async Swap is a Uniswap v4 hook that turns swaps into limit orders. Makers escrow their input in the hook and set a
minimum output. Every pool pairs an asset with USDC (the numeraire). Orders are filled by matching against each
other, by permissionless fillers, or against the pool's own liquidity.

* **Pools.** Anyone can create a pool: the hook accepts one that pairs the configured USDC with an asset that has
  code and uses the dynamic-fee flag. The owner cannot open, close or configure pools.
* **Book.** Orders sit at price levels on v4 ticks (`TickPrice`: the floor tick of the exact limit, 0.01% apart).
  The outer index is a bounded bitmap. Within a level they rank by exact limit, then escrowed priority bid, then arrival (`EligiblePrice`); exact
  rational limits decide crossing. New orders and any crossed backlog share one book-wide selection, at most eight
  pairs per call.
* **Venue choice.** A new order goes to the better venue first (`TickPrice.poolBeatsLevel`). If the pool's price
  beats the best opposite level (inside the dynamic-fee window, counting the fee a fill back toward the reference
  would pay), the pool goes first, limited one tick short of that level and inside v4's price range, and the book
  matches the rest. Otherwise the book goes first and the pool must take all of any remainder. A pool fill that
  would leave no active liquidity reverts.
* **Fees.** Book matches and filler fills take 0.02% from what each side receives. Pool fills pay active LPs 0.02%
  and the protocol 0.01%, plus a dynamic fee (`DynamicFeeOrdering`) on a fill that moves the price back toward the
  first pool fill's starting tick within 2 blocks: half the gap it closes, half to LPs and half to `FeeVault`.
* **Settlement.** Book matches credit both sides, and any remainder left below the pool minimum, as PoolManager
  ERC-6909 claims, batched per call (`ClaimTransfers`). Holders redeem them through `TokenClaims` (ERC-20),
  `NativeClaims` (ETH) or `Router.withdrawClaims`. Filler fills and full pool fills pay ERC-20 output directly; native
  output, and a pool fill that leaves part of the order on the book, are credited as claims.
* **Priority bids.** Optional, paid in USDC and escrowed when the order is created. Each fill settles its
  proportional share and the rest settles when the order closes. Every settled bid goes to `FeeVault`, never to LPs. Makers may add funded USDC to the remaining bid through the Router; this changes fee priority without changing their limit price.
* **Minimums.** Fixed at deployment, no setter: an optional minimum order in USDC (`minOrder`, from a dollar amount
  and the numeraire's decimals; 0 by default) and an asset floor per pool (`minAssetAmount`, 10^(decimals − 4), so
  0.0001 of a token). The $0.10 bid cap is derived from the numeraire's decimals too.
* **Signed actions.** Permit2 order witnesses (`swapWithSig`), `SetExecutor`, `UpdatePrice` (binds the order's
  `createdSequence` and its `reprices` count; a reprice that lands after partial matches applies its signed price
  to the remainder) and `CancelOrder` (no order size: covers whatever remains). All use unordered nonces in one space.
* **Router.** The single trusted entry for order creation, and an executor makers can't revoke. `multicall` batches
  actions as the caller (not payable). Order creation and fills pay an MEV tax of the transaction's priority fee
  times `MEV_TAX_GAS` (per chain, fixed at deployment: 20,000,000 on Unichain and Unichain Sepolia, which order by
  priority fee), in `msg.value` on top of any native deposit, credited to `FeeVault` as native claims. The Router can
  cancel for a maker without an executor grant.

## In scope: protocol contracts, 2,824 nSLOC

Non-blank lines outside comments, using the same count that reproduces the prior 2,704 nSLOC.
There are 21 Solidity source files. Changes are relative to `2739d6c`; a zero line-count delta can still
contain a security-relevant change.

| File | nSLOC | Since `2739d6c` | Notes |
|---|---:|---|---|
| `src/AsyncSwap.sol` | 540 | changed (+9) | The hook: pool admission, order creation in `beforeSwap`, venue choice, fills, cancels, signed actions, executor grants, immutable minimums |
| `src/BaseHook.sol` | 171 | unchanged | Uniswap v4 hook base |
| `src/FeeVault.sol` | 34 | unchanged | Holds protocol fees, bids and MEV tax as claims; owner collects |
| `src/ImmutableState.sol` | 13 | unchanged | PoolManager reference |
| `src/MatchingEngine.sol` | 188 | unchanged | Standalone matching benchmark harness; holds no tokens and is not deployed |
| `src/NativeClaims.sol` | 32 | unchanged | Redeems a holder's native-ETH claims to any recipient |
| `src/Router.sol` | 337 | changed (+13) | Maker entry points, top-up funding, signatures, multicall, claims and MEV tax |
| `src/TokenClaims.sol` | 33 | unchanged | Redeems a holder's ERC-20 PoolManager claims to any recipient |
| `src/interfaces/ISignatureTransfer.sol` | 24 | unchanged | Permit2 interface |
| `src/libraries/AsyncFiller.sol` | 359 | changed (+2) | Order storage, escrow, fills, cancels, priority levels, bid settlement, minimum and asset-floor checks |
| `src/libraries/AsyncMatching.sol` | 458 | changed (+2) | Book-wide pair selection, match amounts, reductions, claim payouts, pool fills (full and partial), dust closes |
| `src/libraries/ClaimTransfers.sol` | 37 | unchanged | Batches claim credits for one matching call (34 entries) |
| `src/libraries/CurrencySettler.sol` | 26 | unchanged | Settle/take helpers |
| `src/libraries/DynamicFeeOrdering.sol` | 71 | unchanged | Backrun fee on pool fills inside a 2-block window |
| `src/libraries/EligiblePrice.sol` | 81 | changed (+0) | Linked exact subtree summaries, removal/repair and eligible-order search |
| `src/libraries/OrderSignatures.sol` | 110 | unchanged | EIP-712 types: order witness, cancel, executor, reprice |
| `src/libraries/PriorityFeeUpdates.sol` | 42 | new | Funded bid amendments, fee-tier rekeying and escrow claim minting |
| `src/libraries/RadixPriceTree.sol` | 136 | unchanged | Patricia index of inner priority keys, with node-id reuse |
| `src/libraries/TickBitmap.sol` | 52 | new | Bounded bitmap of occupied v4 tick levels; first/last occupied-bit search |
| `src/libraries/TickPrice.sol` | 59 | unchanged | Price keys on v4 ticks; pool-versus-book comparison and the pool-first limit |
| `src/types/AsyncOrder.sol` | 21 | unchanged | Order struct and id |

The linked libraries are `AsyncMatching`, `TickPrice`, `DynamicFeeOrdering`, `TickBitmap`, `EligiblePrice`
and `PriorityFeeUpdates`. Calls execute against hook storage. CREATE2 addresses depend on bytecode and
all linked dependencies, not merely the library name or salt.

### Supporting deployment review

Review these frozen files for the release, alongside the protocol security review: `script/deploy.sh`,
`script/local/up.sh`, `script/01_DeployHook.s.sol`, the six `00_Deploy*` library scripts,
`script/DeployTokenClaims.s.sol`, `script/DeployNativeClaims.s.sol`, `script/check-contract-sizes.py`,
`script/config/chains.json`, `script/config/UniswapAddresses.sol` and `script/FFIHelper.sol`.
Check dependency order and exact linked addresses, hook permission flags, constructor values, Router/hook
pairing, claim-redeemer PoolManager identity, registry start blocks and bytecode verification. These
supporting files are not included in the protocol nSLOC total. Operational rehearsals remain separate
from proof that the protocol is secure.

## Trust assumptions

* **Owner** (two-step `transferOwnership` / `acceptOwnership`): sweeps tokens sent to the hook by mistake (`sweep`;
  escrow lives in PoolManager claims, not the hook's balance) and collects fees, bids and MEV tax from `FeeVault`.
  It cannot open, close or configure pools or change minimums. Must not be able to take makers' escrow.
* **Router**: the hook trusts its immutable `router` as the only order-creation path, as an executor no maker can
  revoke, for grant-free cancels on a maker's behalf (the Router checks the owner or a signature), and for burning
  cancel nonces, and for maker-authorized, funded priority-fee amendments. A generic executor grant does not authorize spending a maker's USDC for top-ups.
* **Executors**: a maker authorizes executors per pool (`setExecutor` or `setExecutorWithSig`) and can revoke any of
  them except the Router. An executor can only act on that maker's orders.
* **Fillers / matchers / keepers**: anyone; permissionless.
* **Pool creators**: anyone, for any asset with code. A malicious asset must only be able to affect its own pool.
* **Tokens**: USDC plus standard ERC-20s and native ETH. Fee-on-transfer and rebasing tokens are not supported.

## Known issues (do not report)

Acknowledged in the reviews below:

* **Ways to race without the MEV tax** (Pashov 4, 5, 6, 9): a searcher can reprice its own resting order with
  `updatePrice` and settle it with `matchBook` (on the Router or directly on the hook, which needs no unlock), or
  pool-fill its own order through `tryFillOrderFromPoolLiquidity` with its own contract as executor. No user loses
  funds; the tax covers Router creation and fills only.
* **A partly matched order can fall behind an equal-priced order** (Pashov 7): the remainder's minimum rounds up, so
  its exact limit is one unit worse than the maker signed and its bid buys no priority. Pinned by
  `test_knownIssue_partlyMatchedOrderFallsBehindAnEqualOrder`.
* **Fees round to zero on dust orders** (LSP I-01): only with minimums off.
* **The MEV tax needs an exact `msg.value`**: the deposit plus `priority fee × MEV_TAX_GAS`. Wallets should send taxed
  calls with no priority fee; the app does.

By design:

* **A top-up is an additive action.** Repeating it in a new transaction spends the delta again. It resets fee-tier
  age, not maker age, and does not invalidate a previously signed cancellation or reprice. A multicall can
  commit a top-up even when matching succeeds with zero fills. These are explicit semantics, not fill guarantees.

* **Makers can't revoke the Router.** A maker who wants out cancels its orders (through the Router, by signature,
  or directly from its own unlock); the Router acts for a maker only when that maker calls it or signs.

* **Priority bids and top-ups are non-refundable.** All of a bid goes to `FeeVault`, including on cancellation or a dust close.

* **Tokens with recipient callbacks (e.g. ERC-777)** are not supported. Matching pays only claims and runs no
  recipient code; filler fills and full pool fills transfer ERC-20 output after the order is closed.

* **Proceeds are claims.** Recipients redeem through `TokenClaims`, `NativeClaims` or `Router.withdrawClaims`.

* **`DeployWithdrawalRouter`** deploys a testnet-only second Router for claims; the hook trusts only its own Router,
  so cancels through the second one fail.

* `MatchingEngine.sol` is a benchmark harness, not deployed (AuditAgent finding 8, acknowledged).

* Release items in `MAINNET_READINESS.md` (deployment rehearsal, bytecode pinning, throughput stress, deploying the
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

At the freeze commit (PR #78 validation):

* `forge test`: **1,024 passing, 0 failing, 0 skipped, 184 suites**, including the three pinned Unichain fork
  tests at block 61,709,000. Default solc 0.8.26; optimizer 10,000 runs. PR CI also passed with pinned Foundry 1.8.6.
* Invariants retain 64 runs × depth 64 with fail-on-revert. Handlers now interleave fee top-ups with submission,
  cancellation, repricing, matching, claim redemption and LP fills. They check escrow obligations, conservation
  and best exact-price/fee/age selection.
* `MatchingReference.t.sol` independently scans orders and calculates settlement. Fuzz campaigns use 256 runs
  of 64 mixed operations, plus deterministic backlog, maker-age and dust-closure cases. The model shares
  `TickPrice` only for the documented age reset when rounding moves an order to another tick.
* `PriorityFeeTopUp.t.sol` covers ownership, funding failure/short payment, zero/max bids, minimum admission,
  partial fills, both numeraire positions, configured decimals, multicall rollback and payment callbacks.
  `SignedOrders.t.sol` checks pending signed reprices and cancellations after top-ups.
* The **old freeze's coverage percentages have not been rerun for this source** and are not current coverage
  claims. The formal fixtures are executable bytecode checks; legacy Lean models are not maintained proofs
  of this release.
* Runtime sizes (limit 24,576 bytes): hook 24,159; matcher 24,225; Router 23,061; fee-amendment library 5,537;
  bitmap 696; exact-price library 1,966. Hook/matcher headroom is 417/351 bytes.
* [Bitmap measurements](https://github.com/asyncswap/contracts/blob/main/benchmarks/orderbook/README.md) compare the prior radix book with the optimized
  book before top-ups. [Top-up measurements](https://github.com/asyncswap/contracts/blob/main/benchmarks/topups/README.md) use actual Router receipts:
  186,710–235,267 gas over four fixtures, including intrinsic gas and refunds, excluding approvals/setup.
  Neither is a production-throughput guarantee.

```sh
git checkout c9372ff9577ba3950fa321090a7bfb559fc964a4
forge build
python3 script/check-contract-sizes.py
forge test
```

## Deployments

The v1.3.0 testnet registries record new hooks, Routers and linked libraries for this frozen source.
Previous deployment records remain available for existing orders. No in-place storage migration exists.
Unichain Sepolia uses test USDC; Robinhood testnet uses test USDG. See [deployments](/deployments)
for addresses, receipt blocks and release evidence. Testnet deployment does not clear the mainnet audit gate.
See [mainnet readiness](https://github.com/asyncswap/contracts/blob/main/MAINNET_READINESS.md) for the remaining audit and operational gates.
