# 🔐 Security Review — contracts

---

## Scope

|  |  |
| --- | --- |
| **Mode** | default |
| **Files reviewed** | `./src/AsyncSwap.sol` · `./src/TokenClaims.sol` · `./src/MatchingEngine.sol`<br>`./src/ImmutableState.sol` · `./src/NativeClaims.sol` · `./src/FeeVault.sol`<br>`./src/Router.sol` · `./src/BaseHook.sol` · `./src/types/AsyncOrder.sol`<br>`./src/libraries/RadixPriceTree.sol` · `./src/libraries/TickPrice.sol` · `./src/libraries/CurrencySettler.sol`<br>`./src/libraries/DynamicFeeOrdering.sol` · `./src/libraries/ClaimTransfers.sol` · `./src/libraries/OrderSignatures.sol`<br>`./src/libraries/AsyncFiller.sol` · `./src/libraries/AsyncMatching.sol` · `./src/libraries/EligiblePrice.sol`<br>`./script/00_DeployDynamicFeeOrdering.s.sol` · `./script/FFIHelper.sol` · `./script/InitPool.s.sol`<br>`./script/03_Swap.s.sol` · `./script/DeployNativeClaims.s.sol` · `./script/Trade.s.sol`<br>`./script/05_ExecuteOrder.s.sol` · `./script/01_DeployHook.s.sol` · `./script/DeployWithdrawalRouter.s.sol`<br>`./script/00_DeployMatchingLibrary.s.sol` · `./script/04_CancelOrder.s.sol` · `./script/00_DeployTickPrice.s.sol`<br>`./script/02_InitializePool.s.sol` · `./script/00_DeployPoolManager.s.sol` · `./script/DeployTokenClaims.s.sol`<br>`./script/config/UniswapAddresses.sol` · `./script/local/Smoke.s.sol` · `./script/local/LocalMarket.s.sol` |
| **Confidence threshold (1-100)** | 75 |
| **Passes** | 3 |
| **Memory** | 0 records before this scan · 40 after · `7d09cfa` |

---

## Findings

[90] **1. The backrun fee charges the whole output of a fill that crosses the reference tick**

`DynamicFeeOrdering.charge` · Confidence: 90 · seen in 1/3 runs · NEW

**Description**
When a pool fill crosses `refTick`, `charge` takes the gap fee on all of `amountOut`, so the maker also pays on output that closes no gap.

**Fix**

```diff
             int256 from = int256(tickBefore) - self.refTick;
             int256 to = int256(tickAfter) - self.refTick;
+            // Only the output that moves the price back to the reference closes a gap.
+            uint256 feeBase = amountOut;
+            if (to * from < 0) {
+                feeBase = amountOut * SignedMath.abs(from) / (SignedMath.abs(from) + SignedMath.abs(to));
+            }
             // Only a fill toward the reference pays; the part past it closes no gap.
             if (to * from <= 0) to = 0;
             uint256 gapBefore = SignedMath.abs(from);
             uint256 gapAfter = SignedMath.abs(to);
             if (gapAfter < gapBefore) {
-                fee = Math.min(amountOut * (gapBefore + gapAfter) / 40_000, amountOut / 2);
+                fee = Math.min(feeBase * (gapBefore + gapAfter) / 40_000, amountOut / 2);
```

---

[90] **2. A dust order at the end key turns off pool fills for the other side**

`TickPrice.poolBeatsLevel` · Confidence: 90 · seen in 1/3 runs · NEW

**Description**
An attacker rests an order at the clamped end key, so `poolBeatsLevel` returns `MIN_SQRT_PRICE` or `MAX_SQRT_PRICE`, v4 reverts the pool-first swap, and new orders rest for a filler.

**Fix (Option A — clamp the limit)**:

