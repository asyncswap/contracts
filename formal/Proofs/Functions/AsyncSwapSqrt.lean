import Specs.AsyncSwap
import Proofs.Monad
import Proofs.Functions.AsyncSwapLog2
import Proofs.Functions.AsyncSwapMin

open FormalAst Refinement

/-!
# `Math.sqrt` (src/AsyncSwap.sol, OpenZeppelin `Math.sqrt`)

`sqrt(a)`: `0` for `a = 0`; otherwise `result = 1 << (log2(a) >> 1)`, seven unchecked Newton steps
`result = (result + a / result) >> 1`, and `min(result, a / result)`. No guards, empty footprint;
the only possible revert is a division by a zero iterate (panic `0x12`), which never happens.

* `sqrt_run`: for every word `a`, it succeeds, leaves the state unchanged and returns `sqrtPure a`.
* `sqrt_le`: the result `x` satisfies `x * x ≤ a`.

Invariant on every iterate `r` after the first step: `a < (r+1)²` (i.e. `⌊√a⌋ ≤ r`) and `r < 2^130`.
-/

namespace AsyncSwap.Swarm.Sqrt

/-- The initial estimate `2 ^ (⌊log₂ a⌋ / 2)`. -/
def R0 (a : Nat) : Nat := 2 ^ (Nat.log2 a / 2)

/-- One unchecked Newton step, exactly as the model computes it. -/
def step (a r : Nat) : Nat := addw 256 r (a / r) >>> 1

/-- The seventh iterate. -/
def r7 (a : Nat) : Nat :=
  step a (step a (step a (step a (step a (step a (step a (R0 a)))))))

/-- The pure value `Math.sqrt` computes. -/
def sqrtPure (a : Nat) : Nat := if a = 0 then 0 else min (r7 a) (a / r7 a)

theorem amgm_aux (x d : Nat) : 4 * (x * (x + d)) ≤ (x + (x + d)) * (x + (x + d)) := by
  simp only [Nat.add_mul, Nat.mul_add, Nat.mul_comm d x]
  omega

theorem amgm (x y : Nat) : 4 * (x * y) ≤ (x + y) * (x + y) := by
  rcases Nat.le_total x y with h | h
  · obtain ⟨d, rfl⟩ := Nat.exists_eq_add_of_le h
    exact amgm_aux x d
  · obtain ⟨d, rfl⟩ := Nat.exists_eq_add_of_le h
    have := amgm_aux y d
    rw [Nat.mul_comm (y + d) y, Nat.add_comm (y + d) y]
    exact this

theorem sq_succ (u : Nat) : (u + 1) * (u + 1) = u * u + 2 * u + 1 := by
  simp only [Nat.add_mul, Nat.mul_add, Nat.mul_one, Nat.one_mul]
  omega

theorem sq_two (u : Nat) : (2 * u) * (2 * u) = 4 * (u * u) := by
  rw [Nat.mul_mul_mul_comm]

theorem step_eq (a r : Nat) (h : r + a / r < 2 ^ 256) : step a r = (r + a / r) / 2 := by
  unfold step addw
  rw [Nat.mod_eq_of_lt h, Nat.shiftRight_eq_div_pow, Nat.pow_one]

/-- Floor AM–GM: from any positive estimate, one Newton step `t` has `a < (t+1)²`. -/
theorem lower (a r : Nat) (hr : 0 < r) :
    a < ((r + a / r) / 2 + 1) * ((r + a / r) / 2 + 1) := by
  have h1 := Nat.div_add_mod a r
  have h2 := Nat.mod_lt a hr
  generalize a / r = q at h1 ⊢
  have hlt : a < r * (q + 1) := by rw [Nat.mul_succ]; omega
  have h3 := amgm r (q + 1)
  have ht : r + (q + 1) ≤ 2 * ((r + q) / 2 + 1) := by omega
  have h4 := Nat.mul_le_mul ht ht
  rw [sq_two] at h4
  omega

