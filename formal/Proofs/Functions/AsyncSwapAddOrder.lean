import Specs.AsyncSwap
import Proofs.Monad
import Proofs.Functions.AsyncSwapPriceKey
import Proofs.Functions.AsyncSwapCheckMinimum
open FormalAst Refinement

/-!
# `AsyncFiller.addOrder`, `AsyncMatching.addOrder` and the re-key: is the price-key denominator
nonzero at each call site? (src/libraries/AsyncFiller.sol, src/AsyncSwap.sol)

`_priceKey isBuy zfo a b` (= `TickPrice.key`) reverts exactly when its denominator
`den = if zfo then a else b` is zero, with panic `0x12`, and otherwise returns a key in
`[1, 1774545]` with the state unchanged (`AsyncSwap.Swarm.PriceKey.priceKey_spec`). So the question at
each call site is whether its own guards force `den ≠ 0`.

* `AsyncFiller.addOrder` (`addOrder_split`) is `feeStep` (priority-fee guards and the fee pull), then
  `_priceKey isBuy zfo amountIn amountOutMin`, then `tail` (sequence bump, order write, `_append`).
  - `addOrder_key_ok`: if `den ≠ 0`, the key step succeeds with some `k ∈ [1, 1774545]` and leaves
    the state `feeStep` produced: `addOrder` is `tail k` from there.
  - `addOrder_key_zero`: if `den = 0` and the fee step passed, `addOrder` reverts panic `0x12`. The
    library itself has **no** zero-amount guard; it relies on its caller.
* `AsyncMatching.addOrder` (`matching_addOrder_split`) is `checkMinimum` then `AsyncFiller.addOrder`.
  - `matching_addOrder_zeroMin_gap`: with `minOrder = 0`, `checkMinimum` passes anything, so a
    zeroForOne order with `amountIn = 0` reaches the key and reverts panic `0x12`.
  - `matching_addOrder_buy_ok`: with `minOrder ≠ 0`, a zeroForOne buy past `checkMinimum` has
    `amountIn ≥ minOrder ≥ 1`, so the key succeeds.
  The guard that closes the gap sits in the caller, `AsyncSwap._createOrder`
  (`if (amountIn == 0 || hookData.amountOutMin == 0) revert ZeroAmount();`), which is opaque in the
  model (`fn_AsyncSwap_createOrder_1683`); its Foundry evidence is
  `test/formal/AsyncSwapBeforeSwapPriceKey.t.sol`.
* `updatePrice` (`AsyncSwap.Swarm.UpdatePriceFiller.updatePrice_error`): `ZeroAmount`
  excludes `newAmountOutMin = 0`, `OrderNotFound` excludes `amountIn = 0` before `_remove`.
* Partial-fill re-key in `AsyncMatching._reduceAfterMatch`:
  `_priceKey isBuy zfo remainingInput remainingMinimum` with
  `remainingMinimum = mulDiv(amountOutMin, remainingInput, oldInput, Ceil)`. The early-exit guard
  (`remainingInput == 0 → close`) gives `remainingInput ≠ 0`. `mulDivRnd_ceil_pos`: a successful
  ceiling `mulDiv` of two nonzero factors is nonzero. Hence `rekey_priceKey_ok`: when the resting
  order's `amountOutMin ≠ 0`, the re-key never reverts. `rekey_den_sell`: for a sell with
  `minOrder ≠ 0`, the `remainingMinimum < minOrder` guard alone gives `den ≠ 0`.
-/

namespace AsyncSwap.Swarm.AddOrderKey

variable {σ : Type} (ext : Ext σ)

/-! ## Monad laws used for the decomposition -/

theorem ite_bind' {α β : Type} (c : Prop) [Decidable c] (x y : M σ α) (f : α → M σ β) :
    ((if c then x else y) >>= f) = if c then x >>= f else y >>= f := by
  split <;> rfl

theorem throw_bind' {α β : Type} (e : Revert) (f : α → M σ β) :
    ((throw e : M σ α) >>= f) = throw e := by
  funext r s; simp only [run_bind, run_throw]

/-! ## `AsyncFiller.addOrder` -/

