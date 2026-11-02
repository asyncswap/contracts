# Audit scope: Async Swap (2026-10-23)

> Superseded by [`AUDIT_SCOPE_11_01_26.md`](AUDIT_SCOPE_11_01_26.md). Kept for history.

Supersedes [`AUDIT_SCOPE_10_19_26.md`](AUDIT_SCOPE_10_19_26.md), which froze the code at `dc8042d`.

- **Repository:** <https://github.com/asyncswap/contracts>
- **Code frozen at:** `830cd9e378b9cfbdc2e968c91a3d71448c773eb3` on `main` (2026-10-23).
- **Compiler:** solc 0.8.26, optimizer on (`optimizer_runs = 1_000`); see `foundry.toml`.
- **Chain:** Unichain (130) first; any EVM chain with Uniswap v4 later.
- **Builds on:** Uniswap v4 `PoolManager` (hooks, ERC-6909 claims), Permit2 for signed orders, OpenZeppelin
  `SafeERC20`.

## What it is

Async Swap is a Uniswap v4 hook that turns swaps into limit orders. Makers escrow their input in the hook and set
a minimum output. Every pool pairs an asset with USDC (the numeraire). Orders are filled by matching against each
other, by permissionless fillers, or against the pool's own liquidity.

- **Book.** Orders are indexed by price bucket. Within a bucket they rank by escrowed priority bid, then
  arrival. Exact rational limits, not buckets, decide which orders can trade: subtree price summaries find the
  highest-priority order that actually crosses, so an incompatible order at the head of a bucket cannot block
  it. New orders and any crossed backlog share one book-wide selection, at most eight pairs per call.
- **Settlement.** Book matches credit both sides, and any remainder left below the pool minimum, as PoolManager
  ERC-6909 claims. Holders redeem them through `TokenClaims` (ERC-20) or `NativeClaims` (ETH). Filler and
  pool-liquidity fills pay ERC-20 output directly; native output is credited as claims.
- **Priority bids.** Paid in USDC and escrowed when the order is created. Each fill settles its proportional
  share and the rest settles when the order closes. Every settled bid goes to `FeeVault`, never to LPs.
- **Minimum order.** The owner sets a per-pool minimum in USDC base units; a remainder that falls below it is
  closed and refunded as claims.

## In scope: 3,156 nSLOC

nSLOC counts non-blank lines outside comments (the same method reproduces every count in the 10-19 scope).
"Changed" is the diff against the previous freeze, `dc8042d`.

### Contracts (`src/`): 2,268 nSLOC, 16 files

| File | nSLOC | Since `dc8042d` | Notes |
|---|---:|---|---|
| `src/AsyncSwap.sol` | 429 | changed | The hook: order creation in `beforeSwap`, fills, cancels, matching entry points, ownership, minimum order |
| `src/libraries/AsyncMatching.sol` | 372 | **heavily changed** | Book-wide pair selection, match amounts, reductions, claim payouts, pool-liquidity fills |
| `src/libraries/AsyncFiller.sol` | 348 | **heavily changed** | Order storage, escrow, fills, cancels, priority levels, bid settlement, minimum checks |
| `src/Router.sol` | 256 | changed | User entry points: swap, signed swap (Permit2), fill, cancel, signed cancel, matching, pool fills |
| `src/MatchingEngine.sol` | 188 | unchanged | Standalone matching benchmark harness; holds no tokens and is not deployed |
| `src/BaseHook.sol` | 171 | unchanged | Uniswap v4 hook base |
| `src/libraries/RadixPriceTree.sol` | 136 | changed | Patricia index of price levels and priority keys, with node-id reuse |
| `src/libraries/OrderSignatures.sol` | 104 | unchanged | EIP-712 order, cancel, executor and reprice signatures |
| `src/libraries/EligiblePrice.sol` | 81 | **new** | Exact subtree price summaries over the priority tree; eligible-order search |
| `src/FeeVault.sol` | 34 | unchanged | Holds protocol fee and priority-bid claims; owner collects |
| `src/TokenClaims.sol` | 33 | **new** | Redeems a holder's ERC-20 PoolManager claims to any recipient |
| `src/NativeClaims.sol` | 32 | unchanged | Redeems a holder's native-ETH claims to any recipient |
| `src/libraries/CurrencySettler.sol` | 26 | unchanged | Settle/take helpers |
| `src/interfaces/ISignatureTransfer.sol` | 24 | unchanged | Permit2 interface |
| `src/types/AsyncOrder.sol` | 21 | changed | Order struct and id |
| `src/ImmutableState.sol` | 13 | unchanged | PoolManager reference |

