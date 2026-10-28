import Generated.AsyncSwap
import Refinement.Monad
open FormalAst Refinement

/-!
# `TickMath.getSqrtPriceAtTick` (src/AsyncSwap.sol, Uniswap v4 `TickMath`)

The function narrows `tick` to int24 (`signextend(2, tick)`), takes its branch-free absolute value
`absTick = xor(mask, add(mask, tick))` with `mask = sar(255, tick)`, reverts with
`InvalidTick(tick)` when `absTick > MAX_TICK = 887272`, and otherwise builds the Q128.128 ratio
`1.0001^(-absTick/2)` by a 20-step bit ladder, inverts it for positive ticks and rounds it up to
Q64.96 (`uint160`).

* `getSqrtPriceAtTick_eq` / `getSqrtPriceAtTick_run`: for every `tick : Int` the function is
  `if absTickOf tick > 887272 then revert else return sqrtPure tick`, and it never changes the state.
* `getSqrtPriceAtTick_int24`, `getSqrtPriceAtTick_reverts_iff`: for an int24 tick (all Solidity can
  pass) `absTickOf tick = |tick|`, so the function reverts exactly when `|tick| > MAX_TICK`.
* `getSqrtPriceAtTick_zero/_minTick/_maxTick`: it returns `2^96` at tick 0, `MIN_SQRT_PRICE =
  4295128739` at `MIN_TICK` and `MAX_SQRT_PRICE` at `MAX_TICK`.

Proof technique: the `do` block compiles each `if … then price := …` into a let-bound join point;
`extract_lets` lifts the 20 join points into the context, and each is folded with `step_fold`
(`if b then k (f p) else k p = k (step b p)`), so the 2^19 control paths collapse into one term.
-/

namespace AsyncSwap.Swarm.GetSqrtPriceAtTick

/-- The tick narrowed to int24, as `signextend(2, tick)` does. -/
def tick24 (tick : Int) : Int := toSigned 24 (ysignextend 2 (toUnsigned 256 tick))

/-- The branch-free absolute value `xor(mask, add(mask, tick))`, `mask = sar(255, tick)`. -/
def absTickOf (tick : Int) : Nat :=
  yxor (ysar 255 (toUnsigned 256 (tick24 tick)))
    (yadd (ysar 255 (toUnsigned 256 (tick24 tick))) (toUnsigned 256 (tick24 tick)))

/-- One rung of the ladder: `price := price * c >> 128` when bit `bit` of `A` is set. -/
def step (A bit c p : Nat) : Nat := if (A &&& bit != 0) = true then mulw 256 p c >>> 128 else p

/-- The final inversion for positive ticks: `price := type(uint256).max / price`. -/
def invert (t p : Nat) : Nat := if (ysgt t 0 != 0) = true then ydiv (ynot 0) p else p

/-- The Q128.128 ratio `1.0001^(-A/2)` built by the bit ladder. -/
def ladder (A : Nat) : Nat :=
  let p := yxor (yshl 128 1) (ymul (yxor (yshl 128 1) 0xfffcb933bd6fad37aa2d162d1a594001) (yand A 0x1))
  let p := step A 0x2 0xfff97272373d413259a46990580e213a p
  let p := step A 0x4 0xfff2e50f5f656932ef12357cf3c7fdcc p
  let p := step A 0x8 0xffe5caca7e10e4e61c3624eaa0941cd0 p
  let p := step A 0x10 0xffcb9843d60f6159c9db58835c926644 p
  let p := step A 0x20 0xff973b41fa98c081472e6896dfb254c0 p
  let p := step A 0x40 0xff2ea16466c96a3843ec78b326b52861 p
  let p := step A 0x80 0xfe5dee046a99a2a811c461f1969c3053 p
  let p := step A 0x100 0xfcbe86c7900a88aedcffc83b479aa3a4 p
  let p := step A 0x200 0xf987a7253ac413176f2b074cf7815e54 p
  let p := step A 0x400 0xf3392b0822b70005940c7a398e4b70f3 p
  let p := step A 0x800 0xe7159475a2c29b7443b29c7fa6e889d9 p
  let p := step A 0x1000 0xd097f3bdfd2022b8845ad8f792aa5825 p
  let p := step A 0x2000 0xa9f746462d870fdf8a65dc1f90e061e5 p
  let p := step A 0x4000 0x70d869a156d2a1b890bb3df62baf32f7 p
  let p := step A 0x8000 0x31be135f97d08fd981231505542fcfa6 p
  let p := step A 0x10000 0x9aa508b5b7a84e1c677de54f3e99bc9 p
  let p := step A 0x20000 0x5d6af8dedb81196699c329225ee604 p
  let p := step A 0x40000 0x2216e584f5fa1ea926041bedfe98 p
  let p := step A 0x80000 0x48a170391f7dc42444e8fa2 p
  p

