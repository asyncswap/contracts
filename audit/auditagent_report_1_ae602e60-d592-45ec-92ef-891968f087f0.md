# AuditAgent report - Scan ID `ae602e60-d592-45ec-92ef-891968f087f0`

## Scan details

| Key | Value |
|---|---|
| Repository | asyncswap/contracts |
| Branch | `main` |
| Commit | `e04668ec...c294c5f7` |
| Scan ID | `ae602e60-d592-45ec-92ef-891968f087f0` |
| Scan type | Auditor Scan |
| Date | October 22, 2026 |
| Lines of code | 2,849 |
| Contracts in scope | 14 |
| Vulnerabilities found | 12 |
| Audit score | 50 |

## Contracts in scope

- `src/AsyncSwap.sol`
- `src/BaseHook.sol`
- `src/FeeVault.sol`
- `src/ImmutableState.sol`
- `src/MatchingEngine.sol`
- `src/NativeClaims.sol`
- `src/Router.sol`
- `src/interfaces/ISignatureTransfer.sol`
- `src/libraries/AsyncFiller.sol`
- `src/libraries/AsyncMatching.sol`
- `src/libraries/CurrencySettler.sol`
- `src/libraries/OrderSignatures.sol`
- `src/libraries/RadixPriceTree.sol`
- `src/types/AsyncOrder.sol`

## Findings summary

| Severity | Count |
|---|---|
| High | 2 |
| Medium | 8 |
| Low | 2 |
| Info | 0 |
| Best practices | 0 |
| Total | 12 |

## Code summary

AsyncSwap is an asynchronous on-chain limit order book and matching system built as a Uniswap v4 hook. Instead of executing swaps immediately against automated market maker (AMM) liquidity, the hook intercepts exact-input swaps on Uniswap v4 pools and converts them into open limit orders. Every pool initialized with the `AsyncSwap` hook is required to use dynamic LP fees and include a designated chain-specific `numeraire` currency (such as USDC) as one of its pair assets. Makers escrow their input tokens as ERC-6909 claims inside the Uniswap v4 `PoolManager`, ensuring that open-order custody remains segregated from raw contract balances and protocol fees.

### Architecture and Order Lifecycle

