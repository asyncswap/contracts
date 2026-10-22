import Generated.AsyncSwap
import Refinement.Monad

/-!
# AsyncSwap: `Address.functionCallWithValue`

Full characterization: the balance guard, then the low-level call whose outcome is
verified by `verifyCallResultFromTarget`. The function itself writes no storage; the only
state change is whatever the low-level call does.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.FunctionCallWithValue

variable {σ : Type} (ext : Ext σ)

/-- Guard: reverts `AddressInsufficientBalance` when the contract's balance is below `value`,
before any call is made. -/
theorem functionCallWithValue_reverts_insufficient (t : Nat) (d : List Nat) (v : Nat) (env : Env) (w : σ)
    (h : env.balance < v) :
    Address.functionCallWithValue ext t d v env w = .error ⟨"AddressInsufficientBalance"⟩ := by
  simp [Address.functionCallWithValue, h]

/-- A reverting low-level call propagates its error. -/
theorem functionCallWithValue_call_reverts (t : Nat) (d : List Nat) (v : Nat) (env : Env) (w : σ)
    (e : Revert) (h : ¬ env.balance < v) (hc : ext.lowCall t v d env w = .error e) :
    Address.functionCallWithValue ext t d v env w = .error e := by
  simp [Address.functionCallWithValue, h, hc]

/-- Main characterization: with sufficient balance and the low-level call ending in world `w'`
with `(ok, rd)`, the function
* reverts (bubbling `rd`, or `FailedInnerCall` when `rd` is empty) if the call failed,
* reverts `AddressEmptyCode` if it succeeded with empty data on a target without code,
* otherwise returns `rd` unchanged in world `w'` (no further writes). -/
theorem functionCallWithValue_run (t : Nat) (d : List Nat) (v : Nat) (env : Env) (w w' : σ)
    (ok : Bool) (rd : List Nat) (h : ¬ env.balance < v)
    (hc : ext.lowCall t v d env w = .ok ((ok, rd), w')) :
    Address.functionCallWithValue ext t d v env w
      = if ok then
          (if rd.length = 0 ∧ ext.codeLength t = 0 then .error ⟨"AddressEmptyCode"⟩ else .ok (rd, w'))
        else .error (if rd.length > 0 then ⟨"revert"⟩ else ⟨"FailedInnerCall"⟩) := by
  cases ok
  · by_cases h1 : rd.length > 0 <;>
      simp [Address.functionCallWithValue, h, hc, Address.verifyCallResultFromTarget,
        Address.«_revert», h1]
  · by_cases h1 : rd.length = 0 <;> by_cases h2 : ext.codeLength t = 0 <;>
      simp [Address.functionCallWithValue, h, hc, Address.verifyCallResultFromTarget, h1, h2] <;>
      simpa using h1

/-- Footprint: on success the function returns exactly the call's return data and the final
world is the one left by the low-level call (the function writes nothing itself); the call
succeeded and the balance guard held. -/
theorem functionCallWithValue_ok (t : Nat) (d : List Nat) (v : Nat) (env : Env) (w w' : σ)
    (r : List Nat)
    (hr : Address.functionCallWithValue ext t d v env w = .ok (r, w')) :
    ¬ env.balance < v ∧ ext.lowCall t v d env w = .ok ((true, r), w') ∧
      ¬ (r.length = 0 ∧ ext.codeLength t = 0) := by
  by_cases h : env.balance < v
  · rw [functionCallWithValue_reverts_insufficient ext t d v env w h] at hr; cases hr
  refine ⟨h, ?_⟩
  rcases hc : ext.lowCall t v d env w with e | ⟨⟨ok, rd⟩, w''⟩
  · rw [functionCallWithValue_call_reverts ext t d v env w e h hc] at hr; cases hr
  · rw [functionCallWithValue_run ext t d v env w w'' ok rd h hc] at hr
    cases ok
    · simp at hr
    · by_cases h3 : rd.length = 0 ∧ ext.codeLength t = 0
      · simp [h3] at hr
      · simp only [h3, ite_true, ite_false, Except.ok.injEq, Prod.mk.injEq] at hr
        obtain ⟨rfl, rfl⟩ := hr
        exact ⟨rfl, h3⟩

end AsyncSwap.Swarm.FunctionCallWithValue
