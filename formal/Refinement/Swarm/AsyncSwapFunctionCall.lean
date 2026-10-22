import Generated.AsyncSwap
import Refinement.Monad

/-!
# AsyncSwap: `Address.functionCall`

`functionCall(target, data)` is `functionCallWithValue(target, data, 0)`: the balance guard
can never fire (`balance < 0` is false), so the function is the zero-value low-level call
followed by `verifyCallResultFromTarget`. It writes no storage itself; the only state change
is whatever the low-level call does.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.FunctionCall

variable {σ : Type} (ext : Ext σ)

/-- It is exactly `functionCallWithValue` with value `0`. -/
theorem functionCall_eq_withValue (t : Nat) (d : List Nat) (env : Env) (w : σ) :
    Address.functionCall ext t d env w = Address.functionCallWithValue ext t d 0 env w := by
  simp [Address.functionCall]

/-- A reverting low-level call (value `0`) propagates its error. -/
theorem functionCall_call_reverts (t : Nat) (d : List Nat) (env : Env) (w : σ)
    (e : Revert) (hc : ext.lowCall t 0 d env w = .error e) :
    Address.functionCall ext t d env w = .error e := by
  simp [Address.functionCall, Address.functionCallWithValue, hc]

/-- Main characterization: when the zero-value low-level call ends in world `w'` with
`(ok, rd)`, the function
* reverts (bubbling `rd`, or `FailedInnerCall` when `rd` is empty) if the call failed,
* reverts `AddressEmptyCode` if it succeeded with empty data on a target without code,
* otherwise returns `rd` unchanged in world `w'` (no further writes). -/
theorem functionCall_run (t : Nat) (d : List Nat) (env : Env) (w w' : σ)
    (ok : Bool) (rd : List Nat) (hc : ext.lowCall t 0 d env w = .ok ((ok, rd), w')) :
    Address.functionCall ext t d env w
      = if ok then
          (if rd.length = 0 ∧ ext.codeLength t = 0 then .error ⟨"AddressEmptyCode"⟩ else .ok (rd, w'))
        else .error (if rd.length > 0 then ⟨"revert"⟩ else ⟨"FailedInnerCall"⟩) := by
  rw [functionCall_eq_withValue]
  cases ok
  · by_cases h1 : rd.length > 0 <;>
      simp [Address.functionCallWithValue, hc, Address.verifyCallResultFromTarget,
        Address.«_revert», h1]
  · by_cases h1 : rd.length = 0 <;> by_cases h2 : ext.codeLength t = 0 <;>
      simp [Address.functionCallWithValue, hc, Address.verifyCallResultFromTarget, h1, h2] <;>
      simpa using h1

/-- Footprint: on success the function returns exactly the call's return data, the final world
is the one left by the zero-value low-level call (the function writes nothing itself), the
call succeeded, and it did not return empty data from a code-less target. -/
theorem functionCall_ok (t : Nat) (d : List Nat) (env : Env) (w w' : σ) (r : List Nat)
    (hr : Address.functionCall ext t d env w = .ok (r, w')) :
    ext.lowCall t 0 d env w = .ok ((true, r), w') ∧
      ¬ (r.length = 0 ∧ ext.codeLength t = 0) := by
  rcases hc : ext.lowCall t 0 d env w with e | ⟨⟨ok, rd⟩, w''⟩
  · rw [functionCall_call_reverts ext t d env w e hc] at hr; cases hr
  · rw [functionCall_run ext t d env w w'' ok rd hc] at hr
    cases ok
    · simp at hr
    · by_cases h3 : rd.length = 0 ∧ ext.codeLength t = 0
      · simp [h3] at hr
      · simp only [h3, ite_true, ite_false, Except.ok.injEq, Prod.mk.injEq] at hr
        obtain ⟨rfl, rfl⟩ := hr
        exact ⟨rfl, h3⟩

end AsyncSwap.Swarm.FunctionCall
