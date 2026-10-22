import Generated.AsyncSwap
import Refinement.Monad

/-!
# AsyncSwap: library helpers (OpenZeppelin `Address`, `SafeERC20`, `ShortStrings`, `EIP712`; v4 `CustomRevert`)
and `AsyncFiller._priorityKey`

Same characterizations as `RouterLibHelpers` for the AsyncSwap copies, plus:
* `AsyncFiller._priorityKey(fee, seq)` reverts (panic 0x11) iff `seq > 2^64 − 1`, and for
  `fee < 2^64` returns `fee * 2^64 + (2^64 − 1 − seq)`, the key `AsyncSwapSpec/Priority.lean`
  (`priorityKey`) orders as "higher bid first, then earlier sequence".
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.LibHelpers

variable {σ : Type} (ext : AsyncSwap.Ext σ)

theorem revert_run (rd : List Nat) (env : Env) (w : σ) :
    AsyncSwap.Address.«_revert» ext rd env w =
      .error (if rd.length > 0 then ⟨"revert"⟩ else ⟨"FailedInnerCall"⟩) := by
  unfold AsyncSwap.Address.«_revert»
  by_cases h : rd.length > 0 <;> simp [h]

theorem revert_never_ok (rd : List Nat) (env : Env) (w w' : σ) (u : Unit) :
    AsyncSwap.Address.«_revert» ext rd env w ≠ .ok (u, w') := by
  rw [revert_run]; simp

theorem verify_run (target : Nat) (success : Bool) (rd : List Nat) (env : Env) (w : σ) :
    AsyncSwap.Address.verifyCallResultFromTarget ext target success rd env w =
      if success = false then .error (if rd.length > 0 then ⟨"revert"⟩ else ⟨"FailedInnerCall"⟩)
      else if rd.length = 0 ∧ ext.codeLength target = 0 then .error ⟨"AddressEmptyCode"⟩
      else .ok (rd, w) := by
  unfold AsyncSwap.Address.verifyCallResultFromTarget
  cases success
  · simp [revert_run]
  · by_cases h1 : rd.length = 0 <;> by_cases h2 : ext.codeLength target = 0 <;> simp [h1, h2]

theorem verify_ok_iff (target : Nat) (success : Bool) (rd : List Nat) (env : Env) (w : σ) r w' :
    AsyncSwap.Address.verifyCallResultFromTarget ext target success rd env w = .ok (r, w') ↔
      success = true ∧ ¬ (rd.length = 0 ∧ ext.codeLength target = 0) ∧ r = rd ∧ w' = w := by
  rw [verify_run]
  cases success <;> simp
  split <;> simp_all [eq_comm]

theorem functionCallWithValue_run (target : Nat) (data : List Nat) (value : Nat) (env : Env) (w : σ) :
    AsyncSwap.Address.functionCallWithValue ext target data value env w =
      if env.balance < value then .error ⟨"AddressInsufficientBalance"⟩
      else match ext.lowCall target value data env w with
        | .error e => .error e
        | .ok ((s, rd), w1) => AsyncSwap.Address.verifyCallResultFromTarget ext target s rd env w1 := by
  unfold AsyncSwap.Address.functionCallWithValue
  by_cases h : env.balance < value
  · simp [h]
  · simp only [h, run_bind, run_read, run_ite, decide_eq_true_eq, ite_false]
    rcases ext.lowCall target value data env w with e | ⟨⟨s, rd⟩, w1⟩
    · rfl
    · simp only

theorem functionCall_run (target : Nat) (data : List Nat) (env : Env) (w : σ) :
    AsyncSwap.Address.functionCall ext target data env w =
      match ext.lowCall target 0 data env w with
        | .error e => .error e
        | .ok ((s, rd), w1) => AsyncSwap.Address.verifyCallResultFromTarget ext target s rd env w1 := by
  unfold AsyncSwap.Address.functionCall
  simp only [functionCallWithValue_run, Nat.not_lt_zero, ite_false]

/-- The return-data check of `_callOptionalReturn`, given the call's return data. -/
def optionalReturnCheck (rd : List Nat) (env : Env) (w : σ) : Except Revert (Unit × σ) :=
  if rd.length = 0 then .ok ((), w)
  else match (abiWordAt rd 0 : M σ Nat) env w with
    | .error e => .error e
    | .ok (x, w1) => match (abiBool x : M σ Bool) env w1 with
      | .error e => .error e
      | .ok (b, w2) => if b = true then .ok ((), w2) else .error ⟨"SafeERC20FailedOperation"⟩

theorem callOptionalReturn_run (token : Nat) (data : List Nat) (env : Env) (w : σ) :
    AsyncSwap.SafeERC20.«_callOptionalReturn» ext token data env w =
      match AsyncSwap.Address.functionCall ext token data env w with
        | .error e => .error e
        | .ok (rd, w1) => optionalReturnCheck rd env w1 := by
  unfold AsyncSwap.SafeERC20.«_callOptionalReturn» optionalReturnCheck
  simp only [run_bind]
  rcases AsyncSwap.Address.functionCall ext token data env w with e | ⟨rd, w1⟩
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
    AsyncSwap.SafeERC20.safeTransferFrom ext token fr to value env w =
      AsyncSwap.SafeERC20.«_callOptionalReturn» ext token
        ((wordBytes (0x23b872dd * 2 ^ 224)).take 4 ++ abiEncode [fr, to, value]) env w := by
  unfold AsyncSwap.SafeERC20.safeTransferFrom
  simp only [run_bind, run_pure]
  rcases AsyncSwap.SafeERC20.«_callOptionalReturn» ext token _ env w with e | ⟨u, w1⟩ <;> rfl

theorem safeTransferFrom_ok (token fr to value : Nat) (env : Env) (w w' : σ) u
    (h : AsyncSwap.SafeERC20.safeTransferFrom ext token fr to value env w = .ok (u, w')) :
    ∃ rd w1, ext.lowCall token 0 ((wordBytes (0x23b872dd * 2 ^ 224)).take 4 ++ abiEncode [fr, to, value]) env w
        = .ok ((true, rd), w1) ∧ ¬ (rd.length = 0 ∧ ext.codeLength token = 0) ∧
      optionalReturnCheck rd env w1 = .ok (u, w') := by
  rw [safeTransferFrom_run, callOptionalReturn_run, functionCall_run] at h
  revert h
  rcases ext.lowCall token 0 _ env w with e | ⟨⟨s, rd⟩, w1⟩
  · simp
  · simp only
    rcases hv : AsyncSwap.Address.verifyCallResultFromTarget ext token s rd env w1 with e | ⟨r, w2⟩
    · simp
    · rw [verify_ok_iff] at hv
      obtain ⟨hs, hc, rfl, rfl⟩ := hv
      subst hs
      intro h
      exact ⟨r, w2, rfl, hc, h⟩

theorem bubbleUpAndRevertWith_run (a b c : Nat) (env : Env) (w : σ) :
    AsyncSwap.CustomRevert.bubbleUpAndRevertWith ext a b c env w = .error ⟨"revert"⟩ := by
  simp [AsyncSwap.CustomRevert.bubbleUpAndRevertWith]

theorem byteLength_run (sstr : Nat) (env : Env) (w : σ) :
    AsyncSwap.ShortStrings.byteLength ext sstr env w =
      if sstr &&& 0xFF > 31 then .error ⟨"InvalidShortString"⟩ else .ok (sstr &&& 0xFF, w) := by
  unfold AsyncSwap.ShortStrings.byteLength
  by_cases h : sstr &&& 0xFF > 31 <;> simp [h]

theorem byteLength_ok (sstr : Nat) (env : Env) (w w' : σ) n
    (h : AsyncSwap.ShortStrings.byteLength ext sstr env w = .ok (n, w')) :
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
    AsyncSwap.EIP712.«_EIP712Name» ext env w =
      ext.fn_ShortStrings_toStringWithFallback_9627 ext.«_name»
        (do return (ext.get (← get)).«_nameFallback»)
        (fun x => modify fun w => ext.set w (let s := ext.get w; { s with «_nameFallback» := x })) env w := by
  unfold AsyncSwap.EIP712.«_EIP712Name»
  simp only

theorem EIP712Version_run (env : Env) (w : σ) :
    AsyncSwap.EIP712.«_EIP712Version» ext env w =
      ext.fn_ShortStrings_toStringWithFallback_9627 ext.«_version»
        (do return (ext.get (← get)).«_versionFallback»)
        (fun x => modify fun w => ext.set w (let s := ext.get w; { s with «_versionFallback» := x })) env w := by
  unfold AsyncSwap.EIP712.«_EIP712Version»
  simp only

/-! ## `AsyncFiller._priorityKey` -/

theorem priorityKey_reverts (fee seq : Nat) (env : Env) (w : σ) (h : 2 ^ 64 - 1 < seq) :
    AsyncSwap.AsyncFiller.«_priorityKey» ext fee seq env w = .error (panic "0x11") := by
  unfold AsyncSwap.AsyncFiller.«_priorityKey» subc
  simp [show ¬ seq ≤ 2 ^ 64 - 1 by omega]

theorem priorityKey_run (fee seq : Nat) (env : Env) (w : σ) (hf : fee < 2 ^ 64) (hs : seq ≤ 2 ^ 64 - 1) :
    AsyncSwap.AsyncFiller.«_priorityKey» ext fee seq env w =
      .ok (fee * 2 ^ 64 + (2 ^ 64 - 1 - seq), w) := by
  unfold AsyncSwap.AsyncFiller.«_priorityKey» subc shlw
  simp only [hs, ite_true, run_bind, run_pure, run_ite]
  have h1 : (fee <<< 64) % 2 ^ 128 = fee <<< 64 := by
    rw [Nat.shiftLeft_eq]; apply Nat.mod_eq_of_lt
    have : fee * 2 ^ 64 < 2 ^ 64 * 2 ^ 64 := Nat.mul_lt_mul_of_pos_right hf (Nat.two_pow_pos 64)
    show fee * 2 ^ 64 < 2 ^ (64 + 64)
    rw [Nat.pow_add]; exact this
  rw [h1, ← Nat.shiftLeft_add_eq_or_of_lt (by omega), Nat.shiftLeft_eq]

end AsyncSwap.Swarm.LibHelpers
