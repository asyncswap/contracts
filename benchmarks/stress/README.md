# Matching, liquidity, withdrawal and sustained-load stress

This local campaign exercises the v1.3.0 contract source. Production contracts
and deployment scripts are unchanged. Machine-readable results are in `results/`.

## Contract workloads

All four stress tests passed, followed by all 66 tests in the matching,
pool-liquidity and claim-withdrawal regression suites.

| Workload | Coverage | Assertions |
|---|---|---|
| Deep crossing book | 256 resting asks, one aggregate bid, 31 explicit continuations | Exactly eight asks close automatically; FIFO is respected; bounded continuation clears every order; no escrow remains |
| Pool liquidity | 256 orders initially rest without liquidity, then fill on retry; 512 subsequent alternating-direction fills | Orders close, each payout meets its minimum, and asset/quote/bid escrow drains |
| Sustained matching | 32 wallets, 128 simulated block rounds, 4,096 orders and 2,048 matches | Every order closes, each maker receives the expected net claims, claims redeem exactly, and accumulated trade fees plus bids match the independent totals |
| Native withdrawals | 256 create/cancel cycles, 512 partial withdrawals, 512 attempted double spends | Exact ETH payouts, zero residual claims, consumed allowances, and rejected repeat withdrawals |

The sustained matching test also makes 4,096 successful ERC-20 claim
withdrawals. Native claims are tested separately because their payout executes
recipient code. Existing regression cases cover rejected ETH, reentrancy,
insufficient approvals, rollback of a failed withdrawal batch, insufficient
liquidity, partial matches, and failed pool-fill attempts.

```sh
STRESS_ROUNDS=128 forge test --match-path test/StressCompletion.t.sol --match-test test_stress \
  --gas-limit 1000000000000 --json
forge test --match-contract '^(PoolLiquidityFillTest|RouterClaimsTest|AsyncSwapTest)$' --json
```

The default campaign uses 32 rounds to fit the normal test runner. The recorded
extended campaign uses `STRESS_ROUNDS=128`; its results are in
`results/contracts-long.json`. Both pass.

The high test gas ceiling allows long sequences in one Foundry test. It is
**not a chain block gas limit**. Calls within a test share transaction context,
so their aggregate gas and execution duration are not independent-transaction
costs or network throughput. Fixtures use the existing controlled mock-token
setup; this campaign does not establish cross-chain decimal equivalence.

## Sustained API reads

`api_load.py` exercises the local API on port 42079 over the previously indexed
100-transaction fork dataset from interface PR #175. It runs 1 client for
30 seconds, 8 for 60 seconds, and 32 for 120 seconds, capped at ten requests
per second per client. Every response must be successful, nonempty, and contain
the requested order ID and chain. It reports achieved request rate, failures,
and p50/p95/p99 latency in `results/api-load.json`.

Start the disposable PostgreSQL database and interface API using the setup in
`asyncswap/interface/benchmarks/v1.3.0/README.md`, then run:

```sh
python3 benchmarks/stress/api_load.py \
  --receipts /path/to/interface/benchmarks/v1.3.0/mixed-receipts.json \
  --output benchmarks/stress/results/api-load.json
```

The URL is intentionally fixed to localhost. This measures bounded reads over
a small indexed dataset, not maximum capacity or concurrent chain ingestion.

The run completed **42,350 valid responses with zero failures**:

| Clients | Duration | Achieved requests/s | p95 | p99 |
|---|---:|---:|---:|---:|
| 1 | 30.0 s | 9.73 | 9.29 ms | 11.44 ms |
| 8 | 60.1 s | 77.76 | 8.47 ms | 12.07 ms |
| 32 | 120.1 s | 311.25 | 7.05 ms | 9.98 ms |

## Scope

These results complement the independent 100-transaction receipt and
indexer/REST/WebSocket checks in interface PR #175. They do not turn the
stateful Foundry calls into new indexer receipts. The subsequent
[public-testnet ingestion/read soak](../soak/README.md) passed its bounded
ten-minute workload: 98 transactions, all 96 lifecycle events reconciled in
REST/WebSocket, and 10,016 successful reads with no failures. Its earlier
interrupted attempts are preserved separately.
The [crossing-capacity matrix](../crossing/README.md) subsequently settled all
1,000 transactions and 5,200 pairs correctly, but 100 crossing transactions
did not fit any of its 30-million-gas blocks. That capacity target remains unmet.
Reorg/failure recovery remains a separate measurement.
The audit and mainnet readiness gates remain open.
