import Specs.AsyncSwap
import Proofs.Monad

/-!
# Plan item 232: `AsyncFiller.level`

Every theorem here is about the generated def `AsyncSwap.AsyncFiller.level` in
`Generated.AsyncSwap` (no local copy of the function).

Solidity: `level(Book storage book, bool isBuy, uint256 price)` selects
`L = isBuy ? book.bidLevels[price] : book.askLevels[price]`, reads the highest and lowest keys of
`L.priorityOrders` with `RadixPriceTree.best`, and returns
`(hasHead ? L.priorityOrderIds[highestKey] : 0, hasTail ? L.priorityOrderIds[lowestKey] : 0, L.orderCount)`.

* Guards: none of its own; the only revert is the model's `"loop bound"` inside `RadixPriceTree.best`.
* Footprint: empty — `book_set` is never called.
* External calls: none.
-/

open FormalAst Refinement

namespace AsyncSwap
namespace Swarm.Level

variable {σ : Type}

/-! ## Generic monad facts (Hoare-style predicate `Good`, loop invariants) -/

/-- Started in a `Q`-state, `x` ends in a `Q`-state or fails with a `P`-error. -/
def Good (Q : σ → Prop) (P : Revert → Prop) {α : Type} (x : M σ α) : Prop :=
  ∀ r s, Q s → match x r s with
    | .ok (_, s') => Q s'
    | .error e => P e

section closure
variable {Q : σ → Prop} {P : Revert → Prop}

theorem good_pure {α : Type} (a : α) : Good Q P (pure a : M σ α) := by
  intro r s h; simpa [run_pure] using h

theorem good_throw {α : Type} (e : Revert) (he : P e) : Good Q P (throw e : M σ α) := by
  intro r s _; simpa [run_throw] using he

theorem good_bind {α β : Type} {x : M σ α} {f : α → M σ β}
    (hx : Good Q P x) (hf : ∀ a, Good Q P (f a)) : Good Q P (x >>= f) := by
  intro r s h
  rw [run_bind]
  have hxs := hx r s h
  revert hxs
  cases x r s with
  | error e => intro he; exact he
  | ok p => obtain ⟨a, s'⟩ := p; intro hs; exact hf a r s' hs

theorem good_ite {α : Type} (c : Prop) [Decidable c] {x y : M σ α}
    (hx : Good Q P x) (hy : Good Q P y) : Good Q P (if c then x else y) := by
  split <;> assumption

theorem good_forIn_list {α β : Type} (l : List α) (init : β) (f : α → β → M σ (ForInStep β))
    (hf : ∀ a b, Good Q P (f a b)) : Good Q P (forIn l init f) := by
  induction l generalizing init with
  | nil => rw [List.forIn_nil]; exact good_pure init
  | cons a l ih =>
    rw [List.forIn_cons]
    apply good_bind (hf a init)
    intro step
    cases step with
    | done b => exact good_pure b
    | yield b => exact ih b

theorem good_forIn_range {β : Type} (rg : Std.Legacy.Range) (init : β)
    (f : Nat → β → M σ (ForInStep β))
    (hf : ∀ a b, Good Q P (f a b)) : Good Q P (forIn rg init f) := by
  rw [Std.Legacy.Range.forIn_eq_forIn_range']
  exact good_forIn_list _ init f hf

end closure

macro "lvl_step" : tactic => `(tactic| first
  | with_reducible assumption
  | with_reducible apply good_pure
  | (with_reducible apply good_throw); with_reducible assumption
  | with_reducible apply good_ite
  | with_reducible apply good_bind
  | with_reducible apply good_forIn_range
  | with_reducible intro _)

theorem loop_ok {β : Type} (l : List Nat) (init : β) (f : Nat → β → M σ (ForInStep β))
    (I : β → Prop) (hI : I init)
    (hf : ∀ a b r s, I b → ∃ st, f a b r s = .ok (st, s) ∧ I st.value)
    (r : Env) (s s' : σ) (q : β) (h : forIn l init f r s = .ok (q, s')) :
    s' = s ∧ I q := by
  induction l generalizing init with
  | nil => simp at h; obtain ⟨rfl, rfl⟩ := h; exact ⟨rfl, hI⟩
  | cons a l ih =>
    rw [List.forIn_cons, run_bind] at h
    obtain ⟨st, hst, hIst⟩ := hf a init r s hI
    rw [hst] at h
    cases st with
    | done b => simp at h; obtain ⟨rfl, rfl⟩ := h; exact ⟨rfl, hIst⟩
    | yield b => exact ih b hIst h

theorem loop_no_err {β : Type} (l : List Nat) (init : β) (f : Nat → β → M σ (ForInStep β))
    (I : β → Prop) (hI : I init)
    (hf : ∀ a b r s, I b → ∃ st, f a b r s = .ok (st, s) ∧ I st.value)
    (r : Env) (s : σ) (e : Revert) (h : forIn l init f r s = .error e) : False := by
  induction l generalizing init with
  | nil => simp at h
  | cons a l ih =>
    rw [List.forIn_cons, run_bind] at h
    obtain ⟨st, hst, hIst⟩ := hf a init r s hI
    rw [hst] at h
    cases st with
    | done b => simp at h
    | yield b => exact ih b hIst h

/-- The price level read: `bidLevels[price]` for a buy, `askLevels[price]` otherwise. -/
def sel (b : AsyncFiller.Book) (isBuy : Bool) (price : Nat) : AsyncFiller.PriceLevel :=
  if isBuy then b.bidLevels price else b.askLevels price

/-! ## Guards and footprint of `AsyncFiller.level` -/

/-- If `book_get` preserves `Q` and fails only with `P`-errors, and `P` accepts the loop-bound
revert, then `AsyncFiller.level` preserves `Q` and fails only with `P`-errors. -/
theorem level_good (ext : Ext σ) (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (isBuy : Bool) (price : Nat)
    (Q : σ → Prop) (P : Revert → Prop)
    (hbg : Good Q P book_get) (hlb : P ⟨"loop bound"⟩) :
    Good Q P (AsyncFiller.level ext book_get book_set isBuy price) := by
  unfold AsyncFiller.level RadixPriceTree.best
  repeat' lvl_step

/-- **Guards.** If the book read never reverts, the only revert of `AsyncFiller.level` is
`"loop bound"`: it has no `require` of its own. -/
theorem level_reverts (ext : Ext σ) (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (isBuy : Bool) (price : Nat)
    (hbg : ∀ r s, ∃ v s', book_get r s = .ok (v, s'))
    (r : Env) (s : σ) (e : Revert)
    (h : AsyncFiller.level ext book_get book_set isBuy price r s = .error e) :
    e = ⟨"loop bound"⟩ := by
  have hg := level_good ext book_get book_set isBuy price (fun _ => True)
    (fun e => e = ⟨"loop bound"⟩)
    (by intro r s _; obtain ⟨v, s', hh⟩ := hbg r s; simp [hh]) rfl r s trivial
  rw [h] at hg
  exact hg

/-- **Footprint is empty.** If the book read leaves the state unchanged, so does every successful
run of `AsyncFiller.level`. -/
theorem level_frame (ext : Ext σ) (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (isBuy : Bool) (price : Nat)
    (hbg : ∀ r s v s', book_get r s = .ok (v, s') → s' = s)
    (r : Env) (s s' : σ) (res : Nat × Nat × Nat)
    (h : AsyncFiller.level ext book_get book_set isBuy price r s = .ok (res, s')) :
    s' = s := by
  have hg := level_good ext book_get book_set isBuy price (fun w => w = s) (fun _ => True)
    (by
      intro r w hw; revert hw
      cases hh : book_get r w with
      | error e => intro _; trivial
      | ok p => obtain ⟨v, w'⟩ := p; intro hw; simp only; rw [hbg r w v w' hh]; exact hw)
    trivial r s rfl
  rw [h] at hg
  exact hg

/-- `AsyncFiller.level` does not depend on `book_set`: it never writes the book. -/
theorem level_book_set_irrelevant (ext : Ext σ) (book_get : M σ AsyncFiller.Book)
    (bs₁ bs₂ : AsyncFiller.Book → M σ Unit) (isBuy : Bool) (price : Nat) :
    AsyncFiller.level ext book_get bs₁ isBuy price
      = AsyncFiller.level ext book_get bs₂ isBuy price := rfl

/-! ## The result -/

/-- `RadixPriceTree.best` over a read-only tree `t`: a successful run leaves the state unchanged,
returns `(false, 0)` only when `t.root = 0`, and `(true, p)` only when `t.root ≠ 0` with `p` the
price of a leaf. Loop invariant: `done = true → (t.nodes cursor).leaf`. -/
theorem radix_best_result (ext : Ext σ) (tg : M σ RadixPriceTree.Tree)
    (ts : RadixPriceTree.Tree → M σ Unit) (highest : Bool) (t : RadixPriceTree.Tree)
    (htg : ∀ r s, tg r s = .ok (t, s))
    (r : Env) (s s' : σ) (found : Bool) (p : Nat)
    (h : RadixPriceTree.best ext tg ts highest r s = .ok ((found, p), s')) :
    s' = s ∧ (found = false → p = 0 ∧ t.root = 0) ∧
      (found = true → t.root ≠ 0 ∧ ∃ c, (t.nodes c).leaf = true ∧ p = (t.nodes c).price) := by
  unfold RadixPriceTree.best at h
  simp [htg] at h
  by_cases hr : t.root = 0
  · simp [hr] at h
    obtain ⟨⟨rfl, rfl⟩, rfl⟩ := h
    simp [hr]
  · simp [hr] at h
    split at h
    · next q s'' heq =>
      obtain ⟨rfl, hI⟩ := loop_ok _ _ _
        (fun q : Nat × Bool => q.2 = true → (t.nodes q.1).leaf = true) (by simp) (by
          intro a q r s hq
          by_cases hl : (t.nodes q.1).leaf = true
          · simp [htg, hl]
          · cases highest <;> simp [htg, hl] <;> exact fun hd => absurd (hq hd) hl) r s s'' q heq
      split at h
      · simp at h
      · next hd =>
        simp at h
        obtain ⟨⟨rfl, rfl⟩, rfl⟩ := h
        simp at hd
        exact ⟨rfl, by simp, fun _ => ⟨hr, q.1, hI hd, rfl⟩⟩
    · next e heq =>
      exact (loop_no_err _ _ _
        (fun q : Nat × Bool => q.2 = true → (t.nodes q.1).leaf = true) (by simp) (by
          intro a q r s hq
          by_cases hl : (t.nodes q.1).leaf = true
          · simp [htg, hl]
          · cases highest <;> simp [htg, hl] <;> exact fun hd => absurd (hq hd) hl) r s e heq).elim

/-- **Empty level.** If `book_get` reads `b` without changing state and the selected level's
priority tree is empty (`root = 0`), then `AsyncFiller.level` succeeds, returns
`(0, 0, L.orderCount)` and leaves the state unchanged. -/
theorem level_empty (ext : Ext σ) (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (isBuy : Bool) (price : Nat)
    (b : AsyncFiller.Book) (hget : ∀ r s, book_get r s = .ok (b, s))
    (hr : (sel b isBuy price).priorityOrders.root = 0) (r : Env) (s : σ) :
    AsyncFiller.level ext book_get book_set isBuy price r s
      = .ok ((0, 0, (sel b isBuy price).orderCount), s) := by
  unfold AsyncFiller.level RadixPriceTree.best
  cases isBuy <;> simp [sel] at hr <;> simp [hget, hr, sel]

/-- **Result.** If `book_get` reads `b` without changing state and `L = sel b isBuy price`, every
successful run of `AsyncFiller.level` returning `(hd, tl, cnt)` leaves the state unchanged, has
`cnt = L.orderCount`, has `hd = tl = 0` when `L.priorityOrders` is empty, and otherwise has
`hd = L.priorityOrderIds[k₁]` and `tl = L.priorityOrderIds[k₂]` for leaf prices `k₁, k₂` of
`L.priorityOrders`. -/
theorem level_result (ext : Ext σ) (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (isBuy : Bool) (price : Nat)
    (b : AsyncFiller.Book) (hget : ∀ r s, book_get r s = .ok (b, s))
    (r : Env) (s s' : σ) (hd tl cnt : Nat)
    (h : AsyncFiller.level ext book_get book_set isBuy price r s = .ok ((hd, tl, cnt), s')) :
    s' = s ∧ cnt = (sel b isBuy price).orderCount ∧
      ((sel b isBuy price).priorityOrders.root = 0 → hd = 0 ∧ tl = 0) ∧
      ((sel b isBuy price).priorityOrders.root ≠ 0 →
        ∃ c₁ c₂, ((sel b isBuy price).priorityOrders.nodes c₁).leaf = true ∧
          hd = (sel b isBuy price).priorityOrderIds
                 ((sel b isBuy price).priorityOrders.nodes c₁).price ∧
          ((sel b isBuy price).priorityOrders.nodes c₂).leaf = true ∧
          tl = (sel b isBuy price).priorityOrderIds
                 ((sel b isBuy price).priorityOrders.nodes c₂).price) := by
  have hp : book_get = pure b := by funext r s; exact hget r s
  subst hp
  unfold AsyncFiller.level at h
  cases isBuy <;> simp only [sel, Bool.false_eq_true, ite_true, ite_false] at h ⊢ <;>
  · simp only [run_bind, pure_bind] at h
    split at h
    · next q1 s1 h1 =>
      obtain ⟨f1, k1⟩ := q1
      obtain ⟨rfl, hf1, ht1⟩ := radix_best_result ext _ _ _ _ (fun _ _ => rfl) _ _ _ _ _ h1
      split at h
      · next q2 s2 h2 =>
        obtain ⟨f2, k2⟩ := q2
        obtain ⟨rfl, hf2, ht2⟩ := radix_best_result ext _ _ _ _ (fun _ _ => rfl) _ _ _ _ _ h2
        rcases f1 with _ | _ <;> rcases f2 with _ | _ <;> simp at h <;>
          obtain ⟨⟨ha, hb, hc⟩, hs⟩ := h <;> subst_vars
        · exact ⟨rfl, rfl, fun _ => ⟨rfl, rfl⟩, fun h0 => absurd (hf1 rfl).2 h0⟩
        · exact absurd (hf1 rfl).2 (ht2 rfl).1
        · exact absurd (hf2 rfl).2 (ht1 rfl).1
        · obtain ⟨hr, c1, hl1, rfl⟩ := ht1 rfl
          obtain ⟨_, c2, hl2, rfl⟩ := ht2 rfl
          exact ⟨rfl, rfl, fun h0 => absurd h0 hr, fun _ => ⟨c1, c2, hl1, rfl, hl2, rfl⟩⟩
      · simp at h
    · simp at h

end Swarm.Level
end AsyncSwap
