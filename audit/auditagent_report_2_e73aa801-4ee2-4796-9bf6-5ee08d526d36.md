# AuditAgent report - Scan ID `e73aa801-4ee2-4796-9bf6-5ee08d526d36`

## Scan details

| Key | Value |
|---|---|
| Repository | asyncswap/contracts |
| Branch | `main` |
| Commit | `961879f2...aacc2b9f` |
| Scan ID | `e73aa801-4ee2-4796-9bf6-5ee08d526d36` |
| Scan type | Auditor Scan |
| Date | October 23, 2026 |
| Lines of code | 4,000 |
| Contracts in scope | 28 |
| Vulnerabilities found | 3 |
| Audit score | 88 |

## Contracts in scope

- `src/AsyncSwap.sol`
- `src/BaseHook.sol`
- `src/FeeVault.sol`
- `src/ImmutableState.sol`
- `src/MatchingEngine.sol`
- `src/NativeClaims.sol`
- `src/Router.sol`
- `src/TokenClaims.sol`
- `src/interfaces/ISignatureTransfer.sol`
- `src/libraries/AsyncFiller.sol`
- `src/libraries/AsyncMatching.sol`
- `src/libraries/CurrencySettler.sol`
- `src/libraries/EligiblePrice.sol`
- `src/libraries/OrderSignatures.sol`
- `src/libraries/RadixPriceTree.sol`
- `src/types/AsyncOrder.sol`
- `script/00_DeployMatchingLibrary.s.sol`
- `script/00_DeployPoolManager.s.sol`
- `script/01_DeployHook.s.sol`
- `script/02_InitializePool.s.sol`
- `script/03_Swap.s.sol`
- `script/04_CancelOrder.s.sol`
- `script/05_ExecuteOrder.s.sol`
- `script/DeployNativeClaims.s.sol`
- `script/DeployTokenClaims.s.sol`
- `script/FFIHelper.sol`
- `script/InitPool.s.sol`
- `script/Trade.s.sol`

## Findings summary

| Severity | Count |
|---|---|
| High | 0 |
| Medium | 1 |
| Low | 2 |
| Info | 0 |
| Best practices | 0 |
| Total | 3 |

## Code summary

AsyncSwap is an on-chain limit order book and asynchronous swap execution protocol built as a Uniswap v4 hook. Instead of executing swaps immediately against an automated market maker (AMM) curve at any price, AsyncSwap intercepts exact-input swaps in `_beforeSwap`, escrows the maker's input tokens as ERC-6909 claims inside the Uniswap v4 `PoolManager`, and converts the swap into an open limit order stored in a per-pool order book. Orders can be settled through three complementary mechanisms: direct peer-to-peer order book matching against crossing orders, atomic execution against active Uniswap v4 concentrated liquidity positions if the maker's limit price is met in full, or full-order settlement by external fillers.

### Core Architecture and Components

- **AsyncSwap (Uniswap v4 Hook)**: The central contract that implements `beforeInitialize`, `beforeAddLiquidity`, and `beforeSwap` (with `beforeSwapReturnDelta`). It enforces that every initialized pool pairs an asset with the protocol's configured `numeraire` currency (USDC) and uses dynamic LP fees. It manages order creation, ERC-6909 claim escrow, executor authorizations, EIP-712 signature verification for gasless updates, and order settlement entry points.
- **Router**: The primary user-facing and relayer-facing executor contract. It wraps order creation, external fills, cancellations, book matching, and pool-liquidity retries inside `IPoolManager.unlock` callbacks, using EVM transient storage to pass execution context across the callback boundary and integrating with Permit2 for gasless witness-verified order creation.
- **AsyncFiller and AsyncMatching Libraries**: `AsyncFiller` manages per-pool state, executor permissions, minimum order size validation, priority fee rules, price updates, cancellations, and full-order filler settlements. `AsyncMatching` is an externally linked library called via `DELEGATECALL` that executes pairwise order book matching, proportional partial-fill accounting, and atomic swaps against Uniswap v4 pool liquidity.
- **RadixPriceTree and EligiblePrice Libraries**: `RadixPriceTree` provides a 128-bit Patricia radix tree with node recycling to index `uint128` WAD-scaled price levels and intra-level priority keys (`priorityFee` and queue `sequence`) with a maximum traversal depth of 128 bits. `EligiblePrice` augments each intra-level priority tree with exact 512-bit rational price bounds (`Ratio`), allowing the matching engine to locate the highest-priority order within a shared truncated WAD price bucket that truly crosses an opposing limit price without linear scans.
- **FeeVault, NativeClaims, and TokenClaims**: `FeeVault` holds protocol fill fees and settled priority fees as ERC-6909 claims separate from active order escrow. `NativeClaims` and `TokenClaims` are helper contracts that allow users to burn their `PoolManager` ERC-6909 claims (received from direct book matches, native ETH payouts, or refunds) and withdraw the underlying native ETH or ERC-20 tokens.
- **MatchingEngine**: A standalone, non-custodial price-time matching harness built on `RadixPriceTree` for benchmarking limit order book operations without token settlement.

