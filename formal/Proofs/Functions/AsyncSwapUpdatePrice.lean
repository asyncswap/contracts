import Specs.AsyncSwap
import Proofs.Monad
import Proofs.Functions.AsyncSwapKey
import Proofs.Functions.AsyncSwapTickPrice
import Proofs.Functions.AsyncSwapMinPriorityFee
import Proofs.Functions.AsyncSwapCheckMinimum
import Proofs.Functions.AsyncSwapUpdatePriceIte

/-!
# `AsyncFiller.updatePrice` and `AsyncFiller._priceKey` (src/AsyncSwap.sol)

`updatePrice(order, id, newAmountOutMin = n, caller)`:

* reverts `NotOrderOwner` iff `caller ≠ order.owner` (`updatePrice_notOwner`);
* then `ZeroAmount` iff `n = 0` (`updatePrice_zero`);
* then `OrderNotFound` iff `orders[id].amountIn = 0` (`updatePrice_notFound`);
* on success (`updatePrice_ok`): `checkMinimum` passed; for a sell, `minPriorityFee(n)` did not
  overflow and, if `n` raised the minimum output, `priorityFee ≥ min(⌊n·10/10000⌋, 100000)`; then
  `_remove` ran, `_priceKey` returned a key `p ∈ [1, MAX_TICK − MIN_TICK + 1]` (its denominator
  was nonzero), `nextSequence + 1 < 2⁶⁴`, and between `_remove` and `_append` exactly
  `orders[id].amountOutMin := n`, `orders[id].price := p`, `orders[id].sequence := nextSequence+1`
  and `book.nextSequence := nextSequence + 1` were written; then `_append` ran.
* `_priceKey` reaches `TickMath` only through `TickPrice.key`; its only revert is panic `0x12`
  (division by zero), exactly when the denominator (`amountIn` if zeroForOne, else `amountOut`)
  is zero, and it never writes (`priceKey_ok_iff`, `priceKey_error`).
* every revert of `updatePrice` from state `s` is in `ErrorClass … s` (`updatePrice_error`): one
  of its own guards, `MathOverflowedMulDiv` (fee), panic `0x11` (sequence), a revert of
  `checkMinimum` run from `s`, a revert of `_remove` run from the state `checkMinimum` left, a
  revert of `_append` (on some state), or panic `0x12` from `_priceKey` where this run's
  `checkMinimum` and `_remove` succeeded and the order `_remove` left is zeroForOne with
  `amountIn = 0`. No other revert (in particular none from TickMath) leaves `updatePrice`.

`_remove` and `_append` are the model's generated defs `AsyncFiller.«_remove»` and
`AsyncFiller.«_append»`; here they appear as calls (their own behaviour is proved elsewhere).

## The external entry points (`AsyncSwap.updatePrice`, `AsyncSwap.updatePriceWithSig`)

* `AsyncSwap.updatePrice ext order n` *is* `AsyncFiller.updatePrice` on the slots
  `asyncOrders[P]`, `priceBooks[P]` (`P = toId(order.key)`), with
  `id = keccak(chainid, P, owner, zeroForOne, salt)` and `caller = msg.sender` (`updatePrice_eq`).
* `AsyncSwap.updatePriceWithSig` *is* `_verify(owner, hashUpdatePrice(..), nonce, deadline, sig)`
  followed by the same call with `caller = order.owner` (`updatePriceWithSig_eq`).
* Hence the guards, the error classification (no TickMath revert) and the success shape transfer.

The storage accessors are lawful lenses on two disjoint slots (orders state, book).
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.UpdatePriceFiller

variable {σ : Type} (ext : Ext σ)

/-! ## `_priceKey`: its only revert is division by zero -/

