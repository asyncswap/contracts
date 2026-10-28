import Generated.AsyncSwap
import Refinement.Monad
import Refinement.Swarm.AsyncSwapTickPrice
import Refinement.Swarm.AsyncSwapFloorTick
import Refinement.Swarm.AsyncSwapTickBounds
open FormalAst Refinement

/-!
# `TickPrice.key` is total for a nonzero denominator (src/AsyncSwap.sol)

The range lemmas for `getTickAtSqrtPrice` (`logR_bounds`, `ticks_bounds`,
`getTickAtSqrtPrice_bounded`) live in `Refinement.Swarm.AsyncSwapTickBounds`.

* `floorTick_bounded`: for `den ≠ 0`, `floorTick` succeeds, no writes, tick in `[MIN_TICK, MAX_TICK]`.
* `key_ok`, `key_no_revert`: for a nonzero denominator `TickPrice.key` succeeds, no writes, with key
  in `[1, MAX_TICK - MIN_TICK + 1]`. On that tick range `subcI 24 t MIN_TICK` and
  `subcI 24 MAX_TICK t` lie in `[0, 1774544]` (fit `int24`) and `addc 128 _ 1` does not overflow
  (`bucket_run`).
* `key_spec`, `key_reverts_iff`: `key` reverts exactly when the denominator is zero, and then with
  panic `0x12`.
-/

namespace AsyncSwap.Swarm.TickBounds

/-- **`floorTick` for a nonzero denominator.** It never reverts, never writes, and returns a tick in
`[MIN_TICK, MAX_TICK]`. -/
theorem floorTick_bounded {σ : Type} (ext : Ext σ) (num den : Nat) (env : Env) (s : σ)
    (hd : den ≠ 0) :
    ∃ t, TickPrice.floorTick ext num den env s = .ok (t, s) ∧
      TickMath.MIN_TICK ≤ t ∧ t ≤ TickMath.MAX_TICK := by
  have tailB : ∀ sp, ∃ t, AsyncSwap.Swarm.FloorTick.tail ext sp env s = .ok (t, s) ∧
      TickMath.MIN_TICK ≤ t ∧ t ≤ TickMath.MAX_TICK := by
    intro sp
    unfold AsyncSwap.Swarm.FloorTick.tail
    by_cases h1 : sp < TickMath.MIN_SQRT_PRICE
    · rw [ite_eq_left h1]; exact ⟨_, rfl, by decide, by decide⟩
    rw [ite_eq_right h1]
    by_cases h2 : sp ≥ TickMath.MAX_SQRT_PRICE
    · rw [ite_eq_left h2]; exact ⟨_, rfl, by decide, by decide⟩
    rw [ite_eq_right h2]
    have hm : sp % 2 ^ 160 = sp := by
      apply Nat.mod_eq_of_lt
      unfold TickMath.MAX_SQRT_PRICE at h2; omega
    rw [hm]
    exact getTickAtSqrtPrice_bounded ext sp env s (by omega) (by omega)
  rw [AsyncSwap.Swarm.FloorTick.floorTick_run, ite_eq_right hd]
  split
  · exact tailB _
  split
  · exact ⟨_, rfl, by decide, by decide⟩
  · exact tailB _

