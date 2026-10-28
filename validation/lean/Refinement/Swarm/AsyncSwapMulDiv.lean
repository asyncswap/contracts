import Generated.AsyncSwap
import Refinement.Monad

/-!
# AsyncSwap: `Math.mulDiv` (OpenZeppelin full-precision `x * y / d`, both overloads)

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

The rounding overload `Math.mulDiv(x, y, d, rounding)` (`Math.mulDiv_11270` in this model) is
the floor, plus one (checked) when `rounding` is odd (`Ceil`, `Expand`) and `x * y % d ≠ 0`.

Core Lean only (no Mathlib): congruences are argued as divisibilities in `Int`, and the
polynomial identities are closed by `grind`'s ring solver.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.MulDiv

variable {σ : Type} (ext : Ext σ)

/-! ## Word arithmetic -/

theorem W_eq : W = 2^256 := rfl
theorem W_pos : 1 < W :=
  Nat.lt_of_lt_of_le (by decide : 1 < 2^1) (Nat.pow_le_pow_right (by decide) (by decide))

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
    have : ynot 0 = W - 1 := by simp [ynot]
    rw [this]; unfold ymulmod; rw [ite_neg' (by omega)]
  rw [h1, mulw_eq]
  generalize x * y = P at hP
  have hdm := Nat.div_add_mod P W
  have hl : P % W < W := Nat.mod_lt _ (by omega)
  have hh : P / W < W - 1 := by
    rw [Nat.div_lt_iff_lt_mul (by omega)]
    have e := Nat.mul_sub_one (W - 1) W
    have : W - 1 ≤ (W - 1) * W := Nat.le_mul_of_pos_right _ (by omega)
    omega
  generalize P / W = h at *
  generalize P % W = l at *
  have e : W * h = (W - 1) * h + h := by
    have := Nat.sub_one_mul W h
    have : h ≤ W * h := Nat.le_mul_of_pos_left _ (by omega)
    omega
  have hm : P % (W - 1) = (h + l) % (W - 1) := by
    rw [← hdm, e, show (W - 1) * h + h + l = (h + l) + (W - 1) * h by omega,
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
  have e : ∀ t, 2 * t / 2 = t := fun t => by omega
  cases i with
  | zero => rw [Nat.testBit_and]; simp [Nat.testBit_zero]
  | succ j =>
    rw [Nat.testBit_and, Nat.testBit_add_one, Nat.testBit_add_one, Nat.testBit_add_one, e, e, e,
      Nat.testBit_and]

theorem lowbit_odd (n d : Nat) (hd : d % 2 = 1) (hn : d < 2^n) : d &&& (2^n - d) = 1 := by
  obtain ⟨m, rfl⟩ : ∃ m, n = m + 1 := by
    rcases n with _ | m
    · rw [Nat.pow_zero] at hn; omega
    · exact ⟨m, rfl⟩
  apply Nat.eq_of_testBit_eq; intro i
  rw [Nat.testBit_and]
  cases i with
  | zero =>
    have : (2^(m+1) - d) % 2 = 1 := by rw [Nat.pow_succ]; omega
    simp [Nat.testBit_zero, hd, this]
  | succ j =>
    rw [Nat.testBit_add_one, Nat.testBit_add_one, Nat.testBit_add_one]
    have h1 : (2^(m+1) - d) / 2 = 2^m - (d / 2 + 1) := by rw [Nat.pow_succ]; omega
    have h2 : d / 2 < 2^m := by rw [Nat.pow_succ] at hn; omega
    rw [h1, Nat.testBit_two_pow_sub_succ h2]
    cases (d / 2).testBit j <;> simp

theorem lowbit (k : Nat) :
    ∀ n o, o % 2 = 1 → 2^k * o < 2^n → (2^k * o) &&& (2^n - 2^k * o) = 2^k := by
  induction k with
  | zero =>
    intro n o ho hn
    simp only [Nat.pow_zero, Nat.one_mul] at hn ⊢
    exact lowbit_odd n o ho hn
  | succ k ih =>
    intro n o ho hn
    have h1 : 2^(k+1) * o = 2 * (2^k * o) := by
      rw [Nat.pow_succ, Nat.mul_comm (2^k) 2, Nat.mul_assoc]
    have hpos : 0 < 2^k * o := Nat.mul_pos (Nat.two_pow_pos k) (by omega)
    obtain ⟨m, rfl⟩ : ∃ m, n = m + 1 := by
      rcases n with _ | m
      · rw [Nat.pow_zero] at hn; omega
      · exact ⟨m, rfl⟩
    have h3 : 2^k * o < 2^m := by rw [h1, Nat.pow_succ] at hn; omega
    have h2 : 2^(m+1) - 2 * (2^k * o) = 2 * (2^m - 2^k * o) := by rw [Nat.pow_succ]; omega
    rw [h1, h2, and_double, ih m o ho h3, Nat.pow_succ, Nat.mul_comm]

/-- Every positive `d` is `2^k * o` with `o` odd. -/
theorem two_pow_odd_aux (n : Nat) : ∀ d, 0 < d → d ≤ n → ∃ k o, o % 2 = 1 ∧ d = 2^k * o := by
  induction n with
  | zero => intro d hd hn; omega
  | succ n ih =>
    intro d hd hn
    by_cases h : d % 2 = 1
    · exact ⟨0, d, h, by rw [Nat.pow_zero, Nat.one_mul]⟩
    · obtain ⟨k, o, ho, he⟩ := ih (d / 2) (by omega) (by omega)
      exact ⟨k + 1, o, ho, by rw [Nat.pow_succ, Nat.mul_comm (2^k) 2, Nat.mul_assoc, ← he]; omega⟩

/-! ## Stage 4: the Newton–Raphson inverse modulo `2^256` -/

/-- Truncating to a word doesn't change a value modulo any `N ∣ 2^256`. -/
theorem dvd_modW {N : Nat} (hN : N ∣ W) (e : Nat) : (N : Int) ∣ ((e % W : Nat) : Int) - (e : Int) := by
  have h := Nat.div_add_mod e W
  have hW : (N : Int) ∣ (W : Int) := Int.natCast_dvd_natCast.mpr hN
  generalize e / W = q at h
  generalize e % W = r at h ⊢
  have h' : (W : Int) * (q : Int) + (r : Int) = (e : Int) := by exact_mod_cast h
  have e2 : (r : Int) - e = -((W : Int) * (q : Int)) := by omega
  rw [e2, Int.dvd_neg]; exact Int.dvd_trans hW (Int.dvd_mul_right _ _)

/-- The Newton identity with every truncation error made explicit: if `n ≡ a·v`, `v ≡ 2 - u`,
`W ≡ 0`, `u ≡ d·a` modulo `N = P²` and `d·a = P·t + 1`, then `d·n - 1` is an explicit multiple
of `N`, because `d·a·(2 - d·a) - 1 = -(d·a - 1)² = -P²·t²`. -/
theorem ring_id (d a n v u W N P t c1 c2 c3 c4 : Int)
    (h1 : n - a * v = N * c1) (h2 : v - (2 + W - u) = N * c2) (h3 : W = N * c3)
    (h4 : u - d * a = N * c4) (h5 : d * a = P * t + 1) (h6 : N = P * P) :
    d * n - 1 = N * (d * c1 + d * a * c2 + d * a * c3 - d * a * c4 - t * t) := by
  have e1 : d * n - 1 = d * (n - a * v) + (d * a) * (v - (2 + W - u)) + (d * a) * W
      - (d * a) * (u - d * a) - (d * a - 1) * (d * a - 1) := by grind
  have e2 : d * a - 1 = P * t := by omega
  rw [e1, h1, h2, h3, h4, e2, h6]
  grind

/-- One Newton–Raphson step, as the model writes it. -/
def nstep (d a : Nat) : Nat := mulw 256 a (subw 256 2 (mulw 256 d a))

theorem fold_nstep (d a : Nat) : mulw 256 a (subw 256 2 (mulw 256 d a)) = nstep d a := rfl

/-- Each step doubles the number of correct low bits of the inverse:
`d·a ≡ 1 (mod 2^m)` implies `d·a·(2 - d·a) ≡ 1 (mod 2^(2m))`. -/
theorem nstep_spec (m d a : Nat) (hm : 1 ≤ m) (hm2 : 2 * m ≤ 256) (h : d * a % 2^m = 1) :
    d * nstep d a % 2^(2*m) = 1 := by
  have hN : 2^(2*m) ∣ W := Nat.pow_dvd_pow 2 hm2
  have h1N : 1 < 2^(2*m) :=
    Nat.lt_of_lt_of_le (by decide : 1 < 2^1) (Nat.pow_le_pow_right (by decide) (by omega))
  have hW := W_pos
  have hu : ((2^(2*m) : Nat) : Int) ∣ ((mulw 256 d a : Nat) : Int) - ((d * a : Nat) : Int) :=
    dvd_modW hN (d * a)
  have huW : mulw 256 d a < W := Nat.mod_lt _ (by omega)
  have hv_eq : subw 256 2 (mulw 256 d a) = (2 + W - mulw 256 d a) % W := by
    unfold subw; rw [← W_eq, Nat.mod_eq_of_lt huW]
  have hv : ((2^(2*m) : Nat) : Int) ∣ ((subw 256 2 (mulw 256 d a) : Nat) : Int)
      - (2 + (W : Int) - ((mulw 256 d a : Nat) : Int)) := by
    have := dvd_modW hN (2 + W - mulw 256 d a)
    rw [hv_eq]
    have hc : ((2 + W - mulw 256 d a : Nat) : Int) = 2 + (W : Int) - ((mulw 256 d a : Nat) : Int) := by
      omega
    rw [← hc]; exact this
  have hn : ((2^(2*m) : Nat) : Int) ∣ ((nstep d a : Nat) : Int)
      - ((a * subw 256 2 (mulw 256 d a) : Nat) : Int) := dvd_modW hN _
  have hWd : ((2^(2*m) : Nat) : Int) ∣ (W : Int) := Int.natCast_dvd_natCast.mpr hN
  have hda : d * a = 2^m * (d * a / 2^m) + 1 := by
    have := Nat.div_add_mod (d * a) (2^m); omega
  have hpp : 2^(2*m) = 2^m * 2^m := by rw [Nat.two_mul, Nat.pow_add]
  generalize nstep d a = n at hn ⊢
  generalize subw 256 2 (mulw 256 d a) = v at hv hn
  generalize mulw 256 d a = u at hu hv
  generalize d * a / 2^m = t at hda
  generalize 2^(2*m) = N at hu hv hn hWd hpp h1N ⊢
  generalize 2^m = P at hda hpp
  have hda' : (d : Int) * (a : Int) = (P : Int) * (t : Int) + 1 := by exact_mod_cast hda
  have hpp' : (N : Int) = (P : Int) * (P : Int) := by exact_mod_cast hpp
  rw [Int.natCast_mul] at hu hn
  obtain ⟨c1, h1⟩ := hn
  obtain ⟨c2, h2⟩ := hv
  obtain ⟨c3, h3⟩ := hWd
  obtain ⟨c4, h4⟩ := hu
  obtain ⟨c, hc⟩ : ∃ c : Int, (d : Int) * (n : Int) - 1 = (N : Int) * c :=
    ⟨_, ring_id _ _ _ _ _ _ _ _ _ c1 c2 c3 c4 h1 h2 h3 h4 hda' hpp'⟩
  have hI : ((d * n : Nat) : Int) % (N : Int) = 1 := by
    rw [Int.natCast_mul, show (d : Int) * (n : Int) = 1 + (N : Int) * c by omega,
      Int.add_mul_emod_self_left, Int.emod_eq_of_lt (by decide) (by omega)]
  exact_mod_cast hI

/-- The seed `(3 * d) ^ 2` is an inverse of an odd `d` modulo `2^4`. -/
theorem init_spec (o : Nat) (ho : o % 2 = 1) : o * (mulw 256 3 o ^^^ 2) % 16 = 1 := by
  have h16 : (16 : Nat) ∣ 2^256 := Nat.pow_dvd_pow 2 (by decide : 4 ≤ 256)
  have e1 : mulw 256 3 o % 16 = 3 * (o % 16) % 16 := by
    unfold mulw; rw [Nat.mod_mod_of_dvd _ h16]; omega
  have e2 : (mulw 256 3 o ^^^ 2) % 16 = (3 * (o % 16) % 16) ^^^ 2 := by
    have := @Nat.xor_mod_two_pow (mulw 256 3 o) 2 4
    simp only [Nat.reducePow, Nat.reduceMod] at this
    rw [this, e1]
  rw [Nat.mul_mod, e2]
  have hlt : o % 16 < 16 := Nat.mod_lt _ (by decide)
  have ho' : o % 16 % 2 = 1 := by omega
  generalize o % 16 = j at hlt ho' ⊢
  have key : ∀ j, j < 16 → j % 2 = 1 → j * ((3 * j % 16) ^^^ 2) % 16 = 1 := by decide
  exact key j hlt ho'

/-- Six steps give the inverse modulo `2^256`. -/
theorem inv_spec (o : Nat) (ho : o % 2 = 1) :
    o * nstep o (nstep o (nstep o (nstep o (nstep o (nstep o (mulw 256 3 o ^^^ 2)))))) % W
      = 1 := by
  have h4 : o * (mulw 256 3 o ^^^ 2) % 2^4 = 1 := init_spec o ho
  have h8 := nstep_spec 4 o _ (by decide) (by decide) h4
  have h16 := nstep_spec 8 o _ (by decide) (by decide) h8
  have h32 := nstep_spec 16 o _ (by decide) (by decide) h16
  have h64 := nstep_spec 32 o _ (by decide) (by decide) h32
  have h128 := nstep_spec 64 o _ (by decide) (by decide) h64
  exact nstep_spec 128 o _ (by decide) (by decide) h128

/-! ## Stage 5: shifting the numerator and multiplying by the inverse -/

theorem final (P d k o p0 p1 inv : Nat) (hk : k < 256) (hd : d = 2^k * o)
    (hsub : p1 * W + p0 = P - P % d) (hp0 : p0 < W) (hinv : o * inv % W = 1) (hq : P / d < W) :
    mulw 256 (p0 / 2^k ||| mulw 256 p1 (2^(256-k) % W)) inv = P / d := by
  have hW : W = 2^k * 2^(256-k) := by rw [W_eq, ← Nat.pow_add]; congr 1; omega
  have hk0 : 0 < 2^k := Nat.two_pow_pos k
  have e1' : mulw 256 p1 (2^(256-k) % W) = (p1 % 2^k) * 2^(256-k) := by
    rw [mulw_eq, Nat.mul_mod_mod, hW, Nat.mul_mod_mul_right]
  have e2 : p0 / 2^k < 2^(256-k) := by
    rw [Nat.div_lt_iff_lt_mul hk0]; rw [hW] at hp0
    have := Nat.mul_comm (2^k) (2^(256-k)); omega
  have e3 : p0 / 2^k ||| (p1 % 2^k) * 2^(256-k) = (p1 % 2^k) * 2^(256-k) + p0 / 2^k := by
    rw [Nat.or_comm, ← Nat.shiftLeft_eq, Nat.shiftLeft_add_eq_or_of_lt e2]
  have hQ : (P - P % d) / 2^k = o * (P / d) := by
    have := Nat.div_add_mod P d
    rw [show P - P % d = 2^k * (o * (P / d)) by rw [← Nat.mul_assoc, ← hd]; omega,
      Nat.mul_div_cancel_left _ hk0]
  have hQ2 : (P - P % d) / 2^k = p1 * 2^(256-k) + p0 / 2^k := by
    rw [← hsub, hW, Nat.mul_left_comm, Nat.mul_add_div hk0]
  have hp1 : p1 * 2^(256-k) = (p1 % 2^k) * 2^(256-k) + (p1 / 2^k) * W := by
    rw [hW, ← Nat.mul_assoc, ← Nat.add_mul]
    congr 1
    have := Nat.div_add_mod p1 (2^k)
    have := Nat.mul_comm (p1 / 2^k) (2^k)
    omega
  have hoq : o * (P / d) = ((p1 % 2^k) * 2^(256-k) + p0 / 2^k) + (p1 / 2^k) * W := by
    omega
  have hA : (o * (P / d)) % W = ((p1 % 2^k) * 2^(256-k) + p0 / 2^k) % W := by
    rw [hoq, Nat.add_mul_mod_self_right]
  rw [e1', e3, mulw_eq, Nat.mul_mod, ← hA, ← Nat.mul_mod, Nat.mul_comm o (P / d), Nat.mul_assoc,
    Nat.mul_mod, hinv, Nat.mul_one, Nat.mod_mod, Nat.mod_eq_of_lt hq]

/-! ## The function -/

/-- Success: for 256-bit `x`, `y` and a nonzero 256-bit `d` whose quotient `x * y / d` fits 256
bits, `Math.mulDiv` returns exactly `⌊x * y / d⌋` and leaves the world unchanged. -/
theorem mulDiv_ok (x y d : Nat) (env : Env) (s : σ) (hx : x < W) (hy : y < W) (hd : 0 < d)
    (hdW : d < W) (hq : x * y / d < W) :
    Math.mulDiv ext x y d env s = .ok (x * y / d, s) := by
  have hW := W_pos
  have hd0 : d ≠ 0 := by omega
  unfold Math.mulDiv
  simp only [run_bind, run_pure, run_ite, run_throw, fold_nstep]
  rw [hi_word x y hx hy, mulw_eq x y]
  by_cases h0 : x * y / W = 0
  · have hlt : x * y < W := by rwa [Nat.div_eq_zero_iff_lt (by omega)] at h0
    simp [h0, divc, hd0, Nat.mod_eq_of_lt hlt]
  · have hlt : x * y / W < d := by
      rw [Nat.div_lt_iff_lt_mul (by omega)]
      rw [Nat.div_lt_iff_lt_mul hd] at hq
      have := Nat.mul_comm W d; omega
    have hPW : x * y / W < W := by omega
    have h1 : 1 ≤ x * y / W := Nat.one_le_iff_ne_zero.mpr h0
    simp only [h0, beq_iff_eq, decide_eq_true_eq, Nat.not_le.mpr hlt, ↓reduceIte]
    obtain ⟨k, o, ho, hdk⟩ := two_pow_odd_aux d d hd (Nat.le_refl d)
    have hk0 : 0 < 2^k := Nat.two_pow_pos k
    have hk : k < 256 := by
      apply Nat.lt_of_not_le; intro hk
      have : 2^256 ≤ 2^k := Nat.pow_le_pow_right (by decide) hk
      have : 2^k ≤ 2^k * o := Nat.le_mul_of_pos_right _ (by omega)
      rw [W_eq] at hdW; omega
    have hT : d &&& subw 256 0 d = 2^k := by
      have hs : subw 256 0 d = 2^256 - d := by
        unfold subw; rw [W_eq] at hdW
        rw [Nat.mod_eq_of_lt hdW, Nat.mod_eq_of_lt (by omega)]
        all_goals omega
      rw [hs, hdk]; exact lowbit k 256 o ho (by rw [← hdk, ← W_eq]; exact hdW)
    have hdo : ydiv d (2^k) = o := by
      rw [ydiv_pos _ _ (by omega), hdk, Nat.mul_div_cancel_left _ hk0]
    have hWk : W = 2^k * 2^(256-k) := by rw [W_eq, ← Nat.pow_add]; congr 1; omega
    have htw : yadd (ydiv (ysub 0 (2^k)) (2^k)) 1 = 2^(256-k) % W := by
      have hkW : 2^k < W := by rw [W_eq]; exact Nat.pow_lt_pow_right (by decide) hk
      have h1 : 1 ≤ 2^(256-k) := Nat.one_le_two_pow
      rw [ysub_lt 0 _ hkW hk0, ydiv_pos _ _ (by omega), Nat.zero_add,
        show W - 2^k = 2^k * (2^(256-k) - 1) by rw [hWk, Nat.mul_sub_one],
        Nat.mul_div_cancel_left _ hk0, yadd, Nat.sub_add_cancel h1]
    have hmm : ymulmod x y d = x * y % d := by simp [ymulmod, hd0]
    rw [hT, hdo, htw, hmm, ydiv_pos _ _ (by omega)]
    have hrW : x * y % d < W := Nat.lt_trans (Nat.mod_lt _ hd) hdW
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
    rw [Nat.le_div_iff_mul_le hd] at hov
    have := Nat.mul_comm W d; omega
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

/-- The prelude's `mulDivFloor`, run, in the shape of `mulDiv_spec`. -/
theorem mulDivFloor_run (x y d : Nat) (env : Env) (s : σ) :
    mulDivFloor (σ := σ) x y d env s
      = if d = 0 then .error (if x * y < W then panic "0x12" else ⟨"MathOverflowedMulDiv"⟩)
        else if x * y / d < W then .ok (x * y / d, s)
        else .error ⟨"MathOverflowedMulDiv"⟩ := by
  have hW := W_pos
  have k : d = 0 ∨ (d ≤ x * y / W ∧ W ≤ x * y / d) ∨ (x * y / W < d ∧ x * y / d < W) := by
    rcases Nat.eq_zero_or_pos d with hd | hd
    · exact Or.inl hd
    · right
      by_cases h : d ≤ x * y / W
      · left; refine ⟨h, ?_⟩
        rw [Nat.le_div_iff_mul_le (by omega)] at h
        rw [Nat.le_div_iff_mul_le hd, Nat.mul_comm W d]; exact h
      · right; refine ⟨Nat.lt_of_not_le h, ?_⟩
        rw [Nat.le_div_iff_mul_le (by omega)] at h
        rw [Nat.div_lt_iff_lt_mul hd, Nat.mul_comm W d]; exact Nat.lt_of_not_le h
  have hle := Nat.div_le_self (x * y) d
  unfold mulDivFloor
  rw [← W_eq]
  generalize x * y / W = H at *
  generalize x * y / d = Q at *
  generalize x * y = P at *
  simp only [run_ite, run_throw, run_pure]
  repeat' split
  all_goals first | rfl | (exfalso; omega)

/-- For a nonzero denominator, `Math.mulDiv` is exactly the prelude's floor `mulDivFloor`. -/
theorem mulDiv_eq_mulDivFloor (x y d : Nat) (env : Env) (s : σ) (hx : x < W) (hy : y < W)
    (hdW : d < W) (hd : d ≠ 0) :
    Math.mulDiv ext x y d env s = mulDivFloor (σ := σ) x y d env s := by
  rw [mulDiv_spec ext x y d env s hx hy hdW, mulDivFloor_run, ite_neg' hd]

/-- On 256-bit inputs, `Math.mulDiv` is exactly the prelude's floor `mulDivFloor` for every
denominator, zero included. -/
theorem mulDiv_eq_mulDivFloor_any (x y d : Nat) (env : Env) (s : σ) (hx : x < W) (hy : y < W)
    (hdW : d < W) :
    Math.mulDiv ext x y d env s = mulDivFloor (σ := σ) x y d env s := by
  rw [mulDiv_spec ext x y d env s hx hy hdW, mulDivFloor_run]

/-! ## The rounding overload `Math.mulDiv(x, y, d, rounding)` -/

theorem addc_W (a : Nat) :
    addc (σ := σ) 256 a 1
      = if a + 1 < W then pure (a + 1) else throw (FormalAst.panic "0x11") := rfl

/-- Complete specification of the rounding overload: it reverts exactly as the floor does
(`d = 0`, or a quotient that doesn't fit 256 bits); otherwise, when `rounding` is odd
(`Ceil`/`Expand`) and `x * y` isn't a multiple of `d`, it returns `⌊x * y / d⌋ + 1`, reverting
with panic `0x11` if that is `2^256`; in every other case it returns `⌊x * y / d⌋`. The world is
unchanged on success. No bound on the inputs is needed. -/
theorem mulDivRound_spec (x y d r : Nat) (env : Env) (s : σ) :
    Math.mulDiv_11270 ext x y d r env s
      = if d = 0 then .error (if x * y < W then panic "0x12" else ⟨"MathOverflowedMulDiv"⟩)
        else if x * y / d < W then
          (if r % 2 = 1 ∧ x * y % d ≠ 0 then
            (if x * y / d + 1 < W then .ok (x * y / d + 1, s) else .error (panic "0x11"))
          else .ok (x * y / d, s))
        else .error ⟨"MathOverflowedMulDiv"⟩ := by
  unfold Math.mulDiv_11270 Math.unsignedRoundsUp
  simp only [addc_W, run_bind, run_pure, run_ite, run_throw, mulDivFloor_run]
  by_cases hd : d = 0
  · simp [hd]
  · by_cases hq : x * y / d < W
    · by_cases hr : r % 2 = 1 <;> by_cases hm : x * y % d = 0 <;>
        by_cases hc : x * y / d + 1 < W <;>
        simp [hd, hq, hr, hm, hc, modc, ymulmod, Nat.pos_iff_ne_zero]
    · simp [hd, hq]

/-- The rounding overload agrees with the prelude's `mulDivRnd` (OpenZeppelin's semantics:
round up for `Ceil` and `Expand`), result, world and revert reason alike. -/
theorem mulDivRound_eq_mulDivRnd (x y d r : Nat) (env : Env) (s : σ) :
    Math.mulDiv_11270 ext x y d r env s = mulDivRnd (σ := σ) x y d r env s := by
  rw [mulDivRound_spec]
  unfold mulDivRnd mulDivCeil
  by_cases hr : r % 2 = 1
  · simp only [hr, ↓reduceIte, addc_W, run_bind, run_ite, run_pure, mulDivFloor_run]
    by_cases hd : d = 0
    · simp [hd]
    · by_cases hq : x * y / d < W
      · by_cases hm : x * y % d = 0 <;> simp [hd, hq, hm]
      · simp [hd, hq]
  · simp only [hr, false_and, ↓reduceIte, mulDivFloor_run]

/-- Rounding down (`rounding` even): with `d ≠ 0` and a quotient that fits, the result is
`⌊x * y / d⌋` and the world is unchanged. -/
theorem mulDivRound_floor (x y d r : Nat) (env : Env) (s : σ) (hr : r % 2 = 0) (hd : d ≠ 0)
    (hq : x * y / d < W) :
    Math.mulDiv_11270 ext x y d r env s = .ok (x * y / d, s) := by
  rw [mulDivRound_spec]; simp [hd, hq, hr]

/-- Rounding up (`rounding` odd): with `d ≠ 0` and `⌈x * y / d⌉ < 2^256`, the result is
`⌈x * y / d⌉ = (x * y + d - 1) / d` and the world is unchanged. -/
theorem mulDivRound_ceil (x y d r : Nat) (env : Env) (s : σ) (hr : r % 2 = 1) (hd : d ≠ 0)
    (hc : (x * y + d - 1) / d < W) :
    Math.mulDiv_11270 ext x y d r env s = .ok ((x * y + d - 1) / d, s) := by
  have hdp : 0 < d := Nat.pos_of_ne_zero hd
  have hdm := Nat.div_add_mod (x * y) d
  have hml := Nat.mod_lt (x * y) hdp
  -- ⌈P / d⌉ = ⌊P / d⌋ + [P % d ≠ 0]
  have hceil : (x * y + d - 1) / d = x * y / d + (if x * y % d = 0 then 0 else 1) := by
    rw [show x * y + d - 1 = (x * y % d + d - 1) + d * (x * y / d) by omega,
      Nat.add_mul_div_left _ _ hdp, Nat.add_comm _ (x * y / d)]
    congr 1
    split
    · exact Nat.div_eq_of_lt (by omega)
    · rw [show x * y % d + d - 1 = (x * y % d - 1) + d * 1 by omega,
        Nat.add_mul_div_left _ _ hdp, Nat.div_eq_of_lt (by omega)]
  rw [hceil] at hc ⊢
  rw [mulDivRound_spec]
  by_cases hm : x * y % d = 0
  · have hq : x * y / d < W := by simpa [hm] using hc
    simp [hd, hq, hm]
  · have hc' : x * y / d + 1 < W := by simpa [hm] using hc
    have hq : x * y / d < W := by omega
    simp [hd, hq, hm, hr, hc']

end AsyncSwap.Swarm.MulDiv
