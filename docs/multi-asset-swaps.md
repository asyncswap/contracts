# Multi-asset swaps: flash fills across order books

Status: **proposed, not implemented.** The plan has two parts:

- **Where any-asset orders live (section 4E):** non-numeraire pools such as ETH/AMD, with orders placed
  exactly like today's.
- **How they fill (section 4F): flash fills.** The Router hands a filler the order's escrowed input
  inside its own PoolManager unlock and calls the filler back. Using flash accounting, the filler
  routes through any Uniswap v4 pool and any Async Swap book, in a loop it controls, until the maker's
  minimum is paid. Nothing has to be pre-funded, and USDC in the middle of a route nets to zero.

Flash fills also answer most of the earlier open problem, matching an order across several books:
a filler can fill resting ETH/USDC bids and AMD/USDC asks inside one unlock to deliver an ETH to AMD
order. Proposals and reviews are welcome.

## 1. The problem

Every Async Swap market is an asset against its chain's numeraire (USDC, or USDG on Robinhood):
ETH/USDG, AMD/USDG, TSLA/USDG. That keeps liquidity in one place per asset, but a maker who wants
**ETH → AMD** has no book and no pool for that pair. Today the interface says "No pool for this pair
yet".

The plan lets that maker place the order anyway, on an ETH/AMD pool (section 4E), and fills it with a
flash fill (section 4F): from that pool's own LP liquidity when there is any, or by a filler who turns
the maker's ETH into AMD inside the same unlock, through whatever pools and books it chooses.

### Matching across order books

A non-numeraire order (ETH → AMD) could be filled from liquidity that already sits in the protocol,
spread across several books:

- resting ETH/USDG bids (buyers of the maker's ETH) together with resting AMD/USDG asks (sellers of
  the AMD the maker wants), with the USDG netting out in between;
- opposite non-numeraire orders (AMD → ETH) on the same ETH/AMD pool;
- longer rings across several non-numeraire pools (ETH → AMD, AMD → TSLA, TSLA → ETH);
- the numeraire pools' LP liquidity for whatever the books cannot cover.

Matching automatically means the protocol, not an outside filler, finds these combinations and
settles them atomically, with every maker getting at least their limit, in a way that stays fair,
bounded in gas, and inside a matching engine that is already at the contract size limit. The order
books are separate data structures, each with its own price keys in numeraire units, so a match that
spans two or more of them has no single place to happen inside the matching engine. Flash fills (4F)
move that work out of the engine and into the filler's callback: the filler fills each book's resting
orders in turn inside one unlock, and flash accounting nets the USDC in between. The engine itself does
not change. Rings and uniform prices across many orders at once (approaches C and D) build on the
same callback.

What we want, in order of ambition:

1. **Any asset for any asset**, instantly, at a fair price.
2. **Any asset for any asset as a limit order**, without the maker ending up holding something they
   did not ask for.
3. **Baskets**: several assets in, several out, in one trade.
4. **Coincidences of wants (CoWs)**: orders that offset each other trade directly, without paying
   pool fees and price impact on both sides. Not only one order against its exact opposite, but rings
   (ETH → AMD, AMD → TSLA, TSLA → ETH) and matches through the existing books.
5. **The cheapest liquidity wins**, whether it is a resting order, an Async Swap pool, another
   Uniswap v4 pool, or a filler's inventory.

And what must stay true:

- A maker never receives less than the minimum they signed.
- Liquidity should stay concentrated in the numeraire pools. Non-numeraire pools may hold LP
  liquidity (approach E), but the protocol does not depend on it: an asset pair with no LPs still
  works through fillers, and the number of pools that need LPs does not grow with the square of the
  number of assets.
- Orders are good till cancelled (no expiry), as decided for single-pair orders.

## 2. Constraints in today's contracts

These come straight from `src/` and decide where any answer can live.