/-- A successful `_priceKey` keeps the state, had a nonzero denominator, and returns a key in
`[1, MAX_TICK − MIN_TICK + 1]`. -/
theorem priceKey_ok_iff (isBuy zeroForOne : Bool) (amountIn amountOut : Nat) (env : Env) (s s' : σ)
    (p : Nat)
    (h : AsyncFiller.«_priceKey» ext isBuy zeroForOne amountIn amountOut env s = .ok (p, s')) :
    s' = s ∧ (if zeroForOne then amountIn else amountOut) ≠ 0 ∧ 1 ≤ p ∧
      (p : Int) ≤ TickMath.MAX_TICK - TickMath.MIN_TICK + 1 := by
  simp only [AsyncFiller.«_priceKey»] at h
  by_cases hd : (if zeroForOne then amountIn else amountOut) = 0
  · rw [AsyncSwap.Swarm.TickPrice.key_zero_den ext isBuy zeroForOne amountIn amountOut env s hd] at h
    cases h
  · obtain ⟨k, hk, k1, k2⟩ :=
      AsyncSwap.Swarm.TickBounds.key_no_revert ext isBuy zeroForOne amountIn amountOut env s hd
    rw [hk] at h
    simp only [Except.ok.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl⟩ := h
    exact ⟨rfl, hd, k1, k2⟩

/-- Every revert of `_priceKey` is panic `0x12` with a zero denominator. -/
theorem priceKey_error (isBuy zeroForOne : Bool) (amountIn amountOut : Nat) (env : Env) (s : σ)
    (e : Revert)
    (h : AsyncFiller.«_priceKey» ext isBuy zeroForOne amountIn amountOut env s = .error e) :
    (if zeroForOne then amountIn else amountOut) = 0 ∧ e = panic "0x12" := by
  simp only [AsyncFiller.«_priceKey»] at h
  by_cases hd : (if zeroForOne then amountIn else amountOut) = 0
  · rw [AsyncSwap.Swarm.TickPrice.key_zero_den ext isBuy zeroForOne amountIn amountOut env s hd] at h
    cases h
    exact ⟨hd, rfl⟩
  · obtain ⟨k, hk, -, -⟩ :=
      AsyncSwap.Swarm.TickBounds.key_no_revert ext isBuy zeroForOne amountIn amountOut env s hd
    rw [hk] at h
    cases h

/-! ## `updatePrice` -/

/-- The order map after `updatePrice`'s three writes to `orders[id]`. -/
def writtenOrders (S : AsyncFiller.State_) (id n p q : Nat) : Nat → AsyncFiller.OrderInfo :=
  upd S.orders id { S.orders id with amountOutMin := n, price := p, sequence := q }

def w1 (S : AsyncFiller.State_) (id n : Nat) : AsyncFiller.State_ :=
  { S with orders := upd S.orders id { S.orders id with amountOutMin := n } }
def w2 (S : AsyncFiller.State_) (id p : Nat) : AsyncFiller.State_ :=
  { S with orders := upd S.orders id { S.orders id with price := p } }
def w3 (S : AsyncFiller.State_) (id q : Nat) : AsyncFiller.State_ :=
  { S with orders := upd S.orders id { S.orders id with sequence := q } }
def wb (B : AsyncFiller.Book) (q : Nat) : AsyncFiller.Book := { B with nextSequence := q }

variable (sg : M σ AsyncFiller.State_) (ss : AsyncFiller.State_ → M σ Unit)
  (bg : M σ AsyncFiller.Book) (bs : AsyncFiller.Book → M σ Unit)
  (view : σ → AsyncFiller.State_) (bview : σ → AsyncFiller.Book)
  (putS : σ → AsyncFiller.State_ → σ) (putB : σ → AsyncFiller.Book → σ)

/-- Guard 1: anyone but `order.owner` reverts `NotOrderOwner`. -/
theorem updatePrice_notOwner (order : AsyncOrder) (id n caller : Nat) (env : Env) (s : σ)
    (hc : caller ≠ order.owner) :
    AsyncFiller.updatePrice ext sg ss bg bs order id n caller env s = .error ⟨"NotOrderOwner"⟩ := by
  have : (caller != order.owner) = true := by simpa using hc
  simp [AsyncFiller.updatePrice, this]

/-- Guard 2: the owner with `newAmountOutMin = 0` reverts `ZeroAmount`. -/
theorem updatePrice_zero (order : AsyncOrder) (id caller : Nat) (env : Env) (s : σ)
    (hc : caller = order.owner) :
    AsyncFiller.updatePrice ext sg ss bg bs order id 0 caller env s = .error ⟨"ZeroAmount"⟩ := by
  subst hc
  simp [AsyncFiller.updatePrice]

/-- Guard 3: an order with `amountIn = 0` reverts `OrderNotFound`. -/
theorem updatePrice_notFound
    (hsg : ∀ r t, sg r t = .ok (view t, t))
    (order : AsyncOrder) (id n caller : Nat) (env : Env) (s : σ)
    (hc : caller = order.owner) (hn : n ≠ 0) (h0 : ((view s).orders id).amountIn = 0) :
    AsyncFiller.updatePrice ext sg ss bg bs order id n caller env s = .error ⟨"OrderNotFound"⟩ := by
  subst hc
  have hn' : (n == 0) = false := by simpa using hn
  simp [AsyncFiller.updatePrice, hn', hsg, h0]

/-- What `updatePrice` does from `_remove` on, started in state `t` and ending in `s'`. -/
def Tail (id n : Nat) (env : Env) (t s' : σ) : Prop :=
  ∃ s1 s2 sp p,
    AsyncFiller.«_remove» ext sg (fun x => ss x) bg (fun x => bs x) id env t = .ok ((), s1) ∧
    (if ((view s1).orders id).zeroForOne then ((view s1).orders id).amountIn else n) ≠ 0 ∧
    AsyncFiller.«_priceKey» ext ((view s1).orders id).isBuy ((view s1).orders id).zeroForOne
      ((view s1).orders id).amountIn n env sp = .ok (p, sp) ∧
    1 ≤ p ∧ (p : Int) ≤ TickMath.MAX_TICK - TickMath.MIN_TICK + 1 ∧
    (bview s1).nextSequence + 1 < 2 ^ 64 ∧
    view s2 = { view s1 with
      orders := writtenOrders (view s1) id n p ((bview s1).nextSequence + 1) } ∧
    bview s2 = { bview s1 with nextSequence := (bview s1).nextSequence + 1 } ∧
    AsyncFiller.«_append» ext sg (fun x => ss x) bg (fun x => bs x) id env s2 = .ok ((), s')

theorem tail_fin
    (l1 : ∀ t x, view (putS t x) = x) (l2 : ∀ t x, bview (putS t x) = bview t)
    (_l3 : ∀ t b, view (putB t b) = view t) (l4 : ∀ t b, bview (putB t b) = b)
    (id n : Nat) (env : Env) (t s1 sp s3 s' : σ) (a a' : Unit) (p q : Nat)
    (hrm : AsyncFiller.«_remove» ext sg (fun x => ss x) bg (fun x => bs x) id env t
      = .ok (a, s1))
    (hpk : AsyncFiller.«_priceKey» ext ((view s1).orders id).isBuy ((view s1).orders id).zeroForOne
      ((view s1).orders id).amountIn n env (putS s1 (w1 (view s1) id n)) = .ok (p, sp))
    (hadd : (if (bview sp).nextSequence + 1 < 2 ^ 64 then
        Except.ok ((bview sp).nextSequence + 1, putS sp (w2 (view sp) id p))
      else Except.error (panic "0x11")) = Except.ok (q, s3))
    (hap : AsyncFiller.«_append» ext sg (fun x => ss x) bg (fun x => bs x) id env
      (putS (putB s3 (wb (bview s3) q)) (w3 (view s3) id q)) = .ok (a', s')) :
    Tail ext sg ss bg bs view bview id n env t s' := by
  cases a; cases a'
  obtain ⟨rfl, hden, hp1, hp2⟩ := priceKey_ok_iff ext _ _ _ _ _ _ _ _ hpk
  split at hadd
  next hq =>
    simp only [Except.ok.injEq, Prod.mk.injEq] at hadd
    obtain ⟨rfl, rfl⟩ := hadd
    simp only [l2] at hq
    unfold Tail
    refine ⟨s1, _, putS s1 (w1 (view s1) id n), p, hrm, hden, hpk, hp1, hp2, hq, ?_, ?_, hap⟩
    · simp only [l1, l2, w1, w2, w3, writtenOrders, upd_same]
      congr 1
      funext k
      by_cases hk : k = id <;> simp [upd, hk]
    · simp [l1, l2, l4, wb]
  next => cases hadd

/-- **Success.** With lawful accessors, a successful `updatePrice` passed the three guards, the
minimum-order check and (for a sell) the priority-fee check, and then ran `Tail`: `_remove`,
the writes of `amountOutMin`, `price` (a key in `[1, MAX_TICK−MIN_TICK+1]`) and `sequence` to
`orders[id]` and of `nextSequence + 1 < 2⁶⁴` to the book, then `_append`. -/
theorem updatePrice_ok
    (hsg : ∀ r t, sg r t = .ok (view t, t))
    (hss : ∀ x r t, ss x r t = .ok ((), putS t x))
    (hbg : ∀ r t, bg r t = .ok (bview t, t))
    (hbs : ∀ b r t, bs b r t = .ok ((), putB t b))
    (l1 : ∀ t x, view (putS t x) = x) (l2 : ∀ t x, bview (putS t x) = bview t)
    (l3 : ∀ t b, view (putB t b) = view t) (l4 : ∀ t b, bview (putB t b) = b)
    (order : AsyncOrder) (id n caller : Nat) (env : Env) (s s' : σ) (u : Unit)
    (h : AsyncFiller.updatePrice ext sg ss bg bs order id n caller env s = .ok (u, s')) :
    caller = order.owner ∧ n ≠ 0 ∧ ((view s).orders id).amountIn ≠ 0 ∧
    ∃ s0,
      AsyncFiller.checkMinimum ext (do return (← sg)) (fun x => do ss (x)) (do return (← bg))
        (fun x => do bs (x))
        (ext.keccak [order.key.currency0, order.key.currency1, order.key.fee,
          toUnsigned 256 order.key.tickSpacing, order.key.hooks])
        ((view s).orders id).isBuy ((view s).orders id).zeroForOne ((view s).orders id).amountIn n
        env s = .ok ((), s0) ∧
      (((view s0).orders id).isBuy = false →
        n * 10 / 2 ^ 256 < 10000 ∧
        (((view s0).orders id).amountOutMin < n →
          min (n * 10 / 10000) 100000 ≤ ((view s0).orders id).priorityFee)) ∧
      Tail ext sg ss bg bs view bview id n env s0 s' := by
  simp only [AsyncFiller.updatePrice, PoolIdLibrary.toId, run_bind, run_pure, run_ite, run_throw,
    hsg, hss, hbg, hbs, l1, l2, l3, upd_same,
    AsyncSwap.Swarm.MinPriorityFee.minPriorityFee_eq, addc] at h
  split at h
  · cases h
  next h1 =>
  split at h
  · cases h
  next h2 =>
  split at h
  · cases h
  next h3 =>
  refine ⟨by simpa using h1, by simpa using h2, by simpa using h3, ?_⟩
  split at h
  next a s0 hcm =>
    cases a
    refine ⟨s0, hcm, ?_⟩
    split at h
    next hsell =>
      split at h
      next m t hm =>
        split at hm
        · cases hm
        next hov =>
          simp only [Except.ok.injEq, Prod.mk.injEq] at hm
          obtain ⟨rfl, rfl⟩ := hm
          split at h
          next hgt =>
            split at h
            · cases h
            next hfee =>
              refine ⟨fun _ => ⟨Nat.lt_of_not_le hov,
                fun _ => Nat.le_of_not_lt (fun hc => hfee (decide_eq_true hc))⟩, ?_⟩
              repeat' (split at h)
              all_goals (try cases h)
              all_goals (apply tail_fin ext sg ss bg bs view bview putS putB l1 l2 l3 l4 <;>
                assumption)
          next hle =>
            refine ⟨fun _ => ⟨Nat.lt_of_not_le hov,
              fun hlt => absurd (decide_eq_true hlt) hle⟩, ?_⟩
            repeat' (split at h)
            all_goals (try cases h)
            all_goals (apply tail_fin ext sg ss bg bs view bview putS putB l1 l2 l3 l4 <;>
              assumption)
      next => cases h
    next hbuy =>
      refine ⟨fun hb => by simp [hb] at hbuy, ?_⟩
      repeat' (split at h)
      all_goals (try cases h)
      all_goals (apply tail_fin ext sg ss bg bs view bview putS putB l1 l2 l3 l4 <;> assumption)
  next => cases h

/-- `checkMinimum` writes nothing when the PoolManager slot read (`getSlot0`) writes nothing. -/
theorem checkMinimum_frame
    (hsg : ∀ r t, sg r t = .ok (view t, t)) (hbg : ∀ r t, bg r t = .ok (bview t, t))
    (hslot : ∀ m q r t a t', StateLibrary.getSlot0 ext m q r t = .ok (a, t') → t' = t)
    (pid : Nat) (ib zf : Bool) (ai ao : Nat) (env : Env) (s s0 : σ)
    (h : AsyncFiller.checkMinimum ext sg (fun x => ss x) bg (fun x => bs x) pid ib zf ai ao env s
      = .ok ((), s0)) : s0 = s := by
  have hg := AsyncSwap.Swarm.CheckMinimum.checkMinimum_good ext sg (fun x => ss x) bg
    (fun x => bs x) pid ib zf ai ao (· = s) (fun _ => True)
    (fun r t ht => by simp only [hbg]; exact ht)
    (fun r t ht => by simp only [hsg]; exact ht)
    (fun m q r t ht => by
      cases hx : StateLibrary.getSlot0 ext m q r t with
      | error e => trivial
      | ok v => obtain ⟨a, t'⟩ := v; exact (hslot m q r t a t' hx).trans ht)
    trivial trivial trivial env s rfl
  rw [h] at hg
  exact hg

/-- **Success, with the frame.** If the PoolManager slot read writes nothing, a successful
`updatePrice` runs `Tail` from its own initial state `s`: the only storage it changes outside
`_remove`/`_append` is `orders[id].amountOutMin/price/sequence` and `book.nextSequence`. -/
theorem updatePrice_ok_frame
    (hsg : ∀ r t, sg r t = .ok (view t, t))
    (hss : ∀ x r t, ss x r t = .ok ((), putS t x))
    (hbg : ∀ r t, bg r t = .ok (bview t, t))
    (hbs : ∀ b r t, bs b r t = .ok ((), putB t b))
    (l1 : ∀ t x, view (putS t x) = x) (l2 : ∀ t x, bview (putS t x) = bview t)
    (l3 : ∀ t b, view (putB t b) = view t) (l4 : ∀ t b, bview (putB t b) = b)
    (hslot : ∀ m q r t a t', StateLibrary.getSlot0 ext m q r t = .ok (a, t') → t' = t)
    (order : AsyncOrder) (id n caller : Nat) (env : Env) (s s' : σ) (u : Unit)
    (h : AsyncFiller.updatePrice ext sg ss bg bs order id n caller env s = .ok (u, s')) :
    caller = order.owner ∧ n ≠ 0 ∧ ((view s).orders id).amountIn ≠ 0 ∧
      (((view s).orders id).isBuy = false →
        ((view s).orders id).amountOutMin < n →
          min (n * 10 / 10000) 100000 ≤ ((view s).orders id).priorityFee) ∧
      Tail ext sg ss bg bs view bview id n env s s' := by
  obtain ⟨h1, h2, h3, s0, hcm, hfee, htail⟩ :=
    updatePrice_ok ext sg ss bg bs view bview putS putB hsg hss hbg hbs l1 l2 l3 l4
      order id n caller env s s' u h
  obtain rfl := checkMinimum_frame ext sg ss bg bs view bview hsg hbg hslot _ _ _ _ _ env s s0 hcm
  exact ⟨h1, h2, h3, fun hb hlt => (hfee hb).2 hlt, htail⟩

/-! ## Every revert of `updatePrice`, classified -/

/-- The reverts `updatePrice order id n` can produce when run from state `s`. TickMath is reached
only through `_priceKey` (`TickPrice.key`), whose only revert is the last disjunct, tied to this
run: `checkMinimum` from `s` succeeded with `s0`, `_remove` from `s0` succeeded with `s1`, and the
order in `s1` is zeroForOne with `amountIn = 0`. The `checkMinimum` and `_remove` disjuncts are
reverts of those calls on this run's states; the `_append` disjunct is a revert of `_append` on
some state. -/
def ErrorClass (order : AsyncOrder) (id n : Nat) (env : Env) (s : σ) (e : Revert) : Prop :=
  e = ⟨"NotOrderOwner"⟩ ∨ e = ⟨"ZeroAmount"⟩ ∨ e = ⟨"OrderNotFound"⟩ ∨
  e = ⟨"PriorityFeeTooSmall"⟩ ∨ e = ⟨"MathOverflowedMulDiv"⟩ ∨ e = panic "0x11" ∨
  AsyncFiller.checkMinimum ext sg (fun x => ss x) bg (fun x => bs x)
      (ext.keccak [order.key.currency0, order.key.currency1, order.key.fee,
        toUnsigned 256 order.key.tickSpacing, order.key.hooks])
      ((view s).orders id).isBuy ((view s).orders id).zeroForOne ((view s).orders id).amountIn n
      env s = .error e ∨
  (∃ s0, AsyncFiller.checkMinimum ext sg (fun x => ss x) bg (fun x => bs x)
      (ext.keccak [order.key.currency0, order.key.currency1, order.key.fee,
        toUnsigned 256 order.key.tickSpacing, order.key.hooks])
      ((view s).orders id).isBuy ((view s).orders id).zeroForOne ((view s).orders id).amountIn n
      env s = .ok ((), s0) ∧
    AsyncFiller.«_remove» ext sg (fun x => ss x) bg (fun x => bs x) id env s0 = .error e) ∨
  (∃ t, AsyncFiller.«_append» ext sg (fun x => ss x) bg (fun x => bs x) id env t = .error e) ∨
  (e = panic "0x12" ∧ ∃ s0 s1,
    AsyncFiller.checkMinimum ext sg (fun x => ss x) bg (fun x => bs x)
      (ext.keccak [order.key.currency0, order.key.currency1, order.key.fee,
        toUnsigned 256 order.key.tickSpacing, order.key.hooks])
      ((view s).orders id).isBuy ((view s).orders id).zeroForOne ((view s).orders id).amountIn n
      env s = .ok ((), s0) ∧
    AsyncFiller.«_remove» ext sg (fun x => ss x) bg (fun x => bs x) id env s0 = .ok ((), s1) ∧
    ((view s1).orders id).zeroForOne = true ∧ ((view s1).orders id).amountIn = 0)

/-- **Revert classification.** With lawful accessors every revert of `updatePrice` from `s` is in
`ErrorClass … s`: its own guards, the fee mulDiv overflow, the `nextSequence` overflow, a revert of
`checkMinimum` from `s`, of `_remove` from the state `checkMinimum` left, of `_append`, or
`_priceKey`'s division by zero, which happens only when this run's `checkMinimum` and `_remove`
succeeded and the order `_remove` left is zeroForOne with `amountIn = 0` (the `ZeroAmount` guard
already excluded `n = 0`). -/
theorem updatePrice_error
    (hsg : ∀ r t, sg r t = .ok (view t, t))
    (hss : ∀ x r t, ss x r t = .ok ((), putS t x))
    (hbg : ∀ r t, bg r t = .ok (bview t, t))
    (hbs : ∀ b r t, bs b r t = .ok ((), putB t b))
    (l1 : ∀ t x, view (putS t x) = x) (l2 : ∀ t x, bview (putS t x) = bview t)
    (l3 : ∀ t b, view (putB t b) = view t)
    (order : AsyncOrder) (id n caller : Nat) (env : Env) (s : σ) (e : Revert)
    (h : AsyncFiller.updatePrice ext sg ss bg bs order id n caller env s = .error e) :
    ErrorClass ext sg ss bg bs view order id n env s e := by
  simp only [AsyncFiller.updatePrice, PoolIdLibrary.toId, run_bind, run_pure, run_ite, run_throw,
    hsg, hss, hbg, hbs, l1, l2, l3, upd_same,
    AsyncSwap.Swarm.MinPriorityFee.minPriorityFee_eq, addc] at h
  repeat' (split at h)
  all_goals (try cases h)
  -- (the goal stays folded as `ErrorClass …` so the rewrites below touch only hypotheses)
  -- the fee computation writes nothing: identify its output state with `checkMinimum`'s
  all_goals (try fee_state_norm)
  -- a guarded `throw` that fired: read off its revert
  all_goals (try simp only [ite_err_ok_eq_err, ite_ok_err_eq_err] at *)
  all_goals (unfold ErrorClass)
  all_goals (first
    | exact Or.inl rfl
    | exact Or.inr (Or.inl rfl)
    | exact Or.inr (Or.inr (Or.inl rfl))
    | exact Or.inr (Or.inr (Or.inr (Or.inl rfl)))
    | (obtain ⟨-, rfl⟩ := ‹_ ∧ _ = e›
       first
        | exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inl rfl))))
        | exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inl rfl))))))
    | exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inl (by assumption)))))))
    | exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inl
        ⟨_, by assumption, by assumption⟩)))))))
    | exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inl
        ⟨_, by assumption⟩))))))))
    | (obtain ⟨hd, rfl⟩ := priceKey_error ext _ _ _ _ _ _ _
         ‹AsyncFiller.«_priceKey» ext _ _ _ _ _ _ = Except.error e›
       refine Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inr
         ⟨rfl, ?_⟩))))))))
       split at hd
       · exact ⟨_, _, by assumption, by assumption, by assumption, hd⟩
       · exact absurd (by simpa using hd) ‹¬(n == 0) = true›))