/-- **`TickPrice.key` for a nonzero denominator.** With `den = amountIn` (zeroForOne) or `amountOut`
nonzero, the floor tick `t` lies in `[MIN_TICK, MAX_TICK]`, `key` returns `keyPure isBuy zeroForOne t`
with the state unchanged, and that key lies in `[1, MAX_TICK - MIN_TICK + 1]`. -/
theorem key_ok {σ : Type} (ext : Ext σ) (isBuy zeroForOne : Bool) (amountIn amountOut : Nat)
    (env : Env) (s : σ) (hden : (if zeroForOne then amountIn else amountOut) ≠ 0) :
    ∃ t, TickPrice.floorTick ext (if zeroForOne then amountOut else amountIn)
        (if zeroForOne then amountIn else amountOut) env s = .ok (t, s) ∧
      TickMath.MIN_TICK ≤ t ∧ t ≤ TickMath.MAX_TICK ∧
      TickPrice.key ext isBuy zeroForOne amountIn amountOut env s =
        .ok (AsyncSwap.Swarm.TickPrice.keyPure isBuy zeroForOne t, s) ∧
      1 ≤ AsyncSwap.Swarm.TickPrice.keyPure isBuy zeroForOne t ∧
      (AsyncSwap.Swarm.TickPrice.keyPure isBuy zeroForOne t : Int) ≤
        TickMath.MAX_TICK - TickMath.MIN_TICK + 1 := by
  obtain ⟨t, hf, hlo, hhi⟩ := floorTick_bounded ext _ _ env s hden
  have hk := AsyncSwap.Swarm.TickPrice.key_run ext isBuy zeroForOne amountIn amountOut env s s t
    hf hlo hhi
  obtain ⟨k1, k2⟩ := AsyncSwap.Swarm.TickPrice.keyPure_range isBuy zeroForOne t hlo hhi
  refine ⟨t, hf, hlo, hhi, hk, k1, ?_⟩
  simp only [TickMath.MIN_TICK, TickMath.MAX_TICK]
  omega

/-- **`TickPrice.key` never reverts and never writes for a nonzero denominator.** -/
theorem key_no_revert {σ : Type} (ext : Ext σ) (isBuy zeroForOne : Bool) (amountIn amountOut : Nat)
    (env : Env) (s : σ) (hden : (if zeroForOne then amountIn else amountOut) ≠ 0) :
    ∃ k, TickPrice.key ext isBuy zeroForOne amountIn amountOut env s = .ok (k, s) ∧
      1 ≤ k ∧ (k : Int) ≤ TickMath.MAX_TICK - TickMath.MIN_TICK + 1 := by
  obtain ⟨t, _, _, _, hk, k1, k2⟩ := key_ok ext isBuy zeroForOne amountIn amountOut env s hden
  exact ⟨_, hk, k1, k2⟩

/-- **Full specification of `TickPrice.key`.** Either the denominator is zero and `key` reverts with
panic `0x12`, or it is nonzero and `key` succeeds with the state unchanged and a key in
`[1, 1774545]`. -/
theorem key_spec {σ : Type} (ext : Ext σ) (isBuy zeroForOne : Bool) (amountIn amountOut : Nat)
    (env : Env) (s : σ) :
    ((if zeroForOne then amountIn else amountOut) = 0 ∧
        TickPrice.key ext isBuy zeroForOne amountIn amountOut env s = .error (panic "0x12")) ∨
    ((if zeroForOne then amountIn else amountOut) ≠ 0 ∧
        ∃ k, TickPrice.key ext isBuy zeroForOne amountIn amountOut env s = .ok (k, s) ∧
          1 ≤ k ∧ k ≤ 1774545) := by
  by_cases hd : (if zeroForOne then amountIn else amountOut) = 0
  · exact Or.inl ⟨hd, AsyncSwap.Swarm.TickPrice.key_zero_den ext isBuy zeroForOne amountIn
      amountOut env s hd⟩
  · obtain ⟨k, hk, k1, k2⟩ := key_no_revert ext isBuy zeroForOne amountIn amountOut env s hd
    refine Or.inr ⟨hd, k, hk, k1, ?_⟩
    simp only [TickMath.MIN_TICK, TickMath.MAX_TICK] at k2
    omega

/-- **`TickPrice.key` reverts iff the denominator is zero.** -/
theorem key_reverts_iff {σ : Type} (ext : Ext σ) (isBuy zeroForOne : Bool) (amountIn amountOut : Nat)
    (env : Env) (s : σ) :
    (∃ e, TickPrice.key ext isBuy zeroForOne amountIn amountOut env s = .error e) ↔
      (if zeroForOne then amountIn else amountOut) = 0 := by
  rcases key_spec ext isBuy zeroForOne amountIn amountOut env s with ⟨hd, he⟩ | ⟨hd, k, hk, _⟩
  · exact ⟨fun _ => hd, fun _ => ⟨_, he⟩⟩
  · constructor
    · rintro ⟨e, he⟩; rw [hk] at he; cases he
    · intro h; exact absurd h hd

end AsyncSwap.Swarm.TickBounds