| Constraint | Where | Consequence |
|---|---|---|
| Only the trusted Router may swap through an Async Swap pool. | `AsyncSwap._beforeSwap`: `if (sender != router) revert NotTrustedRouter()` | Standard v4 routers and aggregators cannot route through our pools. |
| Every swap becomes an order: the hook escrows the whole input and returns no output. | `_beforeSwap` takes `amountSpecified` and returns a `BeforeSwapDelta` for the input only | A swap never hands output back in the same call, so two pools cannot be chained in one swap path. |
| The Router address is fixed at hook deployment. | `address public immutable router` | A new routing entry point means a new Router and a new hook deployment. |
| `PoolManager.unlock` cannot be nested. | v4-core `unlock`: `AlreadyUnlocked` | A separate contract cannot fill Async Swap orders inside its own unlock; that has to happen in the Router's. Flash fills (4F) solve this by having the Router call the filler back from inside its unlock. |
| Fills pay the maker before releasing the input. | `Router.fillOrder` → `AsyncSwap.executeOrder` → `AsyncFiller.fill`: the filler settles the output, then receives the input | A filler must already hold the output token. A flash fill reverses the order: input first, callback, then the output check. |
| The hook, Router and matching libraries are within a few hundred bytes of EIP-170. | `forge build --sizes` | New logic belongs in a linked library, not in the hook or Router. |

## 3. Tools Uniswap v4 gives us

Two kinds of accounting do most of the work.

**Flash accounting (PoolManager).** Inside one `unlock`, swaps on any number of pools, `take`,
`settle`, `mint` and `burn` only change per-currency **deltas**. Only the net delta per currency must
be zero when `unlock` returns. A route ETH → USDG → AMD through two pools moves only ETH in and AMD out;
the USDG nets to zero and never leaves the PoolManager.

**Custom accounting (hooks).** A hook's `beforeSwap` can return a `BeforeSwapDelta` that takes over the
swap: it can consume the input *and* provide the output itself, so the pool's own curve is skipped.
Async Swap already uses this, but only to take the input (and turn it into an order).

**ERC-6909 claims.** Balances held inside the PoolManager, transferable without moving tokens. Async
Swap escrow, proceeds and fees are already claims.

**Callbacks inside an unlock.** While the PoolManager is unlocked, any contract can call `swap`,
`take`, `settle`, `mint` and `burn`; each caller builds up its own deltas, and all of them must be
zero when `unlock` returns. So the contract that opened the unlock (our Router) can call out to a
filler's contract, let it trade on any pool, and check the result afterwards. This is the same shape
as a flash loan or a Uniswap swap callback, and it is what flash fills use.

## 4. Approaches

The proposed plan combines two approaches. **E** decides where any-asset orders live (non-numeraire
pools, a few hook guards). **F** decides how they fill (a flash-fill callback on the Router). F works for
every order, numeraire pairs included, and is what makes matching across books possible. A to D remain
alternatives or later layers on top.

### E. Non-numeraire pools (v1: pool liquidity, then fillers)

**Two pool types, told apart by the pool key.** The hook already decides whether a pool pairs a token
with the numeraire: `_beforeInitialize` checks `key.currency0 == numeraire || key.currency1 ==
numeraire` and today reverts with `NumeraireRequired` otherwise. That check is a pure function of the
`PoolKey`, so a pool's type needs no storage, no order-id bits and no extra hook data.

| | Numeraire pool (ETH/USDG) | Non-numeraire pool (ETH/AMD) |
|---|---|---|
| Recognised by | One currency is the numeraire | Neither currency is the numeraire |
| Liquidity | Book, matching engine and LP positions, as today | LP positions if anyone provides them; **no book** in v1 |
| An order's limit | In the other currency, as today | In the other currency: an ETH → AMD order sets its minimum in AMD |
| Fills | As today | The pool's own LP liquidity, or a filler paying AMD |

**v1 is as simple as possible: the pool's liquidity first, then fillers.** No book, no matching, no
routing.

1. **Create.** Anyone initializes an ETH/AMD pool with the Async Swap hook. LPs may add liquidity to it
   like any v4 pool; it works without them.
2. **Place.** The maker swaps ETH into it through the Router, as for any order. The ETH is escrowed as
   claims and the order records its minimum in AMD. It is not inserted into a book.
3. **Fill from pool liquidity.** In the same transaction, `matchNewOrder` tries the pool's own LP
   liquidity, as numeraire pools already do when the pool beats the book (here there is no book, so
   the pool always goes first). The existing `fillOrderFromPoolLiquidity` path swaps the order against
   the LP positions and fills it only if the output meets the maker's AMD minimum; otherwise the order
   rests. Anyone can retry later, as LPs add liquidity or prices move, through the existing
   `Router.fillFromPoolLiquidity`. This path has no numeraire dependency: the 0.01% protocol fee and
   the dynamic fee are taken in the order's own input and output currencies.
