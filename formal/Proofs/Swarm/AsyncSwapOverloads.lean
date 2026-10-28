import Specs.AsyncSwap
import Proofs.Swarm.AsyncSwapTryRecover
open FormalAst

/-!
# Remaining overloads of `CustomRevert.revertWith` and `ECDSA.tryRecover` (AsyncSwap)

Defs as in this model: `revertWith_10633` (bytes4, int24), `revertWith_10613` (bytes4),
`tryRecover_9681` (hash, bytes).

* `CustomRevert.revertWith(bytes4, int24)` (used by `TickMath.getSqrtPriceAtTick`) and
  `CustomRevert.revertWith(bytes4)` (used by `SafeCast.toInt256`): one assembly block ending
  in `revert`, so they always revert, whatever the arguments, environment or state.
* `ECDSA.tryRecover(hash, bytes signature)`: never reverts and leaves the state unchanged.
  For a 65-byte signature it decodes `r`, `s` and `v` (the first byte of the third word) and
  returns the 4-argument `tryRecover` result. For any other length it returns
  `(0, 2 = InvalidSignatureLength, length)`.
-/

namespace AsyncSwap.Swarm.Overloads
open AsyncSwap
variable {σ : Type} (ext : Ext σ)

theorem revertWith_int_run (selector : Nat) (value : Int) (r : Env) (s : σ) :
    CustomRevert.revertWith_10633 ext selector value r s = Except.error ⟨"revert"⟩ := rfl

theorem revertWith_int_never_succeeds (selector : Nat) (value : Int) (r : Env) (s : σ)
    (res : Unit × σ) : CustomRevert.revertWith_10633 ext selector value r s ≠ Except.ok res := by
  rw [revertWith_int_run]; simp

theorem revertWith_sel_run (selector : Nat) (r : Env) (s : σ) :
    CustomRevert.revertWith_10613 ext selector r s = Except.error ⟨"revert"⟩ := rfl

theorem revertWith_sel_never_succeeds (selector : Nat) (r : Env) (s : σ)
    (res : Unit × σ) : CustomRevert.revertWith_10613 ext selector r s ≠ Except.ok res := by
  rw [revertWith_sel_run]; simp

/-- Closed form of the bytes overload of `tryRecover`. -/
def bytesSpec (hash : Nat) (sig : List Nat) : Nat × Nat × Nat :=
  if sig.length = 65 then
    Swarm.TryRecover.spec ext hash ((ybyte 0 (bytesWordAt sig (0x60 - 32))) % 2 ^ 8)
      (bytesWordAt sig (0x20 - 32)) (bytesWordAt sig (0x40 - 32))
  else (0, 2, sig.length)

theorem tryRecoverBytes_eq (hash : Nat) (sig : List Nat) (env : Env) (st : σ) :
    ECDSA.tryRecover_9681 ext hash sig env st = Except.ok (bytesSpec ext hash sig, st) := by
  unfold ECDSA.tryRecover_9681 bytesSpec
  by_cases h : sig.length = 65
  · have := Swarm.TryRecover.tryRecover_eq ext hash ((ybyte 0 (bytesWordAt sig (0x60 - 32))) % 2 ^ 8)
      (bytesWordAt sig (0x20 - 32)) (bytesWordAt sig (0x40 - 32)) env st
    simp [h, this]
  · have hb : (sig.length == 65) = false := by simpa using h
    simp [hb, h, pure, ReaderT.pure, StateT.pure, Except.pure]

/-- Any length other than 65 is reported as `InvalidSignatureLength` (2) with the length. -/
theorem tryRecoverBytes_bad_length (hash : Nat) (sig : List Nat) (env : Env) (st : σ)
    (h : sig.length ≠ 65) :
    ECDSA.tryRecover_9681 ext hash sig env st = Except.ok ((0, 2, sig.length), st) := by
  rw [tryRecoverBytes_eq]; simp [bytesSpec, h]

/-- `NoError` from the bytes overload implies a 65-byte signature and a nonzero signer. -/
theorem tryRecoverBytes_noError (hash : Nat) (sig : List Nat) (env : Env) (st : σ)
    (a c : Nat) (st' : σ)
    (hres : ECDSA.tryRecover_9681 ext hash sig env st = Except.ok ((a, 0, c), st')) :
    sig.length = 65 ∧ a ≠ 0 ∧ st' = st := by
  rw [tryRecoverBytes_eq] at hres
  by_cases h : sig.length = 65
  · refine ⟨h, ?_⟩
    simp only [bytesSpec, h, ite_true] at hres
    exact Swarm.TryRecover.tryRecover_noError_signer_ne_zero ext hash _ _ _ env st a 0 c st'
      (by rw [Swarm.TryRecover.tryRecover_eq]; exact hres) rfl
  · simp [bytesSpec, h] at hres

end AsyncSwap.Swarm.Overloads