/-- Round a Q128.128 ratio up to Q64.96 and keep it in `uint160`. -/
def finalize (p : Nat) : Nat := yshr 32 (yadd p (ysub (yshl 32 1) 1)) % 2 ^ 160

/-- The value the function returns. -/
def sqrtPure (tick : Int) : Nat :=
  finalize (invert (toUnsigned 256 (tick24 tick)) (ladder (absTickOf tick)))

/-! ## Folding the join points -/

theorem step_fold {σ : Type} (A bit c p : Nat) (k : Unit → Nat → M σ Nat) :
    (if (A &&& bit != 0) = true then k () (mulw 256 p c >>> 128) else k () p)
      = k () (step A bit c p) := by
  unfold step; split <;> rfl

theorem invert_fold {σ : Type} (t p : Nat) (k : Unit → Nat → M σ Nat) :
    (if (ysgt t 0 != 0) = true then k () (ydiv (ynot 0) p) else k () p) = k () (invert t p) := by
  unfold invert; split <;> rfl

theorem maxTick_word : toUnsigned 256 TickMath.MAX_TICK = 887272 := by decide +kernel

/-! ## Guard, footprint and value -/

/-- Monadic form: `TickMath.getSqrtPriceAtTick` is `if absTick > MAX_TICK then revert else return
sqrtPure tick`. -/
theorem getSqrtPriceAtTick_eq {σ : Type} (ext : Ext σ) (tick : Int) :
    TickMath.getSqrtPriceAtTick ext tick
      = if absTickOf tick > 887272 then throw ⟨"revert"⟩ else pure (sqrtPure tick) := by
  unfold TickMath.getSqrtPriceAtTick
  extract_lets t0 sq t1 m A p0 k20 k19 k18 k17 k16 k15 k14 k13 k12 k11 k10 k9 k8 k7 k6 k5 k4
    k3 k2 k1 a2 p1 k0
  have hA : absTickOf tick = A := rfl
  have ht : tick24 tick = t1 := rfl
  have hp1 : p1 = mulw 256 p0 0xfff97272373d413259a46990580e213a >>> 128 := by
    simp only [p1, a2]
  have h0 : k0 () = if (A &&& 2 != 0) = true then k1 () p1 else k1 () p0 := rfl
  have h1 : ∀ p, k1 () p = k2 () (step A 0x4 0xfff2e50f5f656932ef12357cf3c7fdcc p) := by
    intro p; exact step_fold _ _ _ _ _
  have h2 : ∀ p, k2 () p = k3 () (step A 0x8 0xffe5caca7e10e4e61c3624eaa0941cd0 p) := by
    intro p; exact step_fold _ _ _ _ _
  have h3 : ∀ p, k3 () p = k4 () (step A 0x10 0xffcb9843d60f6159c9db58835c926644 p) := by
    intro p; exact step_fold _ _ _ _ _
  have h4 : ∀ p, k4 () p = k5 () (step A 0x20 0xff973b41fa98c081472e6896dfb254c0 p) := by
    intro p; exact step_fold _ _ _ _ _
  have h5 : ∀ p, k5 () p = k6 () (step A 0x40 0xff2ea16466c96a3843ec78b326b52861 p) := by
    intro p; exact step_fold _ _ _ _ _
  have h6 : ∀ p, k6 () p = k7 () (step A 0x80 0xfe5dee046a99a2a811c461f1969c3053 p) := by
    intro p; exact step_fold _ _ _ _ _
  have h7 : ∀ p, k7 () p = k8 () (step A 0x100 0xfcbe86c7900a88aedcffc83b479aa3a4 p) := by
    intro p; exact step_fold _ _ _ _ _
  have h8 : ∀ p, k8 () p = k9 () (step A 0x200 0xf987a7253ac413176f2b074cf7815e54 p) := by
    intro p; exact step_fold _ _ _ _ _
  have h9 : ∀ p, k9 () p = k10 () (step A 0x400 0xf3392b0822b70005940c7a398e4b70f3 p) := by
    intro p; exact step_fold _ _ _ _ _
  have h10 : ∀ p, k10 () p = k11 () (step A 0x800 0xe7159475a2c29b7443b29c7fa6e889d9 p) := by
    intro p; exact step_fold _ _ _ _ _
  have h11 : ∀ p, k11 () p = k12 () (step A 0x1000 0xd097f3bdfd2022b8845ad8f792aa5825 p) := by
    intro p; exact step_fold _ _ _ _ _
  have h12 : ∀ p, k12 () p = k13 () (step A 0x2000 0xa9f746462d870fdf8a65dc1f90e061e5 p) := by
    intro p; exact step_fold _ _ _ _ _
  have h13 : ∀ p, k13 () p = k14 () (step A 0x4000 0x70d869a156d2a1b890bb3df62baf32f7 p) := by
    intro p; exact step_fold _ _ _ _ _
  have h14 : ∀ p, k14 () p = k15 () (step A 0x8000 0x31be135f97d08fd981231505542fcfa6 p) := by
    intro p; exact step_fold _ _ _ _ _
  have h15 : ∀ p, k15 () p = k16 () (step A 0x10000 0x9aa508b5b7a84e1c677de54f3e99bc9 p) := by
    intro p; exact step_fold _ _ _ _ _
  have h16 : ∀ p, k16 () p = k17 () (step A 0x20000 0x5d6af8dedb81196699c329225ee604 p) := by
    intro p; exact step_fold _ _ _ _ _
  have h17 : ∀ p, k17 () p = k18 () (step A 0x40000 0x2216e584f5fa1ea926041bedfe98 p) := by
    intro p; exact step_fold _ _ _ _ _
  have h18 : ∀ p, k18 () p = k19 () (step A 0x80000 0x48a170391f7dc42444e8fa2 p) := by
    intro p; exact step_fold _ _ _ _ _
  have h19 : ∀ p, k19 () p = k20 () (invert (toUnsigned 256 t1) p) := by
    intro p; exact invert_fold _ _ _
  rw [maxTick_word, h0, hp1, step_fold, h1, h2, h3, h4, h5, h6, h7, h8, h9, h10, h11, h12, h13,
    h14, h15, h16, h17, h18, h19]
  unfold sqrtPure
  rw [hA, ht]
  by_cases hg : A > 887272
  · rw [ite_eq_left (decide_eq_true hg), ite_eq_left hg]
    rfl
  · rw [ite_eq_right (by simpa using hg), ite_eq_right hg]
    rfl