### Scripts (`script/`): 888 nSLOC, 14 files

| File | nSLOC | Since `dc8042d` | Notes |
|---|---:|---|---|
| `script/FFIHelper.sol` | 142 | changed | FFI helpers; minimum priority bid, approvals, and reading an order's assigned salt from chain |
| `script/Trade.s.sol` | 122 | changed | End-to-end trading flows on a deployment |
| `script/01_DeployHook.s.sol` | 105 | changed | Hook deployment: CREATE2 salt, owner, numeraire, default minimum order, post-deploy checks |
| `script/config/UniswapAddresses.sol` | 94 | unchanged | Per-chain PoolManager, Permit2 and USDC addresses |
| `script/03_Swap.s.sol` | 84 | changed | Place an order through the Router (authorizes the Router, pays the minimum bid) |
| `script/lib/Deployments.sol` | 70 | unchanged | Reading and writing deployment records |
| `script/InitPool.s.sol` | 66 | unchanged | Pool initialization |
| `script/02_InitializePool.s.sol` | 46 | unchanged | Pool initialization (dynamic fee, USDC pair) |
| `script/00_DeployMatchingLibrary.s.sol` | 35 | unchanged | Deploy and link `AsyncMatching` |
| `script/00_DeployPoolManager.s.sol` | 34 | unchanged | Local PoolManager for testing |
| `script/05_ExecuteOrder.s.sol` | 40 | changed | Fill an order at its live amounts |
| `script/04_CancelOrder.s.sol` | 22 | unchanged | Cancel an order |
| `script/DeployTokenClaims.s.sol` | 14 | **new** | Deploy `TokenClaims` |
| `script/DeployNativeClaims.s.sol` | 14 | unchanged | Deploy `NativeClaims` |

Supporting deployment tooling (not Solidity; review for correctness of what gets deployed, not counted in nSLOC):
`script/deploy.sh`, `script/deploy-unichain.sh`, `script/deploy-arc.sh`, `script/mine-hook-salt.ts`, `script/price.ts`,
`script/sync-deployment-record.py`, `script/check-mainnet-readiness.sh`, `script/stress-matching-engine.sh`,
`script/config/chains.json`.

For the scripts, the questions are: does the hook get deployed with the intended owner, numeraire, flags, default
minimum order and linked library; are the per-chain addresses right; can a deployment be front-run or left
half-configured. (An earlier finding, M-02, was a deploy-script bug that made the CREATE2 deployer the hook owner.)

The order scripts (`03_Swap`, `Trade`, `05_ExecuteOrder`, `04_CancelOrder`) were fixed in `830cd9e` and run end to
end on Anvil: deploy, initialize a pool, place, fill and cancel.

Out of scope: `test/`, `dependencies/`, `docs/`, `site/`.

## Where to look hardest

- **Exact eligibility** (`EligiblePrice.sol`, `AsyncMatching._bookPair`, `AsyncFiller` append/remove/refresh):
  subtree summaries must stay exact through insertion, removal, repricing, node-id reuse and every partial fill,
  including fills that change neither the price key nor the bid. A stale summary could hide a crossing order or
  select one that does not cross.
- **Escrow conservation across partial matches**: both orders are reduced before either leg pays out; remainders
  keep the maker's own limit (`ceil(minimum × remaining / input)`); a remainder below the pool minimum is closed
  and refunded as claims.
- **Claim payouts** (`_transferEscrow`, `TokenClaims`, `NativeClaims`): match legs burn hook claims and mint the
  recipient's, so matching runs no token code; redemption burns before paying and must restore claims and
  allowance on failure.
- **Priority-bid escrow and settlement**: bids are minted as hook claims at creation and settled to `FeeVault`
  proportionally per fill and in full on close, cancel, fill or pool fill; the hook must never end a transaction
  owing an unpaid bid, whichever executor created the order.
- **Maker/taker and price**: the order created first (`createdSequence`) is the maker and sets the price;
  repricing resets queue position (`sequence`) but not that.