4. **Fill by a filler.** For orders the pool cannot fill, a filler calls `Router.fillOrder` and pays
   AMD from inventory, as today, or uses a **flash fill** (4F): it receives the maker's ETH first and
   turns it into AMD inside the same unlock, through any Uniswap v4 pool or our numeraire books. Either
   way the maker receives AMD (less 0.02%) and the filler keeps the ETH it did not need (less 0.02%).
5. **Reprice and cancel** work as today.

**Contract changes for v1.** The order code assumes every pool has a numeraire side, so a few places
need a non-numeraire guard. None of them touch the matching engine.

1. `_beforeInitialize`: allow non-numeraire pools instead of reverting with `NumeraireRequired`.
   `_beforeAddLiquidity` keeps allowing LP positions, as for any pool.
2. Order creation: do not insert the order into a book.
3. `matchNewOrder`: for these pools, skip the book and try only the pool's LP liquidity (the pool goes
   first unconditionally; `_poolBeatsBook` compares against a book that does not exist).
4. Minimum order size: use the decimals floor on both tokens. Today `checkMinimum` checks a dollar
   minimum (`minOrder`, which deployments set to 0, i.e. off: `DEPLOY_MIN_ORDER_USD` defaults to 0) and
   an asset floor (`minAssetAmount = 10^(decimals - assetPrecision)`, at least 0.0001 of a whole token
   with `assetPrecision = 4`). The asset floor is the real minimum and depends only on decimals, so a
   non-numeraire pool computes it for both currencies at initialize and checks the order's input and
   output against their own floors. No valuation or oracle is needed; the dollar minimum does not
   apply (there is no dollar side). `closeBelowMinimum` uses the same floors.
5. Priority bids: their minimum is computed from the numeraire side, and without a book they decide
   nothing. Require zero on non-numeraire pools in v1.
6. Fill and cancel: both remove the order from its book first; that removal must accept orders that
   were never in one.

This ships with the next hook and Router deployment (the Router address is immutable in the hook) and
needs a review pass.

**What it gives.** Any-asset limit orders, and instant fills on placement wherever a non-numeraire
pool has LP liquidity, with no new order type, no new storage and no change to how orders fill.

**What it does not give on its own.** Where a pool has no LP liquidity, fills depend on fillers, and
without flash fills a filler must already hold the output token. With 4F, a filler needs no inventory:
the team can run a reference filler that watches non-numeraire orders and flash-fills them whenever the
route through the numeraire books and pools beats the maker's limit.

**Later steps toward automatic matching.**

- **`fillFromNumeraire`, now a reference flash filler.** The ETH → USDG → AMD route (the ETH/USDG book,
  then its LP liquidity; then the AMD/USDG book, then its LP liquidity) no longer needs to live in the
  hook. It becomes a small, permissionless filler contract built on 4F that anyone can call. Matching
  across two books, done atomically, without growing the size-limited hook.
- **Matching inside non-numeraire pools (v2).** Direct ETH ⇄ AMD matches by running the existing
  matching engine on a non-numeraire pool; see the plan below.
- **Rings and batches.** Matching across many books at once is approaches C and D.

#### v2 plan: matching inside a non-numeraire pool

The matching itself does not depend on the numeraire. Crossing, match amounts and partial fills
(`_crosses`, `_matchAmounts`, `EligiblePrice`) are pure price ratios, and trade fees are taken in each
side's own currency. What depends on the numeraire is a thin layer of units around it:

| Piece | Today | On a non-numeraire pool |
|---|---|---|
| Buy or sell (`isBuy`) | Set when the input is the numeraire (`_beforeSwap`) | Set when the input is the pool's **quote currency** |
| Price keys (`_priceKey`, `TickPrice`) | Ordered as numeraire per asset, with a flag for whether the numeraire is `currency1` | The same code, oriented to the quote currency |
| Pool before book (`_poolBeatsBook`) | Uses the same orientation flag | Generalizes with the price keys |
| Minimum order size | Decimals floor on the asset (dollar minimum off by default) | Decimals floor on both currencies (v1 already does this) |
| Priority bids | Paid in the numeraire; minimum is 0.1% of the order's numeraire value, capped at $0.10 | Still paid in the numeraire; the minimum uses the flat $0.10 cap, since the order has no numeraire value |

**The change is to give every pool a quote currency.** Numeraire pools keep the numeraire. A
non-numeraire pool takes one of its two currencies, fixed at initialize: `currency1` is the simplest
rule, or the currency with the deeper numeraire market so prices read naturally. With that, the
existing engine runs on non-numeraire pools unchanged, and two opposite ETH ⇄ AMD orders match each
other directly.