end AsyncSwap.Swarm.UpdatePriceFiller

/-! ## The external entry points -/

namespace AsyncSwap.Swarm.UpdatePriceEntry

open AsyncSwap.Swarm.UpdatePriceFiller

variable {σ : Type} (ext : Ext σ)

/-- The storage accessors both entry points hand to `AsyncMatching.updatePrice`. -/
def SG (P : Nat) : M σ AsyncFiller.State_ := do return ((ext.get (← get)).asyncOrders P)
def SS (P : Nat) : AsyncFiller.State_ → M σ Unit := fun x =>
  modify fun w => ext.set w (let s := ext.get w; { s with asyncOrders := upd (s.asyncOrders) P (x) })
def BG (P : Nat) : M σ AsyncFiller.Book := do return ((ext.get (← get)).priceBooks P)
def BS (P : Nat) : AsyncFiller.Book → M σ Unit := fun x =>
  modify fun w => ext.set w (let s := ext.get w; { s with priceBooks := upd (s.priceBooks) P (x) })

/-- `order.key.toId()`. -/
def pid (order : AsyncOrder) : Nat :=
  ext.keccak [order.key.currency0, order.key.currency1, order.key.fee,
    toUnsigned 256 order.key.tickSpacing, order.key.hooks]

/-- `order.orderId()`. -/
def oid (order : AsyncOrder) (env : Env) : Nat :=
  ext.keccak [env.chainid, pid ext order, order.owner, ybool order.zeroForOne, order.salt]

