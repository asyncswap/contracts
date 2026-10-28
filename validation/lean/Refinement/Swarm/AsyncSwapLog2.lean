import Generated.AsyncSwap
import Refinement.Monad
open FormalAst Refinement

/-!
# `Math.log2` (src/AsyncSwap.sol, OpenZeppelin `Math.log2`)

`log2(value)` is an unrolled binary search: for `k = 128, 64, …, 1` it shifts `value` right by `k`
and adds `k` to `result` whenever `value >> k > 0`, all `unchecked`.

* `log2_run`: for every environment and state it succeeds, returns `log2Pure value` and leaves the
  state unchanged (no guards, empty footprint).
* `log2_eq`: for `value < 2^256`, the result is `Nat.log2 value` (`⌊log₂ value⌋`, `0` for `0`); the
  unchecked additions never wrap.
-/

namespace AsyncSwap.Swarm.Log2

/-- One stage of the binary search, followed by the rest `g`. -/
def stage (k : Nat) (g : Nat → Nat → Nat) (v res : Nat) : Nat :=
  if (decide (v >>> k > 0)) then g (v >>> k) (addw 256 res k) else g v res

def G1 (v res : Nat) : Nat := if (decide (v >>> 1 > 0)) then addw 256 res 1 else res
def G2 := stage 2 G1
def G4 := stage 4 G2
def G8 := stage 8 G4
def G16 := stage 16 G8
def G32 := stage 32 G16
def G64 := stage 64 G32
def G128 := stage 128 G64

/-- The pure value `Math.log2` computes. -/
def log2Pure (value : Nat) : Nat := G128 value 0

theorem ite_ok_pair {σ : Type} (c : Prop) [Decidable c] (a b : Nat) (s : σ) :
    (if c then (Except.ok (a, s) : Except Revert (Nat × σ)) else .ok (b, s))
      = .ok (if c then a else b, s) := by
  split <;> rfl

/-- `Math.log2` never reverts, writes nothing, and returns `log2Pure value`. -/
theorem log2_run {σ : Type} (ext : Ext σ) (value : Nat) (r : Env) (s : σ) :
    Math.log2 ext value r s = .ok (log2Pure value, s) := by
  simp only [Math.log2, log2Pure, G128, G64, G32, G16, G8, G4, G2, G1, stage,
    run_ite, run_pure, ite_ok_pair]

/-! ## The value -/

theorem log2_shift (v k : Nat) (h : 2 ^ k ≤ v) : Nat.log2 v = k + Nat.log2 (v >>> k) := by
  rw [Nat.shiftRight_eq_div_pow]
  have hk : 0 < 2 ^ k := Nat.two_pow_pos k
  have hq : v / 2 ^ k ≠ 0 := by
    have : 1 ≤ v / 2 ^ k := (Nat.le_div_iff_mul_le hk).2 (by simpa using h)
    omega
  have hv : v ≠ 0 := by omega
  apply Nat.le_antisymm
  · -- log2 v < k + log2 q + 1  ⇔  v < 2^(k + log2 q + 1)
    have h1 := (Nat.log2_lt hq (k := Nat.log2 (v / 2 ^ k) + 1)).1 (Nat.lt_succ_self _)
    have h2 : v < 2 ^ (k + (Nat.log2 (v / 2 ^ k) + 1)) := by
      rw [Nat.pow_add, Nat.mul_comm]
      exact (Nat.div_lt_iff_lt_mul hk).1 h1
    have := (Nat.log2_lt hv).2 h2
    omega
  · -- 2^(k + log2 q) ≤ v
    have h1 := (Nat.le_log2 hq (k := Nat.log2 (v / 2 ^ k))).1 (Nat.le_refl _)
    have h2 : 2 ^ (k + Nat.log2 (v / 2 ^ k)) ≤ v := by
      rw [Nat.pow_add, Nat.mul_comm]
      exact (Nat.le_div_iff_mul_le hk).1 h1
    exact (Nat.le_log2 hv).2 h2

/-- `g` computes `res + log2 v` on its domain. -/
def Spec (k : Nat) (g : Nat → Nat → Nat) : Prop :=
  ∀ v res, 1 ≤ v → v < 2 ^ k → res + k ≤ 256 → g v res = res + Nat.log2 v

theorem spec_G1 : Spec 2 G1 := by
  intro v res h1 h2 h3
  have h2' : v < 4 := h2
  have hv : v = 1 ∨ v = 2 ∨ v = 3 := by omega
  rcases hv with rfl | rfl | rfl <;>
    simp [G1, addw, Nat.mod_eq_of_lt (show res + 1 < 2 ^ 256 by omega)] <;> decide

theorem spec_stage (k : Nat) (g : Nat → Nat → Nat) (hg : Spec k g) : Spec (k + k) (stage k g) := by
  intro v res h1 h2 h3
  unfold stage
  have hk : 0 < 2 ^ k := Nat.two_pow_pos k
  by_cases hs : v >>> k > 0
  · simp only [hs, decide_true, ite_true]
    have hge : 2 ^ k ≤ v := by
      rw [Nat.shiftRight_eq_div_pow] at hs
      have := (Nat.le_div_iff_mul_le hk).1 hs
      omega
    have hlt : v >>> k < 2 ^ k := by
      rw [Nat.shiftRight_eq_div_pow]
      apply (Nat.div_lt_iff_lt_mul hk).2
      rw [← Nat.pow_add]; exact h2
    have hadd : addw 256 res k = res + k := by
      unfold addw; apply Nat.mod_eq_of_lt
      have : (256 : Nat) < 2 ^ 256 := by decide
      omega
    rw [hadd, hg _ _ hs hlt (by omega), log2_shift v k hge]
    omega
  · simp only [hs, decide_false]
    have hlt : v < 2 ^ k := by
      apply Nat.lt_of_not_le
      intro hge
      apply hs
      rw [Nat.shiftRight_eq_div_pow]
      exact (Nat.le_div_iff_mul_le hk).2 (by simpa using hge)
    exact hg _ _ h1 hlt (by omega)

theorem spec_G128 : Spec 256 G128 :=
  spec_stage 128 _ (spec_stage 64 _ (spec_stage 32 _ (spec_stage 16 _
    (spec_stage 8 _ (spec_stage 4 _ (spec_stage 2 _ spec_G1))))))

/-- For every word `value`, `Math.log2` returns `⌊log₂ value⌋` (and `0` for `0`), never reverts and
leaves the state unchanged. -/
theorem log2_eq {σ : Type} (ext : Ext σ) (value : Nat) (hv : value < 2 ^ 256) (r : Env) (s : σ) :
    Math.log2 ext value r s = .ok (Nat.log2 value, s) := by
  rw [log2_run]
  by_cases h0 : value = 0
  · subst h0; rfl
  · have := spec_G128 value 0 (by omega) hv (by decide)
    simp only [log2Pure, this, Nat.zero_add]

end AsyncSwap.Swarm.Log2
