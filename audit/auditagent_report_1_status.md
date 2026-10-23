# AuditAgent report 1: status

Tracks [`auditagent_report_1_ae602e60-d592-45ec-92ef-891968f087f0.md`](auditagent_report_1_ae602e60-d592-45ec-92ef-891968f087f0.md)
(Nethermind AuditAgent, scan `ae602e60`, commit `e04668ec`), plus two findings of the same kind found
while fixing it.

| Status | Meaning |
| --- | --- |
| **Fixed** | Code changed; a regression test fails on the old code and passes on the new. |
| **Acknowledged** | Kept as is on purpose; the reason is recorded. |
| **Not fixed** | Open; needs a design decision. A recommended option is given. |

## Summary

| # | Severity | Finding | Status |
| --- | --- | --- | --- |
| 1 | High | `fill` pays out while the order is still live | **Fixed** |
| 2 | High | `fillFromPoolLiquidity` pays before removing the order | **Fixed** |
| 3 | Medium | Coarse `_priceKey` buckets: a non-crossing head blocks its level | **Fixed** |
| 4 | Medium | Temporary LPs capture priority bids / divert `FeeVault` forfeits | **Fixed** |
| 5 | Medium | Filler `maxPrice` caps payment, not the input received | **Fixed** |
| 6 | Medium | Favorable partial fills weaken the remaining limit | **Fixed** |
| 7 | Medium | Custom executors can skip the priority bid | **Fixed** |
| 8 | Medium | New orders bypass a crossed backlog left by the 8-match cap | **Acknowledged** (harness) / **Fixed** (live) |
| 9 | Medium | An unreceivable ERC-20 payout blocks matching | **Fixed** |
| 10 | Medium | `updatePrice` resets `sequence`, flipping maker/taker of a crossed pair | **Fixed** |
| 11 | Low | Deleting an emptied level costs gas in its historical peak | **Fixed** |
| 12 | Low | One dust order blocks `setOrderingMode` | **Fixed** |
| R-1 | — | Router fill checks the order, pulls ERC-20, then executes | **Fixed** |
| R-2 | — | A new order is matchable before its input is settled | **Fixed** |

