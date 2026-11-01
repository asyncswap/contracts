# Audit

- [AUDIT_SCOPE_10_23_26.md](AUDIT_SCOPE_10_23_26.md): scope for the next audit of this repository, frozen at
  `830cd9e`.
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
| L-01 | Low | A small partial match voids a maker's relayed cancel or reprice | Open | [Report](lsp_security_review_2026-11-01.md#l-01-a-small-partial-match-voids-a-makers-relayed-cancel-or-reprice); `test/security/poc/SignedCancelGrief.t.sol` |
| L-02 | Low | Pool squatting before a token is deployed disables its asset floor | ✅ Fixed | [Report](lsp_security_review_2026-11-01.md#l-02-pool-squatting-disables-the-asset-floor); an asset with no code reverts `AssetHasNoCode`; `test/security/poc/PoolSquatAssetFloor.t.sol` |
| I-01 | Informational | Fee rounding on dust remainders (only with minimums off) | Acknowledged | [Report](lsp_security_review_2026-11-01.md#i-01-fee-rounding-on-dust-remainders); `test/security/poc/DustTradeFee.t.sol` |
