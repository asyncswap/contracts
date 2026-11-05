# Crossing-heavy block capacity

A crossing order can execute against resting orders as soon as it enters the
book. This test measures how those transactions pack into a **30,000,000-gas
local block**, rather than counting cheap resting-order posts or treating a
long Foundry test as one real block.

**Matching correctness passed; the 100-crossing-transactions-per-block target
was not met.** Ten workloads submitted 100 independent Router transactions
each. All 1,000 transactions succeeded across their mined blocks and settled
5,200 pairs. No measured workload fit all 100 transactions into one block.

## Results

| Incoming side | Makers filled per transaction | Resting price levels | Transactions in first block | Blocks for 100 transactions | Total receipt gas |
|---|---:|---|---:|---:|---:|
| Buy | 1 | 100 distinct | 46 | 3 | 64,206,366 |
| Buy | 1 | One crowded | 51 | 2 | 56,175,608 |
| Sell | 1 | 100 distinct | 44 | 3 | 66,765,875 |
| Sell | 1 | One crowded | 49 | 3 | 58,730,398 |
| Buy | 8 | 100 distinct | 11 | 10 | 244,143,855 |
| Buy | 8 | 800 distinct | 10 | 10 | 264,822,314 |
| Buy | 8 | One crowded | 12 | 9 | 224,611,121 |
| Sell | 8 | 100 distinct | 11 | 10 | 246,822,687 |
| Sell | 8 | 800 distinct | 10 | 10 | 267,389,398 |
| Sell | 8 | One crowded | 12 | 9 | 227,269,820 |

For example, a transaction that matches eight makers is **one transaction and
eight matched pairs**. Twelve such transactions settle 96 pairs, but still count
as only twelve transactions toward the 100-transaction target.

Single-fill batches consumed 56.18–66.77 million gas for 100 transactions;
eight-fill batches consumed 224.61–267.39 million. The first blocks held 44–51
single-fill transactions or 10–12 eight-fill transactions. These counts apply
to the transaction gas-limit policy below; they are not universal maxima or
transactions-per-second measurements.

## Method

- Export the current v1.3.0 production contract source into isolated Anvil state
  using the shared test deployment scaffold. This is not a live-network fork.
- Use a real 18-decimal mock asset and 6-decimal mock quote, a zero-liquidity pool,
  100 incoming owners and a different owner for every resting order. Fees and
  the funded 100,000-quote-unit priority bid are enabled; gas priority fees are zero.
- Seed 100 resting orders for single-fill workloads or 800 for eight-fill
  workloads. In distinct-price workloads each group of one or eight makers has
  one price; 100 groups traverse ascending asks or descending bids. Crowded
  workloads put every maker at the same exact price. Two additional workloads
  give all 800 resting makers distinct prices, so each transaction removes eight
  price levels. Their incoming limit allows 10% slack while the input exactly
  covers the eight intended fills; exact settlement amounts are checked from events.
- Disable automining, queue all 100 transactions in FIFO order, then mine under
  the enforced 30-million-gas limit until the pending queue drains. The gas
  budget is not raised to make the batch fit.
- Each workload uses a fixed transaction gas limit: 120% of the first transaction's
  gas estimate, rounded up to 1,000. Anvil's block admission also requires enough
  remaining gas to cover that declared limit. Reserved headroom can leave usable
  gas unfilled or create a short final block. Changing gas limits can change the
  packing counts; dividing the block budget by average receipt gas is not an
  observed capacity result.
- Check every successful receipt, block gas total and exact fill count; then
  verify price/FIFO maker IDs, asset and quote amounts, all closed orders, exact
  maker/taker net claims, accumulated protocol fees and funded bids, empty book,
  and zero hook escrow.

Setup and token approvals are excluded. Receipt gas includes intrinsic gas and
applied refunds. Independent transactions reset transaction-scoped storage
warmth; the fixture's aggregate Foundry setup gas is never reported as capacity.
Mock ERC-20 transfer costs, no LP liquidity, the chosen book shapes and Cancun
rules bound these results. Native assets, production token implementations,
mixed LP routing and other chain gas budgets can change the measurements.

## Reproduce and inspect

Requires Python 3, Foundry and the repository's existing Solidity dependencies.
No signing keys, RPC credentials or public broadcasts are needed. The runner
creates only loopback Anvil nodes and terminates them on exit.

```sh
python3 benchmarks/crossing/run.py
```

`results/summary.json` records the compiler, tools, production-source hashes,
transaction gas limits, every block's occupancy and all assertion outcomes.
`results/<workload>.json.gz` retains every full receipt and log. To inspect one:

```sh
python3 - <<'PY_READ'
import gzip, json
with gzip.open('benchmarks/crossing/results/buy_eight_distinct.json.gz', 'rt') as source:
    result = json.load(source)
print(json.dumps(result['blocks'], indent=2))
PY_READ
```

The test is complete, but the 100-crossing-transactions-per-block readiness
target remains unmet at this budget. Meeting it requires different execution
costs or an explicitly revised capacity target. This work does not clear the
audit gate or test reorg recovery and multi-hour production resilience.