theorem ne_of_inv (a x : Nat) (ha1 : 0 < a) (h : a < (x + 1) * (x + 1)) : x ≠ 0 := by
  intro hx; subst hx; simp at h; omega

/-- The invariant `a < (r+1)² ∧ r < 2^130` is preserved by a step, and the step does not wrap. -/
theorem step_inv (a r : Nat) (ha1 : 0 < a) (ha : a < 2 ^ 256)
    (h1 : a < (r + 1) * (r + 1)) (h2 : r < 2 ^ 130) :
    a < (step a r + 1) * (step a r + 1) ∧ step a r < 2 ^ 130 := by
  have hr : 0 < r := Nat.pos_of_ne_zero (ne_of_inv a r ha1 h1)
  have hq : a / r < r + 3 := by
    rw [Nat.div_lt_iff_lt_mul hr]
    rw [sq_succ] at h1
    simp only [Nat.add_mul]
    omega
  have hA : 2 * 2 ^ 130 + 3 < (2 : Nat) ^ 256 := by decide
  have hsum : r + a / r < 2 ^ 256 := by omega
  rw [step_eq a r hsum]
  refine ⟨lower a r hr, ?_⟩
  by_cases hc : a < r * r
  · have : a / r < r := (Nat.div_lt_iff_lt_mul hr).2 hc
    omega
  · have hr128 : r < 2 ^ 128 := by
      apply Nat.lt_of_not_le
      intro hge
      have := Nat.mul_le_mul hge hge
      have hP : (2 : Nat) ^ 128 * 2 ^ 128 = 2 ^ 256 := by decide
      omega
    have hB : (2 : Nat) ^ 128 + 1 < 2 ^ 130 := by decide
    omega

theorem R0_pos (a : Nat) : 0 < R0 a := Nat.two_pow_pos _

theorem shlw_R0 (a : Nat) (ha1 : 0 < a) (ha : a < 2 ^ 256) :
    shlw 256 1 (Nat.log2 a >>> 1) = R0 a := by
  have he : Nat.log2 a < 256 := (Nat.log2_lt (by omega)).2 ha
  unfold shlw R0
  rw [Nat.shiftLeft_eq, Nat.one_mul, Nat.shiftRight_eq_div_pow, Nat.pow_one]
  exact Nat.mod_eq_of_lt (Nat.pow_lt_pow_right (by decide) (by omega))

/-- The first step from `R0 a` does not wrap and enters the invariant. -/
theorem init_inv (a : Nat) (ha1 : 0 < a) (ha : a < 2 ^ 256) :
    a < (step a (R0 a) + 1) * (step a (R0 a) + 1) ∧ step a (R0 a) < 2 ^ 130 := by
  have hne : a ≠ 0 := by omega
  have he : Nat.log2 a < 256 := (Nat.log2_lt hne).2 ha
  have hR := R0_pos a
  have hRle : R0 a ≤ 2 ^ 127 := Nat.pow_le_pow_right (by decide) (by omega)
  have hlt : a < 2 ^ (Nat.log2 a + 1) := (Nat.log2_lt hne).1 (Nat.lt_succ_self _)
  have hpow : 2 ^ (Nat.log2 a + 1) ≤ 2 ^ (Nat.log2 a / 2 + Nat.log2 a / 2 + 2) :=
    Nat.pow_le_pow_right (by decide) (by omega)
  have hsq : (2 : Nat) ^ (Nat.log2 a / 2 + Nat.log2 a / 2 + 2) = 4 * R0 a * R0 a := by
    unfold R0
    rw [Nat.pow_add, Nat.pow_add]
    generalize 2 ^ (Nat.log2 a / 2) = u
    rw [show (2 : Nat) ^ 2 = 4 from rfl, Nat.mul_comm (u * u) 4, Nat.mul_assoc]
  have hq : a / R0 a < 4 * R0 a := by
    rw [Nat.div_lt_iff_lt_mul hR]; omega
  have hA : 5 * 2 ^ 127 < (2 : Nat) ^ 256 := by decide
  have hB : 5 * 2 ^ 127 < 2 * (2 : Nat) ^ 130 := by decide
  have hsum : R0 a + a / R0 a < 2 ^ 256 := by omega
  rw [step_eq a _ hsum]
  exact ⟨lower a _ hR, by omega⟩