/-- Run form, any `tick : Int`: reverts with `"revert"` iff `absTickOf tick > 887272`; otherwise
returns `sqrtPure tick` and leaves the state unchanged (empty footprint, no external calls). -/
theorem getSqrtPriceAtTick_run {σ : Type} (ext : Ext σ) (tick : Int) (env : Env) (s : σ) :
    TickMath.getSqrtPriceAtTick ext tick env s
      = if absTickOf tick > 887272 then .error ⟨"revert"⟩ else .ok (sqrtPure tick, s) := by
  rw [getSqrtPriceAtTick_eq]
  split <;> rfl

/-! ## The int24 domain -/

theorem xor_allOnes (n y : Nat) (h : y < 2 ^ n) : (2 ^ n - 1) ^^^ y = 2 ^ n - 1 - y := by
  have e1 := BitVec.toNat_xor (BitVec.allOnes n) (BitVec.ofNat n y)
  rw [BitVec.allOnes_xor, BitVec.toNat_not, BitVec.toNat_allOnes, BitVec.toNat_ofNat,
    Nat.mod_eq_of_lt h] at e1
  exact e1.symm

theorem toUnsigned_cast (x : Int) :
    ((toUnsigned 256 x : Nat) : Int) = x % ((2 ^ 256 : Nat) : Int) := by
  unfold toUnsigned
  exact Int.toNat_of_nonneg (Int.emod_nonneg _ (by decide))

theorem sar_low (u : Nat) (h : u < 2 ^ 255) : ysar 255 u = 0 := by
  unfold ysar
  rw [ite_eq_left (by decide)]
  have hc := toUnsigned_cast (toSigned 256 u / ((2 ^ 255 : Nat) : Int))
  generalize toUnsigned 256 (toSigned 256 u / ((2 ^ 255 : Nat) : Int)) = r at hc ⊢
  unfold toSigned wrapI at hc
  simp only [Nat.reduceSub] at hc
  split at hc <;> omega

theorem sar_high (u : Nat) (h1 : 2 ^ 255 ≤ u) (h2 : u < 2 ^ 256) : ysar 255 u = 2 ^ 256 - 1 := by
  unfold ysar
  rw [ite_eq_left (by decide)]
  have hc := toUnsigned_cast (toSigned 256 u / ((2 ^ 255 : Nat) : Int))
  generalize toUnsigned 256 (toSigned 256 u / ((2 ^ 255 : Nat) : Int)) = r at hc ⊢
  unfold toSigned wrapI at hc
  simp only [Nat.reduceSub] at hc
  split at hc <;> omega