/-- `OrderSignatures.hashUpdatePrice(order, id, amountIn, newAmountOutMin, createdSequence, ..)`
evaluated on the pre-state `s`. -/
def hashU (order : AsyncOrder) (n nonce deadline : Nat) (env : Env) (s : σ) : Nat :=
  ext.keccak [OrderSignatures.UPDATE_PRICE_TYPEHASH, order.owner,
    (if order.zeroForOne then (order.key.currency0, order.key.currency1)
      else (order.key.currency1, order.key.currency0)).1,
    (if order.zeroForOne then (order.key.currency0, order.key.currency1)
      else (order.key.currency1, order.key.currency0)).2,
    (((ext.get s).asyncOrders (pid ext order)).orders (oid ext order env)).amountIn, n,
    oid ext order env,
    (((ext.get s).asyncOrders (pid ext order)).orders (oid ext order env)).createdSequence,
    nonce, deadline]

/-- The lens on the two slots. -/
def view (P : Nat) (t : σ) : AsyncFiller.State_ := (ext.get t).asyncOrders P
def bview (P : Nat) (t : σ) : AsyncFiller.Book := (ext.get t).priceBooks P
def putS (P : Nat) (t : σ) (x : AsyncFiller.State_) : σ :=
  ext.set t (let s := ext.get t; { s with asyncOrders := upd (s.asyncOrders) P (x) })