- **Order Creation and Escrow (`AsyncSwap` & `Router`)**: Makers submit orders through the `Router` either directly (`swap`) or gaslessly via a relayer (`swapWithSig`) using a Permit2 signature with the order details attached as a witness. When `PoolManager.swap` triggers `_beforeSwap`, the hook takes the maker's input into ERC-6909 escrow, generates a deterministic collision-resistant salt, inserts the order into the pool's order book, and returns a `BeforeSwapDelta` that nets out the swap amount so the underlying Uniswap v4 pool does not execute a standard AMM trade.
- **Radix Tree Indexing and Ordering Modes (`RadixPriceTree` & `AsyncFiller`)**: Each pool maintains separate bid and ask books indexed by 128-bit WAD-scaled price keys in a Patricia radix tree (`RadixPriceTree`), enabling efficient best-price lookups, insertions, and removals with node ID recycling. Within each price level, a pool operates in either `FIFO` mode (a doubly linked list ordered by submission sequence) or `PriorityFee` mode (a secondary radix tree ordered by a composite key of the maker's non-refundable USDC priority bid and sequence number).
- **Priority Fee Settlement**: In pools configured for `PriorityFee` ordering, makers attach a USDC priority bid (at least $0.10) settled into hook escrow. As an order is matched, filled, or cancelled, the settled priority fee is donated directly to active Uniswap v4 liquidity providers in that pool via `PoolManager.donate`, or routed to the `FeeVault` if the pool has no active LP liquidity.
- **Peer-to-Peer Order Book Matching (`AsyncMatching`)**: Immediately after an order's input is settled in the `Router`, the hook invokes `matchNewOrder` to match the incoming order against crossing resting orders on the opposing side of the book (up to 8 matches per transaction). Direct matches execute at the resting order's limit price, support partial fills, and incur no protocol filler fee. If a large order crosses more than 8 resting orders, anyone can call `matchBook` to continue clearing the crossed book.
- **Pool Liquidity Execution**: If a newly created order still has remaining input after peer-to-peer book matching, the hook attempts an atomic self-call (`fillOrderFromPoolLiquidity`) to swap the full remaining order against active Uniswap v4 LP positions with a 0.30% dynamic LP fee. If the pool lacks sufficient liquidity or cannot meet the maker's minimum output, the self-call reverts safely and the order rests on the book. Resting orders can be retried against pool liquidity at any time via `fillFromPoolLiquidity`.
- **External Filler Execution**: External fillers can fill a resting order in full via `Router.fillOrder` (which calls `AsyncSwap.executeOrder`). The filler provides the maker's live `amountOutMin` plus a 0.30% protocol fee in exchange for the maker's escrowed input. Fillers can specify a `maxPrice` parameter to protect themselves against makers front-running a fill with a price increase.
- **Order Management and Gasless Signatures (`OrderSignatures`)**: Makers can update the `amountOutMin` limit price of an open order (which re-queues the order with fresh time priority), cancel an open order to reclaim their escrowed input, or authorize/revoke executor addresses. The protocol supports EIP-712 gasless signatures for order creation, cancellation, price updates, and executor authorization, along with unordered nonce management.
- **Native ETH Claims and Fee Custody (`NativeClaims` & `FeeVault`)**: While ERC-20 payouts and refunds are transferred directly to recipients, native ETH proceeds and refunds are minted to recipients as ERC-6909 claims (currency ID 0) in the `PoolManager` to prevent native transfer griefing during settlement. Users can withdraw their native ETH claims at any time using the `NativeClaims` contract. All protocol fees from external fills and forfeited priority fees are minted as ERC-6909 claims to the dedicated `FeeVault` contract.
- **Standalone Matching Harness (`MatchingEngine`)**: The repository also includes a standalone `MatchingEngine` contract that implements a price-time radix order book without token custody or settlement, serving as an isolated matching engine and gas benchmark.

### Actors

- **Maker**: A trader who creates asynchronous limit orders, sets or updates limit prices, authorizes executors, and cancels unfilled orders.
- **Filler**: An external market participant or solver who fills resting orders in full by supplying the required output tokens plus the protocol fee in exchange for the maker's escrowed input.
- **Relayer / Keeper**: Any third-party caller who submits EIP-712 signed actions on behalf of makers (`swapWithSig`, `cancelWithSig`, `setExecutorWithSig`, `updatePriceWithSig`) or permissionlessly triggers order book clearing (`matchBook`) and pool liquidity fills (`fillFromPoolLiquidity`).
- **Executor**: A contract (primarily the `Router`) explicitly authorized by a maker to create, fill, or cancel orders on their behalf within the `AsyncSwap` hook.
- **Claim Holder**: Any user or maker who holds native ETH ERC-6909 claims in the `PoolManager` and redeems them for native ETH via `NativeClaims`.
- **Protocol Owner / Pending Owner**: The administrative entity authorized to accept protocol ownership and collect accrued protocol fees from the `FeeVault`.
- **PoolManager**: The core Uniswap v4 singleton contract that invokes hook lifecycle callbacks and `unlockCallback` functions.

### Main Entry Points

- `Router.swap`: Allows a **Maker** to submit a new asynchronous limit order with native ETH or ERC-20 input, settling the input and optional priority fee into `PoolManager` and triggering automatic book matching and pool liquidity fill attempts.
- `Router.swapWithSig`: Allows a **Relayer / Keeper** to submit a gasless limit order signed by a **Maker** via Permit2 witness transfer, optionally registering the `Router` as an authorized executor in the same transaction.
- `Router.fillOrder`: Allows a **Filler** to fill an open resting order in full by paying the maker's live minimum output plus the 0.30% protocol fee, subject to the filler's `maxPrice` slippage bound.
- `Router.cancelOrder`: Allows a **Maker** to cancel their open order and reclaim their escrowed input and settle any escrowed priority fee.
- `Router.cancelWithSig`: Allows a **Relayer / Keeper** to submit a **Maker**'s EIP-712 signature to cancel an open order and return the escrowed input to the maker.
- `Router.matchBook`: Allows any **Relayer / Keeper** to clear up to `maxMatches` (at most 8) crossed order pairs on a pool's order book inside a `PoolManager` unlock.
- `Router.fillFromPoolLiquidity`: Allows any **Relayer / Keeper** to retry executing a resting order in full against active Uniswap v4 LP liquidity.
- `Router.unlockCallback`: Invoked by the **PoolManager** during an unlock session to execute the dispatched router action (swap, gasless swap, fill, cancel, book match, or pool liquidity fill).
- `AsyncSwap.acceptOwnership`: Allows the nominated **Pending Owner** to complete a two-step ownership transfer and become the protocol owner.
- `AsyncSwap.setExecutor`: Allows a **Maker** to directly grant or revoke permission for an **Executor** address on a specific pool.
- `AsyncSwap.setExecutorWithSig`: Allows any **Relayer / Keeper** to submit a **Maker**'s EIP-712 signature granting or revoking permission for an **Executor** on a pool.
- `AsyncSwap.updatePrice`: Allows a **Maker** to directly update the `amountOutMin` limit price of their open order, re-indexing it in the book with a new sequence number.
- `AsyncSwap.updatePriceWithSig`: Allows any **Relayer / Keeper** to submit a **Maker**'s EIP-712 signature to update the `amountOutMin` limit price of an open order.
- `AsyncSwap.invalidateNonce`: Allows a **Maker** to mark an unused EIP-712 nonce as spent, revoking any unsubmitted signature using that nonce.
- `AsyncSwap.recordPriorityFee`: Allows the authorized **Executor** during order creation to convert a newly settled numeraire priority fee into a hook ERC-6909 claim and update the order's priority position.
- `AsyncSwap.executeOrder`: Allows an authorized **Executor** inside a `PoolManager` unlock to execute a full fill of an open order on behalf of a **Filler**.
- `AsyncSwap.matchNewOrder`: Allows the authorized **Executor** during order creation to match the newly created order against crossing resting orders and attempt a fallback fill against pool LP liquidity.
- `AsyncSwap.tryFillOrderFromPoolLiquidity`: Allows an authorized **Executor** inside a `PoolManager` unlock to attempt filling a resting order against active Uniswap v4 pool liquidity.
- `AsyncSwap.fillOrderFromPoolLiquidity`: Invoked via an external self-call by `AsyncSwap` to atomically execute a resting order against active Uniswap v4 pool LP positions.
- `AsyncSwap.matchBook`: Allows any caller inside a `PoolManager` unlock to match up to `maxMatches` crossed bid/ask pairs on a pool's book.
- `AsyncSwap.cancelOrder`: Allows a **Maker** or an authorized **Executor** inside a `PoolManager` unlock to cancel an open order and return escrowed funds to the maker.
- `AsyncSwap.receive`: Accepts native ETH transfers from a **Filler** or **Executor** and records the deposit in transient storage for same-transaction native-output settlement.
- `BaseHook.beforeInitialize`: Invoked by the **PoolManager** before pool initialization to verify that the pool includes the `numeraire` currency, uses dynamic fees, and initializes per-pool hook state.
- `BaseHook.beforeAddLiquidity`: Invoked by the **PoolManager** before liquidity is added to a pool.
- `BaseHook.beforeSwap`: Invoked by the **PoolManager** before a swap to escrow the exact input amount, create an open async order, and return a delta that bypasses standard AMM execution.
- `BaseHook.afterInitialize`, `BaseHook.beforeRemoveLiquidity`, `BaseHook.afterAddLiquidity`, `BaseHook.afterRemoveLiquidity`, `BaseHook.afterSwap`, `BaseHook.beforeDonate`, `BaseHook.afterDonate`: Standard hook entry points exposed to the **PoolManager** that revert as unimplemented in `AsyncSwap`.
- `NativeClaims.redeem`: Allows a **Claim Holder** (who has approved `NativeClaims` on the `PoolManager`) to burn their currency ID 0 claims and receive native ETH at a chosen recipient address.
- `NativeClaims.unlockCallback`: Invoked by the **PoolManager** during `redeem` to burn the caller's ERC-6909 claims and transfer native ETH.
- `FeeVault.collect`: Allows the **Protocol Owner** to withdraw all accumulated protocol fee claims for a given currency to a recipient address.
- `FeeVault.unlockCallback`: Invoked by the **PoolManager** during `collect` to burn the vault's ERC-6909 claims and transfer the underlying tokens to the recipient.
- `MatchingEngine.placeOrder`: Allows any user to place a buy or sell limit order in the standalone benchmark order book, matching up to 8 crossing orders immediately.
- `MatchingEngine.matchBook`: Allows any user to continue clearing up to `maxMatches` crossed pairs in the standalone benchmark order book.
- `MatchingEngine.cancelOrder`: Allows an order owner to cancel their active resting order in the standalone benchmark order book.

## Findings

### 1. `fill` leaves orders live during payouts, enabling reentrant withdrawals of pooled escrow

**Severity:** High  
**Contracts:** `src/libraries/AsyncFiller.sol`, `src/AsyncSwap.sol`, `src/libraries/AsyncMatching.sol`, `src/Router.sol`

#### Context

`AsyncSwap` escrows makers' input as hook-owned ERC-6909 claims in `PoolManager`. Claim balances are currency-specific and shared across pools, rather than isolated by order or pool. A full fill should exchange one order's input for the funded output and close that order exactly once. `Router.fillOrder` funds the gross output inside an unlock and calls `executeOrder`, which delegates through `AsyncMatching.fill` to `AsyncFiller.fill`; authorized custom executors can also call directly inside an unlock.

ERC20 payouts execute token code through `PoolManager.take` and can trigger recipient callbacks. Native payouts instead mint claims without invoking recipients. Pool initialization is permissionless subject to including the `numeraire` and using dynamic fees, so an attacker can introduce a callback-capable counterasset without obtaining protocol approval.

```solidity
// File: src/libraries/AsyncFiller.sol
// @auditagent> Payout precedes order invalidation
output.take(self.poolManager, order.owner, amountOutMin, output.isAddressZero());

if (fee != 0) {
    output.take(self.poolManager, feeVault, fee, true);
    emit OrderFeeAccrued(id, output, fee);
}

input.settle(self.poolManager, hook, amountIn, true);
input.take(self.poolManager, filler, amountIn, input.isAddressZero());
settleOrderPriorityFee(self, order.key, id, hook);
delete self.orders[id];
```

#### Root Cause

`AsyncFiller.fill` caches `amountIn` and `amountOutMin`, then calls `_remove`, but does not delete `self.orders[id]` until after both `output.take` and `input.take`. Consequently, a detached order still passes lifecycle functions' nonzero-`amountIn` existence checks during either payout. The hook's order-mutating entry points have no shared reentrancy guard, and `PoolManager` remains unlocked during the transfers.

In the default FIFO mode, `_remove` does not verify current membership or clear the removed order's linked-list pointers. Placing the target at the head of a level with a same-price successor lets a second removal reuse those stale pointers and decrement the level and book counts without underflow. This supports several independently reachable paths:

1. **Output callback followed by cancellation.** The attacker creates a USDC-input order against their callback-capable output token, plus a small same-price companion. During the maker's output payout, the token calls `AsyncSwap.cancelOrder` as an executor authorized by the attacker-maker. Alternatively, the output token can itself be `order.owner` and cancel directly without a separate cancellation grant, or invoke the maker contract to cancel. `cancel` accepts the live amount, removes the order again, deletes it, burns its input claims, and refunds the maker. The outer fill resumes with its cached `amountIn` and burns and pays that input again to the attacker-filler.

2. **Input callback followed by cancellation.** A callback-capable input token invokes the attacker contract when `input.take` pays the filler. If that contract is also the maker, it calls `cancelOrder` directly as owner. Although the legitimate fill has already burned and transferred the input, the storage record remains live, so cancellation burns and refunds the same amount again. The callback need only reenter once; no malicious output token is required.

3. **Nested execution of the same order.** During the output transfer, an authorized attacker executor funds another gross output payment and reenters `executeOrder` for the unchanged order. The companion permits the nested removal. Both fills use the original cached input amount and redeem it independently before deleting the same record.

4. **Repricing and requeueing before nested execution.** The output callback invokes the contract maker, which calls `updatePrice`, including with the unchanged positive minimum. Repricing checks liveness but not book membership, removes the detached order again, and reinserts it. The attacker then funds another output payment and executes the requeued order within the same unlock. The nested and outer fills each withdraw its input. In these zero-bid FIFO examples, the outer `settleOrderPriorityFee` can read zero from the record deleted by the nested operation and complete without detecting the duplicate withdrawal.

The matching paths expose the same unfinished lifecycle. `_matchPair` calls `_settleTransfers`, including callback-capable `_transferEscrow` payouts, before `_reduceMatchedOrders`. `fillFromPoolLiquidity` pays the maker before removing and deleting the order. Callbacks can invoke `updatePrice` and `matchBook` against these still-live records. In particular, an LP-fill payout can allow a partial match before the outer full fill deletes the remaining record. These matching variants require suitable opposing orders or LP liquidity and successful post-callback accounting; not every arbitrary nested mutation will complete.

#### Impact

Successful full-fill variants pay the target's input twice despite funding it once. Each duplicate redemption consumes an additional `amountIn` from the hook's shared currency claims, including backing belonging to unrelated pools whose makers never authorized the attacker. USDC itself need not support callbacks: a malicious output counterasset is sufficient to steal genuine USDC input escrow.

For example, a 100-USDC target and a 1-USDC companion, together with at least 99 USDC of other makers' claims, can fund two 100-USDC payouts. The attacker receives 200 USDC after depositing 101 USDC, netting 99 USDC before fees and other costs. In the input-callback variant, an attacker acting as both maker and filler also receives back the net output they supplied; the protocol fee remains a cost.

The resulting shortfall can expose both open-order input and paid priority-fee liabilities held in the hook's numeraire claims. Subsequent legitimate fills, cancellations, or matches can revert when claims are exhausted. Duplicate removal also corrupts book counts and, with exactly one successor, deletes its price level while leaving the successor's order live, potentially preventing normal matching, cancellation, or execution. The LP variant can additionally delete an order remainder after reentrant partial matching.

Loss is bounded by available shared claims, token reserves, and successful funding and settlement checks. Repetition and temporary or flash-loaned initial capital can scale extraction toward the available claim balance. Insufficient backing causes the transaction to revert. Native claim payouts do not provide the token-receipt callback used by these attacks, while legitimate ERC777-style assets can provide it without an attacker-issued token.

### 2. `fillFromPoolLiquidity` pays before removing the order, enabling reentrant theft of shared USDC escrow

**Severity:** High  
**Contracts:** `src/libraries/AsyncMatching.sol`, `src/AsyncSwap.sol`, `src/Router.sol`

#### Context

`AsyncMatching.fillFromPoolLiquidity` executes an order against active pool liquidity by burning its input claims, swapping the input, and paying the maker. It is reached both automatically through `Router.swap` → `AsyncSwap.matchNewOrder` and when retrying a resting order through `Router.fillFromPoolLiquidity` → `AsyncSwap.tryFillOrderFromPoolLiquidity`. Both routes use an external self-call to `fillOrderFromPoolLiquidity` so a failed attempt rolls back the swap while preserving the resting order.

A successful fill should consume the order's remaining input once, satisfy its stored minimum, and close the order. Maker inputs are held as hook-owned PoolManager ERC-6909 claims, pooled by currency across orders and pools rather than isolated per order.

```solidity
// File: src/libraries/AsyncMatching.sol
// @auditagent> Payout precedes order removal
output.take(self.poolManager, maker, amountOut, output.isAddressZero());
AsyncFiller._remove(self, book, id);
delete self.orders[id];
```

#### Root Cause

`fillFromPoolLiquidity` calls `_swapAgainstPool`, which burns the order's full input claims, but leaves its order record and book entry unchanged until after `output.take`. For ERC-20 output, this payout invokes the token's transfer logic while the already-spent order still appears fully funded and matchable.

An attacker controlling the output token and both sides of a prepared book match can exploit either entry path. For a resting-order retry, the attacker initially leaves noncrossing buy and sell orders open, then uses `updatePrice` to make the sell cross the buy before triggering the LP fill; repricing does not itself match them. For automatic filling, the attacker leaves an overpriced sell resting and submits a noncrossing USDC buy through `Router.swap`. During the buy's LP-output transfer, the token, acting as the sell-order maker, calls `updatePrice` to make the orders cross. In either case, the token callback calls the permissionless `AsyncSwap.matchBook` directly inside the existing PoolManager unlock.

The nested match treats the LP-filled buy as unspent. `_settleTransfers` pays the attacker-controlled seller by calling `_transferEscrow`, burning additional USDC claims from the hook's shared balance. The attacker makes this match partial, leaving both the buy's remaining input and minimum nonzero so it stays indexed. When execution returns, the outer LP fill successfully removes and deletes that reduced order without accounting for the additional input spent by the nested match.

Each settlement can leave PoolManager currency deltas balanced, so the unlock's zero-delta check does not enforce per-order escrow backing. The self-call's `try/catch` also provides no protection when both the nested match and outer LP fill succeed.

#### Impact

The additional USDC payment consumes claims backing unrelated makers' open orders, including orders in other pools sharing USDC. Those orders remain recorded as live, but subsequent fills or cancellations can revert because the hook no longer holds enough claims to honor their escrow obligations.

For example, a 100 USDC buy requiring 100 attacker tokens can spend its full input against LPs, then partially match a 50-token sell for another 50 USDC during payout. The seller receives that additional 50 USDC while other makers' obligations are left 50 USDC underbacked. Smaller nested matches can likewise extract 12.5 USDC or 10 USDC. In the latter case, a 100 USDC buy requiring 90 tokens can be LP-filled while the callback exchanges another 9 tokens for 10 USDC.

If the attacker also controls the pool's LP liquidity, they can recover the USDC received by their LP position from the original swap while retaining the additional USDC extracted through the book match. Repeated successful attempts can drain available shared USDC escrow. Each attempt is limited by the amount partially matched and the remaining hook-held claims; insufficient claims cause the nested burn to revert rather than produce a successful theft. Exploitation requires callback-capable ERC-20 output, a selectable crossing partial match, and liquidity satisfying the original order's full-input and minimum-output checks.

Severity Note:
- The payout must invoke attacker-controlled token code; a transfer that does not call back cannot enter matchBook from this path.
- Each successful attempt can take only the USDC burned by the nested partial match, and only while the hook still holds enough shared claims for that burn.

### 3. Coarse `_priceKey` buckets break exact-price priority and permit head-of-line blocking

**Severity:** Medium  
**Contracts:** `src/libraries/AsyncFiller.sol`, `src/libraries/AsyncMatching.sol`, `src/AsyncSwap.sol`, `src/Router.sol`

#### Context

`AsyncFiller` indexes bids and asks by a WAD-scaled raw-amount price key. Within each key, `bestAtPrice` selects the FIFO head or the order with the highest paid priority fee, using sequence to break fee ties. `AsyncSwap.matchNewOrder` invokes `AsyncMatching.matchIncoming` after an order's input is settled; permissionless continuation through `Router.matchBook` invokes `AsyncMatching.matchBook`. These paths should select the best exact opposing price before applying the configured tie-breaker. Direct trades execute at the resting order's limit, and unmatched incoming orders may subsequently attempt a pool-liquidity fill. Makers can also change live limits through `AsyncSwap.updatePrice`.

```solidity
// File: src/libraries/AsyncMatching.sol
bytes32 bidId = book.bestAtPrice(true, bidPrice);
bytes32 askId = book.bestAtPrice(false, askPrice);
// @auditagent> Noncrossing heads hide matches
if (!_crosses(bidPrice, askPrice, self.orders[bidId], self.orders[askId])) break;
```

#### Root Cause

`_priceKey` floors `amountIn * 1e18 / amountOutMin` for buys and `amountOutMin * 1e18 / amountIn` for sells, then clamps the result to `[1, type(uint128).max]`. Distinct exact limits therefore share a level, but `bestAtPrice` ranks that level by time or paid fee rather than exact price. The same compression is used when repricing orders and when recalculating remaining orders after partial matches.

For an 18-decimal asset paired with six-decimal USDC, an ordinary key step represents $0.000001 per token: approximately 1% of a $0.0001 price or 10% of a $0.00001 price. Prices below $0.000001 floor to zero and are clamped to key `1`; together with prices flooring to one, all raw quote/asset ratios below `2e-18` share that key. Upper-bound saturation also merges wider price ranges.

Both matching loops inspect only the selected order at each best key. For equal keys, `_crosses` correctly checks the selected orders' exact limits, but a failed check immediately breaks the loop. Rejecting that head does not establish that other orders in the same level are non-crossing. Repeated `matchBook` calls select the same unchanged heads and make no progress. The construction applies to expensive asks hiding cheaper asks and, symmetrically, low-priced bids hiding higher bids. In `PriorityFee` mode, a worse-priced order can obtain the same blocking position through a higher funded priority bid.

For example, an earlier FIFO ask selling `10e18` asset units for `109` USDC base units, a later ask selling `1e24` units for `10_100_000`, and a bid offering `10_500_000` for `1e24` units all have key `10`. The bid crosses the later ask but not the first. Its automatic `matchIncoming` call stops at the small first ask, and subsequent permissionless `matchBook` calls stop at the same pair. This is also reachable through authorized executors submitting orders directly through `PoolManager.swap` and calling `matchNewOrder` after input settlement.

The blocker can also be established through `updatePrice`. An attacker can place an ask for `10e18` asset units at `10_000_000` USDC units and update its minimum to `10_000_003`, retaining key `1_000_000`. Updating resets its sequence and re-appends it, but doing so before the honest orders arrive still leaves it ahead of them. A later ask for `1e24` units at `1_000_000_000_000` and a bid offering `1_000_000_200_000` for those units share that key; only the later ask crosses the bid.

If the worse-priced head does cross, the same selection error causes price-priority inversion rather than blocking. The exact crossing check establishes that the selected order satisfies the incoming limit, not that it offers the best available price. An older worse-priced order can win in FIFO mode, or a worse-priced seller can pay a higher priority fee to execute before a better-priced seller. Settlement then uses that selected resting order's price.

#### Impact

A small funded order can deny fee-free direct matching of substantially larger compatible orders without escrow proportional to the volume queued behind it. In the key-`10` example, only 10 low-priced tokens and no priority fee are required for the FIFO blocker. Both matching functions terminate at the affected best level, and repeated continuation calls can execute zero pairs despite compatible opposing escrow.

When the selected head crosses, takers can lose available price improvement and better-priced makers lose execution priority. For example, asks selling one billion tokens (`1e27` units) for 10,100 and 10,800 USDC both have key `10`. If their funded priority bids are respectively `100_000` and `110_000` USDC base units, a buyer offering up to 10,900 USDC for those tokens selects the worse ask and pays 10,800 rather than 10,100 USDC. The attacker captures 700 USDC of available price improvement before its priority fee. The difference can scale with order size and reach several percent for low-priced assets; clamped buckets can span wider relative ranges. Execution nevertheless remains bounded by the buyer's submitted limit.

If active pool liquidity is absent, insufficient, or cannot meet the order's minimum, the failed fallback is caught and affected orders remain open. If a pool fill succeeds, the incoming order may instead receive worse execution than the available book match and incur an LP fee. External/private fills remain another route, but charge a fill fee that direct book matching does not.

This does not directly steal escrow, force execution below a maker's minimum, disable every settlement route, or prevent authorized cancellation. The obstruction persists while the worse-priced order remains selected and non-crossing. Makers can cancel, reprice, obtain another fill, or wait for the blocker to be removed or filled; paid priority fees remain subject to their normal non-refundable settlement rules.

Severity Note:
- Loss from price inversion is bounded by the incoming order's own limit and, except at the clamped key bounds, by less than one price-key step.
- An incoming order can still fill against active pool liquidity when that path meets its minimum; that fallback does not match a hidden resting order at the same key.

### 4. `settlePriorityFee` lets temporary LPs recapture priority bids and divert `FeeVault` forfeitures

**Severity:** Medium  
**Contracts:** `src/libraries/AsyncFiller.sol`, `src/AsyncSwap.sol`, `src/libraries/AsyncMatching.sol`, `src/Router.sol`

#### Context

In `OrderingMode.PriorityFee`, makers escrow USDC bids as hook-owned ERC-6909 claims through `recordPriorityFee` to obtain same-price queue priority. These bids are intended to be non-refundable. `AsyncFiller.settlePriorityFee` distributes paid bids on cancellation, filler fills, pool-liquidity fills, and direct matching. Matches settle proportional shares, with any remaining bid settled when the order closes. If no liquidity is active, the fee goes to `FeeVault`; otherwise, `PoolManager.donate` distributes it to the currently in-range LPs.

```solidity
// File: src/libraries/AsyncFiller.sol
// @auditagent> Instantaneous liquidity selects recipients
if (self.poolManager.getLiquidity(key.toId()) == 0) {
    // No active LP can receive a PoolManager donation, so the non-refundable
    // bid is forfeited to the protocol FeeVault.
    self.numeraire.settle(self.poolManager, hook, amount, true);
    self.numeraire.take(self.poolManager, self.feeVault, amount, true);
    emit PriorityFeeForfeited(key.toId(), id, maker, amount);
    return;
}
uint256 amount0 = numeraire == key.currency0 ? amount : 0;
uint256 amount1 = numeraire == key.currency1 ? amount : 0;
self.poolManager.donate(key, amount0, amount1, "");
```

#### Root Cause

Both the donation-versus-forfeiture decision and the donation recipients depend exclusively on instantaneous in-range liquidity. `_beforeAddLiquidity` accepts arbitrary positions, and there is no liquidity-age or same-block/unlock eligibility restriction. An attacker can therefore control the liquidity receiving a bid while choosing when settlement occurs through several paths:

- Same-unlock matching: an attacker contract calls `PoolManager.unlock`, adds a large in-range position, invokes the unrestricted `AsyncSwap.matchBook` on crossed paid orders, then removes the position and collects the donation. The attacker can also fund its own crossing order and trigger incoming-order matching through an authorized executor. For matching that does not move the AMM price, flash accounting nets the add/remove principal, avoiding upfront LP capital; gas, rounding, and actual bid/order funding still apply.
- Self-cancellation: a contract maker can surround `AsyncSwap.cancelOrder` with liquidity changes in its own unlock because `cancel` permits `executor == order.owner`. Alternatively, in one transaction it can add a minimal position through one unlock, cancel through `Router.cancelOrder` in a second unlock, and remove and collect through a later unlock. Each sequential unlock must settle its own deltas. In an otherwise empty pool, even a minimal position changes a protocol forfeiture into a donation to the maker.
- Other completion triggers: temporary liquidity can surround permissionless `Router.matchBook`, an attacker-funded crossing order submitted through `Router.swap`, or `Router.fillOrder`, whose caller must pay the maker's output plus the protocol fee. `Router.fillFromPoolLiquidity` also lets an outside caller force a full AMM execution and bid settlement without fresh maker consent, provided the Router remains an authorized executor and the pool can satisfy the order's minimum.

An existing maker-owned or colluding LP can capture bids without adding a new position. Temporary positions need not have existed when the bids were paid or have provided meaningful execution liquidity. Removing them afterward does not reverse the consumed bid or restore the forfeited `FeeVault` revenue.

#### Impact

A maker controlling most active liquidity can obtain queue priority while recovering nearly all of its supposedly non-refundable bid, or cancel and recover that bid alongside its returned order input. Outside LP/filler attackers can similarly capture other makers' settled bids. Existing LPs receive only their diluted liquidity share, potentially negligible, and an otherwise empty pool loses the entire forfeiture that should have reached `FeeVault`, apart from rounding.

A successful forced `fillFromPoolLiquidity` execution can also earn the attacker its liquidity share of the 0.30% pool-fill swap fee. The maker still receives at least `amountOutMin`: this attack diverts bids and completion rewards rather than bypassing the maker's execution limit. New priority bids range from `MIN_PRIORITY_FEE` of 100,000 USDC base units ($0.10) to `MAX_PRIORITY_FEE` of `type(uint64).max`; partial matches expose proportional shares. Capture depends on the attacker's in-range liquidity share. Same-unlock, unchanged-price match/cancel paths avoid upfront LP principal and AMM price exposure, while sequential-unlock and swap/fill variants require funding and remain subject to execution, gas, and rounding costs.

Severity Note:
- Same-unlock principal netting assumes Uniswap v4 credits a donation to liquidity added earlier in that unlock and returns position principal when the pool price is unchanged.
- A capture is economically rational only when the attacker's in-range share of the settled bid exceeds gas and any liquidity that must be funded before an unlock ends. The minimum bid is 100,000 numeraire base units.

### 5. Filler `maxPrice` caps total payment but not the input received, so a maker can shrink the order and reprice into the cap

**Severity:** Medium  
**Contracts:** `src/Router.sol`

#### Context

`Router.fillOrder` lets any filler fill a resting order in full. The filler pays the order's live minimum output plus the protocol fee and receives the maker's remaining escrowed input via `HOOK.executeOrder`. Per the NatSpec, `maxPrice` protects fillers from a maker who front-runs them with `updatePrice` to bump the stored price. In the `FillOrder` branch of `unlockCallback`, the router reads `HOOK.asyncOrderInfo(poolId, id)`, adds `HOOK.calculatePoolFee(...)`, and checks the result against the transient `MAX_PRICE_LOCATION` value. It then pulls that amount from the filler and executes the fill. The native path in `fillOrder` performs the same live-price read and requires `msg.value == livePrice`.

```solidity
// File: src/Router.sol
// @auditagent> live amountIn discarded
(, uint256 livePrice) = HOOK.asyncOrderInfo(orderData.order.key.toId(), id);
livePrice += HOOK.calculatePoolFee(orderData.order.key.fee, livePrice);
uint256 maxPrice;
assembly ("memory-safe") {
    maxPrice := tload(MAX_PRICE_LOCATION)
}
// @auditagent> only total payment capped
require(livePrice <= maxPrice, "Price exceeds maxPrice");
```

#### Root Cause

Both the pre-unlock native check and the callback discard the first return value of `asyncOrderInfo`, which is the live remaining `amountIn`. The filler-supplied `order.amountIn` is never compared with it, and no per-unit price check exists. The protection therefore bounds only the total paid, not the quantity received.

The live `amountIn` of a resting order can shrink after the filler submits:
- Direct matching (`matchNewOrder` / `matchBook`) partially fills resting orders at their limit price.
- The maker can then call `updatePrice` / `updatePriceWithSig` to set any new `amountOutMin`.

Combining the two, a maker can cut the order to a fraction of its size and raise the remaining minimum until `net + fee` sits just under the filler's `maxPrice` (or equals `msg.value` on the native path).

Example: order A offers 100 X for at least 100 Y, and a filler submits `fillOrder(A, maxPrice = 100.3 Y)`.
1. The maker, from a second address, places a crossing order buying 90 X at A's price. `matchNewOrder` matches it against A at A's resting price, so the maker's two addresses just swap with each other at no net cost. A now has 10 X remaining with a minimum of about 10 Y.
2. The maker reprices A to about 100 Y.
3. The filler's transaction executes. The live gross is about 100.3 Y, which is at most `maxPrice`, so the filler pays 100.3 Y and receives only 10 X.

#### Impact

A filler can lose up to `maxPrice` minus the market value of the remainder actually delivered. In the example this is about 90 Y, captured by the maker. Even a filler who sets a tight `maxPrice`, exactly equal to the full-size price, is unprotected. The native path is also affected, because the maker only needs to choose a new minimum whose gross equals the pinned `msg.value`. The attack requires the maker to get the partial match and reprice ordered before the filler's transaction, e.g. through a public mempool, a builder, or a bundling contract using `updatePriceWithSig`.

Severity Note:
- Extraction requires a self-match that shrinks the resting input and a later price update that raises the remaining minimum so the gross payment still clears the filler's cap or equals the pinned native value.

### 6. Favorable partial fills weaken remaining limits or prematurely close orders

**Severity:** Medium  
**Contracts:** `src/libraries/AsyncMatching.sol`

#### Context

`AsyncMatching.matchIncoming` matches incoming orders against resting counterparties, while `matchBook` repeatedly matches the best bid and ask. Both use `_reduceAfterMatch` to update each order’s remaining input, minimum output, and book price. Unspent input should remain available at no worse than the maker’s last authorized minimum-output-per-input ratio unless the maker cancels or reprices it.

```solidity
// File: src/libraries/AsyncMatching.sol
uint256 remainingInput = oldInput - params.inputUsed;
// @auditagent> Favorable fills weaken limits
uint256 remainingMinimum = params.outputReceived >= oldMinimum ? 0 : oldMinimum - params.outputReceived;
```

#### Root Cause

`_reduceAfterMatch` calculates `remainingMinimum` by subtracting all `outputReceived` from `oldMinimum`, including output exceeding the proportional minimum for the input consumed. A favorable partial fill therefore credits its price improvement against the minimum required for unfilled input, weakening the remaining order’s authorized per-unit limit.

When `remainingMinimum` remains positive, the function stores the reduced minimum and derives a new book price from it. Subsequent `_crosses` and `_matchAmounts` checks use these weakened values. This permits a seller’s remainder to execute against a lower-priced resting bid during the same `matchBook` call, or a buyer’s remainder to execute against a later incoming ask above the buyer’s originally authorized maximum price.

If the favorable partial fill instead satisfies the entire `oldMinimum`, `remainingMinimum` becomes zero. The function then removes and deletes the order even when input remains, refunding that input rather than keeping it available for matching.

#### Impact

Both sellers and buyers can lose the benefit of favorable execution to a later counterparty:

- Seller through `matchBook`: a seller offers 100 tokens for at least 100 USDC. An earlier bid first purchases 50 tokens for 75 USDC. The remaining 50 tokens are then listed for only 25 USDC instead of at least 50 USDC. An attacker’s resting 25-USDC bid can purchase that remainder in the same call, capturing the seller’s 25-USDC price improvement.
- Buyer through `matchIncoming`: a buyer offers 100 USDC for at least 100 assets. A resting seller supplies 20 assets for 10 USDC, leaving 90 USDC escrowed but a minimum of only 80 assets instead of 90. If pool liquidity does not consume the remainder, an attacker can submit an ask supplying 80 assets for 90 USDC. The attacker receives 10 USDC more than the buyer’s original 1-USDC-per-asset limit permits for those assets.

In both examples, the victim still receives the original aggregate minimum; the loss is the earlier price improvement, not an aggregate-minimum shortfall. Capturing it requires a favorable partial fill and an executable counterorder at the weakened price. Separately, when a partial fill already satisfies the aggregate minimum, the remaining input is refunded and the order prematurely terminates without maker cancellation or repricing. That branch prevents further matching of the remainder but does not confiscate the refunded input.

### 7. Optional priority-fee escrow lets custom executors bypass mandatory bids

**Severity:** Medium  
**Contracts:** `src/AsyncSwap.sol`, `src/Router.sol`, `src/libraries/AsyncFiller.sol`, `src/libraries/AsyncMatching.sol`

#### Context

In `OrderingMode.PriorityFee`, orders must declare a bid of at least `MIN_PRIORITY_FEE`, or 100,000 numeraire base units. Paid bids are non-refundable: execution or cancellation distributes them to active LPs, or to the `FeeVault` when no active liquidity exists. `AsyncSwap._beforeSwap` escrows the order input and creates the order. The supplied `Router` then transfers the bid, calls `recordPriorityFee`, and invokes `matchNewOrder`. However, makers can authorize their own executors and submit swaps directly through the `PoolManager`.

```solidity
// File: src/libraries/AsyncFiller.sol
    priorityFeeEscrowed: priorityFee == 0
});
// @auditagent> Unpaid orders enter book
_append(self, book, id);
```

#### Root Cause

`AsyncFiller.addOrder` checks only the declared `priorityFee` against the minimum and maximum. It immediately appends the order to the active book even though a nonzero bid starts with `priorityFeeEscrowed` set to false. Creation establishes no additional PoolManager payment obligation for that bid; the separate `recordPriorityFee` call creates the bid claims and corresponding debit, but calling it is optional.

A maker can authorize a custom unlock executor through `setExecutor`, create an order through `PoolManager.swap` with a valid declared bid, and settle only the order input. By omitting both `recordPriorityFee` and `matchNewOrder`, the executor can finish the unlock while leaving the unpaid order active in the book.

Alternatively, the executor can omit only `recordPriorityFee` and call `matchNewOrder` against a funded crossing counterparty or suitable pool liquidity. Resting unpaid orders can also be processed through `matchBook`, retried through `tryFillOrderFromPoolLiquidity`, privately filled through `executeOrder`, or canceled through `cancelOrder`. None of these paths requires the mandatory bid to have been escrowed. `paidPriorityFee` instead returns zero, matching skips bid settlement, and full execution or cancellation deletes the order without collecting its declared bid. Partial matching also treats the unpaid bid as zero and can replace the remaining declared bid with zero.

#### Impact

Permissionless makers can occupy the active book without paying its mandatory admission cost, enabling cheaper book/storage griefing. They must still pay gas and escrow the order input, but unfilled create-and-cancel cycles return that input without paying the non-refundable bid.

The bypass also allows repeated executions and cancellations without the required priority-fee revenue. For each completed or canceled fee-bypassing order, at least 100,000 numeraire base units are not collected: the corresponding payment is denied to the `FeeVault` when no active liquidity exists at settlement, or to LPs when active liquidity exists. Deleting the order eliminates any later opportunity to collect its declared bid.

Unpaid orders correctly receive zero bid priority, so declaring a large unpaid bid does not obtain high-bid tie priority. The defect bypasses mandatory admission and payment requirements; it does not bypass input funding, normal fill settlement, or ordinary execution fees.

Severity Note:
- Each bypassed order withholds only the bid that was never escrowed. Because an unescrowed bid is sorted and settled as zero, declaring more than the minimum does not buy priority or increase the amount that should have been collected unless the bid is actually paid.

### 8. New orders bypass price-time priority and pick off crossed remainders after the eight-fill cap

**Severity:** Medium  
**Contracts:** `src/MatchingEngine.sol`, `src/libraries/AsyncMatching.sol`

#### Context

`MatchingEngine.placeOrder` matches an incoming order against at most `MAX_MATCHES_PER_CALL` (8) makers, then appends any remainder at its limit price. This can leave the book crossed. Permissionless `matchBook` continuation selects the best bid and ask, and `_clearOrders` uses the older order as maker, preserving its execution price. `MatchingEngine` only emits fill instructions and does not custody tokens. The live `AsyncMatching` library likewise provides bounded incoming-order and book-continuation paths, but settles matched orders through escrow transfers.

```solidity
// File: src/MatchingEngine.sol
bool incomingBuy = incoming.isBuy;
// @auditagent> Existing crossed priority ignored
(bool found, uint128 opposingPrice) = incomingBuy ? book.asks.best(false) : book.bids.best(true);
if (!found || (incomingBuy ? incoming.price < opposingPrice : incoming.price > opposingPrice)) break;

Level storage level = incomingBuy ? book.askLevels[opposingPrice] : book.bidLevels[opposingPrice];
uint64 makerId = level.head;
Order storage maker = book.orders[makerId];
uint128 quantity = incoming.remaining < maker.remaining ? incoming.remaining : maker.remaining;
_fill(book, market, makerId, incomingId, quantity, maker.price);
```

#### Root Cause

The incoming-order paths do not account for an existing crossed backlog. `MatchingEngine._matchIncoming` selects only the best opposing level and fills its head against the newcomer at the resting order's price. It never compares the newcomer with higher-priority orders already resting on its own side. `AsyncMatching.matchIncoming` has the same selection omission: it selects the best opposing order, while `_matchPair` determines the maker only within that selected pair.

This permits two forms of priority bypass, with example prices scaled by `PRICE_SCALE`:

- Liquidity diversion: nine one-unit asks at 100 followed by a ten-unit bid at 110 produce eight fills, leaving one ask and the bid's two-unit crossed remainder. A later one-unit bid at 100 takes the last ask before the older, better-priced bid. A later order can also bypass earlier same-price priority.
- Remainder pick-off: when a crossed bid remainder at 110 faces older asks at 100, a new sell order priced at or below 110 can execute against that remainder at 110, skipping the older asks. Continuation would instead pair the remainder with those older asks at 100. The attacker can then buy the displaced asks at 100. The directions reverse for sell remainders.

The crossed state can arise naturally when an order needs more than eight maker matches, or be forced through a dust sandwich. In the harness, nonzero amounts and prices suffice and no tokens are required. An attacker can front-run a large buy at 110 with eight one-wei asks at 99 ahead of real asks at 100. The victim exhausts its entire match budget on dust and rests crossed; the attacker then performs the sell-and-buy back-run before continuation clears the backlog.

#### Impact

Later, lower-priority orders can capture liquidity owed to existing orders, leaving those orders unfilled and depriving older opposing makers of priority. The pick-off path also removes price improvement from the capped taker. For a remainder quantity `Q` sold to the victim at 110 and repurchased from older asks at 100, the fill instructions represent approximately `10 * Q` in gross quote-value extraction before costs, provided sufficient older liquidity remains.

All fills can remain within the participants' declared limits. The attack depends on reaching the crossed backlog before a keeper clears it. Because `MatchingEngine` holds no assets, its demonstrated harm is incorrect fill allocation and pricing; monetary loss depends on a consumer settling those instructions. In live `AsyncMatching`, the same selection omission can deny timely execution to funded makers when a crossed remainder survives and no LP fallback fills it. This does not establish an unconditional token-loss exploit in the live settlement system.

Severity Note:
- Realized token loss is the price-improvement spread on the still-resting crossed remainder, and only if a later order matches before continuation clears that pair.

### 9. Direct ERC20 payouts let one unreceivable maker block matching and freeze order escrow

**Severity:** Medium  
**Contracts:** `src/libraries/AsyncMatching.sol`, `src/libraries/AsyncFiller.sol`, `src/AsyncSwap.sol`, `src/Router.sol`

#### Context

`AsyncSwap` escrows maker input as ERC-6909 claims in the PoolManager. `Router.swap` and `swapWithSig` settle the input before invoking `matchNewOrder`; `matchBook` continues matching an existing crossed book. `AsyncMatching` pays matched proceeds immediately, while `AsyncFiller.fill` pays the maker's output and `cancel` refunds escrowed input. Native payouts are minted as claims, but ERC20 payouts are direct token transfers.

```solidity
// File: src/libraries/AsyncMatching.sol
currency.settle(manager, hook, amount, true);
// Native output is minted as claims, so settlement makes no call to the recipient.
// @auditagent> Recipient failure aborts matching
currency.take(manager, recipient, amount, currency.isAddressZero());
```

#### Root Cause

`_transferEscrow` uses `currency.isAddressZero()` as the claims flag, making an ERC20 transfer to the recipient part of the matching transaction. `matchIncoming` and `matchBook` select the best-priced order and the first order under the configured FIFO or priority ordering, without isolating failed payouts or skipping an unreceivable counterparty. A token blacklist, paused transfers, or a reverting ERC777-style recipient hook therefore reverts the entire matching call. USDC, the required numeraire of every pool, provides a concrete blacklist-dependent case.

`matchNewOrder` calls `matchIncoming` outside the later LP-fill `try/catch`, so the failure propagates through `Router.swap` or `swapWithSig` and rolls back creation of the crossing order. An already USDC-blocklisted maker can place a very low-priced sell order using another input asset when no existing bid crosses it. Alternatively, an honest maker can become blocklisted after placing an order, or a contract maker can enable a rejecting recipient hook after placement.

The same dependency also exists in `_reduceAfterMatch`, which directly refunds unused input when a match satisfies the order's minimum. `AsyncFiller.fill` directly pays output to the maker, and `cancel` directly refunds input to that same owner. A failed transfer rolls back their order removal or deletion. Cancellation is owner/executor-gated, provides no alternate recipient, and cannot evict an order whose refund fails. The LP-fill path also pushes ERC20 output; its caught failure preserves the resting order rather than clearing it.

#### Impact

A selected order with a failing payout can indefinitely obstruct matching on the affected pool and side while it remains at the front of the book. Crossing `swap` and `swapWithSig` calls revert instead of creating orders, and `matchBook` cannot resolve the crossed book. An extremely low sell price makes the blocker cross a broad range of incoming buys. Non-crossing order creation and private fills of other orders remain available; private filling of the blocking order still fails if its maker cannot receive the output. Native claim payouts do not depend on recipient acceptance.

The escrow consequence depends on which transfers fail. If only output is unreceivable, the maker can still cancel when its input refund is receivable. With no priority bid, a deliberate blocker can therefore recover its escrow principal and grief mainly at transaction cost. If both the maker's output payout and input refund are unreceivable, matching, private filling, and cancellation cannot clear the order, freezing its remaining escrow while those restrictions persist. The book obstruction can end if the owner successfully cancels or reprices the order out of the way, or recipient restrictions change; it is not an unconditional permanent lock.

Severity Note:
- A direct USDC payout reverts only if that recipient is blacklisted or USDC transfers are paused. A normal contract recipient does not reject USDC, so an arbitrary address cannot force this failure.
- The maker can end the book obstruction by cancelling or repricing whenever the escrowed input is still receivable. Remaining escrow cannot be cleared only while both the output payout and the input refund revert.

### 10. Maker/taker role and execution price depend on a mutable `sequence`, which `updatePrice` resets for free, letting a buyer or seller flip the execution price of a crossed pair

**Severity:** Medium  
**Contracts:** `src/libraries/AsyncMatching.sol`, `src/libraries/AsyncFiller.sol`, `src/AsyncSwap.sol`

#### Context

`_matchPair` treats the order with the lower `sequence` as the resting maker. The pair executes at the maker's limit price via `makerBuy`. A crossed book can persist because of the 8-match cap, because `updatePrice` does not trigger matching, or because an order was created through a custom executor that skips `matchNewOrder`. A keeper later calls `matchBook` to clear it.

```solidity
// File: src/libraries/AsyncMatching.sol
// @auditagent> mutable sequence decides maker
bool makerBuy = first.sequence < second.sequence ? first.isBuy : second.isBuy;
AsyncFiller.MatchAmounts memory amounts = _matchAmounts(self.orders[sellId], self.orders[buyId], makerBuy);
```

#### Root Cause

`AsyncFiller.updatePrice` assigns `info.sequence = ++book.nextSequence` even when `newAmountOutMin` equals the current value. It is a direct, non-unlock call by the owner. `_reduceAfterMatch` likewise assigns a fresh sequence whenever a partial fill changes the price key by rounding. The price-time identity that decides who is maker can therefore be changed at will, including by front-running a pending `matchBook`.

#### Impact

In a crossed backlog, the party who would have received the older order's price can have it replaced by the counterparty's price. For example, an older bid at 120 and a newer ask at 100 would execute at 120. The bid owner calls `updatePrice` with an identical value and the pair executes at 100. This transfers surplus from one counterparty to the other without breaching either party's limit. It undermines the stated time-priority execution policy. It requires an existing crossed pair.

Severity Note:
- The amount moved is only the spread between the two orders' limits, and only while that crossed pair remains unmatched until it is cleared. Neither order is filled outside its own limit.

### 11. Deleting an empty price level makes its final removal depend on the historical order-count peak

**Severity:** Low  
**Contracts:** `src/libraries/AsyncFiller.sol`, `src/libraries/RadixPriceTree.sol`

#### Context

`AsyncFiller` indexes each priority-fee price level using a nested `RadixPriceTree.Tree`. Removing an order releases its tree nodes into `freeIds`. When the last order leaves a price level, `_remove` deletes the entire `PriceLevel`, including the nested tree's dynamic recycling array.

```solidity
// File: src/libraries/AsyncFiller.sol
if (priceLevel.orderCount == 0) {
    if (order.isBuy) book.bids.remove(order.price);
    else book.asks.remove(order.price);
    // @auditagent> Clears unbounded nested array
    if (order.isBuy) delete book.bidLevels[order.price];
    else delete book.askLevels[order.price];
}
```

#### Root Cause

Solidity's deletion of the `PriceLevel` recursively clears `priorityOrders.freeIds`, making the final removal linear in the level's historical peak size rather than its current size. A priority tree that held K concurrent orders allocates `2K - 1` nodes. After those orders are removed, all these identifiers occupy `freeIds`; deleting the level clears approximately `ceil((2K - 1) / 8)` packed storage slots.

An attacker can manufacture this condition by building many distinct orders at a victim's price and then canceling every attacker-owned order while the victim remains. Those cancellations skip the level deletion because `orderCount` remains nonzero. The attacker recovers its order inputs, but leaves the victim's final removal responsible for clearing the accumulated array. If that cleanup exceeds the transaction gas limit, the operation reverts. Adding replacement orders does not eliminate the historical allocation: their eventual removal returns the identifiers to the same array.

#### Impact

In the extreme case where a single price level in `PriorityFee` mode accumulates tens of thousands of concurrent orders and all but one are subsequently removed, deleting the `PriceLevel` struct when the final order is removed can exceed the block gas limit due to clearing the packed `uint32[] freeIds` array. While a maker can still recover their order funds by placing a minimal dust order at the same price level so `orderCount` does not reach zero when canceling their main order, the price level itself cannot be fully emptied, leaving dust behind and preventing `book.openOrderCount` from reaching zero to allow `setOrderingMode`.

Severity Note:
- Triggering an out-of-gas revert when deleting `freeIds` (which packs eight `uint32` elements per storage slot) requires a historical peak of tens of thousands of concurrent orders at a single price level, making deliberate exploitation prohibitively expensive in gas with no financial gain.

### 12. `setOrderingMode` can be blocked forever by one unfillable dust order

**Severity:** Low  
**Contracts:** `src/libraries/AsyncFiller.sol`, `src/AsyncSwap.sol`

#### Context

The owner can switch a pool between `FIFO` and `PriorityFee` ordering only while `book.openOrderCount == 0`. Pools can be initialized by anyone, and anyone can place orders through an executor they authorize, including themselves.

```solidity
// File: src/libraries/AsyncFiller.sol
function setOrderingMode(Book storage book, PoolId poolId, OrderingMode mode) internal {
    // @auditagent> one dust order blocks forever
    if (book.openOrderCount != 0) revert InvalidOrderingModeChange();
    book.orderingMode = mode;
```

#### Root Cause

Nothing lets the owner clear the book or force-close orders. An attacker can place a 1-wei order with an extremely large `amountOutMin`. Its price key is clamped to the extreme, so it never crosses. No pool liquidity can meet its minimum, and a private fill would require paying `amountOutMin + fee`. Only its maker can cancel it.

#### Impact

Once such an order exists, `openOrderCount` never returns to zero. The owner can then never change the pool's ordering mode, for example to enable or disable `PriorityFee` mode. The attacker can front-run the owner's configuration call right after pool initialization at almost no cost.

Severity Note:
- Swaps, order placement, fills, and cancels continue in the current ordering mode. Only the owner's ordering-mode change is blocked, and only while the griefer leaves the dust order open.
