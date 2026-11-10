# Multi-asset swaps: an open problem

Status: **open problem.** This page states the problem, the constraints the current contracts put on
any answer, and the approaches we see, with their trade-offs. Nothing here is implemented, and
proposals are welcome.

## 1. The problem

Every Async Swap market is an asset against its chain's numeraire (USDC, or USDG on Robinhood):
ETH/USDG, AMD/USDG, TSLA/USDG. That keeps liquidity in one place per asset, but a maker who wants
**ETH → AMD** has no book and no pool for that pair. Today the interface says "No pool for this pair
yet".

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
- No direct cross pools (ETH/AMD, AMD/TSLA, …): the number of pools would grow with the square of the
  number of assets and liquidity would fragment.
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

Approach E (multi-pool swap orders) is the current lead: it needs the least new machinery and only
uses what the hook already has. A to D are kept for comparison.

### E. Multi-pool swap orders (leading approach)

A multi-pool swap order is an **ordinary order on the input token's numeraire book** with one extra
piece of hook data: the token the maker actually wants. Everything about the order is unchanged: it
rests in the ETH/USDG book at its USDG limit, and matches, fills, reprices and cancels through the
existing paths. Only the payout changes.

**Order data.** `UserParams` gains two fields, set only for these orders:

```solidity
Currency outputToken;  // token B the maker wants; must have a B/numeraire pool on this hook
uint256 minOutputB;    // least B the maker accepts for the order's numeraire proceeds
```

**Storage.** A flag on the stored order and a side mapping, so ordinary orders pay nothing extra:

```solidity
struct OrderInfo {
    // ... existing fields ...
    bool isMultiPoolSwap;  // fits the 2 free bytes after `reprices`: no extra storage slot
}

struct MultiPoolSwap {
    Currency outputToken;
    uint256 minOutputB;
}
mapping(bytes32 orderId => MultiPoolSwap) multiPoolSwaps;  // written only when the flag is set

event AsyncOrderMultiPoolSwap(PoolId indexed poolId, bytes32 indexed orderId, Currency outputToken, uint256 minOutputB);
```

**Lifecycle.**

1. **Place.** An ETH/USDG order with `outputToken = B` and `minOutputB`. The hook checks that a
   B/numeraire pool exists on this hook (a book lives in a pool, and the hook cannot initialize one
   at fill time with no starting price) and that `minOutputB` is set. The interface creates the B
   market first when it is missing, through the existing pool-creation flow.
2. **Fill.** At any time, through any existing path. `isMultiPoolSwap == false` pays USDG exactly as
   today; `true` holds the maker's USDG proceeds in the hook (as ERC-6909 claims, earmarked for the
   order) instead of paying them out.
3. **Convert, in the same transaction.** With custom accounting, the hook buys B with the proceeds:
   first from B's book (resting asks selling B for USDG), then from the B/USDG pool's LP liquidity,
   never worse than `minOutputB` pro rata. The USDG nets to zero inside the PoolManager; the maker
   receives B (`take`, or claims).
4. **Rest the remainder.** Whatever cannot be bought now becomes a **resting B/USDG buy order** owned
   by the maker, funded from the earmarked claims (no second deposit or transaction), priced at
   proceeds / `minOutputB`. It inherits the maker's existing Router executor grant, so it fills,
   reprices and cancels like any other order with no new approval.
5. **Dust.** A remainder below B's book minimum is paid to the maker as USDG claims instead, the same
   rule `closeBelowMinimum` applies today.

**Where conversion runs.** Not inside the matching loops: every maker payout (`fill`, book matches,
pool fills) would otherwise detour into a second book mid-match, in the most size-constrained and
invariant-tested code. The fill earmarks the proceeds; a conversion routine in a linked library then
runs in the same transaction (driven by the Router after the fill, or a permissionless `convert` for
fills that happen elsewhere).

**What falls out.**

- **Cross-pair limit orders** with no new books: ETH rests against USDG as today and B arrives on fill.
- **Coincidences of wants through the books**: conversion buys B from resting B/USDG sellers, so an
  ETH → B order and ordinary B sellers fill each other with no pool touched.
- **Opposite routes meet in the numeraire books**: a resting B/USDG remainder is exactly the bid a
  later B → ETH multi-pool swap order sells into, so pairwise and ring flows clear through the books.
- **Instant cross-pair swaps**: an order that fills on placement converts in the same transaction.

**Limits.** No baskets (one input, one output). Each leg pays the 0.02% trade fee. No per-batch
uniform prices, so ordering still matters as it does today. The maker's limit is in the numeraire
(plus the `minOutputB` guard), not a single cross price; a limit expressed only in B has no stable
place in the input book and belongs to approaches C or D.

**Contract changes.** Two `UserParams` fields and the matching Router change, the
`isMultiPoolSwap` flag and side mapping, the earmark on fill, and the conversion routine in a linked
library (the hook is near EIP-170). The Router address is immutable in the hook, so this ships with
the next hook and Router deployment, and the new path needs an audit pass.

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

- **Direct cross pools:** quadratic pool count and fragmented liquidity.
- **Linked orders inside the matching engine** (an ETH → AMD order held as an ask in one book and a bid
  in another): the most delicate change to the most size-constrained, invariant-tested code.

## 5. Comparison

| | E. Multi-pool swap orders | A. Interface route | B. Instant via custom accounting | C. Intents + ledger | D. Uniform batches |
|---|---|---|---|---|---|
| Instant X → Y | Yes, one transaction | Two steps | Yes, one transaction | Yes | Per batch |
| Limit X → Y | Yes (numeraire limit + `minOutputB`) | Yes (leg 2 rests) | No | Yes | Yes |
| Baskets | No | No | No | Yes | Yes |
| CoWs | Through the books | No | No | Yes | Yes, automatic |
| Reachable by external routers | No | No | Yes | No | No |
| Contract change | Hook data, flag, conversion library | None | Hook | Settlement library + Router | C plus solver rules |

E is the lead: cross-pair limit and instant swaps, and CoWs through the books, with the least new
machinery. The others stack around it. A works today. B makes instant multi-asset swaps native and
opens Async Swap liquidity to the rest of Uniswap v4. C adds limit intents, baskets and CoWs on top of
B's instant fills. D tightens C's acceptance rule into uniform prices.

## 6. Open questions

For E:

- Should conversion try B's LP liquidity at all, or only B's book (keeping the remainder resting
  until a B seller appears)?
- When an earmark is left for `convert` by fills outside the Router, who calls it, and is a small
  keeper reward needed?
- Should the resting B/USDG remainder keep the original order's priority bid, or start with none?

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
