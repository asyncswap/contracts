import Generated.AsyncSwap
import Refinement.Monad

/-!
# AsyncSwap: `SafeERC20._callOptionalReturn`

`_callOptionalReturn(token, data)` performs `Address.functionCall(token, data)` (a zero-value
low-level call checked by `verifyCallResultFromTarget`) and then inspects the return data:
* empty return data: success;
* non-empty but shorter than one word: `abi.decode` revert;
* first word `1` (`true`): success; `0` (`false`): `SafeERC20FailedOperation`;
  anything above `1`: `abi.decode` revert (not a valid `bool`).
It writes no storage itself: the final world is the one the low-level call leaves.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.CallOptionalReturn

variable {σ : Type} (ext : Ext σ)

/-- A reverting inner call (`functionCall`) propagates its error unchanged. -/
theorem callOptionalReturn_call_reverts (tok : Nat) (d : List Nat) (env : Env) (w : σ) (e : Revert)
    (hc : Address.functionCall ext tok d env w = .error e) :
    SafeERC20.«_callOptionalReturn» ext tok d env w = .error e := by
  unfold SafeERC20.«_callOptionalReturn»
  simp [hc]

/-- Main characterization: once the call returns data `rd` in world `w'`, the outcome is decided
by `rd` alone, and no further state is written. -/
theorem callOptionalReturn_after (tok : Nat) (d rd : List Nat) (env : Env) (w w' : σ)
    (hc : Address.functionCall ext tok d env w = .ok (rd, w')) :
    SafeERC20.«_callOptionalReturn» ext tok d env w
      = if rd.length = 0 then .ok ((), w')
        else if rd.length < 32 then .error ⟨"abi.decode"⟩
        else if bytesWord (rd.take 32) = 1 then .ok ((), w')
        else if bytesWord (rd.take 32) = 0 then .error ⟨"SafeERC20FailedOperation"⟩
        else .error ⟨"abi.decode"⟩ := by
  unfold SafeERC20.«_callOptionalReturn»
  simp only [run_bind, hc]
  by_cases h0 : rd.length = 0
  · simp [h0]
  · have h0' : (rd.length != 0) = true := by simpa using h0
    simp only [h0', ite_true, h0, ite_false, run_bind]
    by_cases h32 : rd.length < 32
    · have : ¬ (0 + 32 ≤ rd.length) := by omega
      simp [abiWordAt, this, h32]
    · have : 0 + 32 ≤ rd.length := by omega
      simp only [abiWordAt, this, ite_true, h32, ite_false, List.drop_zero, run_pure]
      by_cases h1 : bytesWord (rd.take 32) = 1
      · simp [abiBool, h1]
      · by_cases h2 : bytesWord (rd.take 32) = 0
        · simp [abiBool, h2]
        · have h3 : ¬ bytesWord (rd.take 32) ≤ 1 := by omega
          simp [abiBool, h1, h2, h3]

/-- Footprint and success condition: on success the zero-value low-level call to `token` with
`data` succeeded, returning `rd` and leaving the final world `w'` (nothing else is written), the
call did not return empty data from a code-less target, and `rd` is either empty or at least one
word whose first word is `1` (`true`). -/
theorem callOptionalReturn_ok (tok : Nat) (d : List Nat) (env : Env) (w w' : σ) (u : Unit)
    (h : SafeERC20.«_callOptionalReturn» ext tok d env w = .ok (u, w')) :
    ∃ rd, ext.lowCall tok 0 d env w = .ok ((true, rd), w') ∧
      ¬ (rd.length = 0 ∧ ext.codeLength tok = 0) ∧
      (rd.length = 0 ∨ (32 ≤ rd.length ∧ bytesWord (rd.take 32) = 1)) := by
  rcases hc : Address.functionCall ext tok d env w with e | ⟨rd, w1⟩
  · rw [callOptionalReturn_call_reverts ext tok d env w e hc] at h; cases h
  · rw [callOptionalReturn_after ext tok d rd env w w1 hc] at h
    have hw : w1 = w' ∧ (rd.length = 0 ∨ (32 ≤ rd.length ∧ bytesWord (rd.take 32) = 1)) := by
      by_cases h0 : rd.length = 0
      · simp only [h0, ite_true, Except.ok.injEq, Prod.mk.injEq] at h
        exact ⟨h.2, Or.inl h0⟩
      · by_cases h32 : rd.length < 32
        · simp [h0, h32] at h
        · by_cases h1 : bytesWord (rd.take 32) = 1
          · simp only [h0, h32, h1, ite_true, ite_false, Except.ok.injEq, Prod.mk.injEq] at h
            exact ⟨h.2, Or.inr ⟨by omega, h1⟩⟩
          · by_cases h2 : bytesWord (rd.take 32) = 0 <;> simp [h0, h32, h1, h2] at h
    obtain ⟨rfl, hrd⟩ := hw
    -- unfold the inner call: zero-value low-level call then `verifyCallResultFromTarget`
    have hfc : Address.functionCall ext tok d env w
        = Address.functionCallWithValue ext tok d 0 env w := by simp [Address.functionCall]
    rw [hfc] at hc
    rcases hl : ext.lowCall tok 0 d env w with e | ⟨⟨ok, rd'⟩, w2⟩
    · simp [Address.functionCallWithValue, hl] at hc
    · cases ok
      · by_cases hp : rd'.length > 0 <;>
          simp [Address.functionCallWithValue, hl, Address.verifyCallResultFromTarget,
            Address.«_revert», hp] at hc
      · by_cases hz : rd'.length = 0 ∧ ext.codeLength tok = 0
        · have hz1 : rd' = [] := List.eq_nil_of_length_eq_zero hz.1
          have hz2 : ext.codeLength tok = 0 := hz.2
          simp [Address.functionCallWithValue, hl, Address.verifyCallResultFromTarget, hz1, hz2] at hc
        · have hv : Address.verifyCallResultFromTarget ext tok true rd' env w2 = .ok (rd', w2) := by
            unfold Address.verifyCallResultFromTarget
            by_cases h1 : rd'.length = 0
            · have h2 : ¬ ext.codeLength tok = 0 := fun h2 => hz ⟨h1, h2⟩
              simp [h1, h2]
            · simp [h1]
          have : Address.functionCallWithValue ext tok d 0 env w = .ok (rd', w2) := by
            simp [Address.functionCallWithValue, hl, hv]
          rw [this] at hc
          simp only [Except.ok.injEq, Prod.mk.injEq] at hc
          obtain ⟨rfl, rfl⟩ := hc
          exact ⟨rd', rfl, hz, hrd⟩

/-- The `false` answer: a call that returns at least a word whose first word is `0` makes
`_callOptionalReturn` revert `SafeERC20FailedOperation`. -/
theorem callOptionalReturn_false_reverts (tok : Nat) (d rd : List Nat) (env : Env) (w w' : σ)
    (hc : Address.functionCall ext tok d env w = .ok (rd, w'))
    (hl : 32 ≤ rd.length) (hf : bytesWord (rd.take 32) = 0) :
    SafeERC20.«_callOptionalReturn» ext tok d env w = .error ⟨"SafeERC20FailedOperation"⟩ := by
  rw [callOptionalReturn_after ext tok d rd env w w' hc]
  have h0 : ¬ rd.length = 0 := by omega
  have h32 : ¬ rd.length < 32 := by omega
  simp [h0, h32, hf]

end AsyncSwap.Swarm.CallOptionalReturn
