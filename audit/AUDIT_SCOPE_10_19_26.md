# Audit scope: Async Swap

- **Repository:** <https://github.com/asyncswap/contracts>
- **Code frozen at:** `dc8042d3eff80d042f92b7cc4300cb3ef56a3c1f` on `main`.
- **Compiler:** solc 0.8.26, optimizer on (`optimizer_runs = 1_000_000`); see `foundry.toml`.
- **Chain:** Unichain (130) first; any EVM chain with Uniswap v4 later.
- **Builds on:** Uniswap v4 `PoolManager` (hooks), Permit2 for signed orders, OpenZeppelin `SafeERC20`.

## What it is

Async Swap is a Uniswap v4 hook that turns swaps into limit orders. Makers escrow their input in the hook
and set a minimum output. Orders are filled by matching against each other (a price-time or priority-fee
order book), by fillers, or against the pool's own liquidity. The pool's numeraire is USDC. Makers can bid
a priority fee (paid in USDC) to be filled first; it goes to the pool's LPs as a donation.

## In scope: 2,963 nSLOC

### Contracts (`src/`): 2,168 nSLOC, 14 files

| File | nSLOC | Notes |
|---|---:|---|
| `src/AsyncSwap.sol` | 430 | The hook: order creation in `beforeSwap`, fills, cancels, matching entry points, ownership, fees |
| `src/libraries/AsyncFiller.sol` | 351 | Order storage, escrow, fills, cancels, price levels (FIFO and priority), priority-fee settlement |
| `src/libraries/AsyncMatching.sol` | 378 | Order-to-order matching, partial fills, pool-liquidity fills (**new, never audited**) |
| `src/Router.sol` | 248 | User entry points: swap, signed swap (Permit2), cancel, signed cancel, matching |
| `src/MatchingEngine.sol` | 188 | Matching entry points and views (**new**) |
| `src/BaseHook.sol` | 171 | Uniswap v4 hook base |
| `src/libraries/RadixPriceTree.sol` | 145 | Best-price index for each side of the book (**new**) |
| `src/libraries/OrderSignatures.sol` | 104 | EIP-712 order and cancel signatures |
| `src/FeeVault.sol` | 34 | Protocol fee and forfeited priority-fee collection |
| `src/NativeClaims.sol` | 32 | Redeems native-ETH proceeds held as PoolManager ERC-6909 claims (**new**) |
| `src/libraries/CurrencySettler.sol` | 26 | Settle/take helpers |
| `src/types/AsyncOrder.sol` | 24 | Order struct and id |
| `src/interfaces/ISignatureTransfer.sol` | 24 | Permit2 interface |
| `src/ImmutableState.sol` | 13 | PoolManager reference |

### Scripts (`script/`): 795 nSLOC, 13 files

| File | nSLOC | Notes |
|---|---:|---|
| `script/01_DeployHook.s.sol` | 100 | Hook deployment: CREATE2 salt, owner, numeraire, post-deploy checks |
| `script/Trade.s.sol` | 123 | End-to-end trading flows on a deployment |
| `script/FFIHelper.sol` | 95 | FFI helpers used by the scripts |
| `script/config/UniswapAddresses.sol` | 94 | Per-chain PoolManager, Permit2 and USDC addresses |
| `script/03_Swap.s.sol` | 71 | Place an order through the Router |
| `script/lib/Deployments.sol` | 70 | Reading and writing deployment records |
| `script/InitPool.s.sol` | 66 | Pool initialization |
| `script/02_InitializePool.s.sol` | 46 | Pool initialization (dynamic fee, USDC pair) |
| `script/00_DeployMatchingLibrary.s.sol` | 35 | Deploy and link `AsyncMatching` |
| `script/00_DeployPoolManager.s.sol` | 34 | Local PoolManager for testing |
| `script/05_ExecuteOrder.s.sol` | 25 | Fill an order |
| `script/04_CancelOrder.s.sol` | 22 | Cancel an order |
| `script/DeployNativeClaims.s.sol` | 14 | Deploy `NativeClaims` |

