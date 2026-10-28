import Generated.AsyncSwap
import Refinement.Monad
import Refinement.Swarm.AsyncSwapSqrt
import Refinement.Swarm.AsyncSwapGetTickAtSqrtPrice
import Refinement.Swarm.AsyncSwapTickBounds
open FormalAst Refinement

/-!
# `TickPrice.floorTick` (src/AsyncSwap.sol)

`floorTick(num, den)`: the largest tick whose price is at most `num / den`, computed as
`sqrtPriceX96 = sqrt(num · 2^192 / den)` when `num / den < 2^64`, `MAX_TICK` when
`num / den ≥ 2^128`, else `sqrt(num · 2^128 / den) << 32`; then clamped to `[MIN_TICK, MAX_TICK]`
or handed to `TickMath.getTickAtSqrtPrice`.

No guards of its own, empty footprint, no external calls. Its only revert of its own is the
division `num / den` by `den = 0` (panic `0x12`): both `mulDiv` calls provably never overflow and
`Math.sqrt` never reverts.

* `floorTick_eq`: for `den ≠ 0` the generated def (join points and all) is the clean program
  "branch on `num / den`, `mulDiv`, `sqrt`, `tail`".
* `floorTick_run`: the exact run, by cases on `den = 0`, `num / den < 2^64`, `num / den ≥ 2^128`.
* `floorTick_no_write`: every successful run returns the state unchanged.
* `sqrtPure_lt`, `shlw_sqrt_no_wrap`, `floorTick_mid_exact`: the sqrt of a word is below `2^128`,
  so the middle branch's `<< 32` never wraps: the price handed on is exactly
  `sqrt(num · 2^128 / den) · 2^32 < 2^160`.
* `floorTick_dispatch`: for `den ≠ 0` the run is `MIN_TICK`, `MAX_TICK` (state unchanged), or
  exactly `getTickAtSqrtPrice sp` for some `MIN_SQRT_PRICE ≤ sp < MAX_SQRT_PRICE` (the `uint160`
  cast is the identity there).
* `floorTick_total`: for `den ≠ 0` (any `num`, including `0`) the run succeeds, leaves the state
  unchanged and returns a tick in `[MIN_TICK, MAX_TICK]`.
* `floorTick_error_iff`: it reverts exactly when `den = 0`.

Proof note: the run is rewritten step by step with `run_bind_ok` so that every step is syntactic;
letting the kernel reduce `match (.ok …)` against `tail` makes it unfold the price comparisons
into the Newton iterates (deep recursion).
-/

namespace AsyncSwap.Swarm.FloorTick

/-- The clamp-and-delegate tail of `floorTick` on a computed sqrt price `sp` (the generated
join point). -/
def tail {σ : Type} (ext : Ext σ) (sp : Nat) : M σ Int :=
  if sp < TickMath.MIN_SQRT_PRICE then pure TickMath.MIN_TICK
  else if sp ≥ TickMath.MAX_SQRT_PRICE then pure TickMath.MAX_TICK
  else TickMath.getTickAtSqrtPrice ext (sp % 2 ^ 160)