**What is special about the numeraire, and why numeraire pools stay the hub.**

1. **One unit of account.** Priority bids and the fee vault use one currency on every pool.
2. **One book per asset.** Liquidity concentrates in each asset's numeraire book, and any cross price
   can be derived through it. Non-numeraire books are optional extras; nothing should depend on them.
3. **A stable midpoint.** Routes through the numeraire leave makers holding a stablecoin between legs.

**How sensitive it is.** The matching math is the same audited, invariant-tested engine on both kinds
of pool. The extra risk is all in the units layer:

- every place that assumes "numeraire = quote" must be generalized, and the property, invariant and
  adversarial tests re-run for both orientations (quote as `currency0` and as `currency1`);
- decimal combinations numeraire pairs never hit (for example 18 against 18, or 6 against 0), and very
  large or very small price ratios, since neither side is a stablecoin;
- the priority-bid minimum on non-numeraire pools, which no longer scales with the order.

Matching **across** books (an ETH → AMD order against the ETH/USDG and AMD/USDG books together) is not
solved by this; it stays the open problem.

### F. Flash fills: a filler callback inside the Router's unlock

**The idea.** Today a filler must hold the output token before filling. A flash fill reverses that: the
Router releases the maker's escrowed input to the filler first, calls the filler's contract back while
the PoolManager is still unlocked, and only then checks that the maker was paid. Inside the callback the
filler has full flash accounting: it can swap on any Uniswap v4 pool, fill other Async Swap orders, take
and settle, in a loop it controls, until it owes the maker the right amount. Every delta must net to
zero before the unlock closes, or the whole transaction reverts.

**Flow of one flash fill (ETH → AMD order, on an ETH/AMD pool).**

1. The filler calls `Router.flashFill(order, maxPrice, data)`. The Router opens one `unlock`.
2. The hook marks the order as being filled (no reprice, cancel or second fill until the end) and
   credits the order's escrowed ETH, less 0.02%, to the filler as a positive delta.
3. The Router calls `IAsyncSwapFlashFiller(msg.sender).asyncSwapFlashFill(order, amountIn, amountOwed, data)`.
4. Inside the callback the filler routes as it likes, for example:
   - fill a resting ETH/USDC bid with the ETH (receives USDC);
   - fill a resting AMD/USDC ask with the USDC (receives AMD);
   - swap any remainder through an ETH/USDC or AMD/USDC Uniswap v4 pool;
   - settle the AMD owed to the maker.
5. The Router checks the maker's AMD (the minimum plus the 0.02% fee) is settled, pays the maker,
   closes the order and returns. The filler keeps any surplus. The unlock closes only if every delta,
   the filler's included, is zero.

**Filling other Async Swap orders from inside the callback.** Each resting order is filled through the
Router, but the Router cannot open a second unlock. The Router therefore exposes **in-unlock entry
points** (`fillOrderInFlash`, `matchBookInFlash`) that run the same fill code without calling `unlock`,
and are accepted only while a flash fill is active and only from that flash fill's filler (recorded in
transient storage). A filler can chain any number of them, across any books, within one transaction.

**Why this is matching across books.** An ETH → AMD order can now be filled entirely from liquidity
already in the protocol: resting ETH/USDC bids buy the maker's ETH and resting AMD/USDC asks supply the
AMD, with the USDC netting to zero in between. Every resting maker fills at or above its own limit,
exactly as in a normal fill. The matching engine is unchanged; the filler is the router between books.

**Contract changes.**

| Piece | Change |
|---|---|
| Router | `flashFill` (opens the unlock, credits the input, calls back, checks the output) and the in-unlock entry points, gated by a transient "active flash fill" slot holding the filler's address. |
| Hook (`AsyncFiller.fill`) | An input-first variant: lock the order, credit the input, and after the callback verify and pay the output. The existing output-first `fill` stays for plain fills. |
| Interface | `IAsyncSwapFlashFiller.asyncSwapFlashFill(order, amountIn, amountOwed, data)`. |
| Fees | Unchanged: 0.02% on each side, the MEV tax on the outer transaction. |
| Code size | New logic goes in a linked library; the hook and Router are near EIP-170. |

The Router address is immutable in the hook and makers authorize the Router as their executor, so this
ships with a new hook and Router deployment, alongside E.