/-- The part of `addOrder` before the price key: priority-fee guards, then the fee pull. -/
def feeStep (sg : M σ AsyncFiller.State_) (isBuy : Bool) (aIn aOut fee : Nat) : M σ Unit := do
  let __t1 ← AsyncFiller.minPriorityFee ext (if isBuy then aIn else aOut)
  if (decide (fee < __t1)) then
    throw ⟨"PriorityFeeTooSmall"⟩
  if (decide (fee > AsyncFiller.MAX_PRIORITY_FEE)) then
    throw ⟨"PriorityFeeTooLarge"⟩
  if (fee != 0) then
    let __t2 ← sg
    let __t3 ← sg
    CurrencySettler.take ext ((__t2).numeraire) ((__t3).poolManager) ((← read).self) fee true

/-- The part of `addOrder` after the price key `price`: sequence bump, order write, `_append`. -/
def tail (sg : M σ AsyncFiller.State_) (ss : AsyncFiller.State_ → M σ Unit)
    (bg : M σ AsyncFiller.Book) (bs : AsyncFiller.Book → M σ Unit)
    (id owner aIn aOut : Nat) (isBuy zfo : Bool) (fee price : Nat) : M σ Unit := do
  let __t5 ← bg
  let a6 := (__t5).nextSequence
  let __t7 ← addc 64 a6 1
  let __t8 ← bg
  bs ({ (__t8) with nextSequence := __t7 })
  let __t9 ← AsyncFiller.«_priorityKey» ext (fee % 2 ^ 64) __t7
  let a10 := ({ owner := owner, amountIn := aIn, amountOutMin := aOut, price := price, isBuy := isBuy, zeroForOne := zfo, sequence := __t7, priorityFee := (fee % 2 ^ 64), priorityKey := __t9, createdSequence := __t7 } : AsyncFiller.OrderInfo)
  let __t11 ← sg
  ss ({ (__t11) with orders := upd ((__t11).orders) id (a10) })
  AsyncFiller.«_append» ext (do return (← sg)) (fun x => do ss (x)) (do return (← bg)) (fun x => do bs (x)) id
  return ()

variable (sg : M σ AsyncFiller.State_) (ss : AsyncFiller.State_ → M σ Unit)
  (bg : M σ AsyncFiller.Book) (bs : AsyncFiller.Book → M σ Unit)

/-- **Decomposition.** `AsyncFiller.addOrder` is the fee step, then
`_priceKey isBuy zfo amountIn amountOutMin`, then the tail on the key. -/
theorem addOrder_split (id owner aIn aOut : Nat) (isBuy zfo : Bool) (fee : Nat) :
    AsyncFiller.addOrder ext sg ss bg bs id owner aIn aOut isBuy zfo fee =
      (feeStep ext sg isBuy aIn aOut fee >>= fun _ =>
        AsyncFiller.«_priceKey» ext isBuy zfo aIn aOut >>= fun p =>
          tail ext sg ss bg bs id owner aIn aOut isBuy zfo fee p) := by
  simp only [AsyncFiller.addOrder, feeStep, tail, bind_assoc, ite_bind', throw_bind', pure_bind]

/-- A revert of the fee step is a revert of `AsyncFiller.addOrder`. -/
theorem addOrder_fee_error (id owner aIn aOut : Nat) (isBuy zfo : Bool) (fee : Nat) (r : Env) (s : σ)
    (e : Revert) (hf : feeStep ext sg isBuy aIn aOut fee r s = .error e) :
    AsyncFiller.addOrder ext sg ss bg bs id owner aIn aOut isBuy zfo fee r s = .error e := by
  rw [addOrder_split, run_bind, hf]