```diff
         int24 offset = int24(int256(uint256(levelKey)) - 1);
-        return (true, TickMath.getSqrtPriceAtTick(quote1 ? offset + TickMath.MIN_TICK : TickMath.MAX_TICK - offset));
+        uint160 limit = TickMath.getSqrtPriceAtTick(quote1 ? offset + TickMath.MIN_TICK : TickMath.MAX_TICK - offset);
+        // v4 rejects a limit at either end of the price range.
+        if (limit <= TickMath.MIN_SQRT_PRICE) limit = TickMath.MIN_SQRT_PRICE + 1;
+        if (limit >= TickMath.MAX_SQRT_PRICE) limit = TickMath.MAX_SQRT_PRICE - 1;
+        return (true, limit);
```

**Fix (Option B — ban-path)**:

```diff
         if (isBuy ? poolKey >= levelKey : poolKey <= levelKey) return (false, 0);
+        // A level at a clamped end key is outside the v4 price range: let the pool go second, with no limit.
+        if (levelKey == 1 || levelKey == uint128(uint24(TickMath.MAX_TICK - TickMath.MIN_TICK)) + 1) return (false, 0);
```

---

[85] **3. The venue choice ignores the dynamic fee, so the pool fills before a better book order**

`AsyncSwap._poolBeatsBook` · Confidence: 85 · seen in 1/3 runs · NEW

**Description**
`_poolBeatsBook` compares only the spot tick with the best level, so inside the backrun window the maker pays up to half its pool output as a dynamic fee to LPs.

**Fix**

```diff
     function _poolBeatsBook(PoolKey calldata key, bool isBuy) private view returns (bool, uint160) {
+        // Inside the ordering window a fill back toward refTick pays the dynamic fee: send the order to the book.
+        AsyncFiller.State storage s = asyncOrders[key.toId()];
+        if (s.refBlock != 0 && block.number <= s.refBlock + DynamicFeeOrdering.ORDERING_WINDOW) {
+            (, int24 tick,,) = poolManager.getSlot0(key.toId());
+            if (isBuy ? tick < s.refTick : tick > s.refTick) return (false, 0);
+        }
```

---

[85] **4. A maker that sets itself as executor fills its own order from the pool with no MEV tax**

`AsyncSwap.tryFillOrderFromPoolLiquidity` · Confidence: 85 · seen in 3/3 runs · NEW

**Description**
`tryFillOrderFromPoolLiquidity` accepts any executor the maker set, so a searcher contract fills its own order from its own unlock and pays no tax.

**Fix**

```diff
     function tryFillOrderFromPoolLiquidity(AsyncOrder calldata order) external returns (bool filled) {
-        if (!asyncOrders[order.key.toId()].isExecutor[order.owner][msg.sender]) {
+        if (msg.sender != router || !asyncOrders[order.key.toId()].isExecutor[order.owner][msg.sender]) {
             revert AsyncFiller.NotAuthorizedExecutor();
         }
```

---

[85] **5. A direct `updatePrice` call lets a searcher make an old order cross with no MEV tax**

`AsyncSwap.updatePrice` · Confidence: 85 · seen in 3/3 runs · NEW

**Description**
Any maker calls `updatePrice` on the hook with no Router and no tax, then matches the repriced order, so the FeeVault gets no tax from the race.

**Fix**

```diff
     function updatePrice(AsyncOrder calldata order, uint256 newAmountOutMin) external {
+        // Reprices go through the Router, which charges mevTax().
+        if (msg.sender != router) revert AsyncFiller.NotAuthorizedExecutor();
         bytes32 id = order.orderId();
```

---

[85] **6. A searcher reprices its own order and calls `matchBook`, so it pays no MEV tax**

`Router.matchBook` · Confidence: 85 · seen in 2/3 runs · NEW

**Description**
`Router.matchBook` and the hook's `matchBook` charge no `mevTax()`, so a searcher who reprices an old order and matches it keeps the priority race value.

**Fix**

```diff
-    function matchBook(PoolKey calldata key, uint8 maxMatches) external {
+    function matchBook(PoolKey calldata key, uint8 maxMatches) external payable {
+        _chargeMevTax(0);
         AsyncOrder memory placeholder;
```