**Safety rules.**

- The order being flash-filled is locked for the whole callback: no reprice, cancel, top-up or second
  fill of it, and `matchBook` skips it.
- Only the filler that started the flash fill may use the in-unlock entry points, and only while it is
  active; the slot is cleared before the unlock returns.
- The maker's check is on the final settled amount, never on intermediate balances, so any route the
  filler takes is fine as long as the maker gets at least its minimum.
- Reentrancy into the Router's normal entry points is refused while a flash fill is active.
- Each in-unlock fill of another order applies that order's own minimum and fees, so resting makers are
  never worse off than in a normal fill.

- **Good:** no filler inventory needed; any route, through any v4 pool and any Async Swap book;
  matching across books without touching the matching engine; works for numeraire pairs too.
  This is the custom-accounting loop the filler controls itself.
- **Bad:** a new Router and hook deployment, and a new trust boundary (the callback) to audit. Fill
  quality still depends on fillers competing; a reference filler helps.

### A. Route through the numeraire in the interface

X → numeraire → Y as two ordinary orders. Leg 1 fills now at market (through the Async Swap pool, or
the Uniswap API where it covers the chain); leg 2 buys Y with the proceeds at the limit implied by the
maker's cross price, and rests if the book cannot fill it yet.

- **Good:** no contract change. The middle asset is the stable numeraire, so the risk between the
  legs is small, and the maker's cross limit is kept exactly once leg 1 has filled.
- **Bad:** two transactions (or one EIP-5792 batch), two fees, two price impacts, no CoWs.

### B. Instant swaps through hooked pools (custom accounting)

Give `_beforeSwap` an **instant mode**: when `hookData` asks for it, the hook fills the swap right away
from its book and then its LP liquidity, and returns the output through `BeforeSwapDelta` instead of
creating an order. If it cannot fill the minimum, the swap reverts. No order, no escrow, no maker
identity is created, so the "only the trusted Router" rule can be relaxed for this mode alone.

Then multi-asset routing is plain Uniswap v4: any router (Universal Router, an aggregator, our own)
swaps ETH → USDG in the ETH/USDG pool and USDG → AMD in the AMD/USDG pool in one path, and flash
accounting nets the USDG.

- **Good:** atomic, one transaction, no new entry point, and Async Swap liquidity becomes reachable by
  every Uniswap v4 router and aggregator.
- **Bad:** a change to the hook's core path (and a new deployment). Instant fills must not let an
  attacker reorder the book or drain LP positions at stale prices; this needs the same care as the
  existing pool-fill path. It solves instant swaps only, not limit orders across pairs or CoWs.

### C. Intents settled with a netting ledger

The maker signs "take these inputs, deliver at least these outputs", with no route:

```solidity
struct TokenAmount { Currency token; uint256 amount; }

struct Intent {
    address maker;
    TokenAmount[] inputs;      // escrowed as claims, like orders today
    TokenAmount[] minOutputs;  // the maker's guarantee
    address recipient;
    bool partialFill;          // all or nothing, or pro rata
    uint256 priorityFee;       // optional numeraire bid, as for orders
    uint256 nonce;             // cancel by invalidating it; no expiry
}
```

C generalizes F from one order to many: a filler settles a list of intents inside one unlock, using a
**ledger** of per-token credits and debits on top of flash accounting. F's callback is the ledger's
step 2:

1. Release each intent's escrowed inputs into the ledger (credit).
2. The filler's callback does whatever it likes: fill resting Async Swap orders on any book, use Async
   Swap pools (instant mode from B), use any other v4 pool, bring inventory, or net intents against
   each other.
3. Pay each intent at least its minimums, as claims by default (debit), with the 0.02% protocol fee.
4. Require every minimum met and every ledger balance non-negative; leftovers are the filler's profit.

CoWs fall out of the ledger rather than being a separate mechanism:

- **Pairwise:** A sells ETH for AMD, B sells AMD for ETH. Each pays the other inside the ledger.
- **Ring:** ETH → AMD, AMD → TSLA, TSLA → ETH net to zero together.
- **Through the books:** A wants ETH → AMD. A resting ETH/USDG bid buys A's ETH and a resting AMD/USDG
  ask sells AMD for that USDG. The USDG nets to zero; A and both resting makers fill at their limits;
  no pool is touched.

- **Good:** any assets, baskets, CoWs through multiple orders, and the cheapest liquidity wins. It
  reuses escrow, claims, fillers and priority bids.
