import Generated.AsyncSwap
import Refinement.Monad
import Refinement.Swarm.AsyncSwapMostSignificantBit
import Refinement.Swarm.AsyncSwapGetSqrtPriceAtTick
open FormalAst Refinement

/-!
# `TickMath.getTickAtSqrtPrice` (src/AsyncSwap.sol, Uniswap v4 `TickMath`)

Reverts `InvalidSqrtPrice` unless `MIN_SQRT_PRICE ≤ sqrtPriceX96 < MAX_SQRT_PRICE`; then takes
`price = sqrtPriceX96 << 32`, `msb = mostSignificantBit(price)`, normalises `r` to 128 significant
bits, computes `log_2(price)` with 14 fractional bits by the squaring ladder (assembly), scales to
`log_sqrt10001`, derives the two candidate ticks `tickLow`, `tickHi`, and returns `tickHi` when
`getSqrtPriceAtTick(tickHi) ≤ sqrtPriceX96`, else `tickLow`.

* `getTickAtSqrtPrice_eq`: in range, the function *is* `msb ← mostSignificantBit(price); tailR …`
  (the generated join points folded into `norm`, `logR`, `tailR`).
* `guard_iff`: for a `uint160` input the range guard is exactly `p ∉ [MIN_SQRT_PRICE, MAX_SQRT_PRICE)`.
* `getTickAtSqrtPrice_out_of_range`: out of range it reverts.
* `getTickAtSqrtPrice_run`: in range, the full run: never hits the msb `require`, never changes the
  state, returns `tickLow` when the candidates agree, else `tickHi` iff `sqrtPrice(tickHi) ≤ p`.
* `getTickAtSqrtPrice_result`: any successful result is `tickLow` or `tickHi`, the state is
  unchanged, and `tickHi` is returned (when distinct from `tickLow`) only if its sqrt price is `≤ p`.
-/

namespace AsyncSwap.Swarm.GetTickAtSqrtPrice

open AsyncSwap.Swarm.MostSignificantBit AsyncSwap.Swarm.GetSqrtPriceAtTick

/-- One rung of the log ladder: square `r` (Q1.127), read the overflow bit `f`, set bit `k` of
`log_2` when it is 1, and halve `r` back. -/
def rung (k : Nat) (st : Nat × Int) : Nat × Int :=
  let r := yshr 127 (ymul st.1 st.1)
  let f := yshr 128 r
  (yshr f r, toSigned 256 (yor (toUnsigned 256 st.2) (yshl k f)))

/-- `r` normalised to 128 significant bits from the price `x` and its msb. -/
def norm (x msb : Nat) : Nat :=
  if msb ≥ 128 then x >>> (subw 256 msb 127) else shlw 256 x (subw 256 127 msb)

/-- Integer part of `log_2`: `(msb - 128) << 64`. -/
def log0 (msb : Nat) : Int :=
  wrapI 256 ((wrapI 256 ((toSigned 256 msb) - 128)) * ((2 ^ 64 : Nat) : Int))

/-- `log_2` in Q64.64 with 14 fractional bits, from the normalised `r` and the msb. -/
def logR (r msb : Nat) : Int :=
  (rung 50 (rung 51 (rung 52 (rung 53 (rung 54 (rung 55 (rung 56 (rung 57 (rung 58 (rung 59
    (rung 60 (rung 61 (rung 62 (rung 63 (r, log0 msb))))))))))))))).2

def tickLowOf (L : Int) : Int :=
  wrapI 24 ((wrapI 256 (wrapI 256 (L * 255738958999603826347141)
    - 3402992956809132418596140100660247210)) / ((2 ^ 128 : Nat) : Int))

def tickHiOf (L : Int) : Int :=
  wrapI 24 ((wrapI 256 (wrapI 256 (L * 255738958999603826347141)
    + 291339464771989622907027621153398088495)) / ((2 ^ 128 : Nat) : Int))

/-- The Q128.128 price `x = sqrtPriceX96 << 32`. -/
def priceOf (p : Nat) : Nat := shlw 256 p 32