---

[75] **7. Ceil rounding on a partial match makes the remainder's limit worse than the maker signed**

`AsyncMatching._reduceAfterMatch` · Confidence: 75 · seen in 2/3 runs · NEW

**Description**
A taker partly fills an order, so the ceil on `remainingMinimum` moves its ratio past an equal competitor, which then fills first and takes the maker's paid priority.

**Fix**

```diff
     struct OrderInfo {
         address owner;
         uint256 amountIn;
         uint256 amountOutMin;
+        /// @dev The signed limit ratio, set at creation and on reprice; partial matches do not round it.
+        uint256 limitIn;
+        uint256 limitOut;
@@ function exactPrice(OrderInfo storage order) internal view returns (EligiblePrice.Ratio memory) {
         return order.isBuy
-            ? EligiblePrice.Ratio(order.amountIn, order.amountOutMin)
-            : EligiblePrice.Ratio(order.amountOutMin, order.amountIn);
+            ? EligiblePrice.Ratio(order.limitIn, order.limitOut)
+            : EligiblePrice.Ratio(order.limitOut, order.limitIn);
```

---

[75] **8. A pool-first fill parks the price in an empty range and freezes pool fills**

`AsyncMatching._swapAgainstPool` · Confidence: 75 · seen in 1/3 runs · NEW

**Description**
A limited pool-first swap crosses the last liquidity range and stops at the book limit with zero liquidity, so every later pool fill reverts with `NoActiveLiquidity`.

**Fix**

```diff
-        if (manager.getLiquidity(key.toId()) == 0) revert NoActiveLiquidity();
+        // No current-tick check: v4 crosses empty ranges, and the full-fill and output checks reject a swap that finds no liquidity.
         Currency input = zeroForOne ? key.currency0 : key.currency1;
```

---

[75] **9. Any caller runs the hook's `matchBook` with no unlock and no Router**

`AsyncSwap.matchBook` · Confidence: 75 · seen in 3/3 runs · NEW

**Description**
`matchBook` moves value only with ERC-6909 `transfer`, which needs no unlock, so any caller runs it outside the Router and pays no MEV tax.

**Fix**

```diff
     function matchBook(PoolKey calldata key, uint8 maxMatches) external returns (uint8 matched) {
+        if (msg.sender != router) revert AsyncFiller.NotAuthorizedExecutor();
```

---

[75] **10. An attacker submits a copied executor grant first, so the relayer's `swapWithSig` reverts**

`Router.swapWithSig` · Confidence: 75 · seen in 1/3 runs · NEW

**Description**
An attacker sends the grant from a pending `swapWithSig` to `setExecutorWithSig` first, so the relayer's call reverts with `NonceAlreadyUsed` and the relayer loses gas.

**Fix (Option A — skip a spent grant)**:

```diff
-        if (grant.signature.length != 0) {
+        // A spent nonce cannot be replayed, so a grant someone already applied needs no second call.
+        if (grant.signature.length != 0 && !HOOK.nonceUsed(order.owner, grant.nonce)) {
             HOOK.setExecutorWithSig(
```

**Fix (Option B — allow-and-handle)**:

```diff
-            HOOK.setExecutorWithSig(
-                order.key, order.owner, address(this), true, grant.nonce, grant.deadline, grant.signature
-            );
+            try HOOK.setExecutorWithSig(
+                order.key, order.owner, address(this), true, grant.nonce, grant.deadline, grant.signature
+            ) {} catch {
+                require(HOOK.isExecutor(order.key.toId(), order.owner, address(this)), "grant failed");
+            }
```

---

[75] **11. The pool-first limit stops one tick past the best resting price**

`TickPrice.poolBeatsLevel` · Confidence: 75 · seen in 3/3 runs · NEW

**Description**
`poolBeatsLevel` returns the floor tick of the best level, so a zeroForOne pool-first swap fills up to one tick worse than the resting order.

**Fix**