/-- On int24 inputs the narrowing `signextend(2, ·)` is the identity. -/
theorem tick24_eq (tick : Int) (h1 : -8388608 ≤ tick) (h2 : tick < 8388608) : tick24 tick = tick := by
  have hu := toUnsigned_cast tick
  unfold tick24 toSigned wrapI ysignextend W
  generalize toUnsigned 256 tick = u at hu ⊢
  simp only [Nat.reduceMul, Nat.reduceAdd, Nat.reduceSub, Nat.reduceLT, ↓reduceIte]
  by_cases hc : u % 2 ^ 24 ≥ 2 ^ 23
  · simp only [hc, ↓reduceIte]
    split <;> omega
  · simp only [hc, ↓reduceIte]
    split <;> omega

/-- On int24 inputs the assembly absolute value is `|tick|`. -/
theorem absTickOf_eq (tick : Int) (h1 : -8388608 ≤ tick) (h2 : tick < 8388608) :
    absTickOf tick = tick.natAbs := by
  unfold absTickOf
  rw [tick24_eq tick h1 h2]
  have hu := toUnsigned_cast tick
  generalize toUnsigned 256 tick = u at hu ⊢
  by_cases hs : 0 ≤ tick
  · rw [sar_low u (by omega)]
    unfold yxor yadd W
    rw [Nat.zero_xor]
    omega
  · rw [sar_high u (by omega) (by omega)]
    unfold yxor yadd W
    have e : (2 ^ 256 - 1 + u) % 2 ^ 256 = 2 ^ 256 - 1 - tick.natAbs := by omega
    rw [e, xor_allOnes 256 _ (by omega)]
    omega

/-- For an int24 tick: reverts iff `|tick| > MAX_TICK`; otherwise returns `sqrtPure tick`, state
unchanged. -/
theorem getSqrtPriceAtTick_int24 {σ : Type} (ext : Ext σ) (tick : Int)
    (h1 : -8388608 ≤ tick) (h2 : tick < 8388608) (env : Env) (s : σ) :
    TickMath.getSqrtPriceAtTick ext tick env s
      = if tick.natAbs > 887272 then .error ⟨"revert"⟩ else .ok (sqrtPure tick, s) := by
  rw [getSqrtPriceAtTick_run, absTickOf_eq tick h1 h2]

/-- For an int24 tick the call reverts exactly when `tick ∉ [MIN_TICK, MAX_TICK]`. -/
theorem getSqrtPriceAtTick_reverts_iff {σ : Type} (ext : Ext σ) (tick : Int)
    (h1 : -8388608 ≤ tick) (h2 : tick < 8388608) (env : Env) (s : σ) :
    (∃ e, TickMath.getSqrtPriceAtTick ext tick env s = .error e) ↔ (tick < -887272 ∨ 887272 < tick) := by
  rw [getSqrtPriceAtTick_int24 ext tick h1 h2]
  by_cases hg : tick.natAbs > 887272
  · simp only [hg, ↓reduceIte]
    exact ⟨fun _ => by omega, fun _ => ⟨_, rfl⟩⟩
  · simp only [hg, ↓reduceIte]
    exact ⟨(fun ⟨_, h⟩ => nomatch h), fun _ => by omega⟩

/-! ## Values at the anchors (Uniswap v4 constants) -/

/-- Tick 0 gives price 1: `sqrtPriceX96 = 2^96`. -/
theorem getSqrtPriceAtTick_zero {σ : Type} (ext : Ext σ) (env : Env) (s : σ) :
    TickMath.getSqrtPriceAtTick ext 0 env s = .ok (2 ^ 96, s) := by
  rw [getSqrtPriceAtTick_int24 ext 0 (by decide) (by decide)]
  have : sqrtPure 0 = 2 ^ 96 := by decide +kernel
  simp [this]

/-- `MIN_TICK` gives `MIN_SQRT_PRICE = 4295128739`. -/
theorem getSqrtPriceAtTick_minTick {σ : Type} (ext : Ext σ) (env : Env) (s : σ) :
    TickMath.getSqrtPriceAtTick ext (-887272) env s = .ok (4295128739, s) := by
  rw [getSqrtPriceAtTick_int24 ext _ (by decide) (by decide)]
  have : sqrtPure (-887272) = 4295128739 := by decide +kernel
  simp [this]

/-- `MAX_TICK` gives `MAX_SQRT_PRICE = 1461446703485210103287273052203988822378723970342`. -/
theorem getSqrtPriceAtTick_maxTick {σ : Type} (ext : Ext σ) (env : Env) (s : σ) :
    TickMath.getSqrtPriceAtTick ext 887272 env s
      = .ok (1461446703485210103287273052203988822378723970342, s) := by
  rw [getSqrtPriceAtTick_int24 ext _ (by decide) (by decide)]
  have : sqrtPure 887272 = 1461446703485210103287273052203988822378723970342 := by decide +kernel
  simp [this]

end AsyncSwap.Swarm.GetSqrtPriceAtTick
