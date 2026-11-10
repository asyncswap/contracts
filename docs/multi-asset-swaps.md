# Multi-asset swaps: an open problem

Status: **v1 proposed, matching an open problem.** Placing and filling any-asset orders has a simple
first answer (section 4E: non-numeraire pools, filled from their own LP liquidity or by fillers). **Matching those orders
automatically across different order books** is the open problem this page is mostly about. Nothing
here is implemented, and proposals are welcome.

## 1. The problem

Every Async Swap market is an asset against its chain's numeraire (USDC, or USDG on Robinhood):
ETH/USDG, AMD/USDG, TSLA/USDG. That keeps liquidity in one place per asset, but a maker who wants
**ETH → AMD** has no book and no pool for that pair. Today the interface says "No pool for this pair
yet".

Version 1 (section 4E) lets that maker place the order anyway, on an ETH/AMD pool, and fills it from
that pool's own LP liquidity when there is any, or by any filler paying AMD. What v1 does **not** do is
match it automatically against other books.

### The open problem: automatic matching across order books

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
spans two or more of them has no single place to happen today. Sections 2 to 4 describe the
constraints and the approaches (B to D, and the later steps of E) that attack this.

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
| `PoolManager.unlock` cannot be nested. | v4-core `unlock`: `AlreadyUnlocked` | A separate contract cannot fill Async Swap orders inside its own unlock; that has to happen in the Router's. |
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

## 4. Approaches

Approach E (non-numeraire pools, filled by fillers) is the proposed v1: it reuses the existing order
and fill paths and needs only a few guards in the hook. It does not solve automatic matching; its
later steps and approaches B to D are the candidates for that.

### E. Non-numeraire pools (v1: filled by fillers)

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
   AMD, sourced however it likes: inventory, any Uniswap v4 pool, our numeraire books, other venues.
   The existing `executeOrder` → `AsyncFiller.fill` already pays the pool's output currency, so the
   maker receives AMD (less 0.02%) and the filler the ETH (less 0.02%).
5. **Reprice and cancel** work as today.

**Contract changes for v1.** The order code assumes every pool has a numeraire side, so a few places
need a non-numeraire guard. None of them touch the matching engine.

1. `_beforeInitialize`: allow non-numeraire pools instead of reverting with `NumeraireRequired`.
   `_beforeAddLiquidity` keeps allowing LP positions, as for any pool.
2. Order creation: do not insert the order into a book.
3. `matchNewOrder`: for these pools, skip the book and try only the pool's LP liquidity (the pool goes
   first unconditionally; `_poolBeatsBook` compares against a book that does not exist).
4. Minimum order size: today's check is in numeraire units, which these pools do not have. In v1,
   either skip it or use a per-pool or per-asset minimum. `closeBelowMinimum` likewise skips them.
5. Priority bids: their minimum is computed from the numeraire side, and without a book they decide
   nothing. Require zero on non-numeraire pools in v1.
6. Fill and cancel: both remove the order from its book first; that removal must accept orders that
   were never in one.

This ships with the next hook and Router deployment (the Router address is immutable in the hook) and
needs a review pass.

**What it gives.** Any-asset limit orders, and instant fills on placement wherever a non-numeraire
pool has LP liquidity, with no new order type, no new storage and no change to how orders fill.

**What it does not give.** Where a pool has no LP liquidity, fills depend on fillers showing up. The
simplest help is an off-chain filler run by the team that watches non-numeraire orders, buys the
output token (Uniswap, or our numeraire books) and fills when the maker's limit leaves a margin. There
are no baskets, and no automatic matching against other books (the open problem in section 1).

**Later steps toward automatic matching.**

- **`fillFromNumeraire`.** A permissionless fill that routes an order's ETH → USDG → AMD through the
  numeraire pools in one transaction: sell the ETH for as much USDG as possible (the ETH/USDG book,
  then its LP liquidity), spend all of it on as much AMD as possible (the AMD/USDG book, then its LP
  liquidity), charge the fee once, and give the maker everything bought if it meets the minimum.
  Using the books means filling resting orders partially at their limits, which the matching code
  already does for book matches. This is matching across two books, done by the protocol.
- **Matching inside non-numeraire pools.** Direct ETH ⇄ AMD matches, by picking one currency as the
  pool's quote side for price keys and minimums so the existing matching engine can run there.
- **Rings and batches.** Matching across many books at once is approaches C and D.

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

A filler settles intents inside one unlock, using a **ledger** of per-token credits and debits on top of
flash accounting:

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

| | E. Non-numeraire pools | A. Interface route | B. Instant via custom accounting | C. Intents + ledger | D. Uniform batches |
|---|---|---|---|---|---|
| Instant X → Y | Where the pool has LP liquidity (v1); yes with `fillFromNumeraire` | Two steps | Yes, one transaction | Yes | Per batch |
| Limit X → Y | Yes, limit in the output token | Yes (leg 2 rests) | No | Yes | Yes |
| Baskets | No | No | No | Yes | Yes |
| Automatic matching across books | No (v1); two books with `fillFromNumeraire` | No | No | Yes | Yes |
| Reachable by external routers | No | No | Yes | No | No |
| Contract change | A few hook guards (v1) | None | Hook | Settlement library + Router | C plus solver rules |

E is the v1: any-asset limit orders, filled by fillers, with a few hook guards and the existing fill
path unchanged. Automatic matching across books comes from E's later steps or from C and D. The others stack around it. A works today. B makes instant multi-asset swaps native and
opens Async Swap liquidity to the rest of Uniswap v4. C adds limit intents, baskets and CoWs on top of
B's instant fills. D tightens C's acceptance rule into uniform prices.

## 6. Open questions

For E (v1):

- Minimum order size on non-numeraire pools: skip it, or a per-pool or per-asset minimum?
- Should the price passed when creating a non-numeraire pool be ignored, or kept as a reference price
  for the interface?
- Who runs the first filler, and how much margin should it require before filling?

For automatic matching across books:

- Should `fillFromNumeraire` use the numeraire books (partial fills of resting orders) or only LP
  liquidity at first?
- Who calls it, and does surplus above the maker's minimum go to the maker or partly to the caller?
- Which currency is a non-numeraire pool's quote side once matching runs inside it?

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
