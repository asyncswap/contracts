import Generated.AsyncSwap
import Refinement.Monad

/-!
# AsyncSwap: `SafeERC20.safeTransferFrom`

Closed form of the generated `SafeERC20.safeTransferFrom`: it issues exactly one low-level
call `token.call{value: 0}(transferFrom(from, to, value))` (selector `0x23b872dd`) and then
* bubbles the call's revert,
* reverts when the call failed (`revert` with return data, else `FailedInnerCall`),
* reverts `AddressEmptyCode` when the call returned nothing from an address without code,
* with non-empty return data, reverts `abi.decode` if fewer than 32 bytes or the first word is
  not a bool, `SafeERC20FailedOperation` if it is `false`,
* and otherwise succeeds returning `()` in the world left by the call (no write of its own).
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.SafeTransferFrom

open AsyncSwap

variable {σ : Type} (ext : AsyncSwap.Ext σ)

/-- The `transferFrom(from, to, value)` calldata the function hands to the token. -/
def transferFromData (fr to value : Nat) : List Nat :=
  (wordBytes (0x23b872dd * 2 ^ 224)).take 4 ++ abiEncode [fr, to, value]

/-- What happens after the low-level call returned `(s, rd)` in world `w1`. -/
def afterCall (token : Nat) (s : Bool) (rd : List Nat) (w1 : σ) : Except Revert (Unit × σ) :=
  if s = false then .error (if rd.length > 0 then ⟨"revert"⟩ else ⟨"FailedInnerCall"⟩)
  else if rd.length = 0 then
    (if ext.codeLength token = 0 then .error ⟨"AddressEmptyCode"⟩ else .ok ((), w1))
  else if rd.length < 32 then .error ⟨"abi.decode"⟩
  else if bytesWord (rd.take 32) = 1 then .ok ((), w1)
  else if bytesWord (rd.take 32) = 0 then .error ⟨"SafeERC20FailedOperation"⟩
  else .error ⟨"abi.decode"⟩

theorem safeTransferFrom_spec (token fr to value : Nat) (env : Env) (w : σ) :
    SafeERC20.safeTransferFrom ext token fr to value env w =
      match ext.lowCall token 0 (transferFromData fr to value) env w with
      | .error e => .error e
      | .ok ((s, rd), w1) => afterCall ext token s rd w1 := by
  unfold SafeERC20.safeTransferFrom SafeERC20.«_callOptionalReturn» Address.functionCall
    Address.functionCallWithValue transferFromData
  simp only [run_bind, run_read, Nat.not_lt_zero, decide_false, run_ite, Bool.false_eq_true,
    ite_false]
  rcases ext.lowCall token 0 ((wordBytes (0x23b872dd * 2 ^ 224)).take 4 ++ abiEncode [fr, to, value])
    env w with e | ⟨⟨s, rd⟩, w1⟩
  · rfl
  · simp only
    unfold afterCall
    cases s
    · by_cases h : rd.length > 0 <;>
        simp [Address.verifyCallResultFromTarget, Address.«_revert», h]
    · by_cases h0 : rd.length = 0
      · by_cases hc : ext.codeLength token = 0 <;>
          simp [Address.verifyCallResultFromTarget, h0, hc]
      · simp only [Address.verifyCallResultFromTarget, run_bind, run_ite, run_pure, h0]
        simp [h0, abiWordAt, abiBool]
        by_cases h32 : rd.length < 32
        · simp [h32, show ¬ 32 ≤ rd.length by omega]
        · simp only [h32, show 32 ≤ rd.length by omega, ite_true, ite_false]
          by_cases h1 : bytesWord (rd.take 32) = 1
          · simp [h1]
          · by_cases h2 : bytesWord (rd.take 32) = 0
            · simp [h2]
            · have : ¬ bytesWord (rd.take 32) ≤ 1 := by omega
              simp [h1, h2, this]

theorem afterCall_ok_iff (token : Nat) (s : Bool) (rd : List Nat) (w1 w' : σ) (u : Unit) :
    afterCall ext token s rd w1 = .ok (u, w') ↔
      s = true ∧ w' = w1 ∧
        ((rd.length = 0 ∧ ext.codeLength token ≠ 0) ∨
         (32 ≤ rd.length ∧ bytesWord (rd.take 32) = 1)) := by
  unfold afterCall
  cases s
  · by_cases h : rd.length > 0 <;> simp [h]
  · by_cases h0 : rd.length = 0
    · by_cases hc : ext.codeLength token = 0 <;> simp [h0, hc, eq_comm]
    · by_cases h32 : rd.length < 32
      · simp [h0, h32]; omega
      · by_cases h1 : bytesWord (rd.take 32) = 1
        · simp [h0, h32, h1, eq_comm]; omega
        · by_cases h2 : bytesWord (rd.take 32) = 0 <;> simp [h0, h32, h1, h2]

/-- Success characterization: `safeTransferFrom` succeeds iff the `transferFrom` low-level
call succeeds with `success = true` and return data `rd` such that `rd` is empty and the target
has code, or `rd` has a first word equal to `1` (`true`). The resulting world is the one left by
the call: the function writes no storage of its own. -/
theorem safeTransferFrom_ok_iff (token fr to value : Nat) (env : Env) (w w' : σ) (u : Unit) :
    SafeERC20.safeTransferFrom ext token fr to value env w = .ok (u, w') ↔
      ∃ rd, ext.lowCall token 0 (transferFromData fr to value) env w = .ok ((true, rd), w') ∧
        ((rd.length = 0 ∧ ext.codeLength token ≠ 0) ∨
         (32 ≤ rd.length ∧ bytesWord (rd.take 32) = 1)) := by
  rw [safeTransferFrom_spec]
  rcases ext.lowCall token 0 (transferFromData fr to value) env w with e | ⟨⟨s, rd⟩, w1⟩
  · simp
  · simp only [afterCall_ok_iff, Except.ok.injEq, Prod.mk.injEq]
    constructor
    · rintro ⟨rfl, rfl, h⟩
      exact ⟨rd, ⟨⟨rfl, rfl⟩, rfl⟩, h⟩
    · rintro ⟨rd', ⟨⟨hs, hr⟩, hw⟩, h⟩
      subst hs hr hw
      exact ⟨rfl, rfl, h⟩

/-- If the low-level call reverts, the function reverts with the same error; no guard precedes
the call. -/
theorem safeTransferFrom_call_reverts (token fr to value : Nat) (env : Env) (w : σ) (e : Revert)
    (h : ext.lowCall token 0 (transferFromData fr to value) env w = .error e) :
    SafeERC20.safeTransferFrom ext token fr to value env w = .error e := by
  rw [safeTransferFrom_spec, h]

end AsyncSwap.Swarm.SafeTransferFrom
