# Matching research and scope

The implementation in this PR is an outer-index optimization with validation of the existing matching rules. It does not implement uniform-price batch clearing or parallel settlement.

## Historical CLOB comparison

| Reference | Design inspected | Implication for Async Swap |
| --- | --- | --- |
| [Kautenja/limit-order-book](https://github.com/Kautenja/limit-order-book/tree/7fc059daf10f0d14d3cae79fc6c7505c956307ac) | Unbalanced price BST, cached best prices, intrusive FIFO queues | Sparse price indexing and direct cancellation are useful; an adversarial EVM workload should avoid unbounded tree depth. The radix/bitmap structure retains bounded traversal. |
| [ajtulloch/quantcup-orderbook](https://github.com/ajtulloch/quantcup-orderbook/tree/f860e0b831a7dd2d0c07a5dbc3723ef15d1067ed) | Flat price-indexed vector, preallocated order storage, lazy cancellation | CPU locality is valuable, but scanning empty prices and cancelled entries is a poor default for bounded onchain work. |

The reference test suites passed locally (99 and 14 tests respectively). An unequal-price probe of the QuantCup default C++ checkout executed at the incoming order's price; its existing tests all used one price. That behavior differs from Async Swap's original-maker price rule. The original winning C branch was inspected separately and was not benchmarked. These are algorithm/behavior comparisons, not throughput comparisons with token settlement.

Async Swap additionally handles input-budget orders, exact rational prices within a tick, priority fees, and atomic claim settlement. Its eight-pair limit bounds each matching call, but does not guarantee that a third party will clear every remaining executable pair.

## Papers

| Paper | Useful direction | Work completed here |
| --- | --- | --- |
| [Efficient and Verified Continuous Double Auctions](https://arxiv.org/abs/2412.08624) | Verify an efficient implementation against a simpler matching specification. | Implemented an independent linear-scan reference model adapted to Async Swap. This is not a reproduction of the paper's Coq implementation or proof. |
| [The Exchange Problem](https://arxiv.org/abs/2403.03046) | Efficient maximum-volume uniform-price batch matching. | Researched only. A batch prototype would change pricing and scheduling rules. |
| [SPEEDEX](https://arxiv.org/abs/2111.02719) | Uniform asset valuations and commutative parallel batch processing. | Researched only. Its system results do not establish EVM gas savings. Any future Async Swap experiment should retain USDC as the intended common numeraire. |
| [The Case of FBA as a DEX Processing Model](https://arxiv.org/abs/2302.01177) | Frequent-batch market-design tradeoffs. | Researched only; welfare conclusions depend on the model, and batching alone does not solve inclusion or tie manipulation. |
| [Lissy](https://arxiv.org/abs/2101.06291) | Onchain priority-queue layouts and gas measurement. | Informed the measurement approach. Historical refund assumptions are not imported into the Cancun benchmark. |
| [The World's Fastest Matching Engine Algorithm](https://arxiv.org/abs/2606.01183) | Priority-Indicated Nodes and CPU locality. | Researched only. Performance/title claims are the author's and were not reproduced. |
| [Fair Combinatorial Auctions](https://arxiv.org/abs/2408.12225) | Per-trader benchmarks for solver batches. | Future solver-mechanism research, not an index optimization. |
| [Ordering by Unanimity](https://arxiv.org/abs/2607.06144) | Application preferences in transaction ordering. | Sequencer-level direction; not achievable by changing only the hook's matcher. |

Henry S. Warren's *Hacker's Delight*, second edition, sections 2–1 and 5–4, informed the bit-technique review. The existing Uniswap v4 `BitMath` already provides assembly-backed low-bit isolation and table/multiplication scans. The bitmap reuses it; the main measured saving comes from storage layout and traversal rather than new assembly.

## Deferred amendments

A queue-only experiment updated the inner fee/sequence entry while retaining the outer level and order counts. Compared with full removal/reinsertion, this saved roughly 3–30% of bookkeeping gas, depending on the number of orders at the price. The harness omits funding and authorization and does not estimate a complete top-up transaction. No user-facing top-up endpoint is included.

Repricing continues to reset queue sequence while preserving original maker age. This PR preserves that implemented rule; changing it, adding fee funding, designing keeper incentives, or implementing either batch-auction paper requires separate work.
