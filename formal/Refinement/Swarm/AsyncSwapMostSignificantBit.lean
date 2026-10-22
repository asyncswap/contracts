import Mathlib
import Generated.AsyncSwap
import Refinement.Monad

/-!
# AsyncSwap: `RadixPriceTree._mostSignificantBit`

`_mostSignificantBit(value)` is a pure binary search over the shifts 64, 32, 16, 8, 4, 2, 1.
It has no guards: the checked `uint8` additions to `bit` never overflow (the total is at most
127), so it never reverts, and it leaves storage untouched. For every `uint128` input
(`value < 2^128`) it returns `Nat.log2 value`, the index of the highest set bit (and `0` for
`value = 0`).
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.MostSignificantBit

variable {σ : Type} (ext : Ext σ)

/-- One halving stage of the binary search: shift by `k` when the high part is nonzero. -/
def stage (k : Nat) (p : Nat × Nat) : Nat × Nat :=
  if p.1 >>> k ≠ 0 then (p.1 >>> k, p.2 + k) else p

/-- The binary search the function performs, as a pure function of `value`. -/
def msbSpec (v : Nat) : Nat :=
  let p := stage 2 (stage 4 (stage 8 (stage 16 (stage 32 (stage 64 (v, 0))))))
  if p.1 >>> 1 ≠ 0 then p.2 + 1 else p.2

set_option maxHeartbeats 4000000 in
/-- Literal semantics: never reverts, storage unchanged, returns `msbSpec value`. -/
theorem mostSignificantBit_spec (v : Nat) (env : Env) (w : σ) :
    RadixPriceTree.«_mostSignificantBit» ext v env w = .ok (msbSpec v, w) := by
  unfold RadixPriceTree.«_mostSignificantBit»
  simp only [addc]
  by_cases h1 : v >>> 64 = 0
  · simp [h1]
    split_ifs <;> simp_all [msbSpec, stage]
  · simp [h1]
    split_ifs <;> simp_all [msbSpec, stage]

theorem stage_snd_le (k : Nat) (p : Nat × Nat) : (stage k p).2 ≤ p.2 + k := by
  unfold stage; split_ifs <;> simp

theorem msbSpec_lt (v : Nat) : msbSpec v < 128 := by
  have h1 := stage_snd_le 64 (v, 0)
  have h2 := stage_snd_le 32 (stage 64 (v, 0))
  have h3 := stage_snd_le 16 (stage 32 (stage 64 (v, 0)))
  have h4 := stage_snd_le 8 (stage 16 (stage 32 (stage 64 (v, 0))))
  have h5 := stage_snd_le 4 (stage 8 (stage 16 (stage 32 (stage 64 (v, 0)))))
  have h6 := stage_snd_le 2 (stage 4 (stage 8 (stage 16 (stage 32 (stage 64 (v, 0))))))
  simp only at h1
  unfold msbSpec
  simp only
  split_ifs <;> omega

/-- Loop invariant of the search: the current value is `v >> bit`, nonzero, and below `2^k`. -/
theorem stage_inv {v k : Nat} {p : Nat × Nat}
    (h : p.1 = v >>> p.2 ∧ p.1 ≠ 0 ∧ p.1 < 2 ^ (2 * k)) :
    (stage k p).1 = v >>> (stage k p).2 ∧ (stage k p).1 ≠ 0 ∧ (stage k p).1 < 2 ^ k := by
  obtain ⟨hu, h0, hlt⟩ := h
  unfold stage
  split_ifs with hs
  · refine ⟨?_, hs, ?_⟩
    · simp only; rw [Nat.shiftRight_add, ← hu]
    · simp only
      rw [Nat.shiftRight_eq_div_pow, Nat.div_lt_iff_lt_mul (by positivity), ← pow_add]
      rwa [← two_mul]
  · refine ⟨hu, h0, ?_⟩
    rw [ne_eq, not_not, Nat.shiftRight_eq_div_pow] at hs
    by_contra hc
    have := Nat.div_pos (not_lt.mp hc) (by positivity : 0 < 2 ^ k)
    omega

theorem shiftRight_msbSpec {v : Nat} (h0 : v ≠ 0) (hv : v < 2 ^ 128) : v >>> msbSpec v = 1 := by
  have i0 : (v, 0).1 = v >>> (v, 0).2 ∧ (v, 0).1 ≠ 0 ∧ (v, 0).1 < 2 ^ (2 * 64) :=
    ⟨by simp, h0, by simpa using hv⟩
  have i1 := stage_inv i0
  have i2 := stage_inv (k := 32) (by simpa using i1)
  have i3 := stage_inv (k := 16) (by simpa using i2)
  have i4 := stage_inv (k := 8) (by simpa using i3)
  have i5 := stage_inv (k := 4) (by simpa using i4)
  have i6 := stage_inv (k := 2) (by simpa using i5)
  unfold msbSpec
  simp only
  generalize stage 2 (stage 4 (stage 8 (stage 16 (stage 32 (stage 64 (v, 0)))))) = p at i6 ⊢
  obtain ⟨hu, hne, hlt⟩ := i6
  split_ifs with hs
  · rw [Nat.shiftRight_add, ← hu, Nat.shiftRight_eq_div_pow]
    rw [Nat.shiftRight_eq_div_pow] at hs
    omega
  · rw [← hu]
    rw [Nat.shiftRight_eq_div_pow] at hs
    omega

theorem msbSpec_eq_log2 {v : Nat} (hv : v < 2 ^ 128) : msbSpec v = Nat.log2 v := by
  by_cases h0 : v = 0
  · subst h0; decide
  have h := shiftRight_msbSpec h0 hv
  rw [Nat.shiftRight_eq_div_pow, Nat.div_eq_iff (by positivity)] at h
  rw [Nat.log2_eq_log_two]
  symm
  apply Nat.log_eq_of_pow_le_of_lt_pow
  · omega
  · rw [pow_succ]
    have : 0 < 2 ^ msbSpec v := by positivity
    omega

/-- It never reverts, leaves storage unchanged, and returns a value below 128 (so the
`uint8` arithmetic on `bit` never overflows). -/
theorem mostSignificantBit_noRevert (v : Nat) (env : Env) (w : σ) :
    ∃ r, r < 128 ∧ RadixPriceTree.«_mostSignificantBit» ext v env w = .ok (r, w) :=
  ⟨msbSpec v, msbSpec_lt v, mostSignificantBit_spec ext v env w⟩

/-- On every `uint128` input it returns the index of the highest set bit, `Nat.log2 value`
(`0` for `value = 0`), and leaves storage unchanged. -/
theorem mostSignificantBit_eq_log2 (v : Nat) (hv : v < 2 ^ 128) (env : Env) (w : σ) :
    RadixPriceTree.«_mostSignificantBit» ext v env w = .ok (Nat.log2 v, w) := by
  rw [mostSignificantBit_spec, msbSpec_eq_log2 hv]

/-- Bit-level meaning for a nonzero `uint128` input: the result `r` satisfies
`2^r ≤ value < 2^(r+1)`. -/
theorem mostSignificantBit_bounds (v : Nat) (h0 : v ≠ 0) (hv : v < 2 ^ 128) (env : Env) (w : σ) :
    ∃ r, RadixPriceTree.«_mostSignificantBit» ext v env w = .ok (r, w) ∧
      2 ^ r ≤ v ∧ v < 2 ^ (r + 1) :=
  ⟨Nat.log2 v, mostSignificantBit_eq_log2 ext v hv env w,
    Nat.log2_self_le h0, Nat.lt_log2_self⟩

end AsyncSwap.Swarm.MostSignificantBit
