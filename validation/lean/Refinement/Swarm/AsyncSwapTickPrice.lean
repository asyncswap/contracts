import Generated.AsyncSwap
import Refinement.Monad
import Refinement.Swarm.AsyncSwapSqrt
import Refinement.Swarm.AsyncSwapGetTickAtSqrtPrice
open FormalAst Refinement

/-!
# `TickPrice.floorTick` and `TickPrice.key` (src/AsyncSwap.sol)

`floorTick(num, den)` maps the price `num / den` to a tick: for `num / den < 2^64` it takes
`sqrtPrice = sqrt(mulDiv(num, 2^192, den))`; for `num / den ≥ 2^128` it returns `MAX_TICK`; otherwise
`sqrtPrice = sqrt(mulDiv(num, 2^128, den)) << 32`. It then clamps (`< MIN_SQRT_PRICE ↦ MIN_TICK`,
`≥ MAX_SQRT_PRICE ↦ MAX_TICK`) and otherwise returns `getTickAtSqrtPrice(uint160(sqrtPrice))`.

`key(isBuy, zeroForOne, amountIn, amountOut)` is the order-book bucket of an order: the floor tick of
`amountOut/amountIn` (zeroForOne) or `amountIn/amountOut`, then `tick - MIN_TICK + 1` when
`isBuy != zeroForOne` and `MAX_TICK - tick + 1` otherwise.

* `floorTick_den_zero`: `den = 0` reverts with panic `0x12` (the only `divc` revert).
* `floorTick_eq_small/_huge/_mid`, `floorTick_run_small/_huge/_mid`: the three branches; the `mulDiv`
  calls never overflow (`scaled_bounds`), `Math.sqrt` never reverts.
* `floorTick_result`: any successful run leaves the state unchanged and returns `MIN_TICK`,
  `MAX_TICK`, or `getTickAtSqrtPrice` of an in-range `uint160` sqrt price.
* `key_eq`, `key_run`, `key_error`, `key_zero_den`: `key` is `floorTick` followed by the bucket
  formula; for a tick in `[MIN_TICK, MAX_TICK]` the bucket is `keyPure` (in `[1, 1774545]`), and
  floorTick's reverts pass through.
* `keyPure_strictMono_buy/_strictAnti_sell`: the bucket is strictly increasing in the tick on one
  side and strictly decreasing on the other.
-/

namespace AsyncSwap.Swarm.TickPrice

open AsyncSwap.Swarm.GetTickAtSqrtPrice

theorem divc_pure {σ : Type} (a b : Nat) (hb : b ≠ 0) : (divc a b : M σ Nat) = pure (a / b) := by
  simp [divc, hb]

theorem mulDivFloor_ok {σ : Type} (x y d : Nat) (hd : d ≠ 0) (h : x * y / 2 ^ 256 < d)
    (r : Env) (s : σ) : (mulDivFloor x y d : M σ Nat) r s = .ok (x * y / d, s) := by
  unfold mulDivFloor
  by_cases hxy : x * y < 2 ^ 256
  · simp [hxy, hd]
  · simp [hxy, show ¬ d ≤ x * y / 2 ^ 256 by omega]

/-- `num / den < 2^k` (with `k + j = 256`) makes `mulDiv(num, 2^j, den)` not overflow and its result
fit a word. -/
theorem scaled_bounds (num den k j : Nat) (hd : den ≠ 0) (hkj : k + j = 256) (hq : num / den < 2 ^ k) :
    num * 2 ^ j / 2 ^ 256 < den ∧ num * 2 ^ j / den < 2 ^ 256 := by
  have h1 : num < 2 ^ k * den := (Nat.div_lt_iff_lt_mul (by omega)).1 hq
  have h2 : num * 2 ^ j < 2 ^ 256 * den := by
    have := Nat.mul_lt_mul_of_pos_right h1 (Nat.two_pow_pos j)
    rw [← hkj, Nat.pow_add]
    calc num * 2 ^ j < 2 ^ k * den * 2 ^ j := this
      _ = 2 ^ k * 2 ^ j * den := by rw [Nat.mul_assoc, Nat.mul_comm den, ← Nat.mul_assoc]
  refine ⟨(Nat.div_lt_iff_lt_mul (Nat.two_pow_pos 256)).2 ?_, (Nat.div_lt_iff_lt_mul (by omega)).2 h2⟩
  rw [Nat.mul_comm den]; exact h2

