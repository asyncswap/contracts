# Flash fills

Status: implemented on the Router and hook for the next audited deployment. v1 deployed hooks are unchanged.
Design background: `docs/multi-asset-swaps.md`, section 4F (on the `intent-spec` branch).

A flash fill lets a filler fill an order with no inventory. The Router hands the filler the order's escrowed
input first, calls the filler back inside its own PoolManager unlock, and only then collects the maker's output.
Inside the callback the filler can route through any Uniswap v4 pool and fill other Async Swap orders, in a loop
it controls.

## Layout

Measured with solc (what CI and deployment use), the hook and Router were already within a few hundred bytes of
EIP-170 before this feature, so neither carries the flash-fill logic:

- **Router:** the callback surface lives in `RouterFlashFills`, a module the Router creates in its constructor. The
  Router's `fallback` runs it by DELEGATECALL, so it executes as the Router (the hook sees the Router as caller), and
  the Router's `unlockCallback` forwards a flash-fill unlock to it the same way. Its code counts toward the Router's
  initcode, not its runtime.
- **Hook:** one Router-only entry point, `AsyncSwap.flashFill(bytes args)`, with `args` =
  `abi.encode(uint8 op, AsyncOrder order, address filler)`; ops 0 (begin), 1 (settle) and 2 (fill paid in claims)
  run in the linked `MultiAsset` library. The flash path charges no pool fee (`calculatePoolFee` is zero).

## Interfaces

- `IAsyncSwapCallback` (implemented by the Router): `fillOrderWithCallback` opens a fill; `fillOrderInCallback` and
  `matchBookInCallback` are the only Router calls accepted while the callback runs, and only from its filler.
- `IAsyncSwapFlashFiller` (implemented by the filler): `asyncSwapFlashFill`, the callback.

A filler integrates against these two interfaces only.

## Flow

1. The filler contract calls `Router.fillOrderWithCallback(order, maxPrice, data)`. `msg.value` is an optional prepayment toward the MEV tax (see below).
2. The Router opens one `unlock`, checks the live order against `maxPrice` and `order.amountIn` (as `fillOrder`
   does), and calls `AsyncSwap.flashFill` (op 0). The hook closes the order (removes it from the book, deletes it,
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
   `AsyncSwap.flashFill` (op 1), which burns them and pays the maker its minimum less the trade fee (ERC20 as
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
| The flash-filled order cannot be repriced, cancelled, topped up, matched or filled again during the callback. | Begin (op 0) closes and deletes the order before the callback. Every later action on it finds no order (`OrderNotFound`), and it is no longer in the book for `matchBook`. |
| Normal Router entry points refuse reentry. | Each opens its own `PoolManager.unlock`, which v4 refuses while the flash fill holds it (`AlreadyUnlocked`). A nested `fillOrderWithCallback` reverts `FlashFillActive`. |
| Only the active filler may use the in-unlock entry points, only while active. | `onlyFlashFiller` compares `msg.sender` with the transient filler slot; the slot is cleared before the output is collected and before the unlock returns. |
| The maker check is on the final amount only. | The owed output is pulled once, after the callback returns. |
| Resting orders filled inside a flash fill are never worse off. | `fillOrderInCallback` applies the same live minimum, `maxPrice`, `order.amountIn` bound and 0.02% fees as `fillOrder`. |
| Only the Router can drive the hook side. | `AsyncSwap.flashFill` reverts `NotTrustedRouter` for any other caller and checks the maker's executor grant. Settle (op 1) only settles the order begin (op 0) opened in the same transaction (transient record in the hook). `RouterFlashFills` called directly reaches the hook as itself, not the Router, and is refused. |

## Toward claims-based settlement of the numeraire

Flash fills are written as a settlement primitive, not only a filler feature, and the same shape could change how
the numeraire leg settles generally:

- Today every fill and match moves the numeraire (USDC, USDG on Robinhood) as a separate payment per order. Inside
  a flash fill the numeraire is only ever a claim balance that rises on one book and falls on the next, and it nets
  to zero inside the PoolManager. Nothing leaves it.
- That generalises: a settlement pass that takes a list of fills across books (approach C in the design doc) can
  use the same hook ops (begin, fill paid in claims, settle) and check only the final
  claim balances, so the numeraire becomes a netting unit between books rather than a transferred asset.
- Makers already receive native payouts as claims. Offering claims for numeraire payouts too (with
  `withdrawClaims` to exit) would let resting liquidity stay inside the PoolManager between trades, which is what
  a cross-book matcher wants to consume.

These are directions, not part of this change.

## Decisions taken on the design's open questions

- Input is credited as ERC-6909 claims the filler burns or trades, not as an open delta: deltas belong to the
  address that creates them, and claims also let book-to-book routes run with no delta at all.
- One order per `fillOrderWithCallback` call. A filler can still fill any number of other orders inside the callback.
- Every fill pays the MEV tax: the outer fill and each `fillOrderInCallback`. The Router pays the FeeVault when the
  fill runs and owes that ETH to the PoolManager until the unlock ends. The filler covers it with `msg.value`, or inside
  its callback with `PoolManager.settleFor(router)` (for example from ETH its route earned). A surplus comes back to
  the filler in ETH. A shortfall reverts `MevTaxUnpaid(owed)`. With no priority fee the tax is zero.
- `matchBookInCallback` pays no tax: `matchBook` is open to anyone outside a flash fill too.
- Surplus above the maker's minimum stays with the filler, as in a plain fill.