Supporting deployment tooling (not Solidity; review for correctness of what gets deployed, not counted in nSLOC):
`script/deploy.sh`, `script/deploy-unichain.sh`, `script/deploy-arc.sh`, `script/mine-hook-salt.ts`, `script/price.ts`,
`script/sync-deployment-record.py`, `script/check-mainnet-readiness.sh`, `script/stress-matching-engine.sh`,
`script/config/chains.json`.

For the scripts, the questions are: does the hook get deployed with the intended owner, numeraire, flags and linked
library; are the per-chain addresses right; can a deployment be front-run or left half-configured. (An earlier finding,
M-02, was a deploy-script bug that made the CREATE2 deployer the hook owner.)

Out of scope: `test/`, `dependencies/`, `docs/`.

## Where to look hardest

The matching engine is new since those audits: `AsyncMatching.sol`, `RadixPriceTree.sol`, `MatchingEngine.sol`,
`NativeClaims.sol`, and the changes since then to `AsyncSwap.sol`, `AsyncFiller.sol` and `Router.sol`. In particular:
escrow conservation across partial matches, the priority-fee escrow and settlement, price levels (FIFO links and
priority keys), native ETH held as ERC-6909 claims, and whether any order can block matching.

## Trust assumptions

- **Owner** (two-step `transferOwnership` / `acceptOwnership`): sets each pool's ordering mode (only while the pool
  has no open orders), collects protocol fees from `FeeVault`. Trusted not to grief, but must not be able to take
  makers' escrow.
- **Executors**: a maker authorizes executors per pool (`setExecutor`); the Router is the usual one. An executor can
  only act on that maker's orders.
- **Fillers / matchers**: anyone; permissionless.
- **Tokens**: USDC plus standard ERC-20s and native ETH. Fee-on-transfer and rebasing tokens are not supported.

## Known issues (do not report)

- **Fees round to zero on dust orders.** The protocol fee is exactly the documented share of gross; on orders under
  roughly 500 base units it rounds to 0 (under $0.0005 for 6-decimal USDC). Acknowledged.
- **Priority bids are non-refundable** once an order fills; with no active liquidity they go to `FeeVault`. By design.
- **A matched token with a recipient callback (e.g. ERC-777)** could re-enter `matchBook` between paying out and
  reducing the orders. Traced through: the accounting holds (the outer reduction either reverts or matches a second
  real payment), but there is no explicit reentrancy guard. Such tokens are not supported.
- Release items in `MAINNET_READINESS.md` (deployment rehearsal, bytecode pinning, throughput stress) are operational,
  not code findings.

## Previous audits (all findings fixed)

| Report | Scope | Result |
|---|---|---|
| Lee, 33 Labs (2026-05-08) | Earlier design, never launched (`asyncswap/protocol`) | C-01, H-01..H-04, L-02, L-03, I-01 fixed; L-01 works as intended |
| H-05 follow-up (2026-08-08) | Earlier design | H-05 fixed; native reentrancy hardening |
| AI-assisted review (2026-10-10) | Earlier design at `760699a` | M-01, M-02, L-01..L-03, I-01, I-03 fixed; I-02 acknowledged |
| Pre-freeze review (2026-10-19) | Matching engine | Unpaid priority bid could freeze a pool: fixed in #9, invariant tests in #10 |

Reports and per-finding evidence: <https://github.com/asyncswap/protocol/tree/dev/audits>. Every fix carries over
and has a regression test in `test/security/`.

## Testing

`forge test`: 155 passing, 0 failing, 1 skipped (the Unichain fork suite runs with `UNICHAIN_FORK_RPC_URL` and
`UNICHAIN_FORK_BLOCK=61279110`). Includes matching invariants (escrow, asset conservation, best price), the unpaid-bid invariants
(`test/UnpaidBidInvariant.t.sol`: matching never reverts, crossing takers always trade, every order is cancellable,
unpaid bids buy no priority) and 17 security regression suites in `test/security/`. Hook runtime: 24,428 bytes
(148 under EIP-170).
