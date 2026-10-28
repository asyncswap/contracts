import Specs.AsyncSwap
import Proofs.Monad
import Proofs.Functions.AsyncSwapKey
open FormalAst Refinement
open AsyncSwap (Ext)

/-!
# S-03: `TickPrice.key` never reverts for a nonzero denominator

For every `isBuy`, `zeroForOne` and words `amountIn`, `amountOut` whose denominator (`amountIn` when
`zeroForOne`, else `amountOut`) is nonzero:

* `TickMath.getTickAtSqrtPrice` returns, for every sqrt price in `[MIN_SQRT_PRICE, MAX_SQRT_PRICE)`,
  a tick in `[MIN_TICK, MAX_TICK]` without reverting or writing;
* `TickPrice.floorTick` on the order's price returns a tick `t ∈ [MIN_TICK, MAX_TICK]`, state unchanged;
* `TickPrice.key` returns a key `k` with `1 ≤ k ≤ MAX_TICK - MIN_TICK + 1`, state unchanged (so the
  int24 subtractions `tick - MIN_TICK` / `MAX_TICK - tick` never panic).
-/

theorem S03.TickPrice_key {σ : Type} (ext : Ext σ) (isBuy zeroForOne : Bool)
    (amountIn amountOut : Nat) (_hIn : amountIn < 2 ^ 256) (_hOut : amountOut < 2 ^ 256)
    (hden : (if zeroForOne then amountIn else amountOut) ≠ 0) (env : Env) (s : σ) :
    (∀ p : Nat, AsyncSwap.TickMath.MIN_SQRT_PRICE ≤ p → p < AsyncSwap.TickMath.MAX_SQRT_PRICE →
      ∃ t, AsyncSwap.TickMath.getTickAtSqrtPrice ext p env s = .ok (t, s) ∧
        AsyncSwap.TickMath.MIN_TICK ≤ t ∧ t ≤ AsyncSwap.TickMath.MAX_TICK) ∧
    ∃ t k,
      AsyncSwap.TickPrice.floorTick ext (if zeroForOne then amountOut else amountIn)
          (if zeroForOne then amountIn else amountOut) env s = .ok (t, s) ∧
        AsyncSwap.TickMath.MIN_TICK ≤ t ∧ t ≤ AsyncSwap.TickMath.MAX_TICK ∧
        AsyncSwap.TickPrice.key ext isBuy zeroForOne amountIn amountOut env s = .ok (k, s) ∧
        1 ≤ k ∧ (k : Int) ≤ AsyncSwap.TickMath.MAX_TICK - AsyncSwap.TickMath.MIN_TICK + 1 := by
  refine ⟨fun p h1 h2 => AsyncSwap.Swarm.TickBounds.getTickAtSqrtPrice_bounded ext p env s h1 h2, ?_⟩
  obtain ⟨t, hf, hlo, hhi, hk, k1, k2⟩ :=
    AsyncSwap.Swarm.TickBounds.key_ok ext isBuy zeroForOne amountIn amountOut env s hden
  exact ⟨t, _, hf, hlo, hhi, hk, k1, k2⟩