theorem run_bind_ok {σ α β : Type} {x : M σ α} {f : α → M σ β} {r : Env} {s s' : σ} {a : α}
    (h : x r s = .ok (a, s')) : (x >>= f) r s = f a r s' := by
  rw [run_bind, h]

theorem mulDivFloor_ok {σ : Type} (x y d : Nat) (hd : d ≠ 0) (h : x * y / 2 ^ 256 < d)
    (r : Env) (s : σ) : (mulDivFloor x y d : M σ Nat) r s = .ok (x * y / d, s) := by
  unfold mulDivFloor
  by_cases hxy : x * y < 2 ^ 256
  · simp [hxy, hd]
  · simp [hxy, show ¬ d ≤ x * y / 2 ^ 256 by omega]

/-- `num / den < 2^k` and `k + e = 256` give `num · 2^e < 2^256 · den`. -/
theorem prod_lt (num den k e : Nat) (hd : den ≠ 0) (hke : k + e = 256) (hq : num / den < 2 ^ k) :
    num * 2 ^ e < 2 ^ 256 * den := by
  have h1 : num < 2 ^ k * den := by
    rw [Nat.div_lt_iff_lt_mul (Nat.pos_of_ne_zero hd)] at hq; exact hq
  have h2 : num * 2 ^ e < 2 ^ k * den * 2 ^ e :=
    Nat.mul_lt_mul_of_pos_right h1 (Nat.two_pow_pos e)
  calc num * 2 ^ e < 2 ^ k * den * 2 ^ e := h2
    _ = 2 ^ (k + e) * den := by rw [Nat.pow_add]; ac_rfl
    _ = 2 ^ 256 * den := by rw [hke]

/-- Under `num / den < 2^k`, `mulDiv(num, 2^e, den)` with `k + e = 256` does not overflow
(`num·2^e / 2^256 < den`) and its result is a word (`num·2^e / den < 2^256`). -/
theorem mulDiv_bounds (num den k e : Nat) (hd : den ≠ 0) (hke : k + e = 256)
    (hq : num / den < 2 ^ k) :
    num * 2 ^ e / 2 ^ 256 < den ∧ num * 2 ^ e / den < 2 ^ 256 := by
  have h := prod_lt num den k e hd hke hq
  constructor
  · rw [Nat.div_lt_iff_lt_mul (Nat.two_pow_pos 256), Nat.mul_comm den]; exact h
  · rw [Nat.div_lt_iff_lt_mul (Nat.pos_of_ne_zero hd)]; exact h

/-- **Monadic form.** For `den ≠ 0`, `TickPrice.floorTick` is the clean program. -/
theorem floorTick_eq {σ : Type} (ext : Ext σ) (num den : Nat) (hd : den ≠ 0) :
    TickPrice.floorTick ext num den =
      (if num / den < 2 ^ 64 then
          mulDivFloor num (2 ^ 192) den >>= fun t => Math.sqrt ext t >>= fun q => tail ext q
       else if num / den ≥ 2 ^ 128 then pure TickMath.MAX_TICK
       else
          mulDivFloor num (2 ^ 128) den >>= fun t => Math.sqrt ext t >>= fun q =>
            tail ext (shlw 256 q 32)) := by
  rw [← Nat.one_shiftLeft 64, ← Nat.one_shiftLeft 192, ← Nat.one_shiftLeft 128]
  unfold TickPrice.floorTick
  simp (config := { zeta := false }) only [divc, hd, ↓reduceIte, pure_bind, decide_eq_true_eq]
  rfl

/-- **Revert.** With `den = 0`, `TickPrice.floorTick` reverts with panic `0x12`. -/
theorem floorTick_den_zero {σ : Type} (ext : Ext σ) (num : Nat) (env : Env) (s : σ) :
    TickPrice.floorTick ext num 0 env s = .error (panic "0x12") := by
  unfold TickPrice.floorTick
  rw [run_bind]
  have : (divc num 0 : M σ Nat) env s = .error (panic "0x12") := by simp [divc]
  rw [this]

/-- **Low range.** `num / den < 2^64`: the tail on `sqrt(num · 2^192 / den)`. -/
theorem floorTick_low {σ : Type} (ext : Ext σ) (num den : Nat) (env : Env) (s : σ)
    (hd : den ≠ 0) (hq : num / den < 2 ^ 64) :
    TickPrice.floorTick ext num den env s =
      tail ext (Sqrt.sqrtPure (num * 2 ^ 192 / den)) env s := by
  obtain ⟨b1, b2⟩ := mulDiv_bounds num den 64 192 hd rfl hq
  rw [floorTick_eq ext num den hd, run_ite, if_pos hq,
    run_bind_ok (mulDivFloor_ok _ _ _ hd b1 env s), run_bind_ok (Sqrt.sqrt_run ext _ b2 env s)]

/-- **Saturation.** `num / den ≥ 2^128`: returns `MAX_TICK` with the state unchanged. -/
theorem floorTick_saturates {σ : Type} (ext : Ext σ) (num den : Nat) (env : Env) (s : σ)
    (hd : den ≠ 0) (hq2 : num / den ≥ 2 ^ 128) :
    TickPrice.floorTick ext num den env s = .ok (TickMath.MAX_TICK, s) := by
  have h : (2 : Nat) ^ 64 < 2 ^ 128 := Nat.pow_lt_pow_right (by decide) (by decide)
  have hq : ¬ num / den < 2 ^ 64 := Nat.not_lt.mpr (Nat.le_trans (Nat.le_of_lt h) hq2)
  rw [floorTick_eq ext num den hd, run_ite, if_neg hq, run_ite, if_pos hq2, run_pure]

/-- **Middle range.** `2^64 ≤ num / den < 2^128`: the tail on `sqrt(num · 2^128 / den) << 32`. -/
theorem floorTick_mid {σ : Type} (ext : Ext σ) (num den : Nat) (env : Env) (s : σ)
    (hd : den ≠ 0) (hq : ¬ num / den < 2 ^ 64) (hq2 : ¬ num / den ≥ 2 ^ 128) :
    TickPrice.floorTick ext num den env s =
      tail ext (shlw 256 (Sqrt.sqrtPure (num * 2 ^ 128 / den)) 32) env s := by
  obtain ⟨b1, b2⟩ := mulDiv_bounds num den 128 128 hd rfl (Nat.lt_of_not_le hq2)
  rw [floorTick_eq ext num den hd, run_ite, if_neg hq, run_ite, if_neg hq2,
    run_bind_ok (mulDivFloor_ok _ _ _ hd b1 env s), run_bind_ok (Sqrt.sqrt_run ext _ b2 env s)]

/-- **Exact behaviour of `TickPrice.floorTick`.** -/
theorem floorTick_run {σ : Type} (ext : Ext σ) (num den : Nat) (env : Env) (s : σ) :
    TickPrice.floorTick ext num den env s =
      if den = 0 then .error (panic "0x12")
      else if num / den < 2 ^ 64 then
        tail ext (Sqrt.sqrtPure (num * 2 ^ 192 / den)) env s
      else if num / den ≥ 2 ^ 128 then .ok (TickMath.MAX_TICK, s)
      else tail ext (shlw 256 (Sqrt.sqrtPure (num * 2 ^ 128 / den)) 32) env s := by
  by_cases hd : den = 0
  · subst hd; rw [if_pos rfl]; exact floorTick_den_zero ext num env s
  rw [if_neg hd]
  by_cases hq : num / den < 2 ^ 64
  · rw [if_pos hq]; exact floorTick_low ext num den env s hd hq
  rw [if_neg hq]
  by_cases hq2 : num / den ≥ 2 ^ 128
  · rw [if_pos hq2]; exact floorTick_saturates ext num den env s hd hq2
  · rw [if_neg hq2]; exact floorTick_mid ext num den env s hd hq hq2

/-- The tail never writes storage. -/
theorem tail_no_write {σ : Type} (ext : Ext σ) (sp : Nat) (env : Env) (s s' : σ) (t : Int)
    (h : tail ext sp env s = .ok (t, s')) : s' = s := by
  unfold tail at h
  rw [run_ite] at h
  split at h
  · rw [run_pure] at h; cases h; rfl
  · rw [run_ite] at h
    split at h
    · rw [run_pure] at h; cases h; rfl
    · exact GetTickAtSqrtPrice.getTickAtSqrtPrice_no_write ext _ env s s' t
        (Nat.mod_lt _ (Nat.two_pow_pos 160)) h

/-- **Footprint.** `TickPrice.floorTick` writes no storage: every successful run returns the
state it was given. -/
theorem floorTick_no_write {σ : Type} (ext : Ext σ) (num den : Nat) (env : Env) (s s' : σ)
    (t : Int) (h : TickPrice.floorTick ext num den env s = .ok (t, s')) : s' = s := by
  by_cases hd : den = 0
  · subst hd; rw [floorTick_den_zero] at h; cases h
  by_cases hq : num / den < 2 ^ 64
  · rw [floorTick_low ext num den env s hd hq] at h; exact tail_no_write ext _ env s s' t h
  by_cases hq2 : num / den ≥ 2 ^ 128
  · rw [floorTick_saturates ext num den env s hd hq2] at h; cases h; rfl
  · rw [floorTick_mid ext num den env s hd hq hq2] at h; exact tail_no_write ext _ env s s' t h

/-! ## The sqrt price feeding `getTickAtSqrtPrice` -/

/-- `Math.sqrt`'s value never exceeds the floor square root: `x² ≤ m`. -/
theorem sqrtPure_sq_le (m : Nat) : Sqrt.sqrtPure m * Sqrt.sqrtPure m ≤ m := by
  unfold Sqrt.sqrtPure
  split
  · simp
  · have h1 : min (Sqrt.r7 m) (m / Sqrt.r7 m) ≤ Sqrt.r7 m := Nat.min_le_left _ _
    have h2 : min (Sqrt.r7 m) (m / Sqrt.r7 m) ≤ m / Sqrt.r7 m := Nat.min_le_right _ _
    have h3 := Nat.mul_le_mul h1 h2
    have h4 : Sqrt.r7 m * (m / Sqrt.r7 m) ≤ m := Nat.mul_div_le m (Sqrt.r7 m)
    omega

/-- The sqrt of a word is below `2^128`. -/
theorem sqrtPure_lt (m : Nat) (hm : m < 2 ^ 256) : Sqrt.sqrtPure m < 2 ^ 128 := by
  apply Nat.lt_of_not_le
  intro hge
  have h1 := Nat.mul_le_mul hge hge
  have h2 := sqrtPure_sq_le m
  have hP : (2 : Nat) ^ 128 * 2 ^ 128 = 2 ^ 256 := by rw [← Nat.pow_add]
  omega

/-- **No wrap in the middle branch.** For a word `m`, `sqrt(m) << 32` (mod `2^256`) is exactly
`sqrt(m) · 2^32`, and that is below `2^160`. -/
theorem shlw_sqrt_no_wrap (m : Nat) (hm : m < 2 ^ 256) :
    shlw 256 (Sqrt.sqrtPure m) 32 = Sqrt.sqrtPure m * 2 ^ 32 ∧
      Sqrt.sqrtPure m * 2 ^ 32 < 2 ^ 160 := by
  have h := sqrtPure_lt m hm
  have hb : Sqrt.sqrtPure m * 2 ^ 32 < 2 ^ 160 := by
    calc Sqrt.sqrtPure m * 2 ^ 32 < 2 ^ 128 * 2 ^ 32 :=
          Nat.mul_lt_mul_of_pos_right h (Nat.two_pow_pos 32)
      _ = 2 ^ 160 := by rw [← Nat.pow_add]
  have hw : (2 : Nat) ^ 160 < 2 ^ 256 := Nat.pow_lt_pow_right (by decide) (by decide)
  refine ⟨?_, hb⟩
  unfold shlw
  rw [Nat.shiftLeft_eq, Nat.mod_eq_of_lt (Nat.lt_trans hb hw)]

/-- **Middle range, unwrapped.** For `2^64 ≤ num / den < 2^128`, `TickPrice.floorTick` runs the
tail on `sp = sqrt(num · 2^128 / den) · 2^32`, with `sp < 2^160`: the shift never wraps. -/
theorem floorTick_mid_exact {σ : Type} (ext : Ext σ) (num den : Nat) (env : Env) (s : σ)
    (hd : den ≠ 0) (hq : ¬ num / den < 2 ^ 64) (hq2 : ¬ num / den ≥ 2 ^ 128) :
    TickPrice.floorTick ext num den env s =
        tail ext (Sqrt.sqrtPure (num * 2 ^ 128 / den) * 2 ^ 32) env s ∧
      Sqrt.sqrtPure (num * 2 ^ 128 / den) * 2 ^ 32 < 2 ^ 160 := by
  obtain ⟨_, b2⟩ := mulDiv_bounds num den 128 128 hd rfl (Nat.lt_of_not_le hq2)
  obtain ⟨e, hb⟩ := shlw_sqrt_no_wrap _ b2
  exact ⟨by rw [floorTick_mid ext num den env s hd hq hq2, e], hb⟩

/-- **Low range bound.** For `num / den < 2^64` the price handed to the tail is below `2^128`. -/
theorem floorTick_low_bound (num den : Nat) (hd : den ≠ 0) (hq : num / den < 2 ^ 64) :
    Sqrt.sqrtPure (num * 2 ^ 192 / den) < 2 ^ 128 :=
  sqrtPure_lt _ (mulDiv_bounds num den 64 192 hd rfl hq).2

/-- The tail either clamps or calls `getTickAtSqrtPrice` on `sp` itself, with `sp` in
`[MIN_SQRT_PRICE, MAX_SQRT_PRICE)`. -/
theorem tail_dispatch {σ : Type} (ext : Ext σ) (sp : Nat) (env : Env) (s : σ) :
    tail ext sp env s = .ok (TickMath.MIN_TICK, s) ∨
    tail ext sp env s = .ok (TickMath.MAX_TICK, s) ∨
    (TickMath.MIN_SQRT_PRICE ≤ sp ∧ sp < TickMath.MAX_SQRT_PRICE ∧
      tail ext sp env s = TickMath.getTickAtSqrtPrice ext sp env s) := by
  unfold tail
  by_cases h1 : sp < TickMath.MIN_SQRT_PRICE
  · left; rw [if_pos h1, run_pure]
  by_cases h2 : sp ≥ TickMath.MAX_SQRT_PRICE
  · right; left; rw [if_neg h1, if_pos h2, run_pure]
  right; right
  have hm : sp % 2 ^ 160 = sp :=
    Nat.mod_eq_of_lt (by unfold TickMath.MAX_SQRT_PRICE at h2; omega)
  refine ⟨Nat.le_of_not_lt h1, Nat.lt_of_not_le h2, ?_⟩
  rw [if_neg h1, if_neg h2, hm]

/-- **Dispatch of `TickPrice.floorTick`.** For `den ≠ 0`, the run returns `MIN_TICK` or
`MAX_TICK` with the state unchanged, or it is exactly `getTickAtSqrtPrice sp` for a sqrt price
`MIN_SQRT_PRICE ≤ sp < MAX_SQRT_PRICE`. -/
theorem floorTick_dispatch {σ : Type} (ext : Ext σ) (num den : Nat) (env : Env) (s : σ)
    (hd : den ≠ 0) :
    TickPrice.floorTick ext num den env s = .ok (TickMath.MIN_TICK, s) ∨
    TickPrice.floorTick ext num den env s = .ok (TickMath.MAX_TICK, s) ∨
    ∃ sp, TickMath.MIN_SQRT_PRICE ≤ sp ∧ sp < TickMath.MAX_SQRT_PRICE ∧
      TickPrice.floorTick ext num den env s = TickMath.getTickAtSqrtPrice ext sp env s := by
  have lift : ∀ sp, TickPrice.floorTick ext num den env s = tail ext sp env s →
      TickPrice.floorTick ext num den env s = .ok (TickMath.MIN_TICK, s) ∨
      TickPrice.floorTick ext num den env s = .ok (TickMath.MAX_TICK, s) ∨
      ∃ sp, TickMath.MIN_SQRT_PRICE ≤ sp ∧ sp < TickMath.MAX_SQRT_PRICE ∧
        TickPrice.floorTick ext num den env s = TickMath.getTickAtSqrtPrice ext sp env s := by
    intro sp h
    rw [h]
    rcases tail_dispatch ext sp env s with h1 | h1 | ⟨a, b, c⟩
    · exact Or.inl h1
    · exact Or.inr (Or.inl h1)
    · exact Or.inr (Or.inr ⟨sp, a, b, c⟩)
  by_cases hq : num / den < 2 ^ 64
  · exact lift _ (floorTick_low ext num den env s hd hq)
  by_cases hq2 : num / den ≥ 2 ^ 128
  · exact Or.inr (Or.inl (floorTick_saturates ext num den env s hd hq2))
  · exact lift _ (floorTick_mid ext num den env s hd hq hq2)

/-! ## Totality -/

/-- **Totality of `TickPrice.floorTick`.** For any `num` (zero included) and `den ≠ 0`, the run
succeeds, leaves the state unchanged, and returns a tick `MIN_TICK ≤ t ≤ MAX_TICK`. -/
theorem floorTick_total {σ : Type} (ext : Ext σ) (num den : Nat) (env : Env) (s : σ)
    (hd : den ≠ 0) :
    ∃ t, TickPrice.floorTick ext num den env s = .ok (t, s) ∧
      TickMath.MIN_TICK ≤ t ∧ t ≤ TickMath.MAX_TICK := by
  rcases floorTick_dispatch ext num den env s hd with h | h | ⟨sp, h1, h2, h⟩
  · exact ⟨_, h, by decide, by decide⟩
  · exact ⟨_, h, by decide, by decide⟩
  · rw [h]; exact TickBounds.getTickAtSqrtPrice_bounded ext sp env s h1 h2

/-- **Revert condition of `TickPrice.floorTick`.** It reverts exactly when `den = 0`. -/
theorem floorTick_error_iff {σ : Type} (ext : Ext σ) (num den : Nat) (env : Env) (s : σ) :
    (∃ e, TickPrice.floorTick ext num den env s = .error e) ↔ den = 0 := by
  constructor
  · rintro ⟨e, he⟩
    apply Classical.byContradiction
    intro hd
    obtain ⟨t, ht, _, _⟩ := floorTick_total ext num den env s hd
    rw [ht] at he
    cases he
  · intro hd
    subst hd
    exact ⟨_, floorTick_den_zero ext num env s⟩

end AsyncSwap.Swarm.FloorTick
