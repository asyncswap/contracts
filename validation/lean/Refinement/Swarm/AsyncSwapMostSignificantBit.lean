import Generated.AsyncSwap
import Refinement.Monad
open FormalAst Refinement

/-!
# `BitMath.mostSignificantBit` (src/AsyncSwap.sol, Uniswap v4 `BitMath`)

`require(x > 0)`, then a branch-free binary search in assembly: for `s = 128, 64, 32, 16, 8` it sets
bit `log₂ s` of `r` when `x >> r > 2^s - 1`, and finishes with a de Bruijn-style byte lookup on the
remaining `x >> r < 256`.

* `mostSignificantBit_run`: it reverts with `"require"` iff `x = 0`; otherwise it returns `msbPure x`
  and leaves the state unchanged (empty footprint, no external calls).
* `mostSignificantBit_eq`: for `0 < x < 2^256` the result is `Nat.log2 x`, i.e. the unique `R` with
  `2^R ≤ x < 2^(R+1)`.
-/

namespace AsyncSwap.Swarm.MostSignificantBit

/-- One stage: `r := or(r, shl(k, gt(shr(r, x), c))) mod 2^8`. -/
def stage (k c r x : Nat) : Nat := (yor r (yshl k (ylt c (yshr r x)))) % 2 ^ 8

/-- The final de Bruijn lookup on `y = x >> r`. -/
def lut (y : Nat) : Nat :=
  ybyte (yand 0x1f (yshr y 0x8421084210842108cc6318c6db6d54be))
    0x0706060506020500060203020504000106050205030304010505030400000000

/-- The pure value the function returns. -/
def msbPure (x : Nat) : Nat :=
  let r1 := (yshl 7 (ylt 0xffffffffffffffffffffffffffffffff x)) % 2 ^ 8
  let r2 := stage 6 0xffffffffffffffff r1 x
  let r3 := stage 5 0xffffffff r2 x
  let r4 := stage 4 0xffff r3 x
  let r5 := stage 3 0xff r4 x
  (yor r5 (lut (yshr r5 x))) % 2 ^ 8

/-- Guard and footprint: reverts iff `x = 0`; otherwise returns `msbPure x`, state unchanged. -/
theorem mostSignificantBit_run {σ : Type} (ext : Ext σ) (x : Nat) (env : Env) (s : σ) :
    BitMath.mostSignificantBit ext x env s
      = if x > 0 then .ok (msbPure x, s) else .error ⟨"require"⟩ := by
  by_cases hx : x > 0
  · simp [BitMath.mostSignificantBit, msbPure, stage, lut, hx]
  · simp [BitMath.mostSignificantBit, hx]

/-! ## The value -/

/-- The lookup table is right on every byte: `2^ℓ ≤ y < 2^(ℓ+1)` (checked by the kernel). -/
theorem lut_spec : ∀ y, y < 256 → 0 < y → lut y < 8 ∧ 2 ^ lut y ≤ y ∧ y < 2 ^ (lut y + 1) := by
  decide +kernel

/-- OR is addition when the low `n` bits of `r` are clear. -/
theorem or_eq_add (n r f : Nat) (hr : 2 ^ n ∣ r) (hf : f < 2 ^ n) : r ||| f = r + f := by
  obtain ⟨q, rfl⟩ := hr
  have : 2 ^ n * q = q <<< n := by rw [Nat.shiftLeft_eq, Nat.mul_comm]
  rw [this, Nat.shiftLeft_add_eq_or_of_lt hf]

/-- Binary-search invariant: `r` is a multiple of `m`, `r + m ≤ 256`, and `1 ≤ x >> r < 2^m`. -/
def Inv (x m r : Nat) : Prop := m ∣ r ∧ r + m ≤ 256 ∧ 0 < x >>> r ∧ x >>> r < 2 ^ m

theorem stage_inv (x k s c r : Nat) (hs : s = 2 ^ k) (hc : c + 1 = 2 ^ s) (hk : k < 8)
    (h : Inv x (2 * s) r) : Inv x s (stage k c r x) := by
  obtain ⟨hd, hle, hpos, hlt⟩ := h
  have hs1 : 1 ≤ s := by rw [hs]; exact Nat.one_le_two_pow
  have hr : r < 256 := by omega
  have hsW : s < W := by
    have : s ≤ 256 := by omega
    unfold W; exact Nat.lt_of_le_of_lt this (by decide)
  have hshr : yshr r x = x >>> r := by simp [yshr, hr]
  have hps : 0 < 2 ^ s := Nat.two_pow_pos s
  unfold stage
  rw [hshr]
  by_cases hb : c < x >>> r
  · have hge : 2 ^ s ≤ x >>> r := by omega
    have hl : yshl k (ylt c (x >>> r)) = s := by
      simp only [yshl, ylt, ybool, hb, decide_true, ite_true, show k < 256 by omega,
        Nat.shiftLeft_eq, Nat.one_mul]
      rw [← hs]; exact Nat.mod_eq_of_lt hsW
    have hd2 : 2 ^ (k + 1) ∣ r := by
      rw [Nat.pow_succ, ← hs, Nat.mul_comm]; exact hd
    have hor : yor r s = r + s := by
      unfold yor; rw [hs]
      exact or_eq_add (k + 1) r (2 ^ k) hd2 (Nat.pow_lt_pow_right (by decide) (Nat.lt_succ_self k))
    rw [hl, hor, Nat.mod_eq_of_lt (by omega)]
    refine ⟨?_, by omega, ?_, ?_⟩
    · exact Nat.dvd_add (Nat.dvd_trans (Nat.dvd_mul_left s 2) hd) (Nat.dvd_refl s)
    · rw [Nat.shiftRight_add, Nat.shiftRight_eq_div_pow]
      exact Nat.div_pos hge hps
    · rw [Nat.shiftRight_add, Nat.shiftRight_eq_div_pow]
      apply (Nat.div_lt_iff_lt_mul hps).2
      rw [← Nat.pow_add, show s + s = 2 * s by omega]; exact hlt
  · have hl : yshl k (ylt c (x >>> r)) = 0 := by
      simp [yshl, ylt, ybool, hb]
    rw [hl]
    simp only [yor, Nat.or_zero, Nat.mod_eq_of_lt (show r < 2 ^ 8 by omega)]
    exact ⟨Nat.dvd_trans (Nat.dvd_mul_left s 2) hd, by omega, hpos, by omega⟩