/-- The tail after the msb: pick between the two candidate ticks. -/
def tailR {σ : Type} (ext : Ext σ) (p msb r : Nat) : M σ Int :=
  if (tickLowOf (logR r msb) == tickHiOf (logR r msb)) then
    pure (tickLowOf (logR r msb))
  else do
    let t ← TickMath.getSqrtPriceAtTick ext (tickHiOf (logR r msb))
    pure (if decide (t ≤ p) then tickHiOf (logR r msb) else tickLowOf (logR r msb))

/-- The log the function computes for `p` (with the msb of the price). -/
def logOf (p : Nat) : Int := logR (norm (priceOf p) (msbPure (priceOf p))) (msbPure (priceOf p))

/-- The range guard as the model states it. -/
def Guard (p : Nat) : Prop :=
  subw 160 p TickMath.MIN_SQRT_PRICE > TickMath.MAX_SQRT_PRICE_MINUS_MIN_SQRT_PRICE_MINUS_ONE

/-- Monadic form, past the range guard. -/
theorem getTickAtSqrtPrice_eq {σ : Type} (ext : Ext σ) (p : Nat) (hg : ¬ Guard p) :
    TickMath.getTickAtSqrtPrice ext p =
      (do let msb ← BitMath.mostSignificantBit ext (priceOf p); tailR ext p msb (norm (priceOf p) msb)) := by
  unfold Guard at hg
  unfold TickMath.getTickAtSqrtPrice
  simp (config := { zeta := false }) only [hg, decide_false, Bool.false_eq_true, ↓reduceIte]
  apply congrArg (fun k => BitMath.mostSignificantBit ext (priceOf p) >>= k)
  funext msb
  extract_lets
  split
  · rename_i h
    have hm : msb ≥ 128 := of_decide_eq_true h
    rw [show norm (priceOf p) msb = priceOf p >>> (subw 256 msb 127) by simp [norm, hm]]
    rfl
  · rename_i h
    have hm : ¬ msb ≥ 128 := fun hm => h (decide_eq_true hm)
    rw [show norm (priceOf p) msb = shlw 256 (priceOf p) (subw 256 127 msb) by simp [norm, hm]]
    rfl

/-- Out of range (the guard holds) the function reverts `InvalidSqrtPrice`. -/
theorem getTickAtSqrtPrice_out_of_range {σ : Type} (ext : Ext σ) (p : Nat) (env : Env) (s : σ)
    (hg : Guard p) :
    TickMath.getTickAtSqrtPrice ext p env s = .error ⟨"revert"⟩ := by
  unfold Guard at hg
  simp [TickMath.getTickAtSqrtPrice, hg, CustomRevert.revertWith]

/-- For a `uint160` input, the guard is exactly "outside `[MIN_SQRT_PRICE, MAX_SQRT_PRICE)`". -/
theorem guard_iff (p : Nat) (hp : p < 2 ^ 160) :
    Guard p ↔ ¬ (TickMath.MIN_SQRT_PRICE ≤ p ∧ p < TickMath.MAX_SQRT_PRICE) := by
  unfold Guard subw TickMath.MIN_SQRT_PRICE TickMath.MAX_SQRT_PRICE
    TickMath.MAX_SQRT_PRICE_MINUS_MIN_SQRT_PRICE_MINUS_ONE
  omega

/-- In range, the Q128.128 price is `p * 2^32 > 0`. -/
theorem priceOf_pos (p : Nat) (hp : p < 2 ^ 160) (hmin : TickMath.MIN_SQRT_PRICE ≤ p) :
    priceOf p > 0 := by
  unfold priceOf shlw
  unfold TickMath.MIN_SQRT_PRICE at hmin
  rw [Nat.shiftLeft_eq, Nat.mod_eq_of_lt (by omega)]
  omega

/-- The tail, run: no writes, picks `tickLow` or `tickHi`, reverts only if `getSqrtPriceAtTick`
does on `tickHi`. -/
theorem tailR_run {σ : Type} (ext : Ext σ) (p msb r : Nat) (env : Env) (s : σ) :
    tailR ext p msb r env s =
      if tickLowOf (logR r msb) = tickHiOf (logR r msb) then .ok (tickLowOf (logR r msb), s)
      else if absTickOf (tickHiOf (logR r msb)) > 887272 then .error ⟨"revert"⟩
      else .ok ((if sqrtPure (tickHiOf (logR r msb)) ≤ p then tickHiOf (logR r msb)
                 else tickLowOf (logR r msb)), s) := by
  unfold tailR
  by_cases he : tickLowOf (logR r msb) = tickHiOf (logR r msb)
  · simp [he]
  · by_cases ha : absTickOf (tickHiOf (logR r msb)) > 887272
    · simp [he, ha, getSqrtPriceAtTick_run]
    · simp [he, ha, getSqrtPriceAtTick_run]

