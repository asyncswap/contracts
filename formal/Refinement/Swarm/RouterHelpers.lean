import Mathlib
import Generated.Router
import Refinement.Monad

/-!
# Router: small internal helpers

Characterizations of the library helpers the Router model inlines:
`CustomRevert.bubbleUpAndRevertWith`, `Address.{_revert, verifyCallResultFromTarget,
functionCallWithValue, functionCall}`, `SafeERC20.{_callOptionalReturn, safeTransferFrom}`,
`ShortStrings.byteLength`, `EIP712._EIP712Name/_EIP712Version`.
-/

open FormalAst Refinement

namespace Router.Swarm.Helpers

variable {σ : Type} (ext : Ext σ)

/-- `bubbleUpAndRevertWith` always reverts, never touching state. -/
theorem bubbleUpAndRevertWith_reverts (c s x : Nat) (env : Env) (w : σ) :
    CustomRevert.bubbleUpAndRevertWith ext c s x env w = .error ⟨"revert"⟩ := rfl

/-- `_revert` always reverts: bubbling the return data, or `FailedInnerCall` when empty. -/
theorem address_revert_run (rd : List Nat) (env : Env) (w : σ) :
    Address.«_revert» ext rd env w
      = .error (if rd.length > 0 then ⟨"revert"⟩ else ⟨"FailedInnerCall"⟩) := by
  unfold Address.«_revert»
  by_cases h : rd.length > 0 <;> simp [h]

theorem verifyCallResult_fail (t : Nat) (rd : List Nat) (env : Env) (w : σ) :
    Address.verifyCallResultFromTarget ext t false rd env w
      = .error (if rd.length > 0 then ⟨"revert"⟩ else ⟨"FailedInnerCall"⟩) := by
  unfold Address.verifyCallResultFromTarget
  by_cases h : rd.length > 0 <;> simp [Address.«_revert», h]

theorem verifyCallResult_ok (t : Nat) (rd : List Nat) (env : Env) (w : σ) :
    Address.verifyCallResultFromTarget ext t true rd env w
      = if rd.length = 0 ∧ ext.codeLength t = 0 then .error ⟨"AddressEmptyCode"⟩ else .ok (rd, w) := by
  unfold Address.verifyCallResultFromTarget
  by_cases h1 : rd.length = 0 <;> by_cases h2 : ext.codeLength t = 0 <;> simp [h1, h2]

theorem functionCallWithValue_insufficient (t : Nat) (d : List Nat) (v : Nat) (env : Env) (w : σ)
    (h : env.balance < v) :
    Address.functionCallWithValue ext t d v env w = .error ⟨"AddressInsufficientBalance"⟩ := by
  simp [Address.functionCallWithValue, h]

theorem functionCallWithValue_eq (t : Nat) (d : List Nat) (v : Nat) (env : Env) (w : σ)
    (h : ¬ env.balance < v) :
    Address.functionCallWithValue ext t d v env w
      = (do let r ← ext.lowCall t v d; Address.verifyCallResultFromTarget ext t r.1 r.2) env w := by
  simp [Address.functionCallWithValue, h]

theorem functionCall_eq (t : Nat) (d : List Nat) (env : Env) (w : σ) :
    Address.functionCall ext t d env w
      = (do let r ← ext.lowCall t 0 d; Address.verifyCallResultFromTarget ext t r.1 r.2) env w := by
  have : Address.functionCall ext t d env w = Address.functionCallWithValue ext t d 0 env w := by
    simp [Address.functionCall]
  rw [this, functionCallWithValue_eq ext t d 0 env w (Nat.not_lt_zero _)]

/-- `_callOptionalReturn` after the call returned `rd`: succeeds iff `rd` is empty or decodes
to `true`; `false` reverts `SafeERC20FailedOperation`. -/
theorem callOptionalReturn_after (tok : Nat) (d rd : List Nat) (env : Env) (w w' : σ)
    (hc : Address.functionCall ext tok d env w = .ok (rd, w')) :
    SafeERC20.«_callOptionalReturn» ext tok d env w
      = (if rd.length != 0 then
          (do let x ← abiWordAt rd 0; let b ← abiBool x
              if !b then throw ⟨"SafeERC20FailedOperation"⟩ else pure () : M σ Unit) env w'
        else .ok ((), w')) := by
  unfold SafeERC20.«_callOptionalReturn»
  simp only [run_bind, hc]
  by_cases h : rd.length != 0
  · simp only [h, ite_true]
    simp only [run_bind]
    cases abiWordAt (σ := σ) rd 0 env w' with
    | error e => rfl
    | ok p =>
      obtain ⟨x, w''⟩ := p
      simp only
      cases abiBool (σ := σ) x env w'' with
      | error e => rfl
      | ok q =>
        obtain ⟨b, w3⟩ := q
        cases b <;> simp
  · simp [h]

theorem callOptionalReturn_call_reverts (tok : Nat) (d : List Nat) (env : Env) (w : σ) (e : Revert)
    (hc : Address.functionCall ext tok d env w = .error e) :
    SafeERC20.«_callOptionalReturn» ext tok d env w = .error e := by
  unfold SafeERC20.«_callOptionalReturn»
  simp [hc]

/-- `safeTransferFrom` is `_callOptionalReturn` on `transferFrom(from, to, value)` calldata. -/
theorem safeTransferFrom_eq (tok f t v : Nat) (env : Env) (w : σ) :
    SafeERC20.safeTransferFrom ext tok f t v env w
      = SafeERC20.«_callOptionalReturn» ext tok
          ((wordBytes (0x23b872dd * 2 ^ 224)).take 4 ++ abiEncode [f, t, v]) env w := by
  simp only [SafeERC20.safeTransferFrom, run_bind]
  cases SafeERC20.«_callOptionalReturn» ext tok
          ((wordBytes (0x23b872dd * 2 ^ 224)).take 4 ++ abiEncode [f, t, v]) env w with
  | error e => rfl
  | ok p => rfl

theorem byteLength_run (s : Nat) (env : Env) (w : σ) :
    ShortStrings.byteLength ext s env w
      = if s &&& 0xFF > 31 then .error ⟨"InvalidShortString"⟩ else .ok (s &&& 0xFF, w) := by
  unfold ShortStrings.byteLength
  by_cases h : s &&& 0xFF > 31 <;> simp [h]

theorem byteLength_le (s : Nat) (env : Env) (w w' : σ) (r : Nat)
    (h : ShortStrings.byteLength ext s env w = .ok (r, w')) : r ≤ 31 ∧ w' = w := by
  rw [byteLength_run] at h
  split at h
  · cases h
  · cases h; exact ⟨by omega, rfl⟩

theorem eip712Name_eq (env : Env) (w : σ) :
    EIP712.«_EIP712Name» ext env w
      = ext.fn_ShortStrings_toStringWithFallback_5694 (ext.«_name»)
          (do return (ext.get (← get)).«_nameFallback»)
          (fun x => modify fun w => ext.set w (let s := ext.get w; { s with «_nameFallback» := x }))
          env w := by
  simp only [EIP712.«_EIP712Name»]

theorem eip712Version_eq (env : Env) (w : σ) :
    EIP712.«_EIP712Version» ext env w
      = ext.fn_ShortStrings_toStringWithFallback_5694 (ext.«_version»)
          (do return (ext.get (← get)).«_versionFallback»)
          (fun x => modify fun w => ext.set w (let s := ext.get w; { s with «_versionFallback» := x }))
          env w := by
  simp only [EIP712.«_EIP712Version»]

end Router.Swarm.Helpers
