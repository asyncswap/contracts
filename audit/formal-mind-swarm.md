# Formal Mind swarm findings

Findings from Formal Mind's local swarm (planner, prover, reviewer) while proving this repository's contracts against the Lean model formal-ast generates from solc's AST. Each one has a Foundry PoC under `test/`; their status is kept in [README.md](README.md).

### [FM-01] Best-price routing compares only the pool spot tick, then swaps the whole order through the pool, bypassing better book liquidity

**Severity:** medium
**Location:** `src/AsyncSwap.sol:396`
**PoC:** `test/formal/RoutingPoolImpact.t.sol`
**Found:** 2026-10-28

#### Scenario

`matchNewOrder` sends an incoming order to the pool first whenever `_poolBeatsBook` finds the pool's current tick strictly better than the best opposite book level. The pool step (`fillOrderFromPoolLiquidity` → `AsyncMatching._swapAgainstPool`) then swaps the order's entire remaining input with the price limit set to `MIN_SQRT_PRICE+1` / `MAX_SQRT_PRICE-1`. Its only check is the maker's own `amountOutMin`. Nothing stops the swap at the best book price, so a pool that is better only at the margin absorbs the full size along its curve, and the book step afterwards finds no input left. Steps: (1) the pool has thin liquidity at spot 1.0; (2) Alice rests an ask of 10 asset at 1.002; (3) Bob buys with 10 USDC and amountOutMin 4. The pool's tick 0 beats the ask's tick ~19, so the pool goes first and fills all 10 USDC, and Bob receives under 5.1 asset. The ask, which would have given ~9.98, is never touched. Anyone can also steer this: a searcher who sees Bob's order nudges the pool spot one tick below the best ask, lets Bob's order eat the pool down to his limit, and back-runs the move.

#### Evidence

forge test --match-path test/formal/RoutingPoolImpact.t.sol: PASS. Bob receives < 5.1e18 asset for 10e18 USDC while the 10e18 ask at 1.002 remains resting. Code: AsyncSwap.sol:396-403 (poolFirst routing); AsyncMatching._swapAgainstPool sets the extreme price limit and requires inputDelta == -amountIn.

#### PoC run

`forge test --match-path test/formal/RoutingPoolImpact.t.sol`

```
exit 0
No files changed, compilation skipped

Ran 1 test for test/formal/RoutingPoolImpact.t.sol:RoutingPoolImpactTest
[PASS] test_poolSpotOneTickBetterTakesWholeOrderAtFarWorsePrice() (gas: 2118686)
Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 8.38ms (5.35ms CPU time)

Ran 1 test suite in 12.16ms (8.38ms CPU time): 1 tests passed, 0 failed, 0 skipped (1 total tests)
```
