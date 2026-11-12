# Flash fills

Status: implemented on the Router and hook for the next audited deployment. v1 deployed hooks are unchanged.
Design background: `docs/multi-asset-swaps.md`, section 4F (on the `intent-spec` branch).

A flash fill lets a filler fill an order with no inventory. The Router hands the filler the order's escrowed
input first, calls the filler back inside its own PoolManager unlock, and only then collects the maker's output.
Inside the callback the filler can route through any Uniswap v4 pool and fill other Async Swap orders, in a loop
it controls.

## Interfaces

- `IAsyncSwapCallback` (implemented by the Router): `fillOrderWithCallback` opens a fill; `fillOrderInCallback` and
  `matchBookInCallback` are the only Router calls accepted while the callback runs, and only from its filler.
- `IAsyncSwapFlashFiller` (implemented by the filler): `asyncSwapFlashFill`, the callback.

A filler integrates against these two interfaces only.

## Flow

1. The filler contract calls `Router.fillOrderWithCallback(order, maxPrice, data)`. `msg.value` is the MEV tax only.
2. The Router opens one `unlock`, checks the live order against `maxPrice` and `order.amountIn` (as `fillOrder`
   does), and calls `AsyncSwap.beginFlashFill`. The hook closes the order (removes it from the book, deletes it,
   settles its priority bid to the vault) and credits its input, less the 0.02% trade fee, to the filler as
   ERC-6909 claims. The fee goes to the vault.
3. The Router records the filler in a transient slot and calls
   `IAsyncSwapFlashFiller(filler).asyncSwapFlashFill(order, amountIn, amountOwed, data)`.
4. In the callback the filler may:
   - fill other orders with `Router.fillOrderInCallback(order, maxPrice)`, paying their output in claims and
     receiving their input in claims;
   - run the matcher with `Router.matchBookInCallback(key, maxMatches)`;
   - `burn` claims and swap on any v4 pool, `take`, `settle`, `mint`.
   Before returning, it must hold `amountOwed` claims of the order's output and approve the Router for them on the
   PoolManager.
5. The Router clears the slot, transfers `amountOwed` output claims from the filler to the hook, and calls
   `AsyncSwap.settleFlashFill`, which burns them and pays the maker its minimum less the trade fee (ERC20 as
   tokens, native ETH as claims, as in a plain fill). Any surplus stays with the filler. The unlock closes only if
   every delta, the filler's included, is zero.

## Payments are claims

Every payment inside a flash fill is an ERC-6909 claim, not a token transfer and not an open delta:

- the order's input is credited to the filler as claims;
- `fillOrderInCallback` pulls the resting maker's output from the filler as claims (`transferFrom`, so the filler
  approves the Router per currency) and credits the order's input to the filler as claims;
- the final maker check pulls the owed output as claims.

So a filler that only moves between Async Swap books never opens a PoolManager delta at all: it trades claims it
was just credited. Swaps on other v4 pools are bridged with `burn` (claims to credit) and `mint` (credit to
claims). Native ETH is claim id 0 and needs no `msg.value`.

## Safety rules, and how each is enforced

| Rule | Enforcement |
|---|---|
| The flash-filled order cannot be repriced, cancelled, topped up, matched or filled again during the callback. | `beginFlashFill` closes and deletes the order before the callback. Every later action on it finds no order (`OrderNotFound`), and it is no longer in the book for `matchBook`. |
| Normal Router entry points refuse reentry. | `noFlashFill` on `swap`, `swapWithSig`, `fillOrder`, `cancelOrder`, `cancelWithSig`, `cancelAndWithdraw`, `withdrawClaims`, `topUpPriorityFee`, `matchBook`, `fillFromPoolLiquidity` and `fillOrderWithCallback` (no nesting). These also open their own unlock, which v4 refuses. |
| Only the active filler may use the in-unlock entry points, only while active. | `onlyFlashFiller` compares `msg.sender` with the transient filler slot; the slot is cleared before the output is collected and before the unlock returns. |
| The maker check is on the final amount only. | The owed output is pulled once, after the callback returns. |
| Resting orders filled inside a flash fill are never worse off. | `fillOrderInCallback` applies the same live minimum, `maxPrice`, `order.amountIn` bound and 0.02% fees as `fillOrder`. |
| Only the Router can drive the hook side. | `beginFlashFill`, `settleFlashFill` and `executeOrderWithClaims` revert `NotTrustedRouter` for any other caller, and check the maker's executor grant. `settleFlashFill` only settles the order `beginFlashFill` opened in the same transaction (transient record in the hook). |

## Toward claims-based settlement of the numeraire

Flash fills are written as a settlement primitive, not only a filler feature, and the same shape could change how
the numeraire leg settles generally:

- Today every fill and match moves the numeraire (USDC, USDG on Robinhood) as a separate payment per order. Inside
  a flash fill the numeraire is only ever a claim balance that rises on one book and falls on the next, and it nets
  to zero inside the PoolManager. Nothing leaves it.
- That generalises: a settlement pass that takes a list of fills across books (approach C in the design doc) can
  use the same three hooks (`beginFlashFill`, `executeOrderWithClaims`, `settleFlashFill`) and check only the final
  claim balances, so the numeraire becomes a netting unit between books rather than a transferred asset.
- Makers already receive native payouts as claims. Offering claims for numeraire payouts too (with
  `withdrawClaims` to exit) would let resting liquidity stay inside the PoolManager between trades, which is what
  a cross-book matcher wants to consume.

These are directions, not part of this change.

## Decisions taken on the design's open questions

- Input is credited as ERC-6909 claims the filler burns or trades, not as an open delta: deltas belong to the
  address that creates them, and claims also let book-to-book routes run with no delta at all.
- One order per `fillOrderWithCallback` call. A filler can still fill any number of other orders inside the callback.
- In-unlock fills pay no further MEV tax; the outer `fillOrderWithCallback` pays it once.
- Surplus above the maker's minimum stays with the filler, as in a plain fill.