- **Ordering of state changes and external calls** in `fill`, `fillFromPoolLiquidity` and the Router's fill path
  (`_requireUnchanged` after the ERC-20 pull).

## Trust assumptions

- **Owner** (two-step `transferOwnership` / `acceptOwnership`): sets each pool's minimum order (`setMinOrder`)
  and the default for new pools (`setDefaultMinOrder`), sweeps tokens sent to the hook by mistake (`sweep`;
  escrow lives in PoolManager claims, not the hook's balance), and collects fees and bids from `FeeVault`.
  Trusted not to grief, but must not be able to take makers' escrow.
- **Executors**: a maker authorizes executors per pool (`setExecutor` or `setExecutorWithSig`); the Router is
  the usual one. An executor can only act on that maker's orders.
- **Fillers / matchers**: anyone; permissionless.
- **Tokens**: USDC plus standard ERC-20s and native ETH. Fee-on-transfer and rebasing tokens are not supported.

## Known issues (do not report)

- **Fees round to zero on dust orders.** The protocol fee is exactly the documented share of gross; on orders under
  roughly 500 base units it rounds to 0 (under $0.0005 for 6-decimal USDC). Acknowledged.
- **Priority bids are non-refundable.** The filled share settles as the order fills and the remainder when it
  closes, including on cancellation; all of it goes to `FeeVault`. By design.
- **Tokens with recipient callbacks (e.g. ERC-777)** are not supported. Matching no longer pays out in tokens, so
  it runs no recipient code; filler and pool-liquidity fills still transfer ERC-20 output, after the order is
  closed.
- **Proceeds are claims.** A recipient of a match must redeem through `TokenClaims` or `NativeClaims` to receive
  tokens. Intended.
- `MatchingEngine.sol` matches an incoming order before a crossed backlog; it is a benchmark harness, not
  deployed (AuditAgent finding 8, acknowledged).
- Release items in `MAINNET_READINESS.md` (deployment rehearsal, bytecode pinning, throughput stress, deploying the
  claim redeemers) are operational, not code findings.

## Previous audits

| Report | Scope | Result |
|---|---|---|
| Lee, 33 Labs (2026-05-08) | Earlier design, never launched (`asyncswap/protocol`) | C-01, H-01..H-04, L-02, L-03, I-01 fixed; L-01 works as intended |
| H-05 follow-up (2026-08-08) | Earlier design | H-05 fixed; native reentrancy hardening |
| AI-assisted review (2026-10-10) | Earlier design at `760699a` | M-01, M-02, L-01..L-03, I-01, I-03 fixed; I-02 acknowledged |
| Pre-freeze review (2026-10-19) | Matching engine | Unpaid priority bid could freeze a pool: fixed in #9 |
| Nethermind AuditAgent (scan `ae602e60`) | `e04668e` | All 12 findings and 2 related issues fixed or acknowledged; see [`auditagent_report_1_status.md`](auditagent_report_1_status.md) |

Earlier reports and per-finding evidence: <https://github.com/asyncswap/protocol/tree/dev/audits>. Every fix
carries over and has a regression test in `test/security/` or `test/nethermind_auditagent/`.

## Testing

At the freeze commit:

- `forge test`: 833 passing, 0 failing, 1 skipped (the Unichain fork suite runs with `UNICHAIN_FORK_RPC_URL` and
  `UNICHAIN_FORK_BLOCK=61279110`).
- 10 invariants across `MatchingInvariantTest`, `PriorityMatchingInvariantTest` and `LpMatchingInvariantTest`
  (64 runs × depth 64, fail-on-revert): escrow equals outstanding obligations, asset conservation, best prices
  against a linear scan, and the hook holds no USDC beyond escrow.
- Regression suites in `test/security/` and `test/nethermind_auditagent/`; `test/TokenClaims.t.sol`; Python
  reference vectors for exact eligibility and priority (`EligiblePythonVectors`, `PriorityPythonVectors`);
  single-call bytecode property checks in `test/formal/`.
- Coverage of `src/`: 99.9% lines, 99.4% statements, 98.8% branches, 100% functions.
- Runtime sizes: AsyncSwap 19,237 bytes, AsyncMatching 19,064, Router 17,580 (EIP-170 limit 24,576).
