import Generated.AsyncSwap
import Refinement.Monad
open FormalAst Refinement

/-!
# `Math.min` (src/AsyncSwap.sol, OpenZeppelin `Math.min`)

`min(a, b) = a < b ? a : b`. No guards, empty footprint.

* `min_run`: for every environment and state it succeeds, returns `min a b` and leaves the state
  unchanged.
* `min_spec`: the result is at most both arguments and equals one of them.
-/

namespace AsyncSwap.Swarm.Min

/-- `Math.min` never reverts, writes nothing, and returns `min a b`. -/
theorem min_run {σ : Type} (ext : Ext σ) (a b : Nat) (r : Env) (s : σ) :
    Math.min ext a b r s = .ok (min a b, s) := by
  simp only [Math.min, run_pure]
  congr 2
  by_cases h : a < b
  · simp [h, Nat.min_eq_left (Nat.le_of_lt h)]
  · simp [h, Nat.min_eq_right (Nat.le_of_not_lt h)]

/-- The value returned by `Math.min` is a lower bound of both arguments and is one of them. -/
theorem min_spec {σ : Type} (ext : Ext σ) (a b : Nat) (r : Env) (s : σ) :
    ∃ m, Math.min ext a b r s = .ok (m, s) ∧ m ≤ a ∧ m ≤ b ∧ (m = a ∨ m = b) := by
  refine ⟨min a b, min_run ext a b r s, Nat.min_le_left a b, Nat.min_le_right a b, ?_⟩
  rcases Nat.le_total a b with h | h
  · exact Or.inl (Nat.min_eq_left h)
  · exact Or.inr (Nat.min_eq_right h)

end AsyncSwap.Swarm.Min