/-- **Nonzero denominator: the key never reverts.** If `den ≠ 0` and the fee step leaves `s₁`,
the key step returns some `k ∈ [1, 1774545]` without touching the state, and
`AsyncFiller.addOrder` is the tail on `k` from `s₁`. -/
theorem addOrder_key_ok (id owner aIn aOut : Nat) (isBuy zfo : Bool) (fee : Nat) (r : Env) (s s1 : σ)
    (hden : (if zfo then aIn else aOut) ≠ 0)
    (hf : feeStep ext sg isBuy aIn aOut fee r s = .ok ((), s1)) :
    ∃ k, 1 ≤ k ∧ k ≤ 1774545 ∧
      AsyncFiller.addOrder ext sg ss bg bs id owner aIn aOut isBuy zfo fee r s =
        tail ext sg ss bg bs id owner aIn aOut isBuy zfo fee k r s1 := by
  rcases AsyncSwap.Swarm.PriceKey.priceKey_spec ext isBuy zfo aIn aOut r s1 with
    ⟨hd, _⟩ | ⟨_, k, hk, k1, k2⟩
  · exact absurd hd hden
  · refine ⟨k, k1, k2, ?_⟩
    rw [addOrder_split, run_bind, hf]
    simp only [run_bind, hk]

/-- **Zero denominator: the library has no guard of its own.** If `den = 0` and the fee step
passed, `AsyncFiller.addOrder` reverts with panic `0x12` from the price key. -/
theorem addOrder_key_zero (id owner aIn aOut : Nat) (isBuy zfo : Bool) (fee : Nat) (r : Env) (s s1 : σ)
    (hden : (if zfo then aIn else aOut) = 0)
    (hf : feeStep ext sg isBuy aIn aOut fee r s = .ok ((), s1)) :
    AsyncFiller.addOrder ext sg ss bg bs id owner aIn aOut isBuy zfo fee r s =
      .error (panic "0x12") := by
  rcases AsyncSwap.Swarm.PriceKey.priceKey_spec ext isBuy zfo aIn aOut r s1 with
    ⟨_, he⟩ | ⟨hd, _⟩
  · rw [addOrder_split, run_bind, hf]
    simp only [run_bind, he]
  · exact absurd hden hd

/-- Under a passing fee step, `AsyncFiller.addOrder`'s key step reverts iff `den = 0`. -/
theorem addOrder_key_reverts_iff (id owner aIn aOut : Nat) (isBuy zfo : Bool) (fee : Nat) (r : Env)
    (s s1 : σ) (hf : feeStep ext sg isBuy aIn aOut fee r s = .ok ((), s1)) :
    (AsyncFiller.addOrder ext sg ss bg bs id owner aIn aOut isBuy zfo fee r s =
        .error (panic "0x12") ∧
      ∃ e, AsyncFiller.«_priceKey» ext isBuy zfo aIn aOut r s1 = .error e) ↔
      (if zfo then aIn else aOut) = 0 := by
  constructor
  · rintro ⟨-, h⟩
    exact (AsyncSwap.Swarm.PriceKey.priceKey_reverts_iff ext isBuy zfo aIn aOut r s1).1 h
  · intro hd
    exact ⟨addOrder_key_zero ext sg ss bg bs id owner aIn aOut isBuy zfo fee r s s1 hd hf,
      (AsyncSwap.Swarm.PriceKey.priceKey_reverts_iff ext isBuy zfo aIn aOut r s1).2 hd⟩

/-! ## `AsyncMatching.addOrder`: `checkMinimum`, then `AsyncFiller.addOrder` -/

/-- **Decomposition.** `AsyncMatching.addOrder` runs `checkMinimum` on the order's fields, then
`AsyncFiller.addOrder` on them. -/
theorem matching_addOrder_split (order : AsyncFiller.NewOrder) :
    AsyncMatching.addOrder ext sg ss bg bs order =
      (AsyncFiller.checkMinimum ext sg ss bg bs order.poolId order.isBuy order.zeroForOne
          order.amountIn order.amountOutMin >>= fun _ =>
        AsyncFiller.addOrder ext sg ss bg bs order.id order.owner order.amountIn order.amountOutMin
          order.isBuy order.zeroForOne order.priorityFee) := by
  simp only [AsyncMatching.addOrder, bind_pure_unit]

