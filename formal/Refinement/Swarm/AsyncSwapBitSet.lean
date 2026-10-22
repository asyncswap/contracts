import Mathlib
import Generated.AsyncSwap
import Refinement.Monad

/-!
# AsyncSwap: `RadixPriceTree._bitSet`

`_bitSet(value, bit)` is pure: it never reverts, leaves storage untouched, and returns
whether bit `bit` of `value` is set (with the `uint128` mask `1 << bit`, which is zero once
`bit ≥ 128`).
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.BitSet

variable {σ : Type} (ext : Ext σ)

/-- Literal semantics: never reverts, storage unchanged, returns `(value & (1 << bit mod 2^128)) ≠ 0`. -/
theorem bitSet_spec (v b : Nat) (env : Env) (w : σ) :
    RadixPriceTree.«_bitSet» ext v b env w = .ok ((v &&& shlw 128 1 b) != 0, w) := by
  simp [RadixPriceTree.«_bitSet», run_pure]

/-- Bit-level meaning: returns `true` iff `bit < 128` and bit `bit` of `value` is set. -/
theorem bitSet_testBit (v b : Nat) (env : Env) (w : σ) :
    RadixPriceTree.«_bitSet» ext v b env w = .ok (decide (b < 128) && v.testBit b, w) := by
  rw [bitSet_spec]
  by_cases hb : b < 128
  · have h1 : shlw 128 1 b = 2 ^ b := by
      unfold shlw
      rw [Nat.one_shiftLeft, Nat.mod_eq_of_lt (Nat.pow_lt_pow_right (by norm_num) hb)]
    rw [h1, Nat.and_two_pow]
    cases v.testBit b <;> simp [hb]
  · have h1 : shlw 128 1 b = 0 := by
      unfold shlw
      rw [Nat.one_shiftLeft]
      exact Nat.mod_eq_zero_of_dvd (Nat.pow_dvd_pow 2 (by omega))
    simp [h1, hb]

/-- It never reverts. -/
theorem bitSet_noRevert (v b : Nat) (env : Env) (w : σ) :
    ∃ r, RadixPriceTree.«_bitSet» ext v b env w = .ok (r, w) :=
  ⟨_, bitSet_spec ext v b env w⟩

end AsyncSwap.Swarm.BitSet
