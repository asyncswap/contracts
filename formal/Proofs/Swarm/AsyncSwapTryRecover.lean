import Specs.AsyncSwap
open FormalAst

/-!
# `ECDSA.tryRecover(hash, v, r, s)` (src/AsyncSwap.sol, OpenZeppelin ECDSA)

No guards that revert, empty storage footprint, no external calls besides the
`ecrecover` precompile (modelled as `ext.ecrecover`). The result is the triple
`(signer, RecoverError, errorArg)`:

* `s > secp256k1n / 2` (malleable upper-half `s`, EIP-2) → `(0, 3 = InvalidSignatureS, s)`;
* otherwise, `ecrecover` returns `0`                       → `(0, 1 = InvalidSignature, 0)`;
* otherwise                                                → `(ecrecover hash v r s, 0 = NoError, 0)`.
-/

namespace AsyncSwap
namespace Swarm.TryRecover
variable {σ : Type}

/-- Half the secp256k1 group order: the EIP-2 bound on `s`. -/
def halfN : Nat := 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0

/-- The specification of `tryRecover`'s return value. -/
def spec (ext : Ext σ) (hash v r s' : Nat) : Nat × Nat × Nat :=
  if s' > halfN then (0, 3, s')
  else if ext.ecrecover hash v r s' = 0 then (0, 1, 0)
  else (ext.ecrecover hash v r s', 0, 0)

/-- `ECDSA.tryRecover` never reverts, leaves the state unchanged, and returns `spec`. -/
theorem tryRecover_eq (ext : Ext σ) (hash v r s' : Nat) (env : Env) (st : σ) :
    ECDSA.tryRecover ext hash v r s' env st = .ok (spec ext hash v r s', st) := by
  unfold ECDSA.tryRecover spec halfN
  by_cases h1 : s' > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0
  · simp [h1, pure, ReaderT.pure, StateT.pure, Except.pure]
  · by_cases h2 : ext.ecrecover hash v r s' = 0
    · simp [h1, h2, pure, ReaderT.pure, StateT.pure, Except.pure]
    · simp [h1, h2, pure, ReaderT.pure, StateT.pure, Except.pure]

/-- Malleable signatures (`s` in the upper half) are rejected with `InvalidSignatureS`. -/
theorem tryRecover_high_s (ext : Ext σ) (hash v r s' : Nat) (env : Env) (st : σ)
    (h : s' > halfN) :
    ECDSA.tryRecover ext hash v r s' env st = .ok ((0, 3, s'), st) := by
  rw [tryRecover_eq]; simp [spec, h]

/-- A zero `ecrecover` result (with low `s`) is reported as `InvalidSignature`. -/
theorem tryRecover_zero_signer (ext : Ext σ) (hash v r s' : Nat) (env : Env) (st : σ)
    (h : ¬ s' > halfN) (h0 : ext.ecrecover hash v r s' = 0) :
    ECDSA.tryRecover ext hash v r s' env st = .ok ((0, 1, 0), st) := by
  rw [tryRecover_eq]; simp [spec, h, h0]

/-- Otherwise the recovered signer is returned with `NoError`. -/
theorem tryRecover_ok (ext : Ext σ) (hash v r s' : Nat) (env : Env) (st : σ)
    (h : ¬ s' > halfN) (h0 : ext.ecrecover hash v r s' ≠ 0) :
    ECDSA.tryRecover ext hash v r s' env st =
      .ok ((ext.ecrecover hash v r s', 0, 0), st) := by
  rw [tryRecover_eq]; simp [spec, h, h0]

/-- Whenever the error code is `NoError` (0), the returned signer is nonzero
and the state is unchanged. -/
theorem tryRecover_noError_signer_ne_zero (ext : Ext σ) (hash v r s' : Nat) (env : Env)
    (st : σ) (a b c : Nat) (st' : σ)
    (hres : ECDSA.tryRecover ext hash v r s' env st = .ok ((a, b, c), st'))
    (hb : b = 0) : a ≠ 0 ∧ st' = st := by
  rw [tryRecover_eq] at hres
  unfold spec at hres
  by_cases h1 : s' > halfN
  · simp [h1] at hres; omega
  · by_cases h2 : ext.ecrecover hash v r s' = 0
    · simp [h1, h2] at hres; omega
    · simp [h1, h2] at hres
      obtain ⟨⟨ha, -, -⟩, hst⟩ := hres
      exact ⟨ha ▸ h2, hst.symm⟩

end Swarm.TryRecover
end AsyncSwap