/-- **The gap at the library boundary.** With `minOrder = 0`, a zeroForOne order with
`amountIn = 0` whose fee step passes reverts panic `0x12` in `AsyncMatching.addOrder` (the
`ZeroAmount` check lives one hop up, in `AsyncSwap._createOrder`). -/
theorem matching_addOrder_zeroMin_gap (order : AsyncFiller.NewOrder) (r : Env) (s s0 s1 : σ)
    (b : AsyncFiller.Book) (hb : bg r s = .ok (b, s0)) (hm : b.minOrder = 0)
    (hz : order.zeroForOne = true) (ha : order.amountIn = 0)
    (hf : feeStep ext sg order.isBuy order.amountIn order.amountOutMin order.priorityFee r s0 =
      .ok ((), s1)) :
    AsyncMatching.addOrder ext sg ss bg bs order r s = .error (panic "0x12") := by
  rw [matching_addOrder_split, run_bind,
    AsyncSwap.Swarm.CheckMinimum.checkMinimum_zero ext sg ss bg bs _ _ _ _ _ r s s0 b hb hm]
  exact addOrder_key_zero ext sg ss bg bs _ _ _ _ _ _ _ r s0 s1 (by simp [hz, ha]) hf

/-- **A minimum covers a zeroForOne buy.** With `minOrder ≠ 0`, a zeroForOne buy that passes
`checkMinimum` has `amountIn ≥ minOrder ≥ 1`, so its key step cannot revert: after a passing fee
step `AsyncMatching.addOrder` is the tail on a key in `[1, 1774545]`. -/
theorem matching_addOrder_buy_ok (order : AsyncFiller.NewOrder) (r : Env) (s s0 s1 : σ)
    (b : AsyncFiller.Book) (hb : bg r s = .ok (b, s0)) (hm : b.minOrder ≠ 0)
    (hbuy : order.isBuy = true) (hz : order.zeroForOne = true)
    (hcm : AsyncFiller.checkMinimum ext sg ss bg bs order.poolId order.isBuy order.zeroForOne
      order.amountIn order.amountOutMin r s = .ok ((), s0))
    (hf : feeStep ext sg order.isBuy order.amountIn order.amountOutMin order.priorityFee r s0 =
      .ok ((), s1)) :
    ∃ k, 1 ≤ k ∧ k ≤ 1774545 ∧
      AsyncMatching.addOrder ext sg ss bg bs order r s =
        tail ext sg ss bg bs order.id order.owner order.amountIn order.amountOutMin order.isBuy
          order.zeroForOne order.priorityFee k r s1 := by
  have hcm' := hcm
  rw [hbuy, AsyncSwap.Swarm.CheckMinimum.checkMinimum_buy ext sg ss bg bs _ _ _ _ r s s0 b hb hm]
    at hcm'
  have hge : b.minOrder ≤ order.amountIn := by
    by_cases hlt : order.amountIn < b.minOrder
    · simp [hlt] at hcm'
    · omega
  obtain ⟨k, k1, k2, hk⟩ := addOrder_key_ok ext sg ss bg bs order.id order.owner order.amountIn
    order.amountOutMin order.isBuy order.zeroForOne order.priorityFee r s0 s1
    (by simp only [hz, ite_true]; omega) hf
  refine ⟨k, k1, k2, ?_⟩
  rw [matching_addOrder_split, run_bind, hcm]
  exact hk

/-! ## The partial-fill re-key (`AsyncMatching._reduceAfterMatch`) -/