/-- For a word `0 < x < 2^256`, the pure value is the unique `R` with `2^R ≤ x < 2^(R+1)`. -/
theorem msbPure_spec (x : Nat) (h0 : 0 < x) (hx : x < 2 ^ 256) :
    2 ^ msbPure x ≤ x ∧ x < 2 ^ (msbPure x + 1) := by
  have h0inv : Inv x (2 * 128) 0 :=
    ⟨Nat.dvd_zero _, by omega, by simpa using h0, by simpa using hx⟩
  have hfirst : (yshl 7 (ylt 0xffffffffffffffffffffffffffffffff x)) % 2 ^ 8
      = stage 7 0xffffffffffffffffffffffffffffffff 0 x := by
    simp [stage, yshr, yor]
  have i1 := stage_inv x 7 128 0xffffffffffffffffffffffffffffffff 0
    (by decide) (by decide) (by decide) h0inv
  have i2 := stage_inv x 6 64 0xffffffffffffffff _ (by decide) (by decide) (by decide) i1
  have i3 := stage_inv x 5 32 0xffffffff _ (by decide) (by decide) (by decide) i2
  have i4 := stage_inv x 4 16 0xffff _ (by decide) (by decide) (by decide) i3
  have i5 := stage_inv x 3 8 0xff _ (by decide) (by decide) (by decide) i4
  unfold msbPure
  simp only []
  rw [hfirst]
  generalize stage 3 0xff (stage 4 0xffff (stage 5 0xffffffff
    (stage 6 0xffffffffffffffff (stage 7 0xffffffffffffffffffffffffffffffff 0 x) x) x) x) x = R at i5 ⊢
  obtain ⟨hd, hle, hpos, hlt⟩ := i5
  have hR256 : R < 256 := by omega
  have hshr : yshr R x = x >>> R := by simp [yshr, hR256]
  rw [hshr]
  obtain ⟨l8, llo, lhi⟩ := lut_spec (x >>> R) hlt hpos
  have hor : yor R (lut (x >>> R)) = R + lut (x >>> R) := or_eq_add 3 R _ hd l8
  rw [hor, Nat.mod_eq_of_lt (by omega)]
  have hp : 0 < 2 ^ R := Nat.two_pow_pos R
  generalize lut (x >>> R) = L at llo lhi ⊢
  rw [Nat.shiftRight_eq_div_pow] at llo lhi
  constructor
  · rw [Nat.pow_add, Nat.mul_comm]
    exact (Nat.le_div_iff_mul_le hp).1 llo
  · rw [Nat.add_assoc, Nat.pow_add, Nat.mul_comm]
    exact (Nat.div_lt_iff_lt_mul hp).1 lhi

/-- For every word `0 < x < 2^256`, `BitMath.mostSignificantBit` returns `⌊log₂ x⌋` and leaves the
state unchanged. -/
theorem mostSignificantBit_eq {σ : Type} (ext : Ext σ) (x : Nat) (h0 : 0 < x) (hx : x < 2 ^ 256)
    (env : Env) (s : σ) :
    BitMath.mostSignificantBit ext x env s = .ok (Nat.log2 x, s) := by
  rw [mostSignificantBit_run]
  simp only [show x > 0 from h0, ite_true]
  obtain ⟨hlo, hhi⟩ := msbPure_spec x h0 hx
  have hx0 : x ≠ 0 := by omega
  have e : Nat.log2 x = msbPure x := by
    apply Nat.le_antisymm
    · have := (Nat.log2_lt hx0).2 hhi; omega
    · exact (Nat.le_log2 hx0).2 hlo
  rw [e]

/-- `BitMath.mostSignificantBit` reverts with `"require"` exactly when `x = 0`. -/
theorem mostSignificantBit_zero {σ : Type} (ext : Ext σ) (env : Env) (s : σ) :
    BitMath.mostSignificantBit ext 0 env s = .error ⟨"require"⟩ := by
  rw [mostSignificantBit_run]; simp

end AsyncSwap.Swarm.MostSignificantBit