```diff
-        return (true, TickMath.getSqrtPriceAtTick(quote1 ? offset + TickMath.MIN_TICK : TickMath.MAX_TICK - offset));
+        int24 levelTick = quote1 ? offset + TickMath.MIN_TICK : TickMath.MAX_TICK - offset;
+        // The key is a floor tick: a quote1 sell or a quote0 buy swaps down to it, past the exact level.
+        if (quote1 != isBuy && levelTick < TickMath.MAX_TICK) ++levelTick;
+        return (true, TickMath.getSqrtPriceAtTick(levelTick));
```

---

Findings List

| # | Confidence | Title |
|---|---|---|
| 1 | [90] | The backrun fee charges the whole output of a fill that crosses the reference tick |
| 2 | [90] | A dust order at the end key turns off pool fills for the other side |
| 3 | [85] | The venue choice ignores the dynamic fee, so the pool fills before a better book order |
| 4 | [85] | A maker that sets itself as executor fills its own order from the pool with no MEV tax |
| 5 | [85] | A direct `updatePrice` call lets a searcher make an old order cross with no MEV tax |
| 6 | [85] | A searcher reprices its own order and calls `matchBook`, so it pays no MEV tax |
| 7 | [75] | Ceil rounding on a partial match makes the remainder's limit worse than the maker signed |
| 8 | [75] | A pool-first fill parks the price in an empty range and freezes pool fills |
| 9 | [75] | Any caller runs the hook's `matchBook` with no unlock and no Router |
| 10 | [75] | An attacker submits a copied executor grant first, so the relayer's `swapWithSig` reverts |
| 11 | [75] | The pool-first limit stops one tick past the best resting price |

---

## Leads

_Vulnerability trails with concrete code smells where the full exploit path could not be completed in one analysis pass. These are not false positives — they are high-signal leads for manual review. Not scored._

