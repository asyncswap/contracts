import Generated.Router
import Refinement.Monad

/-!
# Router: library helpers (OpenZeppelin `Address`, `SafeERC20`, `ShortStrings`, `EIP712`; v4 `CustomRevert`)

Exact run characterizations of the generated helpers:
* `Address._revert` always reverts (bubbling `returndata`, or `FailedInnerCall` when it is empty).
* `Address.verifyCallResultFromTarget` returns `returndata` exactly when the call succeeded and
  not (empty return data from a target without code); otherwise it reverts.
* `Address.functionCallWithValue` reverts `AddressInsufficientBalance` when `balance < value`,
  else is the low-level call followed by the verification; `functionCall` is the `value = 0` case.
* `SafeERC20._callOptionalReturn` succeeds exactly when the call is accepted and the return data is
  empty or its first word ABI-decodes to `true`; `safeTransferFrom` is that check on the calldata
  `transferFrom(from, to, value)`. None of them writes storage beyond what the call itself does.
* `CustomRevert.bubbleUpAndRevertWith` always reverts.
* `ShortStrings.byteLength` is `sstr & 0xff`, reverting `InvalidShortString` above 31.
* `EIP712._EIP712Name/_EIP712Version` are `toStringWithFallback(_name/_version, fallback slot)`.
-/

open FormalAst Refinement

namespace Router.Swarm.LibHelpers

variable {σ : Type} (ext : Router.Ext σ)

theorem revert_run (rd : List Nat) (env : Env) (w : σ) :
    Router.Address.«_revert» ext rd env w =
      .error (if rd.length > 0 then ⟨"revert"⟩ else ⟨"FailedInnerCall"⟩) := by
  unfold Router.Address.«_revert»
  by_cases h : rd.length > 0 <;> simp [h]