/-- `mulDiv(num, 1 << j, den)` followed by `k`, when it doesn't overflow. -/
theorem mulDivFloor_bind {σ : Type} (num den j : Nat) (env : Env) (s : σ) (hd : den ≠ 0)
    (b1 : num * 2 ^ j / 2 ^ 256 < den) (k : Nat → M σ Int) :
    (mulDivFloor num (1 <<< j) den >>= k) env s = k (num * 2 ^ j / den) env s := by
  rw [run_bind, Nat.one_shiftLeft, mulDivFloor_ok num _ den hd b1 env s]

/-- `Math.sqrt m` followed by `k`, for a word `m`. -/
theorem sqrt_bind {σ : Type} (ext : Ext σ) (m : Nat) (hm : m < 2 ^ 256) (env : Env) (s : σ)
    (k : Nat → M σ Int) :
    (Math.sqrt ext m >>= k) env s = k (AsyncSwap.Swarm.Sqrt.sqrtPure m) env s := by
  rw [run_bind, AsyncSwap.Swarm.Sqrt.sqrt_run ext m hm]

/-- The clamp-and-delegate tail of `floorTick`. -/
def clamp {σ : Type} (ext : Ext σ) (q : Nat) : M σ Int :=
  if decide (q < TickMath.MIN_SQRT_PRICE) then pure TickMath.MIN_TICK
  else if decide (q ≥ TickMath.MAX_SQRT_PRICE) then pure TickMath.MAX_TICK
  else TickMath.getTickAtSqrtPrice ext (q % 2 ^ 160)

theorem floorTick_den_zero {σ : Type} (ext : Ext σ) (num : Nat) (env : Env) (s : σ) :
    TickPrice.floorTick ext num 0 env s = .error (panic "0x12") := by
  simp [TickPrice.floorTick, divc]

theorem floorTick_eq_small {σ : Type} (ext : Ext σ) (num den : Nat) (hd : den ≠ 0)
    (hq : num / den < 1 <<< 64) :
    TickPrice.floorTick ext num den =
      (do let m ← mulDivFloor num (1 <<< 192) den
          let q ← Math.sqrt ext m
          clamp ext q) := by
  unfold TickPrice.floorTick
  rw [divc_pure num den hd, pure_bind, ite_eq_left (decide_eq_true hq)]
  rfl

theorem floorTick_eq_huge {σ : Type} (ext : Ext σ) (num den : Nat) (hd : den ≠ 0)
    (hq : ¬ num / den < 1 <<< 64) (hh : num / den ≥ 1 <<< 128) :
    TickPrice.floorTick ext num den = pure TickMath.MAX_TICK := by
  unfold TickPrice.floorTick
  rw [divc_pure num den hd, pure_bind, ite_eq_right (fun h => hq (of_decide_eq_true h)),
    pure_bind, ite_eq_left (decide_eq_true hh)]

theorem floorTick_eq_mid {σ : Type} (ext : Ext σ) (num den : Nat) (hd : den ≠ 0)
    (hq : ¬ num / den < 1 <<< 64) (hh : ¬ num / den ≥ 1 <<< 128) :
    TickPrice.floorTick ext num den =
      (do let m ← mulDivFloor num (1 <<< 128) den
          let q ← Math.sqrt ext m
          clamp ext (shlw 256 q 32)) := by
  unfold TickPrice.floorTick
  rw [divc_pure num den hd, pure_bind, ite_eq_right (fun h => hq (of_decide_eq_true h)),
    pure_bind, ite_eq_right (fun h => hh (of_decide_eq_true h))]
  rfl

