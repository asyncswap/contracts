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

| | A. Interface route | B. Instant via custom accounting | C. Intents + ledger | D. Uniform batches |
|---|---|---|---|---|
| Instant X → Y | Two steps | Yes, one transaction | Yes | Per batch |
| Limit X → Y | Yes (leg 2 rests) | No | Yes | Yes |
| Baskets | No | No | Yes | Yes |
| CoWs | No | No | Yes | Yes, automatic |
| Reachable by external routers | No | Yes | No | No |
| Contract change | None | Hook | Settlement library + Router | C plus solver rules |

The approaches stack rather than compete. A works today. B makes instant multi-asset swaps native and
opens Async Swap liquidity to the rest of Uniswap v4. C adds limit intents, baskets and CoWs on top of
B's instant fills. D tightens C's acceptance rule into uniform prices.

## 6. Open questions

1. Is instant mode (B) safe to expose to every router, or only to an allowlist at first?
2. Should B fill from the book only, LP liquidity only, or both (book first, as today's pool-first
   ordering decides)?
3. Escrowed intents only, or also signed-only intents posted for free and pulled through Permit2 at fill?
4. Should settlement be able to rest a residual as an ordinary order (for example the AMD leg of an
   ETH → AMD intent when the AMD book is empty)?
5. How much surplus goes to makers before batches: none (first valid fill), a reference-price floor,
   or a split with the filler?
6. Who may settle intents at first: anyone, or an allowlist while fillers are few?