theorem divc_run {σ : Type} (a b : Nat) (hb : b ≠ 0) (r : Env) (s : σ) :
    (divc a b : M σ Nat) r s = .ok (a / b, s) := by
  simp [divc, hb]

/-- For every word `a`, `Math.sqrt` never reverts, leaves the state unchanged and returns
`sqrtPure a`: `0` for `a = 0`, else `min(r₇, a / r₇)` with `r₇` the seventh Newton iterate. -/
theorem sqrt_run {σ : Type} (ext : Ext σ) (a : Nat) (ha : a < 2 ^ 256) (r : Env) (s : σ) :
    Math.sqrt ext a r s = .ok (sqrtPure a, s) := by
  by_cases h0 : a = 0
  · subst h0; simp [Math.sqrt, sqrtPure]
  have ha1 : 0 < a := Nat.pos_of_ne_zero h0
  have J1 := init_inv a ha1 ha
  have J2 := step_inv a _ ha1 ha J1.1 J1.2
  have J3 := step_inv a _ ha1 ha J2.1 J2.2
  have J4 := step_inv a _ ha1 ha J3.1 J3.2
  have J5 := step_inv a _ ha1 ha J4.1 J4.2
  have J6 := step_inv a _ ha1 ha J5.1 J5.2
  have J7 := step_inv a _ ha1 ha J6.1 J6.2
  have hfold : ∀ x, addw 256 x (a / x) >>> 1 = step a x := fun _ => rfl
  simp only [Math.sqrt, run_bind, Log2.log2_eq ext a ha,
    shlw_R0 a ha1 ha, beq_iff_eq, h0, ↓reduceIte]
  rw [divc_run a _ (Nat.pos_iff_ne_zero.1 (R0_pos a))]
  simp only [hfold]
  rw [divc_run a _ (ne_of_inv a _ ha1 J1.1)]
  simp only [hfold]
  rw [divc_run a _ (ne_of_inv a _ ha1 J2.1)]
  simp only [hfold]
  rw [divc_run a _ (ne_of_inv a _ ha1 J3.1)]
  simp only [hfold]
  rw [divc_run a _ (ne_of_inv a _ ha1 J4.1)]
  simp only [hfold]
  rw [divc_run a _ (ne_of_inv a _ ha1 J5.1)]
  simp only [hfold]
  rw [divc_run a _ (ne_of_inv a _ ha1 J6.1)]
  simp only [hfold]
  rw [divc_run a _ (ne_of_inv a _ ha1 J7.1)]
  simp only [Min.min_run, sqrtPure, h0, ↓reduceIte, r7]

/-- `Math.sqrt` succeeds with the state unchanged, and the value `x` it returns has `x * x ≤ a`
(it never exceeds `⌊√a⌋`). -/
theorem sqrt_le {σ : Type} (ext : Ext σ) (a : Nat) (ha : a < 2 ^ 256) (r : Env) (s : σ) :
    ∃ x, Math.sqrt ext a r s = .ok (x, s) ∧ x * x ≤ a := by
  refine ⟨sqrtPure a, sqrt_run ext a ha r s, ?_⟩
  unfold sqrtPure
  split
  · simp
  · have h1 : min (r7 a) (a / r7 a) ≤ r7 a := Nat.min_le_left _ _
    have h2 : min (r7 a) (a / r7 a) ≤ a / r7 a := Nat.min_le_right _ _
    have h3 := Nat.mul_le_mul h1 h2
    have h4 : r7 a * (a / r7 a) ≤ a := Nat.mul_div_le a (r7 a)
    omega

end AsyncSwap.Swarm.Sqrt
