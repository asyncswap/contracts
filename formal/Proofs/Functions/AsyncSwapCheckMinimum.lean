import Specs.AsyncSwap
import Proofs.Monad
import Proofs.Functions.AsyncSwapBest
open FormalAst Refinement AsyncSwap.Swarm.Best

/-!
# `AsyncFiller.checkMinimum` (src/AsyncSwap.sol)

`checkMinimum(poolId, isBuy, zeroForOne, amountIn, amountOutMin)` reads `minimum = book.minOrder`.
* `minimum = 0`: no check, returns.
* buy: reverts `BelowMinimumOrder` iff `amountIn < minimum`.
* sell: reverts `BelowMinimumOrder` if `amountOutMin < minimum`; otherwise reads the pool's
  `sqrtPriceX96 = p` (`StateLibrary.getSlot0`) and converts `amountIn` to the other token,
  `⌊⌊amountIn·p/2⁹⁶⌋·p/2⁹⁶⌋` (zeroForOne) or `⌊⌊amountIn·2⁹⁶/p⌋·2⁹⁶/p⌋` (oneForZero), and reverts
  `BelowMinimumOrder` iff that value is below `minimum`.

It never calls `self_set` or `book_set`: its footprint is empty.
-/

namespace AsyncSwap.Swarm.CheckMinimum

variable {σ : Type}

/-! ## Part A: reverts and footprint -/

