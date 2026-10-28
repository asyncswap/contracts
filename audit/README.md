# Audit

- [AUDIT_SCOPE_10_23_26.md](AUDIT_SCOPE_10_23_26.md): scope for the next audit of this repository, frozen at
  `830cd9e`.
- [AUDIT_SCOPE_10_19_26.md](AUDIT_SCOPE_10_19_26.md): earlier scope, frozen at `dc8042d`; superseded.
- [FM-01-routing-pool-impact.md](FM-01-routing-pool-impact.md): Formal Mind swarm finding (Medium, fixed):
  best-price routing sent the whole order through the pool past better book liquidity.
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
