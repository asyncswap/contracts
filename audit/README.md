# Audit

- [AUDIT_SCOPE_11_01_26.md](AUDIT_SCOPE_11_01_26.md): scope for the next audit of this repository, frozen at
  `fdfdf65` (code identical to the testnet deployment, `c13cd5a`).
- [AUDIT_SCOPE_10_23_26.md](AUDIT_SCOPE_10_23_26.md): earlier scope, frozen at `830cd9e`; superseded.
- [AUDIT_SCOPE_10_19_26.md](AUDIT_SCOPE_10_19_26.md): earlier scope, frozen at `dc8042d`; superseded.
- [FM-01-routing-pool-impact.md](FM-01-routing-pool-impact.md): Formal Mind swarm finding (Medium, fixed):
  best-price routing sent the whole order through the pool past better book liquidity.
- [lsp_security_review_2026-11-01.md](lsp_security_review_2026-11-01.md): LSP-augmented security review of
  `81ba6b8`, generated with the [`security-review`](https://github.com/asyncswap/skills/tree/2e9aca64980e7c567dc2045376fb3396d9dfc24b/plugins/solidity-language-server/skills/security-review)
  skill from [asyncswap/skills](https://github.com/asyncswap/skills). Every issue has a Foundry POC in
  [`test/security/poc/`](../test/security/poc/).
- [auditagent_report_1_status.md](auditagent_report_1_status.md): what is fixed, acknowledged or open
  from the Nethermind AuditAgent report
  ([auditagent_report_1_ae602e60-d592-45ec-92ef-891968f087f0.md](auditagent_report_1_ae602e60-d592-45ec-92ef-891968f087f0.md)).

The earlier audits (Lee, 33 Labs; the H-05 follow-up; the AI-assisted review) found bugs in
[asyncswap/protocol](https://github.com/asyncswap/protocol), and their reports and per-finding status live there:
<https://github.com/asyncswap/protocol/tree/dev/audits>.

## Formal Mind swarm

| ID | Severity | Finding | Status | Evidence |
|----|----------|---------|--------|----------|
| FM-01 | Medium | Best-price routing compares only the pool spot tick, then swaps the whole order through the pool, bypassing better book liquidity | ✅ Fixed | [Report](FM-01-routing-pool-impact.md); test `test/formal/RoutingPoolImpact.t.sol` |

## LSP security review (2026-11-01)

Generated with the [`security-review`](https://github.com/asyncswap/skills/tree/2e9aca64980e7c567dc2045376fb3396d9dfc24b/plugins/solidity-language-server/skills/security-review)
skill ([`call-analysis`](https://github.com/asyncswap/skills/tree/2e9aca64980e7c567dc2045376fb3396d9dfc24b/plugins/solidity-language-server/skills/call-analysis),
[`entrypoint-analysis`](https://github.com/asyncswap/skills/tree/2e9aca64980e7c567dc2045376fb3396d9dfc24b/plugins/solidity-language-server/skills/entrypoint-analysis),
[`poc-generator`](https://github.com/asyncswap/skills/tree/2e9aca64980e7c567dc2045376fb3396d9dfc24b/plugins/solidity-language-server/skills/poc-generator)).

| ID | Severity | Finding | Status | Evidence |
|----|----------|---------|--------|----------|
| M-01 | Medium | A leftover signed `SetExecutor` grant from `swapWithSig` can undo a maker's revocation | ✅ Fixed | [Report](lsp_security_review_2026-11-01.md#m-01-a-leftover-signed-setexecutor-grant-can-undo-a-makers-revocation); a supplied grant is always applied and spent; `test/security/poc/GrantReplay.t.sol` |
| M-02 | Medium | A front-run ask can force a new order onto the book at a worse price than the pool (needs mempool ordering) | ✅ Fixed | [Report](lsp_security_review_2026-11-01.md#m-02-a-front-run-ask-can-force-a-new-order-onto-the-book-at-a-worse-price-than-the-pool); the pool fills up to the best book level and the book takes the rest, plus a Router MEV tax on priority fees; `test/security/poc/PoolFirstFrontRun.t.sol`, `test/security/PoolFirstPartialFill.t.sol`, `test/security/MevTax.t.sol` |
| L-01 | Low | A small partial match voids a maker's relayed cancel or reprice | ✅ Fixed | [Report](lsp_security_review_2026-11-01.md#l-01-a-small-partial-match-voids-a-makers-relayed-cancel-or-reprice); cancels cover whatever remains and reprices apply their price to the remainder; `test/security/poc/SignedCancelGrief.t.sol` |
| L-02 | Low | Pool squatting before a token is deployed disables its asset floor | ✅ Fixed | [Report](lsp_security_review_2026-11-01.md#l-02-pool-squatting-disables-the-asset-floor); an asset with no code reverts `AssetHasNoCode`; `test/security/poc/PoolSquatAssetFloor.t.sol` |
| I-01 | Informational | Fee rounding on dust remainders (only with minimums off) | Acknowledged | [Report](lsp_security_review_2026-11-01.md#i-01-fee-rounding-on-dust-remainders); `test/security/poc/DustTradeFee.t.sol` |

## Pashov solidity-auditor review (2026-11-01)

[pashov_security_review_2026-11-01.md](pashov_security_review_2026-11-01.md): three passes of the
[Pashov `solidity-auditor`](https://github.com/pashov/skills) skill (v4.1, 12 agents per pass) over `src/` and
`script/` at `7d09cfa`. 11 findings and 29 leads. Regression tests: `test/security/PashovFindings.t.sol`.

| # | Conf | Finding | Status | Notes |
|---|---|---|---|---|
| 1 | 90 | The backrun fee charges the whole output of a fill that crosses the reference tick | ✅ Fixed | Only the share before the reference pays |
| 2 | 90 | A dust order at the end key turns off pool fills for the other side | ✅ Fixed | The pool-first limit stays inside v4's accepted range |
| 3 | 85 | The venue choice ignores the dynamic fee | ✅ Fixed | Inside the window, a fill back toward the reference counts half its gap worse |
| 4 | 85 | A maker that sets itself as executor fills from the pool with no MEV tax | Acknowledged | No user loses funds; the tax covers Router creation and fills only |
| 5 | 85 | A direct `updatePrice` makes an old order cross with no MEV tax | Acknowledged | As 4 |
| 6 | 85 | Reprice plus `matchBook` pays no MEV tax | Acknowledged | As 4 |
| 7 | 75 | Ceil rounding on a partial match makes the remainder's limit worse | Acknowledged | No funds at risk: a partly matched order can lose its place to an equal-priced order, and its bid (at most $0.10) then buys no priority. Pinned by `test_knownIssue_partlyMatchedOrderFallsBehindAnEqualOrder`. Rounding down lets a worse dust remainder jump ahead (`test_worsePriceCannotJumpAheadWithBidOrAge`); a fix stores the signed ratio or ranks by tick level, then bid, then time. Revisit the priority rule before the audit freeze |
| 8 | 75 | A pool-first fill parks the price in an empty range and freezes pool fills | ✅ Fixed | A pool fill that would leave no active liquidity reverts |
| 9 | 75 | Any caller runs the hook's `matchBook` with no unlock and no Router | Acknowledged | As 4; matching moves only claims and respects every limit |
| 10 | 75 | A copied executor grant submitted first reverts the relayer's `swapWithSig` | ✅ Fixed | A grant whose nonce is spent is skipped |
| 11 | 75 | The pool-first limit stops one tick past the best resting price | ✅ Fixed | One tick higher for a swap that lowers the tick |
