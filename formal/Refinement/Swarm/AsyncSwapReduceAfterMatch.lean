import Generated.AsyncSwap
import Refinement.Monad

/-!
# `AsyncMatching._reduceAfterMatch`

`function _reduceAfterMatch(State storage self, Book storage book, PoolKey memory key,
ReductionParams memory params, address hook) private` (src/AsyncSwap.sol, library
`AsyncMatching`).

With `o = self.orders[params.id]`, `remIn = o.amountIn - params.inputUsed` (checked) and
`rm = remMin o params.outputReceived` (`0` when the match delivered at least `o.amountOutMin`):

* reverts with panic 0x11 when `params.inputUsed > o.amountIn`, before any write;
* settles the pro-rata priority fee through `_settleMatchedPriorityFee`, which returns the unfilled
  fee `u`;
* **closed** (`remIn = 0` or `rm = 0`): `_remove`, delete `orders[id]`, settle the unfilled fee `u`
  for the owner via `settlePriorityFee`, and when `remIn ≠ 0` refund `remIn` of the input currency
  to the owner (`settle` then `take`);
* **partial** (both nonzero): write `orders[id].amountIn := remIn`, `amountOutMin := rm`,
  `priorityFee := u mod 2^64`, compute the new price key `p ∈ [1, 2^128)`, and re-key the order
  (`_remove`, `price := p`, a fresh `sequence = nextSequence + 1` (checked uint64) when the price
  moved, `_append`) exactly when the price moved or, in priority-ordering mode, the fee changed.

`self` and `book` are storage pointers, passed as getter/setter pairs; `Lawful` says they are plain
reads and writes of two disjoint slots of the world, which is how every caller instantiates them.
-/

open FormalAst Refinement

set_option linter.unusedSimpArgs false

namespace AsyncSwap.Swarm.ReduceAfterMatch

variable {σ : Type} (ext : Ext σ)

/-- `remainingMinimum`: the order's minimum output less what the match delivered, floored at 0. -/
def remMin (o : AsyncFiller.OrderInfo) (out : Nat) : Nat :=
  if out ≥ o.amountOutMin then 0 else o.amountOutMin - out

/-- The pool state after the partial-fill writes: `orders[id]` gets the remaining input,
remaining minimum and unfilled priority fee; nothing else changes. -/
def reduced (S : AsyncFiller.State_) (id remIn rm fee : Nat) : AsyncFiller.State_ :=
  { S with orders := upd S.orders id ({ (S.orders id) with amountIn := remIn, amountOutMin := rm, priorityFee := fee }) }

/-- The pool state after re-keying an order at price `p` (same sequence). -/
def repriced (S : AsyncFiller.State_) (id p : Nat) : AsyncFiller.State_ :=
  { S with orders := upd S.orders id ({ (S.orders id) with price := p }) }

/-- The pool state after re-keying an order at price `p` with fresh sequence `q`. -/
def resequenced (S : AsyncFiller.State_) (id p q : Nat) : AsyncFiller.State_ :=
  { S with orders := upd S.orders id ({ (S.orders id) with price := p, sequence := q }) }

/-- The pool state after deleting `orders[id]`. -/
def deleted (S : AsyncFiller.State_) (id : Nat) : AsyncFiller.State_ :=
  { S with orders := upd S.orders id default }

/-- The `State storage self` and `Book storage book` pointers are plain reads and writes of
the world: `self_get`/`book_get` read `g`/`bg` and leave the world alone, `self_set`/`book_set`
write through `ss`/`bs`, a write is read back, and the two slots are disjoint. -/
structure Lawful (self_get : M σ AsyncFiller.State_) (self_set : AsyncFiller.State_ → M σ Unit)
    (book_get : M σ AsyncFiller.Book) (book_set : AsyncFiller.Book → M σ Unit)
    (g : σ → AsyncFiller.State_) (ss : σ → AsyncFiller.State_ → σ)
    (bg : σ → AsyncFiller.Book) (bs : σ → AsyncFiller.Book → σ) : Prop where
  hsg : ∀ env w, self_get env w = .ok (g w, w)
  hss : ∀ x env w, self_set x env w = .ok ((), ss w x)
  hbg : ∀ env w, book_get env w = .ok (bg w, w)
  hbs : ∀ x env w, book_set x env w = .ok ((), bs w x)
  hgss : ∀ w x, g (ss w x) = x
  hbgbs : ∀ w b, bg (bs w b) = b
  hgbs : ∀ w b, g (bs w b) = g w
  hbgss : ∀ w x, bg (ss w x) = bg w

