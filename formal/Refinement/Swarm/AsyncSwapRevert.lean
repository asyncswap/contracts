import Generated.AsyncSwap
import Refinement.Monad

/-!
# AsyncSwap: `Address._revert`

`_revert` always reverts: with non-empty return data it bubbles it up (assembly `revert`),
otherwise it reverts with `FailedInnerCall`. It never succeeds, so it writes no storage and
returns nothing.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.Revert

variable {σ : Type} (ext : Ext σ)

/-- Exact result: an error, whose reason depends only on whether the return data is empty. -/
theorem revert_run (rd : List Nat) (env : Env) (w : σ) :
    Address.«_revert» ext rd env w
      = .error (if rd.length > 0 then ⟨"revert"⟩ else ⟨"FailedInnerCall"⟩) := by
  unfold Address.«_revert»
  by_cases h : rd.length > 0 <;> simp [h]

/-- Non-empty return data is bubbled up (assembly `revert`). -/
theorem revert_nonempty (rd : List Nat) (env : Env) (w : σ) (h : rd.length > 0) :
    Address.«_revert» ext rd env w = .error ⟨"revert"⟩ := by
  rw [revert_run]; simp [h]

/-- Empty return data reverts with `FailedInnerCall`. -/
theorem revert_empty (env : Env) (w : σ) :
    Address.«_revert» ext [] env w = .error ⟨"FailedInnerCall"⟩ := by
  rw [revert_run]; simp

/-- It never succeeds: no state is ever written and no value returned. -/
theorem revert_never_ok (rd : List Nat) (env : Env) (w w' : σ) (u : Unit) :
    Address.«_revert» ext rd env w ≠ .ok (u, w') := by
  rw [revert_run]; simp

end AsyncSwap.Swarm.Revert
