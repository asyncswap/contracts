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
- No non-numeraire pools that hold LP liquidity (ETH/AMD, AMD/TSLA, … with their own LP positions): the
  number of liquidity pools would grow with the square of the number of assets and liquidity would
  fragment. (Non-numeraire pools that only hold orders are a different thing; see approach E.)
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

Approach E (non-numeraire pools) is the current lead: it needs the least new machinery and reuses the
existing order and fill paths almost unchanged. A to D are kept for comparison.

### E. Non-numeraire pools (leading approach)

**Two pool types, told apart by the pool key.** The hook already decides whether a pool pairs a token
with the numeraire: `_beforeInitialize` checks `key.currency0 == numeraire || key.currency1 ==
numeraire` and today reverts with `NumeraireRequired` otherwise. That check is a pure function of the
`PoolKey`, so a pool's type needs no storage, no order-id bits and no extra hook data.

| | Numeraire pool (ETH/USDG) | Non-numeraire pool (ETH/AMD) |
|---|---|---|
| Recognised by | One currency is the numeraire | Neither currency is the numeraire |
| Liquidity | Book, matching engine and LP positions, as today | **Orders only**: no LP positions, so no liquidity fragmentation |
| An order's limit | In the other currency, as today | In the other currency: an ETH → AMD order sets its minimum in AMD |
| Fills | As today | A filler pays AMD, or `fillFromNumeraire` (below) |

**An ETH → AMD order is just an order on the ETH/AMD non-numeraire pool.** Swapping ETH into that pool escrows
the ETH exactly as today, with `amountOutMin` in AMD. The output token is the pool's other currency,
so there is nothing new to declare.

**The existing fill path already handles it.** A fill pays the pool's output currency to the maker and
the input to the filler. On a non-numeraire pool that means a filler pays AMD, sourced however it likes
(inventory, any Uniswap v4 pool, other venues): the PoolManager only requires every currency's delta
to net to zero by the end of the unlock. `executeOrder` and `AsyncFiller.fill` run unchanged, as do
`updatePrice`, `cancelOrder`, priority bids (paid in the global numeraire, which works on any pool),
the indexer and the interface.

**`fillFromNumeraire`: the best output through the numeraire pools.** A permissionless fill, in a
linked library, that anyone may call on a non-numeraire-pool order:

1. Sell the order's ETH for as much USDG as possible: the ETH/USDG book first, then its LP liquidity.
2. Spend **all** of that USDG on as much AMD as possible: the AMD/USDG book first, then its LP
   liquidity.
3. Charge the 0.02% trade fee once, on the final AMD (no fee on the USDG in between, which never leaves
   the PoolManager).
4. Require at least `amountOutMin` (pro rata for a partial fill) and give the maker everything bought.
   Otherwise revert; the order stays open for fillers.

The maker therefore gets the better of what fillers offer and the most AMD the numeraire books and
pools can deliver at that moment. Buying from resting AMD/USDG sellers in step 2 (and selling into
resting ETH/USDG bids in step 1) is a coincidence of wants through the books: those makers fill at
their limits and no pool is touched.

**Contract changes.**

1. `_beforeInitialize`: allow non-numeraire pools instead of reverting with `NumeraireRequired`.
2. `_beforeAddLiquidity`: reject LP positions on non-numeraire pools.
3. Non-numeraire pools skip the book in v1: their orders are escrowed but not inserted into a price book, and
   matching does not run. Minimum order sizes and price keys are defined in numeraire units, which a
   non-numeraire pool does not have; minimums for non-numeraire-pool orders can be checked by valuing the input
   through its numeraire pool, or set per asset.
4. `fillFromNumeraire` in a linked library (the hook is near EIP-170).

Like any hook change this ships with the next hook and Router deployment (the Router address is
immutable in the hook) and needs an audit pass.

**What it gives.** Cross-pair limit orders and instant cross-pair swaps (an order filled in the
transaction that places it), with no new order type, no new storage and no change to how orders fill.

**Limits.** No baskets (one input, one output). Orders on non-numeraire pools do not match each other in v1, so
two opposite ETH ⇄ AMD orders meet only through fillers or through the numeraire books. Each numeraire
leg of `fillFromNumeraire` crosses the spread of that book.

**Later (v2): matching inside non-numeraire pools.** Direct ETH ⇄ AMD coincidences of wants, by picking one
currency as the pool's quote side for price keys and minimums so the existing matching engine can run
on a non-numeraire pool.

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

- **Non-numeraire pools with LP liquidity:** quadratic pool count and fragmented liquidity. (Order-only cross
  pools are approach E.)
- **Linked orders inside the matching engine** (an ETH → AMD order held as an ask in one book and a bid
  in another): the most delicate change to the most size-constrained, invariant-tested code.

## 5. Comparison

| | E. Non-numeraire pools | A. Interface route | B. Instant via custom accounting | C. Intents + ledger | D. Uniform batches |
|---|---|---|---|---|---|
| Instant X → Y | Yes, one transaction | Two steps | Yes, one transaction | Yes | Per batch |
| Limit X → Y | Yes, limit in the output token | Yes (leg 2 rests) | No | Yes | Yes |
| Baskets | No | No | No | Yes | Yes |
| CoWs | Through the numeraire books (v1); direct in v2 | No | No | Yes | Yes, automatic |
| Reachable by external routers | No | No | Yes | No | No |
| Contract change | Pool-type rules + `fillFromNumeraire` library | None | Hook | Settlement library + Router | C plus solver rules |

E is the lead: cross-pair limit and instant swaps, and CoWs through the numeraire books, with no new
order type or storage and the existing fill path unchanged. The others stack around it. A works today. B makes instant multi-asset swaps native and
opens Async Swap liquidity to the rest of Uniswap v4. C adds limit intents, baskets and CoWs on top of
B's instant fills. D tightens C's acceptance rule into uniform prices.

## 6. Open questions

For E:

- How are minimum order sizes checked on non-numeraire pools: by valuing the input through its numeraire pool,
  or with a per-asset minimum?
- Should `fillFromNumeraire` use LP liquidity on both legs, or only the books?
- Should the initial price passed when creating a non-numeraire pool be ignored (non-numeraire pools hold no LP
  liquidity), or recorded as a reference price for the interface?
- In v2, which currency is a non-numeraire pool's quote side for matching (currency1, or the one with the
  deeper numeraire market)?

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
