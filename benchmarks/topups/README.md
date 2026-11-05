# Priority fee top-up measurements

Measured on 2026-11-05 using successful, independent Router transactions on local Anvil. Each
transaction adds 100,000 USDC base units ($0.10) to an existing sell order. No LP liquidity is present.

| Book before the top-up | Initial bid | Receipt gas |
| --- | ---: | ---: |
| One resting order | $0.10 | 186,883 |
| One resting order | $0 | 215,567 |
| 32 orders at the same exact price | $0.10 | 235,267 |
| 256 distinct price levels | $0.10 | 186,710 |

The zero-bid case creates the first USDC escrow balance. The crowded-price case repairs a larger
inner priority tree. The distinct-price case updates one inner queue without traversing or changing
the outer bitmap. Small gas differences also arise from calldata. These fixtures measure transaction
cost, not a maximum bound or production throughput.

Receipts include intrinsic gas and applied refunds. Order placement, wallet funding and token approvals
are excluded. Settings: solc 0.8.26, optimizer 10,000 runs, Cancun, chain ID 31337, 30M block gas limit,
and zero transaction gas price. See [raw receipts and source hashes](results.json).

Run with Python 3.12+, Foundry/Anvil and installed repository dependencies:

```sh
python3 benchmarks/topups/run.py
```

The runner compiles the export fixture into `.local/topup-benchmark`, loads each fixture into a fresh
Anvil instance, impersonates its funded maker, submits the actual Router transaction, and verifies
success plus the emitted added and resulting bids. It updates `results.json`. Fixture setup and
approvals run before export. The export explicitly includes otherwise-unused library/token code and
pool settlement fields so an initially zero-bid book has the same state as a deployed pool.

The implementation and independent-model tests live in `test/PriorityFeeTopUp.t.sol` and
`test/MatchingReference.t.sol`. The invariant handlers also mix fee top-ups with matching, repricing,
cancellation, claim redemption and LP fills. These measurements do not replace correctness checks.
