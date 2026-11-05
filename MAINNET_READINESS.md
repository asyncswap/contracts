# Unichain mainnet readiness

**Blocked: waiting for audit.** Scope: [`audit/AUDIT_SCOPE_11_05_26.md`](audit/AUDIT_SCOPE_11_05_26.md), frozen at
`c9372ff9577ba3950fa321090a7bfb559fc964a4`. If `src/` or `script/` changes before the audit starts, re-freeze in a new dated scope.

## Confirm before broadcast

Fixed at deployment, with no setter:

- **Owner:** `0xb1F0982E02f9F71E60512fd47471d76610CcB556`
- **USDC:** `0x078D782b760474a361dDA0AF3839290b0EF57AD6`
- **PoolManager:** `0x1F98400000000000000000000000000000000004`
- **Minimum order:** `DEPLOY_MIN_ORDER_USD`, default 0
- **MEV tax gas:** 20,000,000, set in `script/config/chains.json`

## After the audit

- [ ] Fix or acknowledge every finding, with a regression test for each fix.
- [ ] Recheck contract sizes; AsyncMatching has 351 bytes and AsyncSwap has 417 bytes left under the 24,576-byte limit.
- [ ] Stress test at 100 transactions per block.
  Local one-sided block packing passed in interface PR #175. Additional
  [matching, liquidity, withdrawals and sustained-read tests](benchmarks/stress/README.md)
  pass locally; these stateful tests do not close the broader block-packing gate.
  [Public-testnet ingestion/read soak attempts](benchmarks/soak/README.md)
  reconciled every confirmed event but were interrupted; the full soak remains open.
- [ ] Rehearse the deployment on a Unichain fork, then pin and verify the bytecode.
- [ ] Deploy `TokenClaims` and `NativeClaims` with the core contracts.
- [ ] Ship claim redemption in the indexer and frontend.

`script/check-mainnet-readiness.sh` exits non-zero until all of this is done.

The outer tick bitmap changes the order-book storage layout. Deploy a new hook with linked
`TickBitmap` and `EligiblePrice` libraries; do not reinterpret an existing radix book as bitmap state.
See [optimization validation](benchmarks/orderbook/README.md) for measurements and compiler settings.

Fee top-ups add the linked `PriorityFeeUpdates` library and a maker-authorized Router endpoint.
Both are included in the refreshed scope. Deploy a new hook and Router after audit clearance. See [fee top-ups](docs/priority-fee-top-ups.md).
