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
| 3 | Medium | Coarse `_priceKey` buckets: a non-crossing head blocks its level | **Fixed locally** |
| 4 | Medium | Temporary LPs capture priority bids / divert `FeeVault` forfeits | **Not fixed** |
| 5 | Medium | Filler `maxPrice` caps payment, not the input received | **Fixed** |
| 6 | Medium | Favorable partial fills weaken the remaining limit | **Fixed** |
| 7 | Medium | Custom executors can skip the priority bid | **Fixed** |
| 8 | Medium | New orders bypass a crossed backlog left by the 8-match cap | **Acknowledged** (harness) / **Not fixed** (live) |
| 9 | Medium | An unreceivable ERC-20 payout blocks matching | **Not fixed** |
| 10 | Medium | `updatePrice` resets `sequence`, flipping maker/taker of a crossed pair | **Not fixed** |
| 11 | Low | Deleting an emptied level costs gas in its historical peak | **Fixed** |
| 12 | Low | One dust order blocks `setOrderingMode` | **Fixed** |
| R-1 | — | Router fill checks the order, pulls ERC-20, then executes | **Fixed** |
| R-2 | — | A new order is matchable before its input is settled | **Fixed** |

Policy changes made alongside: a [minimum order and tiered priority bid](#minimum-order-and-tiered-bid),
and [priority-fee-only pools](#priority-fee-only-pools) (closes 7 and 12).

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
  the two escrow legs pay out (`_settleTransfers`).

Tests: `test/nethermind_auditagent/NethermindAuditAgent.t.sol`
`test_H1_fill_orderClosedBeforeMakerPayout`, `test_H1_match_orderReducedBeforeMakerPayout`,
`test_H2_poolLiquidityFill_orderClosedBeforeMakerPayout`. A token notifies the paid maker, which
only reads the order's record.

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

This is a local fix, not a deployed upgrade. The index bound is independent of blocker count;
external token execution can still revert or consume gas (finding 9). Incoming-vs-backlog priority
(finding 8), LP fee capture (4), and repricing age policy (10) remain separate issues. See
`docs/price-key-crossing.md` and the revised whitepaper for the argument and proof boundaries.

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
  (no pool price), closes it and returns the remaining input after both orders are reduced.
- **Tiered bid.** In PriorityFee mode the least bid is `min($0.10, 0.1% of the order)`: $0.10 from $100
  up, down to $0.01 at the $10 minimum.

Tests: `test/security/MinimumOrder.t.sol`. Formal tests updated: the `addOrder` and `CreateOrderSpec`
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

## Not fixed (decision needed)

### 4: priority bids follow instantaneous liquidity
The donate-or-forfeit decision and the recipients depend only on in-range liquidity at settlement, so
liquidity added for that moment receives the bid. Options: always route bids to `FeeVault`, or pay
only liquidity older than the settlement (needs per-position tracking).

### 8 (live): crossed backlog after the 8-match cap
`AsyncMatching.matchIncoming` matches a new order against the best opposing order and ignores an
existing crossed backlog on its own side. Option: clear the crossed book (`matchBook`) before matching
the incoming order, within the same match budget.

### 9: unreceivable ERC-20 payouts block matching
ERC-20 payouts are direct, so a recipient that cannot receive (e.g. a USDC-blacklisted maker) reverts
the whole match. The maker can still cancel while its input refund is receivable. Options: pay ERC-20
proceeds as PoolManager claims (pull), as native already is; or skip or evict an order whose payout
fails.

### 10: `updatePrice` resets `sequence`
The older order of a crossed pair is the maker, and `updatePrice` always assigns a fresh sequence,
even for an unchanged price, so either side can flip who sets the price. The amount moved is bounded
by the spread of the two limits. Options: keep the sequence when the price key does not change, or
decide maker/taker by something a reprice cannot reset.

## Running the tests

```sh
forge test --match-path "test/nethermind_auditagent/*"
forge test --match-contract RouterOrderWindowTest
forge test                                   # everything
```

## Priority-only validation

- Clean rebuild: `forge test --force` — **783 passed, 0 failed, 1 skipped**, across 123 suites.
  The Unichain fork fixture skips without `UNICHAIN_FORK_RPC_URL`; no fork validation is claimed.
- All six `PriorityFeeOnlyTest` regressions pass, along with the matching invariant campaigns.
- `forge build --sizes`: runtime sizes are 19,237 bytes (`AsyncSwap`), 18,120 bytes
  (`AsyncMatching`), and 17,580 bytes (`Router`), each below the 24,576-byte EIP-170 limit.
- No deployment was performed.
