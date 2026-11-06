# Incoming-order memory path review

The focused source review found no confirmed unresolved defect in the examined path. This was an internal source review with independent read-only review assistance, followed by regression and differential testing. It is not an external audit or a proof of all possible executions.

## Scope and conclusions

- **Funding and authorization:** the hook keeps the pending ID and authorized executor handoff. The staged pool, ID and owner must agree; the input and priority bid are funded before matching. Failed funding rolls the entire operation back. Persistent getters intentionally omit the staged candidate during funding.
- **Lifetime and callbacks:** the eleven transient words bridge the funding callback. Loading clears the staged ID and fields; subsequent swaps cannot reuse a live candidate. Matching remains blocked for the pending pool during funding. Opposite-order mutation is handled by fresh selection, and newly active LP liquidity switches the candidate to the stored route.
- **Selection and accounting:** each iteration selects from the candidate plus the stored book. Exact price precedes remaining fee and queue sequence. The original maker sequence sets settlement price; partial fills retain proportional ceiling-rounded minima. Bid shares, trade fees, dust refunds and claim batching reuse the established settlement helpers. Stored backlog can continue after the candidate closes within the shared eight-pair budget.
- **Bytecode extraction:** linked-library delegatecalls preserve the hook's storage and address context. The LP self-call retains its authorization and isolated revert boundary. The unified maker/taker arithmetic preserves the original early affordability cap and rounding in both directions.
- **Deployment:** the new deterministic library must be linked into newly deployed hook bytecode. Deployment and verification scripts include it, the size gate requires it, and a local test verifies deterministic deployment and idempotent rerun.

## Review-driven regression coverage

`IncomingMemoryTransitions.t.sol` exercises real LP activation inside a token funding callback, opposite-order repricing and cancellation during funding, currency0 as the quote asset, and multiple swaps within one transaction. Assertions check the surviving book, maker age, fee-vault balances, claims and escrow. `IncomingMemoryFunding.t.sol` checks visibility, blocked premature matching and rollback after funding failure. `IncomingMemoryReference.t.sol` checks the independent matching model, fee-priority yielding and global backlog behavior.

All 1,061 local regression tests passed; the added deployment test passed separately. The extended memory suite passed all 14 tests at 2,048 fuzz runs, including randomized sequences of 64 operations. Three pinned Unichain fork tests passed. Arithmetic parity against the optional Huff kernel passed 2,048 full-width cases and 1,250 boundary comparisons. Exact commands, source hashes and results are under `results/`.

## Remaining release gates

The existing audit-scope and Lean artifacts do not prove the new transient state machine. Add that coverage before release, benchmark broader LP/resting workloads, and repeat the public testnet soak after a new deployment. Four noncrossing controls show 2.86–3.21% more gas than baseline. Crossing improvements remain workload-specific, and no tested workload reaches 100 crossing transactions per 30-million-gas block.