def putB (P : Nat) (t : σ) (b : AsyncFiller.Book) : σ :=
  ext.set t (let s := ext.get t; { s with priceBooks := upd (s.priceBooks) P (b) })

theorem hsg (P : Nat) : ∀ r t, SG ext P r t = .ok (view ext P t, t) := fun _ _ => rfl
theorem hss (P : Nat) : ∀ x r t, SS ext P x r t = .ok ((), putS ext P t x) := fun _ _ _ => rfl
theorem hbg (P : Nat) : ∀ r t, BG ext P r t = .ok (bview ext P t, t) := fun _ _ => rfl
theorem hbs (P : Nat) : ∀ b r t, BS ext P b r t = .ok ((), putB ext P t b) := fun _ _ _ => rfl

section Laws
variable (hget : ∀ w s, ext.get (ext.set w s) = s) (P : Nat)
include hget
theorem l1 : ∀ t x, view ext P (putS ext P t x) = x := by
  intro t x; simp [view, putS, hget, upd_same]
theorem l2 : ∀ t x, bview ext P (putS ext P t x) = bview ext P t := by
  intro t x; simp [bview, putS, hget]
theorem l3 : ∀ t b, view ext P (putB ext P t b) = view ext P t := by
  intro t b; simp [view, putB, hget]