/-- The rounding-up tail of `mulDivCeil` (after a successful floor `q₀ = x·y/d`, `d ≠ 0`):
it returns `q₀` (exact) or `q₀ + 1`; with `x·y ≠ 0` the result is nonzero. -/
theorem ceil_tail_pos (n d q : Nat) (r : Env) (s s' : σ) (hn : n ≠ 0)
    (h : (if n % d = 0 then pure (n / d) else if n / d + 1 < 2 ^ 256 then pure (n / d + 1)
      else throw (panic "0x11") : M σ Nat) r s = .ok (q, s')) : q ≠ 0 := by
  by_cases h3 : n % d = 0
  · rw [ite_eq_left h3, run_pure] at h
    cases h
    intro h0
    have := Nat.div_add_mod n d
    rw [h0, h3] at this
    omega
  · rw [ite_eq_right h3, run_ite] at h
    split at h
    · rw [run_pure] at h; cases h; exact Nat.succ_ne_zero _
    · rw [run_throw] at h; cases h

/-- A successful ceiling `mulDiv` (`Math.mulDiv(x, y, d, Ceil)`, `mulDivRnd … 1`) of two nonzero
factors is nonzero: `⌈x·y/d⌉ ≥ 1`. -/
theorem mulDivRnd_ceil_pos (x y d : Nat) (r : Env) (s s' : σ) (q : Nat) (hx : x ≠ 0) (hy : y ≠ 0)
    (h : (mulDivRnd (σ := σ) x y d 1) r s = .ok (q, s')) : q ≠ 0 := by
  have hxy : x * y ≠ 0 := Nat.mul_ne_zero hx hy
  simp only [mulDivRnd, show (1 : Nat) % 2 = 1 from rfl, ite_true, mulDivCeil, mulDivFloor, addc,
    run_bind] at h
  by_cases h1 : x * y < 2 ^ 256
  · by_cases h2 : d = 0
    · simp [h1, h2] at h
    · simp only [h1, h2, ite_true, ite_false, run_pure] at h
      exact ceil_tail_pos (x * y) d q r s s' hxy h
  · by_cases h2 : d ≤ x * y / 2 ^ 256
    · simp [h1, h2] at h
    · simp only [h1, h2, ite_false, run_pure] at h
      exact ceil_tail_pos (x * y) d q r s s' hxy h

/-- **Re-key denominator.** With `remainingInput ≠ 0` (the early-exit guard) and
`remainingMinimum = ⌈amountOutMin·remainingInput/oldInput⌉` from a successful `mulDiv`, the
denominator `if zfo then remainingInput else remainingMinimum` is nonzero whenever the resting
order's `amountOutMin ≠ 0`. -/
theorem rekey_den_ne_zero (zfo : Bool) (amountOutMin oldInput rI rM : Nat) (r : Env) (s s' : σ)
    (hout : amountOutMin ≠ 0) (hrI : rI ≠ 0)
    (hm : (mulDivRnd (σ := σ) amountOutMin rI oldInput 1) r s = .ok (rM, s')) :
    (if zfo then rI else rM) ≠ 0 := by
  have := mulDivRnd_ceil_pos amountOutMin rI oldInput r s s' rM hout hrI hm
  cases zfo <;> simpa

/-- **The re-key never reverts** under the same hypotheses: `_priceKey isBuy zfo remainingInput
remainingMinimum` returns a key in `[1, 1774545]` from any state, without writing. -/
theorem rekey_priceKey_ok (isBuy zfo : Bool) (amountOutMin oldInput rI rM : Nat) (r : Env)
    (s s' t : σ) (hout : amountOutMin ≠ 0) (hrI : rI ≠ 0)
    (hm : (mulDivRnd (σ := σ) amountOutMin rI oldInput 1) r s = .ok (rM, s')) :
    ∃ k, AsyncFiller.«_priceKey» ext isBuy zfo rI rM r t = .ok (k, t) ∧ 1 ≤ k ∧ k ≤ 1774545 := by
  rcases AsyncSwap.Swarm.PriceKey.priceKey_spec ext isBuy zfo rI rM r t with ⟨hd, _⟩ | ⟨_, h⟩
  · exact absurd hd (rekey_den_ne_zero zfo amountOutMin oldInput rI rM r s s' hout hrI hm)
  · exact h

/-- **A sell needs no stored invariant.** With `minOrder ≠ 0`, a sell that survives the
`remainingMinimum < minOrder` close guard (and `remainingInput ≠ 0`) has a nonzero re-key
denominator. -/
theorem rekey_den_sell (zfo : Bool) (rI rM minOrder : Nat) (hrI : rI ≠ 0) (hmin : minOrder ≠ 0)
    (hg : ¬ ((if false then rI else rM) < minOrder)) : (if zfo then rI else rM) ≠ 0 := by
  cases zfo <;> simp at hg ⊢ <;> omega

end AsyncSwap.Swarm.AddOrderKey