Every finding is now fixed or acknowledged; none is open. Policy changes made alongside: a
[minimum order and tiered priority bid](#minimum-order-and-tiered-bid), and
[priority-fee-only pools](#priority-fee-only-pools) (closes 7 and 12).

The fixes are on `main`; no deployment has been made. Storage layout and public ABI changed, so they
ship as fresh contracts, not as an upgrade.

## Fixed

### 1, 2: order state is final before any payout
An ERC-20 payout runs the token's code while the PoolManager is still unlocked, and the hook's own
entry points (`cancelOrder` by the owner, `matchBook`, `updatePrice`, `executeOrder` by an executor)
are callable from there. The order must already be closed or reduced when that code runs.

- `AsyncFiller.fill`: the order is removed, deleted and its paid bid settled (`_closeOrder`) before
  the maker's output, the fee and the filler's input are paid.
- `AsyncMatching.fillFromPoolLiquidity`: the order is removed and deleted before the pool swap and the
  maker's payout.
- `AsyncMatching._matchPair`: recipients are read first (`_payouts`), both orders are reduced, then
  the two escrow legs pay out (`_settleTransfers`). Since the fix for 9, those legs credit PoolManager
  claims and run no token code at all.

Tests: `test/nethermind_auditagent/NethermindAuditAgent.t.sol`
`test_H1_fill_orderClosedBeforeMakerPayout`, `test_H2_poolLiquidityFill_orderClosedBeforeMakerPayout`
(a token notifies the paid maker, which only reads the order's record) and
`test_H1_match_orderReducedBeforeMakerPayout` (the match credits claims and the token's code never runs).

### 3: exact eligibility inside coarse price buckets

`EligiblePrice` augments each priority radix tree with exact subtree price extrema. A lookup
returns the highest-fee, earliest-sequence order that crosses the counterparty in at most 128
branches. Noncrossing heads remain open and no longer hide eligible lower-priority orders.
For a resting equal-key book, selection maximizes buy priority first, then eligible sell priority.
Append/remove and every live partial fill maintain the extrema, including unchanged-key/fee fills.

The original approximately 2-USDC blocker no longer stalls 20,000 USDC of executable orders.
`CoarsePriceBlockingTest` covers both incoming directions. `EligiblePythonVectors.t.sol` compares
514 operations and 132 matches against an independent rational-price Python oracle, including
both clamps, two-sided blockers, mutations, selected IDs, remainders, fees, and maker balances.
`EligiblePriceTest` checks subtree invariants, randomized mutations, full depth, and node reuse.

The index bound is independent of blocker count. Matching runs no token code (finding 9), so a
blocker cannot make it revert or burn gas through a payout. See `docs/price-key-crossing.md` and the
revised whitepaper for the argument.

### 4: priority bids always go to the `FeeVault`
`AsyncFiller.settlePriorityFee` no longer checks in-range liquidity: every settled bid (the filled
share on a match, the rest on close, cancel, fill or pool fill) is burned from the hook's claims and
minted to the `FeeVault`. Liquidity added for the moment of settlement receives none of it. (Active
LPs still earn the 30 bps fill fee on a pool fill, as on any Uniswap swap; that fee is not a bid.)

Tests: `test_M4_liquidityAddedBeforeFillGetsNoBid` (on the audited code the bid shows up as LP fee
growth), `test_filledPriorityBidGoesToFeeVaultNotActiveLps`, `test_lpCollectsFillFeeOnWithdraw`.

### 5: `order.amountIn` bounds what the filler receives
`Router.unlockCallback` (fill) reverts with `"Input below order.amountIn"` when the order's live input
is below `order.amountIn`. A missing order (live input 0) still reaches the hook's `OrderNotFound`.

Tests: `test_M5_RevertWhen_LiveInputBelowFillerExpectation`, `test_M5_fillSucceeds_WhenFillerAcceptsLiveInput`.

### 6: the remainder keeps the maker's own limit
`AsyncMatching._reduceAfterMatch` sets the remaining minimum to
`ceil(oldMinimum * remainingInput / oldInput)` instead of `oldMinimum - outputReceived`. A side
closes only when its input is used up; the early close-and-refund branch is gone.

**Behavior change:** an order that fills at a better price than its limit now keeps its unspent
input on the book at its own limit, where it used to be refunded. Three existing tests were updated:
`test_crossingOrdersMatchAndTransferEscrowedTokens`, `test_priorityFeeBreaksEqualPriceTiesAfterPricePriority`
(`test/AsyncSwap.t.sol`), `test_retryFillsPartiallyMatchedRemainder` (`test/PoolLiquidityFill.t.sol`).

Tests: `test_M6_favorablePartialFill_keepsRemainderLimit`, `test_M6_favorablePartialFill_keepsBuyerRemainderLimit`,
`test_M6_partialFillMeetingWholeMinimum_keepsRemainderResting`.

### 8 (live): one book-wide priority for arrivals and backlog
`AsyncMatching.matchIncoming` now runs `matchBook` on the whole book, within the same 8-match budget,
instead of matching only the new order against the best opposing level. A crossed backlog left by
the cap clears first, by price, then bid, then time; the new order takes its place in that queue.

Test: `test_M8_crossedBacklogClearsBeforeNewerOrder` (on the audited code a newer, worse-priced ask
fills while the older crossed ask stays on the book).

### 9: match payouts are claims
`AsyncMatching._transferEscrow` credits ERC-6909 claims in every currency, for both escrow legs and
for a remainder returned below the pool minimum. Holders redeem with the new `TokenClaims`
(`redeem(currency, recipient, amount)`, after approving it on the PoolManager), to any recipient the
token accepts. A recipient the token refuses therefore cannot revert a match.

Fills by a filler and pool-liquidity fills still pay the maker in ERC-20. A refused maker can only
fail its own order there: the pool fill runs behind a caught self-call and leaves the order resting,
and a filler fill reverts for that one order.

Tests: `test_M9_blockedRecipientDoesNotBlockMatch` (on the audited code the refused transfer reverts
the whole match), `test/TokenClaims.t.sol` (redemption, approvals, a refused transfer restoring claims
and allowance, re-entry).

### 10: the maker role survives a reprice
Each order now records an immutable `createdSequence`. `_matchPair` makes the order with the smaller
`createdSequence` the maker, whose limit sets the price. `updatePrice` still takes a fresh `sequence`,
which only sets queue position among equal-price, equal-bid orders.

Test: `test_M10_repriceKeepsMakerRole` (on the audited code the older buy's reprice flips the maker,
and the seller receives 11 instead of 12).

The regression tests for 4, 8, 9 and 10 were run against the audited commit `e04668e` with the current
`SetupHook` and its pools switched to priority-fee mode: each fails there on its own assertion and
passes on `main`.

### 11: an emptied price level is left in place
`AsyncFiller._remove` no longer deletes the `PriceLevel` when its last order leaves. Its FIFO links
are already zero and its priority tree is empty (root 0); deleting it only cleared the tree's
`nextNodeId` and `freeIds`, a cost that grew with the level's historical peak. Those ids are now
reused by later orders at that price.

Tests: no dedicated gas test.

### R-1: the Router fills only the order it checked
Found while fixing 1 and 2. The fill path read the order (live input, price, `maxPrice`), then pulled
the filler's ERC-20 with `safeTransferFrom`, which runs the token's code, then executed against
whatever storage held by then. A changed price already reverted (the hook's deltas no longer net to
zero); a reduced input did not. `Router` now re-reads the order after the pull and reverts with
`"Order changed during fill"` unless it is unchanged (`_requireUnchanged`).

Test: `test/security/RouterOrderWindow.t.sol` `test_RevertWhen_OrderChangesDuringFillPayment`.

### R-2: a new order is not matchable before its input is settled
Found while fixing 1 and 2. `_beforeSwap` puts the order on the book before the Router pulls the
maker's input and priority bid, and the Router's comment said it "only becomes matchable after this
maker's input has been settled". The permissionless `matchBook` did not enforce that. It now returns 0
while this pool holds the order pending in `PENDING_MATCH_ID_SLOT`, i.e. until `matchNewOrder` takes
it. An early match also needed the PoolManager to hold the token from other escrow or LP reserves.

Test: `test/security/RouterOrderWindow.t.sol` `test_pendingOrder_notMatchableBeforeInputSettled`.

## Minimum order and tiered bid

Async Swap targets institutional-size orders; small trades are better served by the AMM. Measured in
numeraire (USDC) base units:

- **Minimum order.** Each pool has a minimum (`setMinOrder(key, amount)`, owner only); pools start with
  the hook's `defaultMinOrder` (`setDefaultMinOrder`). `script/01_DeployHook.s.sol` sets it to $10
  (`DEPLOY_MIN_ORDER_USD`, scaled by the numeraire's `decimals()`). A buy's input must be at least the
  minimum; a sell's minimum output must be, and so must its input valued at the pool's current price,
  which keeps out sells that ask for the minimum but offer almost nothing. `updatePrice` re-checks it.
  The pool price is an estimate: an empty pool still shows its creation price, so this is an admission
  gate, not an oracle.
- **Remainders.** A partial match that leaves an order worth less than the minimum, by its own terms
  (no pool price), closes it and returns the remaining input as claims after both orders are reduced.
- **Tiered bid.** The least bid is `min($0.10, 0.1% of the order)`: $0.10 from $100 up, down to $0.01
  at the $10 minimum.

Tests: `test/security/MinimumOrder.t.sol`, including a sell and a buy remainder refunded below the
minimum, and the value check on a pool whose numeraire is `currency0`. Formal tests updated: the `addOrder` and `CreateOrderSpec`
fee guards, and `beforeInitialize`'s write set (now also `priceBooks[id].minOrder`).

Hook size: `updatePriceWithSig` called the internal `AsyncFiller.updatePrice`, inlining it into the
hook; it now goes through the linked `AsyncMatching.updatePrice` like `updatePrice`. `AsyncSwap` went
from 24,311 to about 20,200 bytes (EIP-170 limit 24,576).

## Priority-fee-only pools

Findings **7 and 12 are fixed** in the working tree. Every pool queues equal-price orders by
escrowed bid, then sequence. FIFO mode, its links, `setOrderingMode`, `orderingMode`, and the separate
`recordPriorityFee` call are removed. `orderBookOrder` now returns `sequence` and `priorityFee` in
its final two fields instead of FIFO neighbors; clients must update their ABI.

`addOrder` mints the bid's numeraire claims to the hook immediately. This creates a matching hook
debt in PoolManager; the unlock cannot finish until it is settled. The Router pays it with
`settleFor(hook)`. A custom executor cannot leave an order resting with an unpaid declared bid.
The tiered minimum still rounds down in base units, so a tiny order can have a zero minimum when
the pool minimum permits it. This change does not impose a universal $10 minimum.

Tests: `test/security/PriorityFeeOnly.t.sol` checks minimum bids on unconfigured pools, bid ordering,
rejection of an executor that skips payment, successful paid custom execution, equal-bid time ordering,
and removal of the mode setter. Existing placement,
settlement, cancellation and invariant fixtures now account for escrowed bids.

This changes storage layout and public ABI; deploy fresh contracts and update consumers. It is not
a migration of existing orders or deployed contracts.

## Acknowledged

### 8 (harness): `MatchingEngine`
`src/MatchingEngine.sol` is a standalone matching harness and gas benchmark; it holds no tokens.

## Running the tests

```sh
forge test --match-path "test/nethermind_auditagent/*"
forge test --match-contract RouterOrderWindowTest
forge test                                   # everything
```

## Validation

- `forge test`: **833 passed, 0 failed, 1 skipped** across 139 suites. The Unichain fork fixture skips
  without `UNICHAIN_FORK_RPC_URL`; no fork validation is claimed.
- `forge build --sizes`: runtime sizes are 19,237 bytes (`AsyncSwap`), 19,064 bytes (`AsyncMatching`)
  and 17,580 bytes (`Router`), each below the 24,576-byte EIP-170 limit.
- `forge coverage` of `src/`: 99.9% of lines, 99.4% of statements, 98.8% of branches, 100% of
  functions. The uncovered branches are unreachable guards (a matched amount above the order's input,
  `MatchingEngine`'s reentrancy check, a sell-only lookup).
- No deployment was performed.