theorem l4 : ∀ t b, bview ext P (putB ext P t b) = b := by
  intro t b; simp [bview, putB, hget, upd_same]
end Laws

/-! ### Reductions -/

/-- **`AsyncSwap.updatePrice` is `AsyncFiller.updatePrice` on the pool's slots**, with
`id = orderId(order)` and `caller = msg.sender`. -/
theorem updatePrice_eq (order : AsyncOrder) (n : Nat) (env : Env) (s : σ) :
    AsyncSwap.updatePrice ext order n env s =
      AsyncFiller.updatePrice ext (SG ext (pid ext order)) (SS ext (pid ext order))
        (BG ext (pid ext order)) (BS ext (pid ext order))
        order (oid ext order env) n env.sender env s := by
  unfold SG SS BG BS oid pid
  simp only [AsyncSwap.updatePrice, AsyncMatching.updatePrice, AsyncOrderLibrary.orderId,
    PoolIdLibrary.toId, run_bind, run_pure, run_read]
  generalize AsyncFiller.updatePrice ext _ _ _ _ order _ n env.sender env s = X
  rcases X with e | ⟨⟨⟩, s'⟩ <;> rfl

/-- **`AsyncSwap.updatePriceWithSig` is `_verify` then `AsyncFiller.updatePrice`** on the pool's
slots, with the signed digest `hashU` of the pre-state and `caller = order.owner`. -/
theorem updatePriceWithSig_eq (order : AsyncOrder) (n nonce deadline : Nat)
    (signature : List Nat) (env : Env) (s : σ) :
    AsyncSwap.updatePriceWithSig ext order n nonce deadline signature env s =
      match AsyncSwap.«_verify» ext order.owner (hashU ext order n nonce deadline env s) nonce deadline
          signature env s with
      | .ok (_, s1) =>
        AsyncFiller.updatePrice ext (SG ext (pid ext order)) (SS ext (pid ext order))
          (BG ext (pid ext order)) (BS ext (pid ext order))
          order (oid ext order env) n order.owner env s1
      | .error e => .error e := by
  unfold SG SS BG BS hashU oid pid
  simp only [AsyncSwap.updatePriceWithSig, AsyncMatching.updatePrice, AsyncOrderLibrary.orderId,
    OrderSignatures.hashUpdatePrice, OrderSignatures.tokens,
    PoolIdLibrary.toId, run_bind, run_pure, run_read, run_get]
  generalize AsyncSwap.«_verify» ext order.owner _ nonce deadline signature env s = V
  rcases V with e | ⟨⟨⟩, s1⟩
  · rfl
  · simp only
    generalize AsyncFiller.updatePrice ext _ _ _ _ order _ n order.owner env s1 = X
    rcases X with e | ⟨⟨⟩, s'⟩ <;> rfl