/-- Small prices (`num / den < 2^64`): `sqrtPrice = ⌊√(num·2^192/den)⌋`, then the clamp. -/
theorem floorTick_run_small {σ : Type} (ext : Ext σ) (num den : Nat) (env : Env) (s : σ)
    (hd : den ≠ 0) (hq : num / den < 2 ^ 64) :
    TickPrice.floorTick ext num den env s =
      clamp ext (AsyncSwap.Swarm.Sqrt.sqrtPure (num * 2 ^ 192 / den)) env s := by
  have hq' : num / den < 1 <<< 64 := by rw [Nat.one_shiftLeft]; exact hq
  obtain ⟨b1, b2⟩ := scaled_bounds num den 64 192 hd rfl hq
  rw [floorTick_eq_small ext num den hd hq', mulDivFloor_bind num den 192 env s hd b1,
    sqrt_bind ext _ b2 env s]

/-- Huge prices (`num / den ≥ 2^128`): `MAX_TICK`, state unchanged. -/
theorem floorTick_run_huge {σ : Type} (ext : Ext σ) (num den : Nat) (env : Env) (s : σ)
    (hd : den ≠ 0) (hh : num / den ≥ 2 ^ 128) :
    TickPrice.floorTick ext num den env s = .ok (TickMath.MAX_TICK, s) := by
  have hq' : ¬ num / den < 1 <<< 64 := by
    rw [Nat.one_shiftLeft]
    have : (2 : Nat) ^ 64 ≤ 2 ^ 128 := Nat.pow_le_pow_right (by decide) (by decide)
    omega
  have hh' : num / den ≥ 1 <<< 128 := by rw [Nat.one_shiftLeft]; exact hh
  rw [floorTick_eq_huge ext num den hd hq' hh']
  rfl

/-- Middle prices (`2^64 ≤ num / den < 2^128`): `sqrtPrice = ⌊√(num·2^128/den)⌋ << 32`, then the
clamp. -/
theorem floorTick_run_mid {σ : Type} (ext : Ext σ) (num den : Nat) (env : Env) (s : σ)
    (hd : den ≠ 0) (hq : ¬ num / den < 2 ^ 64) (hh : num / den < 2 ^ 128) :
    TickPrice.floorTick ext num den env s =
      clamp ext (shlw 256 (AsyncSwap.Swarm.Sqrt.sqrtPure (num * 2 ^ 128 / den)) 32) env s := by
  have hq' : ¬ num / den < 1 <<< 64 := by rw [Nat.one_shiftLeft]; exact hq
  have hh' : ¬ num / den ≥ 1 <<< 128 := by rw [Nat.one_shiftLeft]; omega
  obtain ⟨b1, b2⟩ := scaled_bounds num den 128 128 hd rfl hh
  rw [floorTick_eq_mid ext num den hd hq' hh', mulDivFloor_bind num den 128 env s hd b1,
    sqrt_bind ext _ b2 env s]

/-- The clamp never writes and returns `MIN_TICK`, `MAX_TICK`, or `getTickAtSqrtPrice` of an
in-range `uint160` price. -/
theorem clamp_result {σ : Type} (ext : Ext σ) (q : Nat) (env : Env) (s s' : σ) (t : Int)
    (h : clamp ext q env s = .ok (t, s')) :
    s' = s ∧ (t = TickMath.MIN_TICK ∨ t = TickMath.MAX_TICK ∨
      (q % 2 ^ 160 = q ∧ TickMath.getTickAtSqrtPrice ext q env s = .ok (t, s))) := by
  unfold clamp at h
  by_cases h1 : q < TickMath.MIN_SQRT_PRICE
  · rw [ite_eq_left (decide_eq_true h1)] at h
    cases h; exact ⟨rfl, Or.inl rfl⟩
  rw [ite_eq_right (fun h' => h1 (of_decide_eq_true h'))] at h
  by_cases h2 : q ≥ TickMath.MAX_SQRT_PRICE
  · rw [ite_eq_left (decide_eq_true h2)] at h
    cases h; exact ⟨rfl, Or.inr (Or.inl rfl)⟩
  rw [ite_eq_right (fun h' => h2 (of_decide_eq_true h'))] at h
  have hlt : q < 2 ^ 160 := by
    simp only [TickMath.MAX_SQRT_PRICE] at h2
    omega
  have hq : q % 2 ^ 160 = q := Nat.mod_eq_of_lt hlt
  rw [hq] at h
  have hs := getTickAtSqrtPrice_no_write ext q env s s' t hlt h
  subst hs
  exact ⟨rfl, Or.inr (Or.inr ⟨hq, h⟩)⟩