/-- **Frame / revert characterisation.** If `book_get`, `self_get` and `getSlot0` keep `Q` and fail
only with `P`-errors, and `P` accepts `BelowMinimumOrder`, `panic 0x12` and `MathOverflowedMulDiv`,
then `checkMinimum` keeps `Q` and fails only with `P`-errors. -/
theorem checkMinimum_good (ext : Ext σ) (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (poolId : Nat) (isBuy zeroForOne : Bool)
    (amountIn amountOutMin : Nat) (Q : σ → Prop) (P : Revert → Prop)
    (hbg : Good Q P book_get) (hsg : Good Q P self_get)
    (hslot : ∀ m p, Good Q P (StateLibrary.getSlot0 ext m p))
    (hbelow : P ⟨"BelowMinimumOrder"⟩) (hdz : P (panic "0x12")) (hov : P ⟨"MathOverflowedMulDiv"⟩) :
    Good Q P (AsyncFiller.checkMinimum ext self_get self_set book_get book_set poolId isBuy
      zeroForOne amountIn amountOutMin) := by
  unfold AsyncFiller.checkMinimum mulDivFloor
  repeat' (first | (with_reducible apply hslot) | good_step)

/-- **Only its own three reverts.** If the reads and `getSlot0` never revert, every revert of
`checkMinimum` is `BelowMinimumOrder`, `panic 0x12` or `MathOverflowedMulDiv`. -/
theorem checkMinimum_reverts (ext : Ext σ) (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (poolId : Nat) (isBuy zeroForOne : Bool)
    (amountIn amountOutMin : Nat)
    (hbg : Good (fun _ => True) (fun _ => False) book_get)
    (hsg : Good (fun _ => True) (fun _ => False) self_get)
    (hslot : ∀ m p, Good (fun _ => True) (fun _ => False) (StateLibrary.getSlot0 ext m p))
    (r : Env) (s : σ) (e : Revert)
    (h : AsyncFiller.checkMinimum ext self_get self_set book_get book_set poolId isBuy
      zeroForOne amountIn amountOutMin r s = .error e) :
    e = ⟨"BelowMinimumOrder"⟩ ∨ e = panic "0x12" ∨ e = ⟨"MathOverflowedMulDiv"⟩ := by
  have hg := checkMinimum_good ext self_get self_set book_get book_set poolId isBuy zeroForOne
    amountIn amountOutMin (fun _ => True)
    (fun e => e = ⟨"BelowMinimumOrder"⟩ ∨ e = panic "0x12" ∨ e = ⟨"MathOverflowedMulDiv"⟩)
    (fun r s _ => by have := hbg r s trivial; split at this <;> simp_all)
    (fun r s _ => by have := hsg r s trivial; split at this <;> simp_all)
    (fun m p r s _ => by have := hslot m p r s trivial; split at this <;> simp_all)
    (Or.inl rfl) (Or.inr (Or.inl rfl)) (Or.inr (Or.inr rfl)) r s trivial
  rw [h] at hg
  exact hg

/-- **Empty footprint.** `checkMinimum` does not depend on the setters: it never writes storage. -/
theorem checkMinimum_setters_irrelevant (ext : Ext σ) (self_get : M σ AsyncFiller.State_)
    (self_set self_set' : AsyncFiller.State_ → M σ Unit) (book_get : M σ AsyncFiller.Book)
    (book_set book_set' : AsyncFiller.Book → M σ Unit) (poolId : Nat) (isBuy zeroForOne : Bool)
    (amountIn amountOutMin : Nat) :
    AsyncFiller.checkMinimum ext self_get self_set book_get book_set poolId isBuy zeroForOne
        amountIn amountOutMin
      = AsyncFiller.checkMinimum ext self_get self_set' book_get book_set' poolId isBuy zeroForOne
        amountIn amountOutMin := by
  unfold AsyncFiller.checkMinimum
  rfl

/-! ## Part B: exact outcomes -/

/-- **No minimum.** When `book.minOrder = 0`, `checkMinimum` succeeds and leaves the state the
book read left. -/
theorem checkMinimum_zero (ext : Ext σ) (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (poolId : Nat) (isBuy zeroForOne : Bool)
    (amountIn amountOutMin : Nat) (r : Env) (s s1 : σ) (b : AsyncFiller.Book)
    (hb : book_get r s = .ok (b, s1)) (hm : b.minOrder = 0) :
    AsyncFiller.checkMinimum ext self_get self_set book_get book_set poolId isBuy zeroForOne
      amountIn amountOutMin r s = .ok ((), s1) := by
  unfold AsyncFiller.checkMinimum
  simp [hb, hm]

/-- **Buy.** With a non-zero minimum, a buy reverts `BelowMinimumOrder` exactly when
`amountIn < minOrder`, and otherwise succeeds without touching the pool. -/
theorem checkMinimum_buy (ext : Ext σ) (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (poolId : Nat) (zeroForOne : Bool)
    (amountIn amountOutMin : Nat) (r : Env) (s s1 : σ) (b : AsyncFiller.Book)
    (hb : book_get r s = .ok (b, s1)) (hm : b.minOrder ≠ 0) :
    AsyncFiller.checkMinimum ext self_get self_set book_get book_set poolId true zeroForOne
      amountIn amountOutMin r s
      = if amountIn < b.minOrder then .error ⟨"BelowMinimumOrder"⟩ else .ok ((), s1) := by
  unfold AsyncFiller.checkMinimum
  by_cases hlt : amountIn < b.minOrder <;> simp [hb, hm, hlt]

/-- **Sell, output minimum too small.** With a non-zero minimum, a sell with
`amountOutMin < minOrder` reverts `BelowMinimumOrder`. -/
theorem checkMinimum_sell_below (ext : Ext σ) (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (poolId : Nat) (zeroForOne : Bool)
    (amountIn amountOutMin : Nat) (r : Env) (s s1 : σ) (b : AsyncFiller.Book)
    (hb : book_get r s = .ok (b, s1)) (hm : b.minOrder ≠ 0) (hlt : amountOutMin < b.minOrder) :
    AsyncFiller.checkMinimum ext self_get self_set book_get book_set poolId false zeroForOne
      amountIn amountOutMin r s = .error ⟨"BelowMinimumOrder"⟩ := by
  unfold AsyncFiller.checkMinimum
  simp [hb, hm, hlt]

/-- **Sell, zeroForOne.** With a non-zero minimum, `amountOutMin ≥ minOrder`, pool price
`sqrtPriceX96 = p` and products that fit 256 bits, the sell reverts `BelowMinimumOrder` exactly
when `⌊⌊amountIn·p/2⁹⁶⌋·p/2⁹⁶⌋ < minOrder`. -/
theorem checkMinimum_sell_zeroForOne (ext : Ext σ) (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (poolId : Nat)
    (amountIn amountOutMin : Nat) (r : Env) (s s1 s2 s3 : σ) (b : AsyncFiller.Book)
    (st : AsyncFiller.State_) (p : Nat) (q : Int × Nat × Nat)
    (hb : book_get r s = .ok (b, s1)) (hm : b.minOrder ≠ 0) (hge : ¬ amountOutMin < b.minOrder)
    (hsg : self_get r s1 = .ok (st, s2))
    (hslot : StateLibrary.getSlot0 ext st.poolManager poolId r s2 = .ok ((p, q), s3))
    (hfit1 : amountIn * p < 2 ^ 256) (hfit2 : amountIn * p / 2 ^ 96 * p < 2 ^ 256) :
    AsyncFiller.checkMinimum ext self_get self_set book_get book_set poolId false true
      amountIn amountOutMin r s
      = if amountIn * p / 2 ^ 96 * p / 2 ^ 96 < b.minOrder then .error ⟨"BelowMinimumOrder"⟩
        else .ok ((), s3) := by
  unfold AsyncFiller.checkMinimum mulDivFloor
  by_cases hlt : amountIn * p / 2 ^ 96 * p / 2 ^ 96 < b.minOrder <;>
    simp [hb, hm, hge, hsg, hslot, hfit1, hfit2, hlt]

/-- **Sell, oneForZero.** With a non-zero minimum, `amountOutMin ≥ minOrder`, pool price
`sqrtPriceX96 = p ≠ 0` and products that fit 256 bits, the sell reverts `BelowMinimumOrder`
exactly when `⌊⌊amountIn·2⁹⁶/p⌋·2⁹⁶/p⌋ < minOrder`. -/
theorem checkMinimum_sell_oneForZero (ext : Ext σ) (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (poolId : Nat)
    (amountIn amountOutMin : Nat) (r : Env) (s s1 s2 s3 : σ) (b : AsyncFiller.Book)
    (st : AsyncFiller.State_) (p : Nat) (q : Int × Nat × Nat)
    (hb : book_get r s = .ok (b, s1)) (hm : b.minOrder ≠ 0) (hge : ¬ amountOutMin < b.minOrder)
    (hsg : self_get r s1 = .ok (st, s2))
    (hslot : StateLibrary.getSlot0 ext st.poolManager poolId r s2 = .ok ((p, q), s3))
    (hp : p ≠ 0)
    (hfit1 : amountIn * 2 ^ 96 < 2 ^ 256) (hfit2 : amountIn * 2 ^ 96 / p * 2 ^ 96 < 2 ^ 256) :
    AsyncFiller.checkMinimum ext self_get self_set book_get book_set poolId false false
      amountIn amountOutMin r s
      = if amountIn * 2 ^ 96 / p * 2 ^ 96 / p < b.minOrder then .error ⟨"BelowMinimumOrder"⟩
        else .ok ((), s3) := by
  unfold AsyncFiller.checkMinimum mulDivFloor
  by_cases hlt : amountIn * 2 ^ 96 / p * 2 ^ 96 / p < b.minOrder <;>
    simp [hb, hm, hge, hsg, hslot, hfit1, hfit2, hp, hlt]

/-- **Sell, oneForZero, uninitialised pool.** When the pool's `sqrtPriceX96` is `0`, the
oneForZero conversion divides by zero and `checkMinimum` reverts (`panic 0x12`, or
`MathOverflowedMulDiv` when `amountIn·2⁹⁶` exceeds one word). -/
theorem checkMinimum_sell_oneForZero_price_zero (ext : Ext σ) (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (poolId : Nat)
    (amountIn amountOutMin : Nat) (r : Env) (s s1 s2 s3 : σ) (b : AsyncFiller.Book)
    (st : AsyncFiller.State_) (q : Int × Nat × Nat)
    (hb : book_get r s = .ok (b, s1)) (hm : b.minOrder ≠ 0) (hge : ¬ amountOutMin < b.minOrder)
    (hsg : self_get r s1 = .ok (st, s2))
    (hslot : StateLibrary.getSlot0 ext st.poolManager poolId r s2 = .ok ((0, q), s3)) :
    AsyncFiller.checkMinimum ext self_get self_set book_get book_set poolId false false
      amountIn amountOutMin r s
      = .error (if amountIn * 2 ^ 96 < 2 ^ 256 then panic "0x12" else ⟨"MathOverflowedMulDiv"⟩) := by
  unfold AsyncFiller.checkMinimum mulDivFloor
  by_cases hfit : amountIn * 2 ^ 96 < 2 ^ 256 <;> simp [hb, hm, hge, hsg, hslot, hfit]

end AsyncSwap.Swarm.CheckMinimum