/-- **Run, in range.** For `MIN_SQRT_PRICE ≤ p < MAX_SQRT_PRICE` the msb `require` never fires, the
state is never changed, and the result is `tickLow` when the two candidates agree, otherwise
`tickHi` exactly when `getSqrtPriceAtTick(tickHi) ≤ p` (reverting only if `tickHi` is not a valid
tick). -/
theorem getTickAtSqrtPrice_run {σ : Type} (ext : Ext σ) (p : Nat) (env : Env) (s : σ)
    (hp : p < 2 ^ 160) (hmin : TickMath.MIN_SQRT_PRICE ≤ p) (hmax : p < TickMath.MAX_SQRT_PRICE) :
    TickMath.getTickAtSqrtPrice ext p env s =
      if tickLowOf (logOf p) = tickHiOf (logOf p) then .ok (tickLowOf (logOf p), s)
      else if absTickOf (tickHiOf (logOf p)) > 887272 then .error ⟨"revert"⟩
      else .ok ((if sqrtPure (tickHiOf (logOf p)) ≤ p then tickHiOf (logOf p)
                 else tickLowOf (logOf p)), s) := by
  have hg : ¬ Guard p := fun h => (guard_iff p hp).1 h ⟨hmin, hmax⟩
  rw [getTickAtSqrtPrice_eq ext p hg]
  simp only [run_bind, mostSignificantBit_run, priceOf_pos p hp hmin, ↓reduceIte]
  rw [tailR_run]
  rfl

/-- **Result.** Any successful run on a `uint160` input leaves the state unchanged and returns one
of the two candidates; `tickHi` (when it differs from `tickLow`) only if its sqrt price is `≤ p`. -/
theorem getTickAtSqrtPrice_result {σ : Type} (ext : Ext σ) (p : Nat) (env : Env) (s s' : σ) (t : Int)
    (hp : p < 2 ^ 160) (h : TickMath.getTickAtSqrtPrice ext p env s = .ok (t, s')) :
    s' = s ∧ TickMath.MIN_SQRT_PRICE ≤ p ∧ p < TickMath.MAX_SQRT_PRICE ∧
      (t = tickLowOf (logOf p) ∨
        (t = tickHiOf (logOf p) ∧ absTickOf t ≤ 887272 ∧ sqrtPure t ≤ p)) := by
  by_cases hg : Guard p
  · rw [getTickAtSqrtPrice_out_of_range ext p env s hg] at h; cases h
  have hr : TickMath.MIN_SQRT_PRICE ≤ p ∧ p < TickMath.MAX_SQRT_PRICE :=
    Classical.byContradiction fun hc => hg ((guard_iff p hp).2 hc)
  obtain ⟨hmin, hmax⟩ := hr
  rw [getTickAtSqrtPrice_run ext p env s hp hmin hmax] at h
  refine ⟨?_, hmin, hmax, ?_⟩
  · split at h
    · cases h; rfl
    · split at h
      · cases h
      · cases h; rfl
  · split at h
    · cases h; exact Or.inl rfl
    · split at h
      · cases h
      · rename_i ha
        cases h
        split
        · rename_i hle; exact Or.inr ⟨rfl, by omega, hle⟩
        · exact Or.inl rfl

/-- The function never writes storage: every run either reverts or returns the state unchanged. -/
theorem getTickAtSqrtPrice_no_write {σ : Type} (ext : Ext σ) (p : Nat) (env : Env) (s s' : σ) (t : Int)
    (hp : p < 2 ^ 160) (h : TickMath.getTickAtSqrtPrice ext p env s = .ok (t, s')) : s' = s :=
  (getTickAtSqrtPrice_result ext p env s s' t hp h).1

end AsyncSwap.Swarm.GetTickAtSqrtPrice
