import Mathlib
import Generated.AsyncSwap
import Refinement.Monad

/-!
# AsyncSwap: `Math.mulDiv` (OpenZeppelin full-precision floor `x * y / d`)

The generated `Math.mulDiv` is the inlined assembly of OpenZeppelin's 512-bit `mulDiv`
(Remco Bloemen's algorithm). For 256-bit inputs it:

* returns `x * y / d` exactly, leaving the world unchanged, when `d ≠ 0` and the quotient
  fits 256 bits;
* reverts `MathOverflowedMulDiv` when `d ≠ 0` and the quotient doesn't fit;
* reverts when `d = 0`: with panic `0x12` if `x * y < 2^256`, with `MathOverflowedMulDiv`
  otherwise.

The proof checks each stage of the algorithm: the high word of the 512-bit product
(`mulmod(x, y, not(0))` trick), the subtraction of the remainder, the extraction of the largest
power of two dividing `d` (`d & -d`), the shift of the 512-bit numerator, and the
Newton–Raphson inverse of the odd part of `d` modulo `2^256` (4 → 8 → … → 256 bits).
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.MulDiv

variable {σ : Type} (ext : Ext σ)

/-! ## Word arithmetic -/

theorem W_eq : W = 2^256 := rfl
theorem W_pos : 1 < W := by rw [W_eq]; norm_num

theorem ite_pos' {α : Type} {c : Prop} [Decidable c] (h : c) (a b : α) :
    (if c then a else b) = a := by simp [h]
theorem ite_neg' {α : Type} {c : Prop} [Decidable c] (h : ¬ c) (a b : α) :
    (if c then a else b) = b := by simp [h]

theorem mulw_eq (a b : Nat) : mulw 256 a b = a * b % W := rfl

theorem ysub_le (a b : Nat) (ha : a < W) (hb : b ≤ a) : ysub a b = a - b := by
  unfold ysub
  rw [Nat.mod_eq_of_lt (by omega : b < W), show a + W - b = (a - b) + W by omega,
    Nat.add_mod_right, Nat.mod_eq_of_lt (by omega)]

theorem ysub_lt (a b : Nat) (hb : b < W) (h : a < b) : ysub a b = a + W - b := by
  unfold ysub
  rw [Nat.mod_eq_of_lt hb, Nat.mod_eq_of_lt (by omega)]

theorem ylt_eq (a b : Nat) : ylt a b = if a < b then 1 else 0 := by
  unfold ylt ybool; by_cases h : a < b <;> simp [h]

theorem ygt_eq (a b : Nat) : ygt a b = if b < a then 1 else 0 := by
  unfold ygt ybool; by_cases h : b < a <;> simp [h]

theorem ydiv_pos (a b : Nat) (hb : b ≠ 0) : ydiv a b = a / b := by simp [ydiv, hb]

/-! ## Stage 1: the high word of the 512-bit product -/

/-- `mm - prod0 - (mm < prod0)` with `mm = mulmod(x, y, 2^256 - 1)` is `x * y / 2^256`. -/
theorem hi_word (x y : Nat) (hx : x < W) (hy : y < W) :
    ysub (ysub (ymulmod x y (ynot 0)) (mulw 256 x y)) (ylt (ymulmod x y (ynot 0)) (mulw 256 x y))
      = x * y / W := by
  have hW := W_pos
  have hP : x * y ≤ (W-1)*(W-1) := Nat.mul_le_mul (by omega) (by omega)
  have h1 : ymulmod x y (ynot 0) = x * y % (W - 1) := by
    simp [ymulmod, ynot, W]
  rw [h1, mulw_eq]
  generalize x * y = P at hP
  have hdm := Nat.div_add_mod P W
  have hl : P % W < W := Nat.mod_lt _ (by omega)
  have hh : P / W < W - 1 := by
    rw [Nat.div_lt_iff_lt_mul (by omega)]
    have : (W - 1) * (W - 1) < (W - 1) * W := Nat.mul_lt_mul_of_pos_left (by omega) (by omega)
    omega
  generalize P / W = h at *
  generalize P % W = l at *
  have e : W * h = (W - 1) * h + h := by
    rw [Nat.sub_one_mul]; have : h ≤ W * h := Nat.le_mul_of_pos_left _ (by omega); omega
  have hm : P % (W - 1) = (h + l) % (W - 1) := by
    rw [← hdm, e, show (W - 1) * h + h + l = (h + l) + (W - 1) * h by ring,
      Nat.add_mul_mod_self_left]
  rw [hm, ylt_eq]
  by_cases hc : h + l < W - 1
  · rw [Nat.mod_eq_of_lt hc, ite_neg' (by omega), ysub_le (h + l) l (by omega) (by omega),
      Nat.add_sub_cancel, ysub_le h 0 (by omega) (by omega), Nat.sub_zero]
  · have hmod : (h + l) % (W - 1) = h + l - (W - 1) := by
      rw [Nat.mod_eq_sub_mod (by omega), Nat.mod_eq_of_lt (by omega)]
    rw [hmod, ite_pos' (by omega), ysub_lt _ _ hl (by omega),
      ysub_le (h + l - (W - 1) + W - l) 1 (by omega) (by omega)]
    omega

/-! ## Stage 2: subtracting the remainder from the 512-bit product -/

theorem sub_rem (P r : Nat) (hr : r < W) (hh : 1 ≤ P / W) (hh2 : P / W < W) (hrP : r ≤ P) :
    ysub (P / W) (ygt r (P % W)) * W + ysub (P % W) r = P - r := by
  have hW := W_pos
  have hdm := Nat.div_add_mod P W
  have hl : P % W < W := Nat.mod_lt _ (by omega)
  rw [ygt_eq]
  generalize P / W = h at *
  generalize P % W = l at *
  by_cases hc : l < r
  · rw [ite_pos' hc, ysub_le _ _ hh2 hh, ysub_lt _ _ hr hc, Nat.sub_one_mul, Nat.mul_comm]
    have : W ≤ W * h := Nat.le_mul_of_pos_right _ hh
    omega
  · rw [ite_neg' hc, ysub_le _ _ hh2 (by omega), ysub_le _ _ hl (by omega), Nat.mul_comm,
      Nat.sub_zero]
    omega

/-! ## Stage 3: `d & -d` is the largest power of two dividing `d` -/

theorem and_double (a b : Nat) : (2 * a) &&& (2 * b) = 2 * (a &&& b) := by
  apply Nat.eq_of_testBit_eq; intro i
  cases i with
  | zero => simp [Nat.testBit_zero]
  | succ j =>
    rw [Nat.testBit_and, Nat.testBit_add_one, Nat.testBit_add_one, Nat.testBit_add_one]
    simp [Nat.testBit_and]

theorem lowbit_odd (n d : Nat) (hd : d % 2 = 1) (hn : d < 2^n) : d &&& (2^n - d) = 1 := by
  obtain ⟨m, rfl⟩ : ∃ m, n = m + 1 := by
    rcases n with _ | m
    · simp at hn; omega
    · exact ⟨m, rfl⟩
  apply Nat.eq_of_testBit_eq; intro i
  rw [Nat.testBit_and]
  cases i with
  | zero =>
    have : (2^(m+1) - d) % 2 = 1 := by rw [pow_succ]; omega
    simp [Nat.testBit_zero, hd, this]
  | succ j =>
    rw [Nat.testBit_add_one, Nat.testBit_add_one, Nat.testBit_add_one]
    have h1 : (2^(m+1) - d) / 2 = 2^m - (d / 2 + 1) := by rw [pow_succ]; omega
    have h2 : d / 2 < 2^m := by rw [pow_succ] at hn; omega
    rw [h1, Nat.testBit_two_pow_sub_succ h2]
    cases (d / 2).testBit j <;> simp

theorem lowbit (k : Nat) :
    ∀ n o, o % 2 = 1 → 2^k * o < 2^n → (2^k * o) &&& (2^n - 2^k * o) = 2^k := by
  induction k with
  | zero => intro n o ho hn; simp only [pow_zero, one_mul] at *; exact lowbit_odd n o ho hn
  | succ k ih =>
    intro n o ho hn
    obtain ⟨m, rfl⟩ : ∃ m, n = m + 1 := by
      rcases n with _ | m
      · have : 0 < 2^(k+1) * o := Nat.mul_pos (by positivity) (by omega)
        rw [pow_zero] at hn; omega
      · exact ⟨m, rfl⟩
    have h1 : 2^(k+1) * o = 2 * (2^k * o) := by ring
    have h3 : 2^k * o < 2^m := by rw [h1, pow_succ] at hn; omega
    have h2 : 2^(m+1) - 2 * (2^k * o) = 2 * (2^m - 2^k * o) := by rw [pow_succ]; omega
    rw [h1, h2, and_double, ih m o ho h3, pow_succ]; ring

/-! ## Stage 4: the Newton–Raphson inverse modulo `2^256` -/

theorem cast_modW {N : Nat} (hN : N ∣ W) (x : Nat) : ((x % W : Nat) : ZMod N) = x := by
  rw [ZMod.natCast_eq_natCast_iff', Nat.mod_mod_of_dvd _ hN]

theorem cast_W {N : Nat} (hN : N ∣ W) : ((W : Nat) : ZMod N) = 0 := by
  obtain ⟨c, hc⟩ := hN
  rw [hc]; push_cast; simp

/-- One Newton–Raphson step, as the model writes it. -/
def nstep (d a : Nat) : Nat := mulw 256 a (subw 256 2 (mulw 256 d a))

theorem fold_nstep (d a : Nat) : mulw 256 a (subw 256 2 (mulw 256 d a)) = nstep d a := rfl

/-- Each step doubles the number of correct low bits of the inverse. -/
theorem nstep_spec (m d a : Nat) (hm : 1 ≤ m) (hm2 : 2 * m ≤ 256) (h : d * a % 2^m = 1) :
    d * nstep d a % 2^(2*m) = 1 := by
  have hN : 2^(2*m) ∣ W := pow_dvd_pow 2 hm2
  have h1N : 1 < 2^(2*m) := Nat.one_lt_two_pow (by omega)
  have hda : d * a = 2^m * (d * a / 2^m) + 1 := by
    have := Nat.div_add_mod (d * a) (2^m); omega
  have key : ((d * nstep d a : Nat) : ZMod (2^(2*m))) = ((1 : Nat) : ZMod (2^(2*m))) := by
    have hz : ((2 : ZMod (2^(2*m))) ^ (2*m)) = 0 := by
      exact_mod_cast ZMod.natCast_self (2^(2*m))
    have hda' : ((d : ZMod (2^(2*m))) * a)
        = 2^m * ((d * a / 2^m : Nat) : ZMod (2^(2*m))) + 1 := by
      exact_mod_cast congrArg (fun t : Nat => (t : ZMod (2^(2*m)))) hda
    have hsub : ((subw 256 2 (mulw 256 d a) : Nat) : ZMod (2^(2*m)))
        = 2 - (d : ZMod (2^(2*m))) * a := by
      have hlt : mulw 256 d a % 2^256 ≤ 2 + 2^256 := by
        have := Nat.mod_lt (mulw 256 d a) (by positivity : 0 < 2^256); omega
      unfold subw
      rw [← W_eq] at hlt ⊢
      rw [cast_modW hN, Nat.cast_sub hlt, cast_modW hN, mulw_eq, cast_modW hN]
      push_cast; rw [cast_W hN]; ring
    unfold nstep
    rw [Nat.cast_mul, mulw_eq a, cast_modW hN, Nat.cast_mul, hsub]
    linear_combination
      (-((d : ZMod (2^(2*m))) * a - 1 + 2^m * ((d * a / 2^m : Nat) : ZMod (2^(2*m))))) * hda'
        - ((d * a / 2^m : Nat) : ZMod (2^(2*m)))^2 * hz
  rw [ZMod.natCast_eq_natCast_iff'] at key
  rwa [Nat.mod_eq_of_lt h1N] at key

/-- The seed `(3 * d) ^ 2` is an inverse of an odd `d` modulo `2^4`. -/
theorem init_spec (o : Nat) (ho : o % 2 = 1) : o * (mulw 256 3 o ^^^ 2) % 2^4 = 1 := by
  rw [Nat.mul_mod, Nat.xor_mod_two_pow, mulw,
    Nat.mod_mod_of_dvd _ (pow_dvd_pow 2 (by norm_num : 4 ≤ 256)), Nat.mul_mod 3]
  have hlt : o % 2^4 < 16 := Nat.mod_lt _ (by norm_num)
  have ho' : o % 2^4 % 2 = 1 := by rw [Nat.mod_mod_of_dvd _ (by norm_num)]; exact ho
  generalize o % 2^4 = j at *
  interval_cases j <;> revert ho' <;> decide

/-- Six steps give the inverse modulo `2^256`. -/
theorem inv_spec (o : Nat) (ho : o % 2 = 1) :
    o * nstep o (nstep o (nstep o (nstep o (nstep o (nstep o (mulw 256 3 o ^^^ 2)))))) % W
      = 1 := by
  have h4 := init_spec o ho
  have h8 := nstep_spec 4 o _ (by norm_num) (by norm_num) h4
  have h16 := nstep_spec 8 o _ (by norm_num) (by norm_num) h8
  have h32 := nstep_spec 16 o _ (by norm_num) (by norm_num) h16
  have h64 := nstep_spec 32 o _ (by norm_num) (by norm_num) h32
  have h128 := nstep_spec 64 o _ (by norm_num) (by norm_num) h64
  exact nstep_spec 128 o _ (by norm_num) (by norm_num) h128

/-! ## Stage 5: shifting the numerator and multiplying by the inverse -/

theorem final (P d k o p0 p1 inv : Nat) (hk : k < 256) (hd : d = 2^k * o)
    (hsub : p1 * W + p0 = P - P % d) (hp0 : p0 < W) (hinv : o * inv % W = 1) (hq : P / d < W) :
    mulw 256 (p0 / 2^k ||| mulw 256 p1 (2^(256-k) % W)) inv = P / d := by
  have hW : W = 2^k * 2^(256-k) := by rw [W_eq, ← pow_add]; congr 1; omega
  have hk0 : 0 < 2^k := by positivity
  have e1 : p1 * 2^(256-k) % W = (p1 % 2^k) * 2^(256-k) := by
    rw [hW, Nat.mul_mod_mul_right]
  have e1' : mulw 256 p1 (2^(256-k) % W) = (p1 % 2^k) * 2^(256-k) := by
    rw [mulw_eq, Nat.mul_mod_mod, e1]
  have e2 : p0 / 2^k < 2^(256-k) := by
    rw [Nat.div_lt_iff_lt_mul hk0]; rw [hW] at hp0; linarith [Nat.mul_comm (2^k) (2^(256-k))]
  have e3 : p0 / 2^k ||| (p1 % 2^k) * 2^(256-k) = (p1 % 2^k) * 2^(256-k) + p0 / 2^k := by
    rw [Nat.lor_comm, ← Nat.shiftLeft_eq, Nat.shiftLeft_add_eq_or_of_lt e2]
  have hQ : (P - P % d) / 2^k = o * (P / d) := by
    have := Nat.div_add_mod P d
    rw [show P - P % d = 2^k * (o * (P / d)) by rw [← Nat.mul_assoc, ← hd]; omega,
      Nat.mul_div_cancel_left _ hk0]
  have hQ2 : (P - P % d) / 2^k = p1 * 2^(256-k) + p0 / 2^k := by
    rw [← hsub, hW, show p1 * (2^k * 2^(256-k)) + p0 = 2^k * (p1 * 2^(256-k)) + p0 by ring,
      Nat.mul_add_div hk0]
  rw [e1', e3, mulw_eq]
  suffices hc : ((((p1 % 2^k) * 2^(256-k) + p0 / 2^k) * inv % W : Nat) : ZMod W)
      = ((P / d : Nat) : ZMod W) by
    rw [ZMod.natCast_eq_natCast_iff', Nat.mod_mod, Nat.mod_eq_of_lt hq] at hc
    exact hc
  have hA : (((p1 % 2^k) * 2^(256-k) : Nat) : ZMod W) = ((p1 * 2^(256-k) : Nat) : ZMod W) := by
    rw [← e1, cast_modW (dvd_refl W)]
  have hinv' : (o : ZMod W) * inv = 1 := by
    have := ZMod.natCast_mod (o * inv) W
    rw [hinv] at this; push_cast at this; exact this.symm
  rw [ZMod.natCast_mod, Nat.cast_mul, Nat.cast_add, hA, ← Nat.cast_add, ← hQ2, hQ, Nat.cast_mul]
  linear_combination ((P / d : Nat) : ZMod W) * hinv'

/-! ## The function -/

/-- Success: for 256-bit `x`, `y` and a nonzero 256-bit `d` whose quotient `x * y / d` fits 256
bits, `Math.mulDiv` returns exactly `⌊x * y / d⌋` and leaves the world unchanged. -/
theorem mulDiv_ok (x y d : Nat) (env : Env) (s : σ) (hx : x < W) (hy : y < W) (hd : 0 < d)
    (hdW : d < W) (hq : x * y / d < W) :
    Math.mulDiv ext x y d env s = .ok (x * y / d, s) := by
  have hW := W_pos
  unfold Math.mulDiv
  simp only [run_bind, run_pure, run_ite, run_throw, fold_nstep]
  rw [hi_word x y hx hy, mulw_eq x y]
  by_cases h0 : x * y / W = 0
  · have hlt : x * y < W := by rwa [Nat.div_eq_zero_iff_lt (by omega)] at h0
    simp [h0, divc, hd.ne', Nat.mod_eq_of_lt hlt]
  · have hlt : x * y / W < d := by
      rw [Nat.div_lt_iff_lt_mul (by omega)]
      rw [Nat.div_lt_iff_lt_mul hd] at hq; linarith [Nat.mul_comm W d]
    have hPW : x * y / W < W := by omega
    have h1 : 1 ≤ x * y / W := Nat.one_le_iff_ne_zero.mpr h0
    simp only [h0, beq_iff_eq, decide_eq_true_eq, Nat.not_le.mpr hlt, ↓reduceIte]
    obtain ⟨k, o, hodd, hdk⟩ := Nat.exists_eq_two_pow_mul_odd hd.ne'
    have ho : o % 2 = 1 := Nat.odd_iff.mp hodd
    have hk0 : 0 < 2^k := by positivity
    have hk : k < 256 := by
      by_contra hk
      have : 2^256 ≤ 2^k := Nat.pow_le_pow_right (by norm_num) (by omega)
      have : 2^k ≤ 2^k * o := Nat.le_mul_of_pos_right _ (by omega)
      rw [W_eq] at hdW; omega
    have hT : d &&& subw 256 0 d = 2^k := by
      have hs : subw 256 0 d = 2^256 - d := by
        unfold subw; rw [W_eq] at hdW
        rw [Nat.mod_eq_of_lt hdW, Nat.mod_eq_of_lt (by omega)]; omega
      rw [hs, hdk]; exact lowbit k 256 o ho (by rw [← hdk, ← W_eq]; exact hdW)
    have hdo : ydiv d (2^k) = o := by
      rw [ydiv_pos _ _ hk0.ne', hdk, Nat.mul_div_cancel_left _ hk0]
    have hWk : W = 2^k * 2^(256-k) := by rw [W_eq, ← pow_add]; congr 1; omega
    have htw : yadd (ydiv (ysub 0 (2^k)) (2^k)) 1 = 2^(256-k) % W := by
      have hkW : 2^k < W := by rw [W_eq]; exact Nat.pow_lt_pow_right (by norm_num) hk
      have h1 : 1 ≤ 2^(256-k) := Nat.one_le_two_pow
      rw [ysub_lt 0 _ hkW hk0, ydiv_pos _ _ hk0.ne', Nat.zero_add,
        show W - 2^k = 2^k * (2^(256-k) - 1) by rw [hWk, Nat.mul_sub_one],
        Nat.mul_div_cancel_left _ hk0, yadd, Nat.sub_add_cancel h1]
    have hmm : ymulmod x y d = x * y % d := by simp [ymulmod, hd.ne']
    rw [hT, hdo, htw, hmm, ydiv_pos _ _ hk0.ne']
    have hrW : x * y % d < W := lt_trans (Nat.mod_lt _ hd) hdW
    have hsub := sub_rem (x * y) (x * y % d) hrW h1 hPW (Nat.mod_le _ _)
    have hp0 : ysub (x * y % W) (x * y % d) < W := Nat.mod_lt _ (by omega)
    simp only [Except.ok.injEq, Prod.mk.injEq, and_true]
    exact final (x * y) d k o _ _ _ hk hdk hsub hp0 (inv_spec o ho) hq

/-- Overflow: with a nonzero `d` whose quotient `x * y / d` doesn't fit 256 bits,
`Math.mulDiv` reverts `MathOverflowedMulDiv`. -/
theorem mulDiv_overflow (x y d : Nat) (env : Env) (s : σ) (hx : x < W) (hy : y < W)
    (hd : 0 < d) (hov : W ≤ x * y / d) :
    Math.mulDiv ext x y d env s = .error ⟨"MathOverflowedMulDiv"⟩ := by
  have hW := W_pos
  unfold Math.mulDiv
  simp only [run_bind, run_pure, run_ite, run_throw, fold_nstep]
  rw [hi_word x y hx hy]
  have hle : d ≤ x * y / W := by
    rw [Nat.le_div_iff_mul_le (by omega)]
    rw [Nat.le_div_iff_mul_le hd] at hov; linarith [Nat.mul_comm W d]
  have h0 : x * y / W ≠ 0 := by omega
  simp [h0, hle]

/-- Zero denominator: `Math.mulDiv` reverts, with panic `0x12` (division by zero) when the
product fits one word and with `MathOverflowedMulDiv` otherwise. -/
theorem mulDiv_zero (x y : Nat) (env : Env) (s : σ) (hx : x < W) (hy : y < W) :
    Math.mulDiv ext x y 0 env s
      = .error (if x * y < W then panic "0x12" else ⟨"MathOverflowedMulDiv"⟩) := by
  have hW := W_pos
  unfold Math.mulDiv
  simp only [run_bind, run_pure, run_ite, run_throw, fold_nstep]
  rw [hi_word x y hx hy]
  by_cases hlt : x * y < W
  · have h0 : x * y / W = 0 := (Nat.div_eq_zero_iff_lt (by omega)).mpr hlt
    simp [h0, hlt, divc]
  · have h0 : x * y / W ≠ 0 := by
      rw [Ne, Nat.div_eq_zero_iff_lt (by omega)]; exact hlt
    simp [h0, hlt]

/-- Complete specification: on 256-bit inputs `Math.mulDiv` returns `⌊x * y / d⌋` with the
world unchanged when `d ≠ 0` and the quotient fits, and otherwise reverts with the Solidity's
reason. -/
theorem mulDiv_spec (x y d : Nat) (env : Env) (s : σ) (hx : x < W) (hy : y < W) (hdW : d < W) :
    Math.mulDiv ext x y d env s
      = if d = 0 then .error (if x * y < W then panic "0x12" else ⟨"MathOverflowedMulDiv"⟩)
        else if x * y / d < W then .ok (x * y / d, s)
        else .error ⟨"MathOverflowedMulDiv"⟩ := by
  by_cases hd : d = 0
  · subst hd; rw [ite_pos' rfl]; exact mulDiv_zero ext x y env s hx hy
  · rw [ite_neg' hd]
    by_cases hq : x * y / d < W
    · rw [ite_pos' hq]; exact mulDiv_ok ext x y d env s hx hy (by omega) hdW hq
    · rw [ite_neg' hq]; exact mulDiv_overflow ext x y d env s hx hy (by omega) (by omega)

/-- For a nonzero denominator, `Math.mulDiv` is exactly the prelude's floor `mulDivFloor`
(same result, same world, same revert). -/
theorem mulDiv_eq_mulDivFloor (x y d : Nat) (env : Env) (s : σ) (hx : x < W) (hy : y < W)
    (hdW : d < W) (hd : d ≠ 0) :
    Math.mulDiv ext x y d env s = mulDivFloor (σ := σ) x y d env s := by
  rw [mulDiv_spec ext x y d env s hx hy hdW, ite_neg' hd]
  unfold mulDivFloor
  rw [W_eq]
  by_cases hq : x * y / d < 2^256 <;> simp [hd]

end AsyncSwap.Swarm.MulDiv