- **Bad:** a new settlement library reachable from the trusted Router (section 2), so a new deployment.
  Fill quality depends on fillers competing.

### D. Uniform-price batch clearing

Settlement in C already takes a list of intents. Tighten the acceptance rule: the solver also submits
one price per token, quoted in the numeraire (its price is 1), and every intent receives exactly its
inputs valued at those prices, which must meet its minimums. Pools cover only the residual.

This is the direction of Walraswap (arXiv:2310.12255) and CoW Protocol. Walraswap's Theorem 6.4 shows
that such a price vector exists together with external AMM swaps that leave a non-negative surplus,
and section 7 there computes it as a convex program.

- **Good:** multi-asset is native, CoWs are found automatically, and ordering within a batch stops
  mattering, which removes most of the MEV the slippage/MEV slider manages today.
- **Bad:** solvers, solver bonding and accountability, and per-block rather than continuous fills.
  The largest change.

### Ruled out

- **Depending on LP liquidity for every pair:** the number of pools that need LPs would grow with the
  square of the number of assets and liquidity would fragment. Approach E allows LP liquidity on
  non-numeraire pools but never depends on it.
- **Linked orders inside the matching engine** (an ETH → AMD order held as an ask in one book and a bid
  in another): the most delicate change to the most size-constrained, invariant-tested code.

## 5. Comparison

| | E. Non-numeraire pools | F. Flash fills | A. Interface route | B. Instant via custom accounting | C. Intents + ledger | D. Uniform batches |
|---|---|---|---|---|---|---|
| Instant X → Y | Where the pool has LP liquidity | Yes, by any filler, no inventory | Two steps | Yes, one transaction | Yes | Per batch |
| Limit X → Y | Yes, limit in the output token | Yes (fills E's orders) | Yes (leg 2 rests) | No | Yes | Yes |
| Baskets | No | No | No | No | Yes | Yes |
| Matching across books | No | Yes, by the filler, one order at a time | No | No | Yes | Yes |
| Filler needs inventory | Yes | No | n/a | n/a | No | No |
| Reachable by external routers | No | No | No | Yes | No | No |
| Contract change | A few hook guards | Router callback + input-first fill | None | Hook | Settlement library + Router | C plus solver rules |

**Plan: E + F.** E gives any-asset limit orders with a few hook guards; F gives every order (any-asset
or numeraire) an inventory-free fill path and matching across books, without touching the matching
engine. Both ship in the next hook and Router deployment. A works today. B would additionally open Async
Swap liquidity to external v4 routers. C extends F to many orders and baskets at once, and D tightens C
into uniform prices.

## 6. Open questions

For E (v1):

- Should the price passed when creating a non-numeraire pool be ignored, or kept as a reference price
  for the interface?
- Who runs the first filler, and how much margin should it require before filling?

For F (flash fills):

- Credit the input as a delta to `take`, or as ERC-6909 claims the filler burns?
- Should a single flash fill be able to fill several of the filler's own orders (a list), or one order
  per call at first?
- Do in-unlock fills of other orders charge the MEV tax again, or only the outer transaction?
- Should surplus above the maker's minimum stay with the filler, or be shared with the maker (the
  price-improvement fee idea)?
- Do we ship a reference flash filler (the numeraire route) at launch, and who runs it?

For automatic matching across books:

- Should `fillFromNumeraire` use the numeraire books (partial fills of resting orders) or only LP
  liquidity at first?
- Who calls it, and does surplus above the maker's minimum go to the maker or partly to the caller?
- Which currency is a non-numeraire pool's quote side in v2: `currency1`, or the one with the deeper
  numeraire market?
- Should priority bids be allowed on non-numeraire pools in v2 with the flat $0.10 minimum, or stay off?

For the other approaches:

1. Is instant mode (B) safe to expose to every router, or only to an allowlist at first?
2. Should B fill from the book only, LP liquidity only, or both (book first, as today's pool-first
   ordering decides)?
3. Escrowed intents only, or also signed-only intents posted for free and pulled through Permit2 at fill?
4. Should settlement be able to rest a residual as an ordinary order (for example the AMD leg of an
   ETH → AMD intent when the AMD book is empty)?
5. How much surplus goes to makers before batches: none (first valid fill), a reference-price floor,
   or a split with the filler?
6. Who may settle intents at first: anyone, or an allowlist while fillers are few?
