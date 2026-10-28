import Specs.AsyncSwap
import Proofs.Monad
open FormalAst

/-!
# `AsyncFiller.minPriorityFee` (src/AsyncSwap.sol)

`minPriorityFee(notional)` computes `tiered = Math.mulDiv(notional, PRIORITY_FEE_BPS = 10, 10000)`
and returns `tiered < MIN_PRIORITY_FEE ? tiered : MIN_PRIORITY_FEE`, i.e.
`min(⌊notional·10/10000⌋, 100000)`. It reads and writes no storage. Its only revert is
`MathOverflowedMulDiv` from `mulDiv`, which needs `notional·10 ≥ 10000·2²⁵⁶` and so never
happens for a `uint256` argument.
-/

namespace AsyncSwap.Swarm.MinPriorityFee

variable {σ : Type}

/-- **Exact outcome.** `minPriorityFee` reverts `MathOverflowedMulDiv` exactly when
`10000 ≤ ⌊notional·10 / 2²⁵⁶⌋`; otherwise it returns `min(⌊notional·10/10000⌋, 100000)` and
leaves the state unchanged. -/
theorem minPriorityFee_eq (ext : Ext σ) (notional : Nat) (r : Env) (s : σ) :
    AsyncFiller.minPriorityFee ext notional r s
      = if 10000 ≤ notional * 10 / 2 ^ 256 then .error ⟨"MathOverflowedMulDiv"⟩
        else .ok (min (notional * 10 / 10000) 100000, s) := by
  unfold AsyncFiller.minPriorityFee mulDivFloor
  simp only [AsyncFiller.PRIORITY_FEE_BPS, AsyncFiller.MIN_PRIORITY_FEE]
  by_cases hfit : notional * 10 < 2 ^ 256
  · have h0 : notional * 10 / 2 ^ 256 = 0 := Nat.div_eq_of_lt hfit
    by_cases hlt : notional * 10 / 10000 < 100000 <;>
      simp [hfit, h0, hlt, Nat.min_def, Nat.le_of_lt] <;> omega
  · by_cases hov : 10000 ≤ notional * 10 / 2 ^ 256
    · simp [hfit, hov]
    · by_cases hlt : notional * 10 / 10000 < 100000 <;>
        simp [hfit, hov, hlt, Nat.min_def] <;> omega

/-- **Never reverts on a word.** For any `uint256` notional, `minPriorityFee` succeeds with
`min(⌊notional·10/10000⌋, 100000)` and does not change the state. -/
theorem minPriorityFee_ok (ext : Ext σ) (notional : Nat) (hn : notional < 2 ^ 256)
    (r : Env) (s : σ) :
    AsyncFiller.minPriorityFee ext notional r s
      = .ok (min (notional * 10 / 10000) 100000, s) := by
  rw [minPriorityFee_eq]
  have : notional * 10 / 2 ^ 256 < 10000 := by
    rw [Nat.div_lt_iff_lt_mul (Nat.two_pow_pos 256)]
    omega
  rw [if_neg (Nat.not_le.mpr this)]

/-- **Bounds and frame.** Whenever `minPriorityFee` succeeds, the state is unchanged and the
returned fee is at most `MIN_PRIORITY_FEE = 100000` and at most `⌊notional/1000⌋`. -/
theorem minPriorityFee_bounds (ext : Ext σ) (notional : Nat) (r : Env) (s s' : σ) (v : Nat)
    (h : AsyncFiller.minPriorityFee ext notional r s = .ok (v, s')) :
    s' = s ∧ v ≤ AsyncFiller.MIN_PRIORITY_FEE ∧ v ≤ notional / 1000 := by
  rw [minPriorityFee_eq] at h
  split at h
  · cases h
  · simp only [Except.ok.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl⟩ := h
    refine ⟨rfl, ?_, ?_⟩
    · exact Nat.min_le_right _ _
    · have : notional * 10 / 10000 = notional / 1000 := by omega
      rw [← this]; exact Nat.min_le_left _ _

end AsyncSwap.Swarm.MinPriorityFee