### Order Lifecycle and Settlement Mechanics

1. **Order Admission and Priority Fees**: A maker submits an exact-input order specifying `amountIn`, `amountOutMin` (defining their limit price), and a non-refundable `priorityFee` denominated in the USDC `numeraire` (at least $0.10 or 0.1% of the order's USDC notional for orders under $100). The order must also satisfy the pool's minimum order value (`minOrder`). The hook escrows both the input currency and the priority fee as `PoolManager` claims and assigns a deterministic `salt` and `orderId`.
2. **Direct Order Book Matching**: Once the maker's input is settled in the `Router` callback, `matchNewOrder` attempts to match crossing bids and asks in the pool's price book (up to 8 matches per call). Orders at the same price level are prioritized by highest `priorityFee` first, then earliest submission sequence. Matches execute at the resting (older) order's limit price, supporting partial fills and settling proportional priority fees to the `FeeVault`. If a partially filled order's remaining value drops below `minOrder`, the remainder is automatically refunded to the maker as ERC-6909 claims. If more than 8 pairs cross, anyone can call `matchBook` to continue clearing the backlog.
3. **Pool Liquidity Execution**: If an incoming order (or a resting order retried via `fillFromPoolLiquidity`) still has open input after book matching, the hook performs an external self-call to swap the order's entire input against active Uniswap v4 LP positions in the pool with a 0.3% (3,000 bps) dynamic LP fee. Because the hook is the swap caller, `PoolManager` skips hook callbacks and executes against pool liquidity; if the pool cannot fill the full `amountIn` or fails to meet `amountOutMin`, the self-call reverts atomically while preserving the resting order on the book.
4. **External Filler Execution**: External fillers can fill any open resting order in full via `Router.fillOrder`. The filler pays the order's live `amountOutMin` plus a 0.3% protocol fee (`amount * 3 / 997`), capped by a filler-specified `maxPrice` to protect against front-running price updates. The maker receives `amountOutMin` (directly for ERC-20 tokens or as ERC-6909 claims for native ETH), the `FeeVault` receives the 0.3% fee and the order's escrowed priority fee, and the filler receives the maker's `amountIn`.
5. **Repricing and Cancellation**: Makers can update an open order's `amountOutMin` directly or via EIP-712 signature, which re-indexes the order at its new price and resets its time sequence. Makers can also cancel an unfilled order (directly or via signature) to reclaim their remaining `amountIn`, while the escrowed priority fee is forfeited to the `FeeVault`.

### Main Entry Points and Actors

- **`Router.swap(AsyncOrder order, bytes userData)`**: Called by a **Maker** to create a new async limit order, transferring the input tokens (ERC-20 or native ETH) and USDC priority fee into `PoolManager` escrow and triggering immediate book matching and pool liquidity fill attempts.
- **`Router.swapWithSig(AsyncOrder order, PermitData permit, ExecutorGrant grant)`**: Called by a **Relayer** on behalf of a **Maker** to create a gasless ERC-20 async limit order using a Permit2 witness signature and an optional signed executor authorization grant.
- **`Router.fillOrder(AsyncOrder order, uint256 maxPrice, bytes data)`**: Called by a **Filler** to fill an open order in full by paying the maker's live minimum output plus the 0.3% protocol fee (bounded by `maxPrice`) in exchange for the maker's escrowed input.
- **`Router.cancelOrder(AsyncOrder order)`**: Called by a **Maker** to cancel their open unfilled order and reclaim their escrowed input currency.
- **`Router.cancelWithSig(AsyncOrder order, uint256 nonce, uint256 deadline, bytes signature)`**: Called by a **Relayer** with a **Maker's** EIP-712 signature to cancel an open order on the maker's behalf and return the escrowed input to the maker.
- **`Router.matchBook(PoolKey key, uint8 maxMatches)`**: Called permissionlessly by **Any User / Keeper** to continue matching up to 8 crossed order pairs in a pool's order book inside a `PoolManager` unlock.
- **`Router.fillFromPoolLiquidity(AsyncOrder order)`**: Called permissionlessly by **Any User / Keeper** to retry filling a resting order in full against active Uniswap v4 LP liquidity.
- **`Router.unlockCallback(bytes data)`**: Called exclusively by the **PoolManager** during an unlock session initiated by the `Router` to execute swap creation, Permit2 transfers, order fills, cancellations, book matching, or pool liquidity fills.
- **`AsyncSwap.setExecutor(PoolId poolId, address executor, bool allow)`**: Called by a **Maker** to authorize or revoke an executor address (such as the `Router`) to submit, fill, or cancel orders on their behalf for a given pool.
- **`AsyncSwap.setExecutorWithSig(PoolKey key, address maker, address executor, bool allow, uint256 nonce, uint256 deadline, bytes signature)`**: Called by a **Relayer** (or the `Router`) with a **Maker's** EIP-712 signature to authorize or revoke an executor for a pool.
- **`AsyncSwap.updatePrice(AsyncOrder order, uint256 newAmountOutMin)`**: Called directly by a **Maker** to modify the `amountOutMin` limit price of their open order and refresh its queue sequence.
- **`AsyncSwap.updatePriceWithSig(AsyncOrder order, uint256 newAmountOutMin, uint256 nonce, uint256 deadline, bytes signature)`**: Called by a **Relayer** with a **Maker's** EIP-712 signature to update the `amountOutMin` limit price of an open order.
- **`AsyncSwap.invalidateNonce(uint256 nonce)`**: Called by a **Maker** to revoke and burn an unused EIP-712 signature nonce.
- **`AsyncSwap.executeOrder(AsyncOrder order, bytes data)`**: Called by an **Authorized Executor** (`Router`) within a `PoolManager` unlock context to settle a full order fill between a filler and a maker.
- **`AsyncSwap.cancelOrder(AsyncOrder order)`**: Called by an **Authorized Executor** (`Router`) or directly by the **Maker** within a `PoolManager` unlock context to cancel an open order and return escrowed input.
- **`AsyncSwap.matchNewOrder(AsyncOrder order)`**: Called by the **Authorized Executor** (`Router`) right after settling a new order's input to match it against the order book and attempt an atomic pool liquidity fill for any remainder.
- **`AsyncSwap.tryFillOrderFromPoolLiquidity(AsyncOrder order)`**: Called by an **Authorized Executor** (`Router`) inside a `PoolManager` unlock to attempt filling a resting order against active Uniswap v4 pool liquidity.
- **`AsyncSwap.fillOrderFromPoolLiquidity(AsyncOrder order, bytes32 id)`**: Called via an external self-call by **AsyncSwap** itself to atomically swap a resting order's input against Uniswap v4 pool liquidity.
- **`AsyncSwap.matchBook(PoolKey key, uint8 maxMatches)`**: Called by an **Executor / Keeper** inside a `PoolManager` unlock context to match up to `maxMatches` crossing order pairs on the book.
- **`AsyncSwap.acceptOwnership()`**: Called by the nominated **Pending Owner** to finalize a two-step ownership transfer of the hook.
- **`AsyncSwap.beforeInitialize(address sender, PoolKey key, uint160 sqrtPriceX96)`**: Called by the **PoolManager** when initializing a pool to enforce `numeraire` inclusion and dynamic fee configuration.
- **`AsyncSwap.beforeAddLiquidity(address sender, PoolKey key, ModifyLiquidityParams params, bytes hookData)`**: Called by the **PoolManager** before a liquidity provider adds liquidity to a hooked pool.
- **`AsyncSwap.beforeSwap(address sender, PoolKey key, SwapParams params, bytes hookData)`**: Called by the **PoolManager** during a swap to intercept exact-input swaps, escrow input claims, and create an open async order.
- **`AsyncSwap.receive()`**: Called by the **Router** (or a **Filler**) to deposit native ETH into the hook's transient ledger prior to executing a native-output order fill.
- **`FeeVault.collect(Currency currency, address recipient)` and `FeeVault.unlockCallback(bytes data)`**: Called by the **Protocol Owner** (and subsequently the **PoolManager**) to burn accumulated ERC-6909 fee claims in the vault and transfer the underlying tokens to a recipient.
- **`NativeClaims.redeem(address recipient, uint256 amount)` and `NativeClaims.unlockCallback(bytes data)`**: Called by a **Claim Holder** (and subsequently the **PoolManager**) to burn native ETH ERC-6909 claims and transfer native ETH to a recipient.
- **`TokenClaims.redeem(Currency currency, address recipient, uint256 amount)` and `TokenClaims.unlockCallback(bytes data)`**: Called by a **Claim Holder** (and subsequently the **PoolManager**) to burn ERC-20 currency claims and transfer the underlying tokens to a recipient.
- **`MatchingEngine.placeOrder(bytes32 market, bool isBuy, uint128 amount, uint128 price)`**: Called by a **Trader / Benchmark User** in the standalone matching harness to submit a limit order and match up to 8 crossing orders.
- **`MatchingEngine.matchBook(bytes32 market, uint8 maxMatches)`**: Called by **Any User** in the standalone matching harness to clear up to 8 crossed orders in a market.
- **`MatchingEngine.cancelOrder(bytes32 market, uint64 orderId)`**: Called by an **Order Owner** in the standalone matching harness to cancel an active order.

## Findings

### 1. Coarse `_priceKey` buckets let fee and time priority override better exact limit prices

**Severity:** Medium  
**Contracts:** `src/libraries/AsyncMatching.sol`, `src/libraries/AsyncFiller.sol`, `src/AsyncSwap.sol`, `src/Router.sol`

#### Context

`AsyncFiller` indexes orders by a truncated, clamped WAD price key. The outer radix trees select the highest bid bucket and lowest ask bucket; orders inside each bucket are ranked by `priorityKey = (priorityFee << 64) | (type(uint64).max - sequence)`, favoring the highest remaining priority fee and then the earliest sequence. Intended price priority requires these tie-breakers to apply only to genuinely equal prices.

`AsyncMatching._bookPair` selects orders for both automatic matching through `AsyncSwap.matchNewOrder` and permissionless continuation through `matchBook`. `_matchPair` settles at the older selected order's exact limit, determined by `createdSequence`. Book matches charge no private-fill fee and distribute proceeds and refunds as PoolManager claims. `bestOrder` uses the same bucket-head selection.

```solidity
// File: src/libraries/AsyncMatching.sol
bidId = book.bestAtPrice(true, bidPrice);
askId = book.bestAtPrice(false, askPrice);
// @auditagent> Crossing bypasses exact ranking
if (_crosses(bidPrice, askPrice, self.orders[bidId], self.orders[askId])) return (bidId, askId);
```

#### Root Cause

`_priceKey` computes `floor(raw quote/asset ratio * PRICE_SCALE)` with `PRICE_SCALE = 1e18`, maps zero to `1`, and saturates values above `type(uint128).max`. Unequal exact limits therefore share a price level. The fixed scale does not account for token decimals or price magnitude: for an 18-decimal asset quoted in six-decimal USDC, the key is approximately `floor(priceUSD * 1e6)`. One key interval represents about 0.1% at $0.001, but about 10% at $0.00001. Prices truncating to zero share key `1` with prices truncating to one; the upper saturation boundary also merges distinct limits.

Within these buckets, `bestAtPrice` ignores exact price and selects only by fee and sequence. `_bookPair` immediately returns those heads when `_crosses` succeeds. That check establishes compatibility, not whether the selected ask is the cheapest or the selected bid is the highest-priced available order. If the heads do not cross, the `exactBounds`/`EligiblePrice` fallback finds priority-ranked crossing alternatives rather than ranking all eligible orders by exact price. It avoids a noncrossing-head obstruction but does not restore best-price execution.

A worse-priced maker can consequently preempt better liquidity either by paying a slightly higher `priorityFee` or, at equal fees, by having an earlier `sequence`. This applies symmetrically to competing asks and bids. The representation is used at creation, by `updatePrice`, and during partial-fill reindexing in `_reduceAfterMatch`, which has its own `_priceKey` implementation. An attacker can therefore enter the shared bucket by creating an order or repricing an existing one. Repricing resets queue sequence but does not defeat a higher-fee advantage, and it preserves `createdSequence`, which determines settlement age.

The affected execution routes include `Router.swap` or another authorized executor's swap/admission path followed by `matchNewOrder`, and continuation through `Router.matchBook`/`AsyncSwap.matchBook`. The same ordering also makes `bestOrder` report a worse exact limit as best.

#### Impact

Takers lose available price improvement, better-priced makers are skipped and may never fill, and an attacker can capture the difference by selling ahead of cheaper liquidity and subsequently repurchasing it. Distinct examples are:

- **Ordinary bucket, fee or sequence preemption:** asks selling `1e27` asset units for 10,100 USDC and 10,800 USDC both map to key `10`. The worse ask can win by being submitted first at equal valid fees, or by carrying a `110_000`-unit priority fee against the cheaper ask's `100_000`. A later buyer offering 10,800 USDC for that quantity crosses both asks but executes against the worse one. Because both asks predate the buyer, the selected ask sets the price. The attacker can then buy the untouched honest ask for 10,100 USDC, restore its inventory, and retain a 700-USDC spread before costs. In the higher-fee version, sell and repurchase priority payments of 0.11 and 0.10 USDC leave 699.79 USDC before gas and redemption costs.

- **Clamped key `1`, tenfold price difference:** an honest ask selling `1e27` asset units for `100_000_000` quote units and an attacker ask selling the same quantity for `1_000_000_000` quote units both map to key `1`. With respective priority fees of `100_000` and `110_000`, a later matching bid pays the attacker 1,000 USDC despite the available 100-USDC ask. Repurchasing that ask restores inventory and captures 900 USDC before costs, or 899.79 USDC after the illustrated two priority payments and before gas.

- **Symmetric bid-side degradation:** in an 18-decimal PEPE/six-decimal USDC pool, bid A offers 100 USDC for approximately 9,174,311 PEPE with a 0.10-USDC priority fee, while bid B offers 100 USDC for 10,000,000 PEPE with a 0.20-USDC fee. Both have key `10`. A later seller offering 10,000,000 PEPE for at least 100 USDC fills B first. Filling A first would exchange only about 9.17 million PEPE for the same 100 USDC, preserving roughly 826,000 PEPE of initial price improvement—about 8% of the lot—as a remainder that can be refunded, left resting, or subsequently matched. Instead, the worse bid consumes the entire seller order and skips A.

- **Loss persists after dust closure:** asks selling `1e27` asset units for 1,100 and 1,800 USDC, with priority fees of `100_000` and `100_001` units, share key `1`. A later buyer offering 1,900 USDC also has key `1`. With `minOrder` set to 1,000 USDC, execution against the worse ask leaves 100 USDC, which is closed and refunded as dust. Executing the cheaper ask first would deliver the same asset quantity and refund 800 USDC. The buyer therefore pays 700 USDC more even after its order closes; the attacker can repurchase the remaining cheaper ask to capture that spread, less costs.

For ordinary nonclamped buckets, the exact-price difference is less than one raw key interval, but this can be economically material for low-priced assets or large quantities. Clamped boundary buckets permit much wider relative differences. Inventory-neutral extraction requires the displaced liquidity to remain available until repurchase; competing fills, cancellations, or repricing can prevent that leg. Individual exact limits remain respected, and the defect does not require an escrow shortfall, insolvency, or a minimum-output bypass.

Severity Note:
- Outside the clamped key boundaries, the exact-price gap inside one bucket is less than one raw key interval, so the loss is material only when that interval is large relative to price or the filled quantity is large.
- Inventory-neutral capture of the spread requires the displaced better order to remain open until a later repurchase; competing fills, cancellations, or repricing can remove that leg. The worse fill itself does not depend on the repurchase.

### 2. `updatePrice` lets sell orders retain a priority bid below the minimum required for their new terms

**Severity:** Low  
**Contracts:** `src/libraries/AsyncFiller.sol`, `src/AsyncSwap.sol`, `src/libraries/AsyncMatching.sol`

#### Context

`AsyncMatching.addOrder` checks minimum order size before `AsyncFiller.addOrder` escrows the priority bid. For sells, the required bid is `minPriorityFee(amountOutMin)`: the lesser of 0.1% of the minimum output and 100,000 USDC base units ($0.10). Makers can subsequently reprice through `AsyncSwap.updatePrice` or authorize a relayer through `updatePriceWithSig`; both reach `AsyncFiller.updatePrice`. Bids are non-refundable: direct matches settle them proportionally, while fills and cancellations settle the remaining bid to `FeeVault`.

```solidity
// File: src/libraries/AsyncFiller.sol
checkMinimum(self, book, order.key.toId(), info.isBuy, info.zeroForOne, info.amountIn, newAmountOutMin);
uint256 old = info.amountOutMin;
_remove(self, book, id);
// @auditagent> Repricing retains undersized bid
info.amountOutMin = newAmountOutMin;
info.price = _priceKey(info.isBuy, info.amountIn, newAmountOutMin);
```

#### Root Cause

`AsyncFiller.updatePrice` validates ownership, order liveness, a positive new minimum, and `checkMinimum`, but never checks whether the retained `priorityFee` satisfies `minPriorityFee(newAmountOutMin)`. It changes the sell's minimum output and price and reinserts the order with fresh time priority without increasing its escrowed bid. Both direct and signed repricing inherit this omission.

With `book.minOrder == 0`, including pools initialized while `defaultMinOrder` remains unset, a maker can create a sell with `amountOutMin = 1` or `999` USDC base units and `priorityFee = 0`, because the tiered bid rounds down to zero. Repricing to `100_000_000` base units (100 USDC), or to 1,000 USDC, retains that zero bid, although either final notional requires 100,000 base units at admission. A nonzero minimum can still allow partial underpayment: under the deployment's configured 10-USDC minimum, an initial 10-USDC sell requires 10,000 base units ($0.01), but repricing to 1,000 USDC does not collect the additional 90,000 base units ($0.09).

Through the ordinary Router route, the initially cheap order must survive placement matching—for example, with no opposing buy or active LP liquidity. After obtaining its assigned salt, the maker can call `updatePrice`, or anyone can relay a valid maker-signed `updatePriceWithSig` for the live order.

Alternatively, a maker controlling a custom executor can perform the bypass atomically. A maker contract can authorize itself through `setExecutor`, create and fund the order through `PoolManager.swap` during an unlock, and call `updatePrice` before the separate `matchNewOrder` call. `_beforeSwap` creates the order but does not match it. The executor may then permit matching or omit `matchNewOrder` and leave the repriced order resting, so this route does not expose the temporary low minimum to execution.

#### Impact

Qualifying sell orders can subsequently be matched, filled—including against LP liquidity when their terms are met—or cancelled while paying less than the mandatory priority bid for their final terms. `FeeVault` loses up to 100,000 USDC base units ($0.10) per order; the 10-to-1,000-USDC example avoids $0.09. Repetition reduces protocol revenue and weakens the mandatory bid's anti-spam and cancellation deterrent.

These low-bid admission variants depend on pool minimums that permit an initial bid below the final requirement; higher minimums can limit or eliminate the underpayment. Makers must still fund their sell input and pay transaction costs, which may exceed the savings. The bypass does not grant higher queue priority: orders remain ranked by their actual bid, and repricing resets time priority. It does not withdraw other makers' escrow, affect counterparties' bids, or bypass the separate filler output fee.

### 3. Signed cancellations cannot be revoked and stay valid after the order is closed by other means

**Severity:** Low  
**Contracts:** `src/Router.sol`

#### Context

`Router.cancelWithSig` lets anyone holding a maker's EIP-712 `CancelOrder` signature cancel that maker's order. The digest commits to the maker, the directional tokens, the `orderId`, the live stored `amountIn`, a maker-scoped `nonce` and a `deadline`. Replay is meant to be blocked by `cancelNonceUsed[maker][nonce]`. `OrderSignatures.hashCancel` states the nonce exists because "order ids can recur (identical order re-placed in the same block after a cancel), so order deletion alone does not stop a signed cancel from being replayed." The project summary also says makers can "Invalidate unused signature nonces (`AsyncSwap.invalidateNonce`)".

```solidity
// File: src/Router.sol
function cancelWithSig(AsyncOrder calldata order, uint256 nonce, uint256 deadline, bytes calldata signature)
    external
{
    if (block.timestamp > deadline) revert SignatureExpired();
    // @auditagent> only consumption path for nonce
    if (cancelNonceUsed[order.owner][nonce]) revert NonceAlreadyUsed();
    cancelNonceUsed[order.owner][nonce] = true;
    bytes32 id = _orderId(order);
    (uint256 amountIn,) = HOOK.asyncOrderInfo(order.key.toId(), id);
    bytes32 digest = _hashTypedDataV4(OrderSignatures.hashCancel(order, id, amountIn, nonce, deadline));
```

#### Root Cause

`cancelNonceUsed` is written in exactly one place: inside `cancelWithSig` itself. The Router has no function that lets a maker mark a cancel nonce as used or revoke a signed cancel. `AsyncSwap.invalidateNonce` lives in the hook's own storage. The Router never reads it, so it cannot affect Router cancel nonces.

Several paths close an order without consuming the outstanding signed-cancel nonce:
- a direct `cancelOrder`
- a full `fillOrder`
- a full book match
- a pool-liquidity fill

After any of these, a previously issued `CancelOrder` signature stays valid until `deadline`. `updatePrice` does not invalidate it either, because the digest binds `orderId` and `amountIn`, not `amountOutMin`.

The nonce therefore only prevents replay when the cancel was executed through `cancelWithSig`. That is narrower than the replay protection the `hashCancel` comment describes.

#### Impact

A maker who handed a signed cancel to a relayer cannot take it back. The relayer, or anyone who saw the signature (for example from a failed public transaction or a relayer API), can cancel the order at any point up to `deadline`, provided the stored `amountIn` still equals the signed amount. This holds even if the maker has since decided to keep the order, and even after the maker calls `AsyncSwap.invalidateNonce` believing their unused signatures are void.

The same applies if an identical order id recurs with the same `amountIn` before the deadline. That case requires the maker to close the original order by another path and re-place an identical order in the same block. The stale signature then cancels the new order.

In each case the maker loses:
- the order's book position and time priority
- the remaining escrowed `priorityFee`, which is forfeited to `FeeVault` on cancellation

The input amount is refunded to the maker, so principal is not stolen. Impact is limited to unwanted cancellation and the loss of the non-refundable bid.