- **A one-unit better price moves ahead of a paid priority bid** — `AsyncFiller.bestAtPrice` · seen in 1/3 runs · NEW — `bestAtPrice` takes the exact best ratio first and uses the bid only for exact ties, so a competitor one base unit better skips a $0.10 bidder. Code smells: exact ratio inside a tick level. The design may intend this.
- **A contract maker can refuse filler fills** — `AsyncFiller.fill` · seen in 1/3 runs · NEW — Filler fills and full pool fills send the maker real tokens, so a contract maker with a callback token can revert fills it does not want. Code smells: real transfer to a maker. We did not verify that a pool would list such an asset.
- **A remainder below the asset floor cannot be repriced** — `AsyncFiller.updatePrice` · seen in 1/3 runs · NEW — `updatePrice` checks the asset floor that the dust close skipped, so the maker of such a remainder can only cancel it. Code smells: two minimum rules that disagree. We did not check whether a keeper can force this on a victim.
- **A partly matched sell cannot raise its price** — `AsyncFiller.updatePrice` · seen in 1/3 runs · NEW — A match cuts the bid in proportion, and `updatePrice` compares that cut bid with the full $0.10 floor, so the seller must cancel and pay a new bid. Code smells: pro-rata bid against a capped floor. The loss is at most one new bid.
- **Two orders at the lowest end key can overflow `_crosses`** — `AsyncMatching._crosses` · seen in 1/3 runs · NEW — At equal end keys the quotient of `mulDiv` is not near `buyOut`, so it can overflow and revert every match on the pool. Code smells: clamped keys share one level. We found no realistic supply that reaches it.
- **A repriced old order stays the maker and pays its own new limit** — `AsyncMatching._matchPair` · seen in 1/3 runs · NEW — `_matchPair` picks the maker by `createdSequence`, so a maker who reprices an old order into a cross pays its own new limit. Code smells: reprice keeps `createdSequence`. We found no third party who can force this.
- **The dust close skips the asset floor** — `AsyncMatching._reduceAfterMatch` · seen in 2/3 runs · NEW — `_reduceAfterMatch` closes a remainder by `minOrder` only, so a partly matched order can rest below `minAssetAmount`. Code smells: one-sided minimum check. We found no loss of funds.
- **One minimum match closes an order and forfeits its whole bid** — `AsyncMatching._reduceAfterMatch` · seen in 1/3 runs · NEW — An attacker matches an order near `minOrder` once, so the dust close sends the maker's remaining bid to the FeeVault. Code smells: forfeit on dust close. The attacker gains nothing, and the documentation says the forfeit is intended.
- **`closeBelowMinimum` skips the asset floor** — `AsyncMatching.closeBelowMinimum` · seen in 2/3 runs · NEW — `closeBelowMinimum` tests only `minOrder`, so a pool-first remainder below `minAssetAmount` stays on the book. Code smells: one-sided minimum check. We found no third-party loss.
- **One crossed pair that fails to match stops the whole book** — `AsyncMatching.matchBook` · seen in 1/3 runs · NEW — `matchBook` breaks on the first pair that `_matchPair` rejects, so such a pair would block every later match on the pool. Code smells: `break` on failure. We found no crossed pair that the rounding rejects.
- **Book matching ignores a revoked Router** — `AsyncMatching.matchBook` · seen in 1/3 runs · NEW — Revoking the Router stops fills, but `_bookPair` never reads `isExecutor`, so any caller still matches the maker's resting orders. Code smells: revocation checked on fills only. We did not confirm whether revocation is meant to pause matching.
- **The native deposit counter is not tied to the depositor** — `AsyncSwap.executeOrder` · seen in 3/3 runs · NEW — `receive()` adds every sender's ETH to one counter per transaction, and `executeOrder` spends it for any authorized executor. Code smells: shared transient counter. We found no path where one party spends another party's deposit.
- **Eight small front-run asks push a buyer's rest through the pool without a limit** — `AsyncSwap.matchNewOrder` · seen in 1/3 runs · NEW — When the book goes first, eight small asks use up the match budget, and the pool then takes the rest with no price limit past better asks. Code smells: 8-pair budget, pool-second swap with limit 0. We did not measure the attacker's profit after fees.
- **`matchNewOrder` does not retry the pool after a failed pool-first step** — `AsyncSwap.matchNewOrder` · seen in 1/3 runs · NEW — When the limited pool-first swap reverts, the book takes only the crossing levels and the rest rests, even when the pool could fill it at the maker's limit. Code smells: empty catch, two-step loop, no unlimited retry. We found no second cause beyond the end-key level.
- **A relayer can starve the pool-first fill of gas** — `AsyncSwap.matchNewOrder` · seen in 2/3 runs · NEW — The empty catch also catches out-of-gas, and the relayer of `swapWithSig` sets the gas limit. Code smells: catch-all try, relayer-chosen gas. We did not measure the gas window.
- **A grant from a reverted `swapWithSig` stays replayable** — `AsyncSwap.setExecutorWithSig` · seen in 1/3 runs · NEW — A `swapWithSig` that reverts leaves its grant public with the nonce unspent, so anyone replays it after the maker revokes the Router directly. Code smells: direct revoke does not spend signed-grant nonces. Fills still respect the maker's limit.
- **`useNonce` accepts only the immutable `router`** — `AsyncSwap.useNonce` · seen in 1/3 runs · NEW — `useNonce` and the grant-free cancel check the immutable `router`, so any second Router cannot burn cancel nonces. Code smells: single trusted address, second Router script. We did not confirm that a maker depends on the second Router.
- **The claim batch has no room above the worst case** — `ClaimTransfers.credit` · seen in 1/3 runs · NEW — `Credit[34]` equals the worst case of eight matches, so one more recipient kind or a higher match cap makes every match revert. Code smells: unchecked array index. We counted no case above 34 today.
- **A just-in-time LP takes back the donated half of the dynamic fee** — `DynamicFeeOrdering._pay` · seen in 1/3 runs · NEW — `_pay` donates half the fee to the liquidity in range after the swap, so a searcher who adds liquidity just before a fill gets most of that half back. Code smells: donate after swap, unhooked liquidity changes. We did not prove net profit after inventory risk.
- **A searcher times the 2-block window so its backrun pays no fee** — `DynamicFeeOrdering.charge` · seen in 1/3 runs · NEW — A fill after `refBlock + 2` starts a new window and pays nothing, so a searcher who opens the window early backruns in a later block for free. Code smells: fixed 2-block window, reference set by the first fill. We did not show a profitable two-block sandwich.
- **A keeper chooses when a passive order pays the backrun fee** — `DynamicFeeOrdering.charge` · seen in 3/3 runs · NEW — Any caller forces a resting order to fill inside the 2-block window, so the passive maker pays the fee meant for a searcher. Code smells: anyone triggers pool fills, the first fill sets the reference. Net attacker profit is unverified.
- **The execute, swap and smoke scripts send no MEV tax** — `ExecuteAsyncOrderScript.run` · seen in 1/3 runs · NEW — `05_ExecuteOrder.s.sol`, `03_Swap.s.sol` and `local/Smoke.s.sol` send no `router.mevTax()`, so they revert on a chain with a nonzero `MEV_TAX_GAS` when the transaction has a priority fee. Code smells: exact `msg.value` check.
- **The scripts use a fixed six-decimal bid floor** — `FFIHelper._priorityFee` · seen in 1/3 runs · NEW — `_priorityFee` hard-codes the cap `100_000`, so with a numeraire of other decimals the scripts send bids that the hook rejects. Code smells: hard-coded cap. It moves no funds.
- **The exact tax check reverts when the base fee moves** — `Router._chargeMevTax` · seen in 1/3 runs · NEW — `_chargeMevTax` requires `msg.value` to equal a tax that depends on the base fee at inclusion, so a transaction capped by `maxFeePerGas` reverts when the base fee rises. Code smells: exact equality on a value the sender cannot know. We did not measure how often this happens.
- **The withdrawal Router is not the hook's `router`, so its cancel paths fail** — `Router.cancelWithSig` · seen in 2/3 runs · NEW — `DeployWithdrawalRouter` deploys a second Router for cancels, but the hook trusts only its immutable `router`, so that Router's cancels revert. Code smells: second Router instance, testnet-only script. We found no loss, because the original Router still cancels.
- **A partial match makes a pending native fill revert** — `Router.fillOrder` · seen in 1/3 runs · NEW — The native branch needs `msg.value` to equal the live minimum exactly, so a partial match or reprice before inclusion makes the filler's call revert. Code smells: exact equality, ERC-20 branch tolerates the same change. We did not measure what the attacker pays.
- **Fillers ignore the priority bid** — `Router.fillOrder` · seen in 1/3 runs · NEW — Fillers and keepers choose any order, so a maker pays the full bid but gets priority only in book matches. Code smells: only `matchBook` reads the priority key. We did not measure the loss.
- **A re-entrant taxed call overwrites the tax slot** — `Router.swapWithSig` · seen in 2/3 runs · NEW — A nested taxed call between `_chargeMevTax` and `_payMevTax` overwrites the outer tax, so that ETH stays in the Router. Code smells: overwrite instead of add. Pass 3 found no reachable nested call, because ERC-1271 checks run under STATICCALL.
- **The trade scripts send no MEV tax** — `TradeScript.run` · seen in 1/3 runs · NEW — `Trade.s.sol`, `03_Swap.s.sol` and `05_ExecuteOrder.s.sol` send no `router.mevTax()`, so a broadcast with a priority fee reverts where `MEV_TAX_GAS` is more than zero. Code smells: exact `msg.value` check. We did not check forge's default priority fee per chain.

---

> ⚠️ This review was performed by an AI assistant. AI analysis can never verify the complete absence of vulnerabilities and no guarantee of security is given. Team security reviews, bug bounty programs, and on-chain monitoring are strongly recommended. For a consultation regarding your projects' security, visit [https://www.pashov.com](https://www.pashov.com)