/-! ### `AsyncSwap.updatePrice`: guards, reverts, success -/

/-- Guard 1 at the entry: a sender other than `order.owner` reverts `NotOrderOwner`. -/
theorem entry_notOwner (order : AsyncOrder) (n : Nat) (env : Env) (s : σ)
    (hc : env.sender ≠ order.owner) :
    AsyncSwap.updatePrice ext order n env s = .error ⟨"NotOrderOwner"⟩ := by
  rw [updatePrice_eq]
  exact UpdatePriceFiller.updatePrice_notOwner ext _ _ _ _ order _ n _ env s hc

/-- Guard 2 at the entry: the owner with `newAmountOutMin = 0` reverts `ZeroAmount`. -/
theorem entry_zero (order : AsyncOrder) (env : Env) (s : σ) (hc : env.sender = order.owner) :
    AsyncSwap.updatePrice ext order 0 env s = .error ⟨"ZeroAmount"⟩ := by
  rw [updatePrice_eq]
  exact UpdatePriceFiller.updatePrice_zero ext _ _ _ _ order _ _ env s hc

/-- Guard 3 at the entry: if `asyncOrders[P].orders[orderId].amountIn = 0` it reverts
`OrderNotFound`. -/
theorem entry_notFound (order : AsyncOrder) (n : Nat) (env : Env) (s : σ)
    (hc : env.sender = order.owner) (hn : n ≠ 0)
    (h0 : (((ext.get s).asyncOrders (pid ext order)).orders (oid ext order env)).amountIn = 0) :
    AsyncSwap.updatePrice ext order n env s = .error ⟨"OrderNotFound"⟩ := by
  rw [updatePrice_eq]
  exact UpdatePriceFiller.updatePrice_notFound ext _ (SS ext (pid ext order)) _
    (BS ext (pid ext order)) (view ext (pid ext order)) (hsg ext _) order _ n _ env s hc hn h0

/-- **Item §4 at the entry: no TickMath revert.** Every revert of `AsyncSwap.updatePrice` from `s`
is in `ErrorClass … s` for the pool's slots: the explicit guards, the fee / sequence overflows, a
revert of `checkMinimum` from `s`, of `_remove` from the state `checkMinimum` left, of `_append`,
or panic `0x12` from `_priceKey` where this run's `checkMinimum` and `_remove` succeeded and the
order `_remove` left is zeroForOne with `amountIn = 0`. -/
theorem entry_error (hget : ∀ w s, ext.get (ext.set w s) = s)
    (order : AsyncOrder) (n : Nat) (env : Env) (s : σ) (e : Revert)
    (h : AsyncSwap.updatePrice ext order n env s = .error e) :
    ErrorClass ext (SG ext (pid ext order)) (SS ext (pid ext order)) (BG ext (pid ext order))
      (BS ext (pid ext order)) (view ext (pid ext order)) order (oid ext order env) n env s e := by
  rw [updatePrice_eq] at h
  exact UpdatePriceFiller.updatePrice_error ext _ _ _ _ _ (bview ext (pid ext order))
    (putS ext (pid ext order)) (putB ext (pid ext order)) (hsg ext _) (hss ext _) (hbg ext _)
    (hbs ext _) (l1 ext hget _) (l2 ext hget _) (l3 ext hget _) order _ n _ env s e h