theorem upd_upd {κ β : Type} [DecidableEq κ] (f : κ → β) (k : κ) (v v' : β) :
    upd (upd f k v) k v' = upd f k v' := by
  funext x; by_cases hx : x = k <;> simp [upd, hx]

theorem post_ok (q p : Nat) (w w' : σ)
    (h : (if q = 0 then Except.ok (1, w)
      else if 340282366920938463463374607431768211455 < q then Except.ok (340282366920938463463374607431768211455, w)
      else Except.ok (q % 340282366920938463463374607431768211456, w)) =
        (Except.ok (p, w') : Except Revert (Nat × σ))) :
    w' = w ∧ 1 ≤ p ∧ p < 2 ^ 128 := by
  by_cases hq0 : q = 0
  · simp only [hq0, ↓reduceIte, Except.ok.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl⟩ := h; exact ⟨rfl, by decide, by decide⟩
  · by_cases hq1 : 340282366920938463463374607431768211455 < q
    · simp only [hq0, hq1, ↓reduceIte, Except.ok.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl⟩ := h; exact ⟨rfl, by decide, by decide⟩
    · simp only [hq0, hq1, ↓reduceIte, Except.ok.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      rw [Nat.mod_eq_of_lt (by omega)]; exact ⟨rfl, by omega, by omega⟩

/-- `AsyncMatching._priceKey` does not touch storage and returns a key in `[1, 2^128)`. -/
theorem priceKey_ok (b : Bool) (a n p : Nat) (env : Env) (w w' : σ)
    (h : AsyncMatching.«_priceKey» ext b a n env w = .ok (p, w')) :
    w' = w ∧ 1 ≤ p ∧ p < 2 ^ 128 := by
  -- The clamp, for any price computation `m` that leaves the world alone. Stated over an
  -- abstract `m` so the kernel never unfolds `mulDivFloor` (whose `x * PRICE_SCALE < 2^256` guard
  -- it would otherwise try to evaluate on a symbolic `x`).
  have tail : ∀ m : M σ Nat, (∀ q w₁, m env w = .ok (q, w₁) → w₁ = w) →
      (do
        let t ← m
        if (t == 0) = true then pure 1
          else if decide (t > 2 ^ 128 - 1) = true then pure (2 ^ 128 - 1)
          else pure (t % 2 ^ 128) : M σ Nat) env w = .ok (p, w') →
      w' = w ∧ 1 ≤ p ∧ p < 2 ^ 128 := by
    intro m hm hr
    simp only [run_bind] at hr
    rcases hq : m env w with e | ⟨q, w₁⟩ <;> rw [hq] at hr
    · cases hr
    · rw [hm q w₁ hq] at hr
      exact post_ok q p w w' (by simpa using hr)
  have frame : ∀ x y d q w₁, mulDivFloor (σ := σ) x y d env w = .ok (q, w₁) → w₁ = w := by
    intro x y d q w₁ hm
    unfold mulDivFloor at hm
    simp only [run_ite, run_throw, run_pure] at hm
    repeat' split at hm
    all_goals (simp only [reduceCtorEq, Except.ok.injEq, Prod.mk.injEq] at hm; try exact hm.2.symm)
  unfold AsyncMatching.«_priceKey» at h
  cases b
  · rw [ite_eq_right_of_eq_false _ _ Bool.false_eq_true] at h
    exact tail _ (frame _ _ _) h
  · rw [ite_eq_left_of_eq_true _ _ (eq_self true)] at h
    exact tail _ (frame _ _ _) h

variable {self_get : M σ AsyncFiller.State_} {self_set : AsyncFiller.State_ → M σ Unit}
    {book_get : M σ AsyncFiller.Book} {book_set : AsyncFiller.Book → M σ Unit}
    {g : σ → AsyncFiller.State_} {ss : σ → AsyncFiller.State_ → σ}
    {bg : σ → AsyncFiller.Book} {bs : σ → AsyncFiller.Book → σ}

/-- **Guard.** Consuming more input than the order holds reverts with panic 0x11 (checked
`oldInput - inputUsed`), before any write or external call. -/
theorem reduceAfterMatch_overuse
    (L : Lawful self_get self_set book_get book_set g ss bg bs)
    (key : PoolKey) (params : AsyncMatching.ReductionParams) (hook : Nat) (env : Env) (w : σ)
    (hu : ((g w).orders params.id).amountIn < params.inputUsed) :
    AsyncMatching.«_reduceAfterMatch» ext self_get self_set book_get book_set key params hook
      env w = .error (FormalAst.panic "0x11") := by
  unfold AsyncMatching.«_reduceAfterMatch»
  have hi : ¬ params.inputUsed ≤ ((g w).orders params.id).amountIn := by omega
  simp only [run_bind, L.hsg, subc, run_throw, hi, ↓reduceIte]

/-- **Closed order.** When no input or no minimum output remains, a successful run consumed no
more than the order's input, settled the pro-rata priority fee (`_settleMatchedPriorityFee`
returning the unfilled fee `u`), ran `_remove`, deleted `orders[id]`, settled `u` for the order's
owner through `settlePriorityFee`, and, when input remains, refunded exactly `remIn` of the input
currency to the owner (`settle` from the hook, then `take` to the owner); otherwise it stops there. -/
theorem reduceAfterMatch_ok_close
    (L : Lawful self_get self_set book_get book_set g ss bg bs)
    (key : PoolKey) (params : AsyncMatching.ReductionParams) (hook : Nat) (env : Env) (w w' : σ)
    (h : AsyncMatching.«_reduceAfterMatch» ext self_get self_set book_get book_set key params hook
      env w = .ok ((), w'))
    (hc : ((g w).orders params.id).amountIn - params.inputUsed = 0 ∨
      remMin ((g w).orders params.id) params.outputReceived = 0) :
    let o := (g w).orders params.id
    let remIn := o.amountIn - params.inputUsed
    params.inputUsed ≤ o.amountIn ∧ ∃ u w1 w2 w3,
      AsyncMatching.«_settleMatchedPriorityFee» ext self_get self_set key params.id
        params.inputUsed o.amountIn hook env w = .ok (u, w1) ∧
      ext.fn_AsyncFiller_remove_6902 self_get self_set book_get book_set params.id env w1 =
        .ok ((), w2) ∧
      AsyncFiller.settlePriorityFee ext self_get self_set key params.id o.owner u hook env
        (ss w2 (deleted (g w2) params.id)) = .ok ((), w3) ∧
      (if remIn = 0 then w' = w3 else ∃ w4,
        CurrencySettler.settle ext params.inputCurrency (g w3).poolManager hook remIn true env w3 =
          .ok ((), w4) ∧
        CurrencySettler.take ext params.inputCurrency (g w4).poolManager o.owner remIn
          (params.inputCurrency == CurrencyLibrary.ADDRESS_ZERO) env w4 = .ok ((), w')) := by
  intro o remIn
  unfold AsyncMatching.«_reduceAfterMatch» at h
  have hi : params.inputUsed ≤ o.amountIn := by
    by_cases hi : params.inputUsed ≤ o.amountIn
    · exact hi
    · simp only [run_bind, L.hsg, subc, run_throw, o, hi, ↓reduceIte] at h
      cases h
  refine ⟨hi, ?_⟩
  have hcond : (((g w).orders params.id).amountIn - params.inputUsed == 0 ||
      remMin ((g w).orders params.id) params.outputReceived == 0) = true := by
    rcases hc with hc | hc <;> simp [hc]
  by_cases ho : params.outputReceived ≥ o.amountOutMin
  · have hr0 : remMin ((g w).orders params.id) params.outputReceived = 0 := by
      simp [remMin, o] at ho ⊢; omega
    rw [hr0] at hcond
    simp only [run_bind, L.hsg, L.hss, L.hbg, L.hbs, run_pure, run_ite, subc, addc, run_throw,
      L.hgss, L.hgbs, L.hbgss, upd_same, upd_upd, CurrencyLibrary.isAddressZero, o, hi, ho,
      ↓reduceIte, decide_true, hcond] at h
    split at h
    next u w1 hs =>
      split at h
      next _ w2 hr =>
        split at h
        next _ w3 hp =>
          refine ⟨u, w1, w2, w3, hs, hr, hp, ?_⟩
          by_cases h0 : remIn = 0
          · have h0' : ((g w).orders params.id).amountIn - params.inputUsed = 0 := h0
            simp only [h0', bne_self_eq_false, Bool.false_eq_true, ↓reduceIte,
              Except.ok.injEq, Prod.mk.injEq, true_and] at h
            simp only [h0, ↓reduceIte, h]
          · have h0' : ¬ ((g w).orders params.id).amountIn - params.inputUsed = 0 := h0
            simp only [h0', bne_iff_ne, ne_eq, not_false_eq_true, ↓reduceIte] at h
            simp only [h0, ↓reduceIte]
            split at h
            next _ w4 hst =>
              split at h
              next _ w5 htk =>
                simp only [Except.ok.injEq, Prod.mk.injEq, true_and] at h
                subst h
                exact ⟨w4, hst, htk⟩
              next => cases h
            next => cases h
        next => cases h
      next => cases h
    next => cases h
  · have hle : params.outputReceived ≤ o.amountOutMin := by omega
    have hrm : remMin ((g w).orders params.id) params.outputReceived =
        ((g w).orders params.id).amountOutMin - params.outputReceived := by
      simp [remMin, o] at ho ⊢; omega
    rw [hrm] at hcond
    simp only [run_bind, L.hsg, L.hss, L.hbg, L.hbs, run_pure, run_ite, subc, addc, run_throw,
      L.hgss, L.hgbs, L.hbgss, upd_same, upd_upd, CurrencyLibrary.isAddressZero, o, hi, ho, hle,
      ↓reduceIte, decide_false, Bool.false_eq_true, hcond] at h
    split at h
    next u w1 hs =>
      split at h
      next _ w2 hr =>
        split at h
        next _ w3 hp =>
          refine ⟨u, w1, w2, w3, hs, hr, hp, ?_⟩
          by_cases h0 : remIn = 0
          · have h0' : ((g w).orders params.id).amountIn - params.inputUsed = 0 := h0
            simp only [h0', bne_self_eq_false, Bool.false_eq_true, ↓reduceIte,
              Except.ok.injEq, Prod.mk.injEq, true_and] at h
            simp only [h0, ↓reduceIte, h]
          · have h0' : ¬ ((g w).orders params.id).amountIn - params.inputUsed = 0 := h0
            simp only [h0', bne_iff_ne, ne_eq, not_false_eq_true, ↓reduceIte] at h
            simp only [h0, ↓reduceIte]
            split at h
            next _ w4 hst =>
              split at h
              next _ w5 htk =>
                simp only [Except.ok.injEq, Prod.mk.injEq, true_and] at h
                subst h
                exact ⟨w4, hst, htk⟩
              next => cases h
            next => cases h
        next => cases h
      next => cases h
    next => cases h

/-- **Partial fill.** When input and minimum both remain, a successful run consumed no more than
the order's input, settled the pro-rata priority fee (`_settleMatchedPriorityFee` returning the
unfilled fee `u`), then wrote exactly `reduced` (remaining input, remaining minimum, `u mod 2^64`)
leaving the book alone, computed the new price key `p ∈ [1, 2^128)` without touching storage, and:
if the price is unchanged and (outside priority mode or with an unchanged fee) it stops there;
otherwise it ran `_remove`, wrote the new price (plus a fresh sequence `nextSequence + 1 < 2^64`
in both the order and the book when the price moved), then `_append`. -/
theorem reduceAfterMatch_ok_partial
    (L : Lawful self_get self_set book_get book_set g ss bg bs)
    (key : PoolKey) (params : AsyncMatching.ReductionParams) (hook : Nat) (env : Env) (w w' : σ)
    (h : AsyncMatching.«_reduceAfterMatch» ext self_get self_set book_get book_set key params hook
      env w = .ok ((), w'))
    (hin : ((g w).orders params.id).amountIn - params.inputUsed ≠ 0)
    (hmn : remMin ((g w).orders params.id) params.outputReceived ≠ 0) :
    let o := (g w).orders params.id
    let remIn := o.amountIn - params.inputUsed
    let rm := remMin o params.outputReceived
    params.inputUsed ≤ o.amountIn ∧ ∃ u w1 w2 p,
      AsyncMatching.«_settleMatchedPriorityFee» ext self_get self_set key params.id
        params.inputUsed o.amountIn hook env w = .ok (u, w1) ∧
      g w2 = reduced (g w1) params.id remIn rm (u % 2 ^ 64) ∧
      bg w2 = bg w1 ∧
      AsyncMatching.«_priceKey» ext ((g w1).orders params.id).isBuy remIn rm env w2 = .ok (p, w2) ∧
      1 ≤ p ∧ p < 2 ^ 128 ∧
      (if p = ((g w1).orders params.id).price ∧ ¬((bg w1).orderingMode = 1 ∧ u ≠ o.priorityFee)
       then w' = w2
       else ∃ w3 w4,
        ext.fn_AsyncFiller_remove_6902 self_get self_set book_get book_set params.id env w2 =
          .ok ((), w3) ∧
        (if p = ((g w1).orders params.id).price then
          g w4 = repriced (g w3) params.id p ∧ bg w4 = bg w3
         else (bg w3).nextSequence + 1 < 2 ^ 64 ∧
          g w4 = resequenced (g w3) params.id p ((bg w3).nextSequence + 1) ∧
          bg w4 = { bg w3 with nextSequence := (bg w3).nextSequence + 1 }) ∧
        ext.fn_AsyncFiller_append_6737 self_get self_set book_get book_set params.id env w4 =
          .ok ((), w')) := by
  intro o remIn rm
  unfold AsyncMatching.«_reduceAfterMatch» at h
  have hi : params.inputUsed ≤ o.amountIn := by
    by_cases hi : params.inputUsed ≤ o.amountIn
    · exact hi
    · simp only [run_bind, L.hsg, subc, run_throw, o, hi, ↓reduceIte] at h
      cases h
  refine ⟨hi, ?_⟩
  have ho : ¬ params.outputReceived ≥ o.amountOutMin := by
    intro ho; exact hmn (by simp [remMin, ho, o])
  have hrm : rm = o.amountOutMin - params.outputReceived := by simp [rm, remMin, ho]
  have hle : params.outputReceived ≤ o.amountOutMin := by omega
  have hcond : (((g w).orders params.id).amountIn - params.inputUsed == 0 ||
      ((g w).orders params.id).amountOutMin - params.outputReceived == 0) = false := by
    have : ((g w).orders params.id).amountOutMin - params.outputReceived ≠ 0 := by
      rw [← hrm]; exact hmn
    simp [hin, this]
  rw [hrm]
  simp only [run_bind, L.hsg, L.hss, L.hbg, L.hbs, run_pure, run_ite, subc, addc, run_throw,
    L.hgss, L.hgbs, L.hbgss, upd_same, upd_upd, CurrencyLibrary.isAddressZero, o, hi, ho, hle,
    ↓reduceIte, decide_false, hcond, Bool.false_eq_true] at h
  split at h
  next u w1 hs =>
    split at h
    next p w2' hpk =>
      obtain ⟨rfl, hp1, hp2⟩ := priceKey_ok ext _ _ _ _ _ _ _ hpk
      simp only [L.hgss, L.hbgss, upd_same] at h
      refine ⟨u, w1, _, p, hs, ?_, ?_, hpk, hp1, hp2, ?_⟩
      · simp only [L.hgss, reduced, remIn, o]
      · simp only [L.hbgss]
      by_cases hp : p = ((g w1).orders params.id).price
      · have hp' : (p != ((g w1).orders params.id).price) = false := by simp [hp]
        by_cases hq : (bg w1).orderingMode = 1 ∧ u ≠ ((g w).orders params.id).priorityFee
        · have hq' : ((bg w1).orderingMode == 1 && u != ((g w).orders params.id).priorityFee) =
              true := by simp [hq.1, hq.2]
          rw [if_neg (fun hc => hc.2 hq)]
          simp only [hp', hq', Bool.not_false, ↓reduceIte, Bool.false_eq_true] at h
          split at h
          next _ w3 hr =>
            split at h
            next _ w4 hap =>
              simp only [Except.ok.injEq, Prod.mk.injEq, true_and] at h
              subst h
              refine ⟨w3, _, hr, ?_, hap⟩
              rw [if_pos hp]
              exact ⟨by simp only [L.hgss, repriced], by simp only [L.hbgss]⟩
            next => cases h
          next => cases h
        · have hq' : ((bg w1).orderingMode == 1 && u != ((g w).orders params.id).priorityFee) =
              false := by
            by_cases hm : (bg w1).orderingMode = 1
            · have hu : u = ((g w).orders params.id).priorityFee :=
                Classical.byContradiction fun hne => hq ⟨hm, hne⟩
              simp [hu]
            · simp [hm]
          rw [if_pos ⟨hp, hq⟩]
          simp only [hp', hq', Bool.not_false, ↓reduceIte, Bool.false_eq_true, Except.ok.injEq,
            Prod.mk.injEq, true_and] at h
          exact h.symm
      · have hp' : (p != ((g w1).orders params.id).price) = true := by simp [hp]
        rw [if_neg (fun hc => hp hc.1)]
        simp only [hp', Bool.not_true, ↓reduceIte, Bool.false_eq_true] at h
        split at h
        next _ w3 hr =>
          by_cases hseq : (bg w3).nextSequence + 1 < 2 ^ 64
          · simp only [hseq, ↓reduceIte, L.hgss, L.hgbs, L.hbgss, L.hbgbs, upd_same, upd_upd] at h
            split at h
            next _ w4 hap =>
              simp only [Except.ok.injEq, Prod.mk.injEq, true_and] at h
              subst h
              refine ⟨w3, _, hr, ?_, hap⟩
              rw [if_neg hp]
              exact ⟨hseq, by simp only [L.hgss, resequenced],
                by simp only [L.hbgbs, L.hgbs, L.hbgss]⟩
            next => cases h
          · simp [hseq] at h
        next => cases h
    next => cases h
  next => cases h

end AsyncSwap.Swarm.ReduceAfterMatch