/-- **floorTick never writes storage**; it returns `MIN_TICK`, `MAX_TICK`, or the
`getTickAtSqrtPrice` of some `uint160` price in `[MIN_SQRT_PRICE, MAX_SQRT_PRICE)`. -/
theorem floorTick_result {σ : Type} (ext : Ext σ) (num den : Nat) (env : Env) (s s' : σ) (t : Int)
    (h : TickPrice.floorTick ext num den env s = .ok (t, s')) :
    s' = s ∧ (t = TickMath.MIN_TICK ∨ t = TickMath.MAX_TICK ∨
      ∃ p, p < 2 ^ 160 ∧ TickMath.MIN_SQRT_PRICE ≤ p ∧ p < TickMath.MAX_SQRT_PRICE ∧
        TickMath.getTickAtSqrtPrice ext p env s = .ok (t, s)) := by
  have lift : ∀ q, clamp ext q env s = .ok (t, s') → s' = s ∧ (t = TickMath.MIN_TICK ∨
      t = TickMath.MAX_TICK ∨ ∃ p, p < 2 ^ 160 ∧ TickMath.MIN_SQRT_PRICE ≤ p ∧
        p < TickMath.MAX_SQRT_PRICE ∧ TickMath.getTickAtSqrtPrice ext p env s = .ok (t, s)) := by
    intro q hc
    obtain ⟨hs, hr⟩ := clamp_result ext q env s s' t hc
    refine ⟨hs, ?_⟩
    rcases hr with hr | hr | ⟨hq, hg⟩
    · exact Or.inl hr
    · exact Or.inr (Or.inl hr)
    · have hp : q < 2 ^ 160 := by rw [← hq]; exact Nat.mod_lt _ (Nat.two_pow_pos 160)
      obtain ⟨_, hmin, hmax, _⟩ := getTickAtSqrtPrice_result ext q env s s t hp hg
      exact Or.inr (Or.inr ⟨q, hp, hmin, hmax, hg⟩)
  by_cases hd : den = 0
  · subst hd; rw [floorTick_den_zero] at h; cases h
  by_cases hq : num / den < 2 ^ 64
  · rw [floorTick_run_small ext num den env s hd hq] at h; exact lift _ h
  by_cases hh : num / den < 2 ^ 128
  · rw [floorTick_run_mid ext num den env s hd hq hh] at h; exact lift _ h
  · rw [floorTick_run_huge ext num den env s hd (by omega)] at h
    cases h; exact ⟨rfl, Or.inr (Or.inl rfl)⟩

/-! ## `key` -/

/-- The bucket of a tick, as `key` computes it for ticks in `[MIN_TICK, MAX_TICK]`. -/
def keyPure (isBuy zeroForOne : Bool) (t : Int) : Nat :=
  if (isBuy != zeroForOne) = true then (t - TickMath.MIN_TICK + 1).toNat
  else (TickMath.MAX_TICK - t + 1).toNat

/-- The bucket step after the floor tick: checked `int24` subtraction, then checked `+1` in uint128. -/
def bucket {σ : Type} (isBuy zeroForOne : Bool) (tick : Int) : M σ Nat :=
  if (isBuy != zeroForOne) = true then do
    let d ← subcI 24 tick TickMath.MIN_TICK
    addc 128 (toUnsigned 24 d) 1
  else do
    let d ← subcI 24 TickMath.MAX_TICK tick
    addc 128 (toUnsigned 24 d) 1

theorem key_eq_true {σ : Type} (ext : Ext σ) (isBuy : Bool) (amountIn amountOut : Nat) :
    TickPrice.key ext isBuy true amountIn amountOut =
      (do let t ← TickPrice.floorTick ext amountOut amountIn; bucket isBuy true t) := by
  unfold TickPrice.key
  rw [ite_eq_left (rfl : true = true)]
  apply congrArg (fun k => TickPrice.floorTick ext amountOut amountIn >>= k)
  funext t
  unfold bucket
  simp only [bind_pure]

theorem key_eq_false {σ : Type} (ext : Ext σ) (isBuy : Bool) (amountIn amountOut : Nat) :
    TickPrice.key ext isBuy false amountIn amountOut =
      (do let t ← TickPrice.floorTick ext amountIn amountOut; bucket isBuy false t) := by
  unfold TickPrice.key
  rw [ite_eq_right (by decide : ¬ false = true)]
  apply congrArg (fun k => TickPrice.floorTick ext amountIn amountOut >>= k)
  funext t
  unfold bucket
  simp only [bind_pure]

/-- `key` is `floorTick` of the order's price, followed by the bucket formula. -/
theorem key_eq {σ : Type} (ext : Ext σ) (isBuy zeroForOne : Bool) (amountIn amountOut : Nat) :
    TickPrice.key ext isBuy zeroForOne amountIn amountOut =
      (do let t ← TickPrice.floorTick ext (if zeroForOne then amountOut else amountIn)
            (if zeroForOne then amountIn else amountOut)
          bucket isBuy zeroForOne t) := by
  cases zeroForOne
  · rw [key_eq_false]; rfl
  · rw [key_eq_true]; rfl

theorem toUnsigned24_of (x : Int) (h0 : 0 ≤ x) (h1 : x < 2 ^ 24) : toUnsigned 24 x = x.toNat := by
  unfold toUnsigned
  rw [Int.emod_eq_of_lt h0 (by simpa using h1)]

theorem fits24 (x : Int) (h0 : -8388608 ≤ x) (h1 : x ≤ 8388607) : fits 24 x = true := by
  have e1 : smin 24 = -8388608 := by rfl
  have e2 : smax 24 = 8388607 := by rfl
  unfold fits; rw [e1, e2]; exact decide_eq_true ⟨h0, h1⟩

/-- For a tick in `[MIN_TICK, MAX_TICK]` the bucket step never reverts and returns `keyPure`. -/
theorem bucket_run {σ : Type} (isBuy zeroForOne : Bool) (t : Int) (env : Env) (s : σ)
    (hlo : TickMath.MIN_TICK ≤ t) (hhi : t ≤ TickMath.MAX_TICK) :
    (bucket isBuy zeroForOne t : M σ Nat) env s = .ok (keyPure isBuy zeroForOne t, s) := by
  simp only [TickMath.MIN_TICK, TickMath.MAX_TICK] at hlo hhi
  unfold bucket keyPure
  by_cases hb : (isBuy != zeroForOne) = true
  · rw [ite_eq_left hb, ite_eq_left hb]
    have hf : fits 24 (t - TickMath.MIN_TICK) = true :=
      fits24 _ (by simp only [TickMath.MIN_TICK]; omega) (by simp only [TickMath.MIN_TICK]; omega)
    have hu : toUnsigned 24 (t - TickMath.MIN_TICK) = (t - TickMath.MIN_TICK).toNat :=
      toUnsigned24_of _ (by simp only [TickMath.MIN_TICK]; omega) (by simp only [TickMath.MIN_TICK]; omega)
    have he : (t - TickMath.MIN_TICK).toNat + 1 = (t - TickMath.MIN_TICK + 1).toNat := by
      simp only [TickMath.MIN_TICK]; omega
    have hlt : (t - TickMath.MIN_TICK + 1).toNat < 2 ^ 128 := by simp only [TickMath.MIN_TICK]; omega
    simp only [run_bind, subcI, hf, ↓reduceIte, run_pure, hu, addc, he, hlt]
  · rw [ite_eq_right hb, ite_eq_right hb]
    have hf : fits 24 (TickMath.MAX_TICK - t) = true :=
      fits24 _ (by simp only [TickMath.MAX_TICK]; omega) (by simp only [TickMath.MAX_TICK]; omega)
    have hu : toUnsigned 24 (TickMath.MAX_TICK - t) = (TickMath.MAX_TICK - t).toNat :=
      toUnsigned24_of _ (by simp only [TickMath.MAX_TICK]; omega) (by simp only [TickMath.MAX_TICK]; omega)
    have he : (TickMath.MAX_TICK - t).toNat + 1 = (TickMath.MAX_TICK - t + 1).toNat := by
      simp only [TickMath.MAX_TICK]; omega
    have hlt : (TickMath.MAX_TICK - t + 1).toNat < 2 ^ 128 := by simp only [TickMath.MAX_TICK]; omega
    simp only [run_bind, subcI, hf, ↓reduceIte, run_pure, hu, addc, he, hlt]

/-- **key, success.** If the floor tick of the order's price is `t ∈ [MIN_TICK, MAX_TICK]`, `key`
returns `keyPure isBuy zeroForOne t` and leaves the state unchanged. -/
theorem key_run {σ : Type} (ext : Ext σ) (isBuy zeroForOne : Bool) (amountIn amountOut : Nat)
    (env : Env) (s s' : σ) (t : Int)
    (hf : TickPrice.floorTick ext (if zeroForOne then amountOut else amountIn)
      (if zeroForOne then amountIn else amountOut) env s = .ok (t, s'))
    (hlo : TickMath.MIN_TICK ≤ t) (hhi : t ≤ TickMath.MAX_TICK) :
    TickPrice.key ext isBuy zeroForOne amountIn amountOut env s =
      .ok (keyPure isBuy zeroForOne t, s) := by
  have hs := (floorTick_result ext _ _ env s s' t hf).1
  subst hs
  rw [key_eq, run_bind, hf]
  exact bucket_run isBuy zeroForOne t env _ hlo hhi

/-- **key, revert.** Every revert of the floor tick is a revert of `key`. -/
theorem key_error {σ : Type} (ext : Ext σ) (isBuy zeroForOne : Bool) (amountIn amountOut : Nat)
    (env : Env) (s : σ) (e : Revert)
    (hf : TickPrice.floorTick ext (if zeroForOne then amountOut else amountIn)
      (if zeroForOne then amountIn else amountOut) env s = .error e) :
    TickPrice.key ext isBuy zeroForOne amountIn amountOut env s = .error e := by
  rw [key_eq, run_bind, hf]

/-- A zero denominator (`amountIn = 0` when zeroForOne, `amountOut = 0` otherwise) makes `key`
revert with panic `0x12`. -/
theorem key_zero_den {σ : Type} (ext : Ext σ) (isBuy zeroForOne : Bool) (amountIn amountOut : Nat)
    (env : Env) (s : σ) (h : (if zeroForOne then amountIn else amountOut) = 0) :
    TickPrice.key ext isBuy zeroForOne amountIn amountOut env s = .error (panic "0x12") := by
  apply key_error
  rw [h]; exact floorTick_den_zero ext _ env s

/-- The bucket range: `1 ≤ key ≤ 2·MAX_TICK + 1`. -/
theorem keyPure_range (isBuy zeroForOne : Bool) (t : Int)
    (hlo : TickMath.MIN_TICK ≤ t) (hhi : t ≤ TickMath.MAX_TICK) :
    1 ≤ keyPure isBuy zeroForOne t ∧ keyPure isBuy zeroForOne t ≤ 1774545 := by
  simp only [TickMath.MIN_TICK, TickMath.MAX_TICK] at hlo hhi
  unfold keyPure
  simp only [TickMath.MIN_TICK, TickMath.MAX_TICK]
  split <;> omega

/-- On the `isBuy != zeroForOne` side the bucket is strictly increasing in the tick. -/
theorem keyPure_strictMono_buy (isBuy zeroForOne : Bool) (hb : (isBuy != zeroForOne) = true)
    (t u : Int) (hlo : TickMath.MIN_TICK ≤ t) (htu : t < u) :
    keyPure isBuy zeroForOne t < keyPure isBuy zeroForOne u := by
  simp only [TickMath.MIN_TICK] at hlo
  unfold keyPure
  rw [ite_eq_left hb, ite_eq_left hb]
  simp only [TickMath.MIN_TICK]
  omega

/-- On the other side the bucket is strictly decreasing in the tick. -/
theorem keyPure_strictAnti_sell (isBuy zeroForOne : Bool) (hb : ¬ (isBuy != zeroForOne) = true)
    (t u : Int) (hhi : u ≤ TickMath.MAX_TICK) (htu : t < u) :
    keyPure isBuy zeroForOne u < keyPure isBuy zeroForOne t := by
  simp only [TickMath.MAX_TICK] at hhi
  unfold keyPure
  rw [ite_eq_right hb, ite_eq_right hb]
  simp only [TickMath.MAX_TICK]
  omega

end AsyncSwap.Swarm.TickPrice
