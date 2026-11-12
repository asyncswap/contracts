# Non-numeraire pools

Status: implemented for the next audited deployment, on top of flash fills (`docs/flash-fills.md`). v1 deployed
hooks are unchanged. Design background: `docs/multi-asset-swaps.md`, section 4E (on the `intent-spec` branch).

A maker can place an order on a pool that does not include the numeraire, for example ETH/TOKEN. Fillers fill it
like any order, and flash fills let them route it through the numeraire books with no inventory.

## Rules

| Rule | Detail |
|---|---|
| Who may open one | Anyone, once both tokens already have a numeraire pool on this hook with the same tick spacing (dynamic fee, this hook). Otherwise `_beforeInitialize` reverts `NumeraireRequired`. The check reads only the hook's own storage: no price, no oracle. |
| Fee | Dynamic fee, as for every pool. |
| Quote side | `currency1`. Orders paying `currency1` are bids and orders paying `currency0` are asks, so opposite orders on the pool cross and match like any book. |
| Minimum order | Each side's decimal floor: `10^(decimals - assetPrecision)` of that token, at least 1 unit. With precision 4, at least 0.0001 of each token. `minOrder` holds the `currency1` floor and `minAssetAmount` the `currency0` floor. There is no dollar minimum on these pools. |
| Priority bids | Not allowed: a bid is paid in the numeraire. A nonzero `priorityFee` reverts `PriorityFeeNeedsNumeraire`, and so does `topUpPriorityFee`. |

Numeraire pools keep their rules unchanged: the dollar minimum on the numeraire side, the asset floor on the other,
and priority bids.

## Notes

- The floors stop dust, not small orders: 0.0001 of a cheap token can be worth very little. A dollar minimum would
  need a price read, which the hook avoids; it can be added later if spam appears.
- Requiring numeraire pools for both tokens means every non-numeraire order has a numeraire route for fillers,
  which is the route a flash fill takes (sell into one book, buy from the other, the numeraire nets to zero).
- Stablecoins other than the numeraire are ordinary tokens under these rules.