/-- **Success at the entry.** If the PoolManager slot read writes nothing, a successful
`AsyncSwap.updatePrice` was sent by `order.owner`, had `newAmountOutMin ≠ 0` and a live order,
passed the priority-fee check, and then ran `Tail` on `asyncOrders[P]` / `priceBooks[P]`: its only
writes outside `_remove`/`_append` are `orders[id].amountOutMin := n`, `price := key ∈
[1, MAX_TICK − MIN_TICK + 1]`, `sequence := nextSequence + 1 < 2⁶⁴` and `book.nextSequence`. -/
theorem entry_ok (hget : ∀ w s, ext.get (ext.set w s) = s)
    (hslot : ∀ m q r t a t', StateLibrary.getSlot0 ext m q r t = .ok (a, t') → t' = t)
    (order : AsyncOrder) (n : Nat) (env : Env) (s s' : σ) (u : Unit)
    (h : AsyncSwap.updatePrice ext order n env s = .ok (u, s')) :
    env.sender = order.owner ∧ n ≠ 0 ∧
      ((view ext (pid ext order) s).orders (oid ext order env)).amountIn ≠ 0 ∧
      (((view ext (pid ext order) s).orders (oid ext order env)).isBuy = false →
        ((view ext (pid ext order) s).orders (oid ext order env)).amountOutMin < n →
          min (n * 10 / 10000) 100000 ≤
            ((view ext (pid ext order) s).orders (oid ext order env)).priorityFee) ∧
      Tail ext (SG ext (pid ext order)) (SS ext (pid ext order)) (BG ext (pid ext order))
        (BS ext (pid ext order)) (view ext (pid ext order)) (bview ext (pid ext order))
        (oid ext order env) n env s s' := by
  rw [updatePrice_eq] at h
  exact UpdatePriceFiller.updatePrice_ok_frame ext _ _ _ _ _ _ (putS ext (pid ext order))
    (putB ext (pid ext order)) (hsg ext _) (hss ext _) (hbg ext _) (hbs ext _)
    (l1 ext hget _) (l2 ext hget _) (l3 ext hget _) (l4 ext hget _) hslot order _ n _ env s s' u h

/-! ### `AsyncSwap.updatePriceWithSig`: reverts, success -/

/-- **Item §4 for the signed entry: no TickMath revert.** Every revert of
`AsyncSwap.updatePriceWithSig` is either a revert of `_verify` (expired deadline, used nonce,
bad signature) or, after `_verify` succeeded with `s1`, in `ErrorClass … s1` for the pool's slots. -/
theorem entrySig_error (hget : ∀ w s, ext.get (ext.set w s) = s)
    (order : AsyncOrder) (n nonce deadline : Nat) (signature : List Nat) (env : Env) (s : σ)
    (e : Revert)
    (h : AsyncSwap.updatePriceWithSig ext order n nonce deadline signature env s = .error e) :
    AsyncSwap.«_verify» ext order.owner (hashU ext order n nonce deadline env s) nonce deadline
        signature env s = .error e ∨
    ∃ s1, AsyncSwap.«_verify» ext order.owner (hashU ext order n nonce deadline env s) nonce
        deadline signature env s = .ok ((), s1) ∧
      ErrorClass ext (SG ext (pid ext order)) (SS ext (pid ext order)) (BG ext (pid ext order))
        (BS ext (pid ext order)) (view ext (pid ext order)) order (oid ext order env) n env s1 e := by
  rw [updatePriceWithSig_eq] at h
  split at h
  next a s1 hv =>
    cases a
    exact Or.inr ⟨s1, hv, UpdatePriceFiller.updatePrice_error ext _ _ _ _ _
      (bview ext (pid ext order)) (putS ext (pid ext order)) (putB ext (pid ext order))
      (hsg ext _) (hss ext _) (hbg ext _) (hbs ext _) (l1 ext hget _) (l2 ext hget _)
      (l3 ext hget _) order _ n _ env s1 e h⟩
  next e' hv =>
    cases h
    exact Or.inl hv

/-- **Success for the signed entry.** A successful `AsyncSwap.updatePriceWithSig` first ran
`_verify` to some `s1`; from `s1` the order (looked up by `orderId`) was live, `newAmountOutMin ≠ 0`,
the priority-fee check passed and `Tail` ran on `asyncOrders[P]` / `priceBooks[P]`. -/
theorem entrySig_ok (hget : ∀ w s, ext.get (ext.set w s) = s)
    (hslot : ∀ m q r t a t', StateLibrary.getSlot0 ext m q r t = .ok (a, t') → t' = t)
    (order : AsyncOrder) (n nonce deadline : Nat) (signature : List Nat) (env : Env)
    (s s' : σ) (u : Unit)
    (h : AsyncSwap.updatePriceWithSig ext order n nonce deadline signature env s = .ok (u, s')) :
    ∃ s1, AsyncSwap.«_verify» ext order.owner (hashU ext order n nonce deadline env s) nonce
        deadline signature env s = .ok ((), s1) ∧
      n ≠ 0 ∧ ((view ext (pid ext order) s1).orders (oid ext order env)).amountIn ≠ 0 ∧
      (((view ext (pid ext order) s1).orders (oid ext order env)).isBuy = false →
        ((view ext (pid ext order) s1).orders (oid ext order env)).amountOutMin < n →
          min (n * 10 / 10000) 100000 ≤
            ((view ext (pid ext order) s1).orders (oid ext order env)).priorityFee) ∧
      Tail ext (SG ext (pid ext order)) (SS ext (pid ext order)) (BG ext (pid ext order))
        (BS ext (pid ext order)) (view ext (pid ext order)) (bview ext (pid ext order))
        (oid ext order env) n env s1 s' := by
  rw [updatePriceWithSig_eq] at h
  split at h
  next a s1 hv =>
    cases a
    obtain ⟨-, h2, h3, h4, h5⟩ := UpdatePriceFiller.updatePrice_ok_frame ext _ _ _ _ _ _
      (putS ext (pid ext order)) (putB ext (pid ext order)) (hsg ext _) (hss ext _) (hbg ext _)
      (hbs ext _) (l1 ext hget _) (l2 ext hget _) (l3 ext hget _) (l4 ext hget _) hslot
      order _ n _ env s1 s' u h
    exact ⟨s1, hv, h2, h3, h4, h5⟩
  next => cases h

end AsyncSwap.Swarm.UpdatePriceEntry
