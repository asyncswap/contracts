import Generated.AsyncSwap
import Refinement.Monad

/-!
# AsyncSwap: `Address.verifyCallResultFromTarget`

Full characterization: reverts, success condition, return value, and frame (no writes).
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.VerifyCallResultFromTarget

variable {σ : Type} (ext : Ext σ)

/-- Exact run: a failed call bubbles the return data (`revert`) or reverts `FailedInnerCall`
when there is none; a successful call with empty return data from a code-less target reverts
`AddressEmptyCode`; otherwise it returns `returndata` unchanged with the world untouched. -/
theorem verify_run (t : Nat) (success : Bool) (rd : List Nat) (env : Env) (w : σ) :
    Address.verifyCallResultFromTarget ext t success rd env w
      = if success = false then
          .error (if rd.length > 0 then ⟨"revert"⟩ else ⟨"FailedInnerCall"⟩)
        else if rd.length = 0 ∧ ext.codeLength t = 0 then .error ⟨"AddressEmptyCode"⟩
        else .ok (rd, w) := by
  unfold Address.verifyCallResultFromTarget
  cases success
  · by_cases h : rd.length > 0 <;> simp [Address.«_revert», h]
  · by_cases h1 : rd.length = 0 <;> by_cases h2 : ext.codeLength t = 0 <;> simp [h1, h2]

/-- Success iff the call succeeded and it did not return empty data from a code-less target;
on success the result is `returndata` and the world is unchanged. -/
theorem verify_ok_iff (t : Nat) (success : Bool) (rd r : List Nat) (env : Env) (w w' : σ) :
    Address.verifyCallResultFromTarget ext t success rd env w = .ok (r, w')
      ↔ success = true ∧ ¬ (rd.length = 0 ∧ ext.codeLength t = 0) ∧ r = rd ∧ w' = w := by
  rw [verify_run]
  cases success
  · by_cases h : rd.length > 0 <;> simp [h]
  · by_cases h : rd.length = 0 ∧ ext.codeLength t = 0
    · simp [h]
    · simp only [h, ite_false, Bool.true_eq_false, Except.ok.injEq, Prod.mk.injEq, true_and,
        not_false_eq_true]
      constructor
      · rintro ⟨rfl, rfl⟩; exact ⟨rfl, rfl⟩
      · rintro ⟨rfl, rfl⟩; exact ⟨rfl, rfl⟩

/-- It never modifies storage: any successful run leaves the world as it found it. -/
theorem verify_frame (t : Nat) (success : Bool) (rd r : List Nat) (env : Env) (w w' : σ)
    (h : Address.verifyCallResultFromTarget ext t success rd env w = .ok (r, w')) : w' = w :=
  ((verify_ok_iff ext t success rd r env w w').mp h).2.2.2

end AsyncSwap.Swarm.VerifyCallResultFromTarget
