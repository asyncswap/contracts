# Unichain mainnet readiness

**Blocked: waiting for audit.** Scope: [`audit/AUDIT_SCOPE_11_03_26.md`](audit/AUDIT_SCOPE_11_03_26.md), frozen at
`2739d6c`. If `src/` or `script/` changes before the audit starts, re-freeze in a new dated scope.

## Confirm before broadcast

Fixed at deployment, with no setter:

- **Owner:** `0xb1F0982E02f9F71E60512fd47471d76610CcB556`
- **USDC:** `0x078D782b760474a361dDA0AF3839290b0EF57AD6`
- **PoolManager:** `0x1F98400000000000000000000000000000000004`
- **Minimum order:** `DEPLOY_MIN_ORDER_USD`, default 0
- **MEV tax gas:** 20,000,000, set in `script/config/chains.json`

## After the audit

- [ ] Fix or acknowledge every finding, with a regression test for each fix.
- [ ] Recheck contract sizes; AsyncMatching has 441 bytes left under the 24,576-byte limit.
- [ ] Stress test at 100 transactions per block.
- [ ] Rehearse the deployment on a Unichain fork, then pin and verify the bytecode.
- [ ] Deploy `TokenClaims` and `NativeClaims` with the core contracts.
- [ ] Ship claim redemption in the indexer and frontend.

`script/check-mainnet-readiness.sh` exits non-zero until all of this is done.
