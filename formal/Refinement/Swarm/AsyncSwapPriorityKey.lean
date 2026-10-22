import Generated.AsyncSwap
import Refinement.Monad
import AsyncSwapSpec.Priority

/-!
# `AsyncFiller._priorityKey`

`_priorityKey(priorityFee, sequence) = (uint256(uint128(priorityFee)) << 64) | (type(uint64).max - sequence)`.

* It reverts (checked-arithmetic panic `0x11`) exactly when `sequence > 2^64 − 1`.
* It never touches storage (the state is returned unchanged) and makes no external call.
* On success it returns `shlw 128 priorityFee 64 ||| (2^64 − 1 − sequence)`; for
  `priorityFee < 2^64` this is `priorityFee * 2^64 + (2^64 − 1 − sequence)`, the spec key
  `AsyncSwap.priorityKey` of `AsyncSwapSpec/Priority.lean`.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.PriorityKey

variable {σ : Type} (ext : AsyncSwap.Ext σ)

/-- Full characterization: panics iff `sequence > 2^64 − 1`, otherwise returns the OR of the
shifted fee and the inverted sequence, leaving the state unchanged. -/
theorem priorityKey_spec (fee seq : Nat) (env : Env) (w : σ) :
    AsyncSwap.AsyncFiller.«_priorityKey» ext fee seq env w
      = if seq ≤ 2 ^ 64 - 1 then .ok ((shlw 128 fee 64) ||| (2 ^ 64 - 1 - seq), w)
        else .error (panic "0x11") := by
  unfold AsyncSwap.AsyncFiller.«_priorityKey» subc
  by_cases h : seq ≤ 2 ^ 64 - 1
  · simp only [h, ite_true, run_bind, run_pure]
  · simp only [h, ite_false]
    rfl

/-- The guard: it reverts with panic `0x11` exactly when `sequence > 2^64 − 1`. -/
theorem priorityKey_reverts (fee seq : Nat) (env : Env) (w : σ) (h : 2 ^ 64 - 1 < seq) :
    AsyncSwap.AsyncFiller.«_priorityKey» ext fee seq env w = .error (panic "0x11") := by
  have hn : ¬ seq ≤ 2 ^ 64 - 1 := by omega
  rw [priorityKey_spec, ite_cond_eq_false _ _ (eq_false hn)]

/-- Any success leaves the state unchanged and implies `sequence ≤ 2^64 − 1`. -/
theorem priorityKey_ok (fee seq : Nat) (env : Env) (w w' : σ) (k : Nat)
    (h : AsyncSwap.AsyncFiller.«_priorityKey» ext fee seq env w = .ok (k, w')) :
    seq ≤ 2 ^ 64 - 1 ∧ w' = w ∧ k = (shlw 128 fee 64) ||| (2 ^ 64 - 1 - seq) := by
  rw [priorityKey_spec] at h
  split at h
  · next hs =>
    simp only [Except.ok.injEq, Prod.mk.injEq] at h
    exact ⟨hs, h.2.symm, h.1.symm⟩
  · cases h

/-- For a 64-bit fee and in-range sequence the result is the spec key
`fee * 2^64 + (2^64 − 1 − seq)` = `AsyncSwap.priorityKey fee seq`, with storage unchanged. -/
theorem priorityKey_run (fee seq : Nat) (env : Env) (w : σ) (hf : fee < 2 ^ 64)
    (hs : seq ≤ 2 ^ 64 - 1) :
    AsyncSwap.AsyncFiller.«_priorityKey» ext fee seq env w
      = .ok (AsyncSwap.priorityKey fee seq, w) := by
  rw [priorityKey_spec, ite_cond_eq_true _ _ (eq_true hs)]
  have hlt : fee <<< 64 < 2 ^ 128 := by
    rw [Nat.shiftLeft_eq]
    have : fee * 2 ^ 64 < 2 ^ 64 * 2 ^ 64 := Nat.mul_lt_mul_of_pos_right hf (Nat.two_pow_pos 64)
    show fee * 2 ^ 64 < 2 ^ (64 + 64)
    rw [Nat.pow_add]; exact this
  have hb : 2 ^ 64 - 1 - seq < 2 ^ 64 := by omega
  unfold shlw AsyncSwap.priorityKey AsyncSwap.maxUint64
  rw [Nat.mod_eq_of_lt hlt, ← Nat.shiftLeft_add_eq_or_of_lt hb, Nat.shiftLeft_eq]

end AsyncSwap.Swarm.PriorityKey