theorem revert_never_ok (rd : List Nat) (env : Env) (w w' : σ) (u : Unit) :
    Router.Address.«_revert» ext rd env w ≠ .ok (u, w') := by
  rw [revert_run]; simp

theorem verify_run (target : Nat) (success : Bool) (rd : List Nat) (env : Env) (w : σ) :
    Router.Address.verifyCallResultFromTarget ext target success rd env w =
      if success = false then .error (if rd.length > 0 then ⟨"revert"⟩ else ⟨"FailedInnerCall"⟩)
      else if rd.length = 0 ∧ ext.codeLength target = 0 then .error ⟨"AddressEmptyCode"⟩
      else .ok (rd, w) := by
  unfold Router.Address.verifyCallResultFromTarget
  cases success
  · simp [revert_run]
  · by_cases h1 : rd.length = 0 <;> by_cases h2 : ext.codeLength target = 0 <;> simp [h1, h2]

theorem verify_ok_iff (target : Nat) (success : Bool) (rd : List Nat) (env : Env) (w : σ) r w' :
    Router.Address.verifyCallResultFromTarget ext target success rd env w = .ok (r, w') ↔
      success = true ∧ ¬ (rd.length = 0 ∧ ext.codeLength target = 0) ∧ r = rd ∧ w' = w := by
  rw [verify_run]
  cases success <;> simp
  split <;> simp_all [eq_comm]

theorem functionCallWithValue_run (target : Nat) (data : List Nat) (value : Nat) (env : Env) (w : σ) :
    Router.Address.functionCallWithValue ext target data value env w =
      if env.balance < value then .error ⟨"AddressInsufficientBalance"⟩
      else match ext.lowCall target value data env w with
        | .error e => .error e
        | .ok ((s, rd), w1) => Router.Address.verifyCallResultFromTarget ext target s rd env w1 := by
  unfold Router.Address.functionCallWithValue
  by_cases h : env.balance < value
  · simp [h]
  · simp only [h, run_bind, run_read, run_ite, decide_eq_true_eq, ite_false]
    rcases ext.lowCall target value data env w with e | ⟨⟨s, rd⟩, w1⟩
    · rfl
    · simp only

theorem functionCall_run (target : Nat) (data : List Nat) (env : Env) (w : σ) :
    Router.Address.functionCall ext target data env w =
      match ext.lowCall target 0 data env w with
        | .error e => .error e
        | .ok ((s, rd), w1) => Router.Address.verifyCallResultFromTarget ext target s rd env w1 := by
  unfold Router.Address.functionCall
  simp only [run_bind, run_pure, functionCallWithValue_run, Nat.not_lt_zero, ite_false]

/-- The return-data check of `_callOptionalReturn`, given the call's return data. -/
def optionalReturnCheck (rd : List Nat) (env : Env) (w : σ) : Except Revert (Unit × σ) :=
  if rd.length = 0 then .ok ((), w)
  else match (abiWordAt rd 0 : M σ Nat) env w with
    | .error e => .error e
    | .ok (x, w1) => match (abiBool x : M σ Bool) env w1 with
      | .error e => .error e
      | .ok (b, w2) => if b = true then .ok ((), w2) else .error ⟨"SafeERC20FailedOperation"⟩

theorem callOptionalReturn_run (token : Nat) (data : List Nat) (env : Env) (w : σ) :
    Router.SafeERC20.«_callOptionalReturn» ext token data env w =
      match Router.Address.functionCall ext token data env w with
        | .error e => .error e
        | .ok (rd, w1) => optionalReturnCheck rd env w1 := by
  unfold Router.SafeERC20.«_callOptionalReturn» optionalReturnCheck
  simp only [run_bind]
  rcases Router.Address.functionCall ext token data env w with e | ⟨rd, w1⟩
  · rfl
  · simp only
    by_cases h : rd.length = 0
    · simp [h]
    · simp only [h, ite_false, bne_iff_ne, ne_eq, not_false_eq_true, run_bind, run_ite]
      simp only [ite_true]
      rcases (abiWordAt rd 0 : M σ Nat) env w1 with e | ⟨x, w2⟩
      · rfl
      · simp only
        rcases (abiBool x : M σ Bool) env w2 with e | ⟨b, w3⟩
        · rfl
        · cases b <;> simp

theorem safeTransferFrom_run (token fr to value : Nat) (env : Env) (w : σ) :
    Router.SafeERC20.safeTransferFrom ext token fr to value env w =
      Router.SafeERC20.«_callOptionalReturn» ext token
        ((wordBytes (0x23b872dd * 2 ^ 224)).take 4 ++ abiEncode [fr, to, value]) env w := by
  unfold Router.SafeERC20.safeTransferFrom
  simp only [run_bind, run_pure]
  rcases Router.SafeERC20.«_callOptionalReturn» ext token _ env w with e | ⟨u, w1⟩ <;> rfl

/-- `safeTransferFrom` succeeds only if the token call itself succeeded (`success = true`) and the
token returned nothing (with code at `token`) or a word decoding to `true`. -/
theorem safeTransferFrom_ok (token fr to value : Nat) (env : Env) (w w' : σ) u
    (h : Router.SafeERC20.safeTransferFrom ext token fr to value env w = .ok (u, w')) :
    ∃ rd w1, ext.lowCall token 0 ((wordBytes (0x23b872dd * 2 ^ 224)).take 4 ++ abiEncode [fr, to, value]) env w
        = .ok ((true, rd), w1) ∧ ¬ (rd.length = 0 ∧ ext.codeLength token = 0) ∧
      optionalReturnCheck rd env w1 = .ok (u, w') := by
  rw [safeTransferFrom_run, callOptionalReturn_run, functionCall_run] at h
  revert h
  rcases ext.lowCall token 0 _ env w with e | ⟨⟨s, rd⟩, w1⟩
  · simp
  · simp only
    rcases hv : Router.Address.verifyCallResultFromTarget ext token s rd env w1 with e | ⟨r, w2⟩
    · simp
    · rw [verify_ok_iff] at hv
      obtain ⟨hs, hc, rfl, rfl⟩ := hv
      subst hs
      intro h
      exact ⟨r, w2, rfl, hc, h⟩

theorem bubbleUpAndRevertWith_run (a b c : Nat) (env : Env) (w : σ) :
    Router.CustomRevert.bubbleUpAndRevertWith ext a b c env w = .error ⟨"revert"⟩ := by
  simp [Router.CustomRevert.bubbleUpAndRevertWith]

theorem byteLength_run (sstr : Nat) (env : Env) (w : σ) :
    Router.ShortStrings.byteLength ext sstr env w =
      if sstr &&& 0xFF > 31 then .error ⟨"InvalidShortString"⟩ else .ok (sstr &&& 0xFF, w) := by
  unfold Router.ShortStrings.byteLength
  by_cases h : sstr &&& 0xFF > 31 <;> simp [h]

theorem byteLength_ok (sstr : Nat) (env : Env) (w w' : σ) n
    (h : Router.ShortStrings.byteLength ext sstr env w = .ok (n, w')) :
    n = sstr % 256 ∧ n ≤ 31 ∧ w' = w := by
  rw [byteLength_run] at h
  split at h
  · cases h
  · next hn =>
    simp only [Except.ok.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl⟩ := h
    refine ⟨?_, by omega, rfl⟩
    have := Nat.and_two_pow_sub_one_eq_mod sstr 8
    simpa using this

theorem EIP712Name_run (env : Env) (w : σ) :
    Router.EIP712.«_EIP712Name» ext env w =
      ext.fn_ShortStrings_toStringWithFallback_5694 ext.«_name»
        (do return (ext.get (← get)).«_nameFallback»)
        (fun x => modify fun w => ext.set w (let s := ext.get w; { s with «_nameFallback» := x })) env w := by
  unfold Router.EIP712.«_EIP712Name»
  simp only [run_bind, run_pure]

theorem EIP712Version_run (env : Env) (w : σ) :
    Router.EIP712.«_EIP712Version» ext env w =
      ext.fn_ShortStrings_toStringWithFallback_5694 ext.«_version»
        (do return (ext.get (← get)).«_versionFallback»)
        (fun x => modify fun w => ext.set w (let s := ext.get w; { s with «_versionFallback» := x })) env w := by
  unfold Router.EIP712.«_EIP712Version»
  simp only [run_bind, run_pure]

end Router.Swarm.LibHelpers
