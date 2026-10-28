import Generated.AsyncSwap
import Refinement.Monad
import Refinement.Swarm.AsyncSwapRepair
open FormalAst Refinement

/-!
# `EligiblePrice.remove` and `AsyncFiller._remove` (src/AsyncSwap.sol)

`EligiblePrice.remove(rank, isBuy)` reads `leaf = leaves[rank]`, its `parent` and `grandparent`,
removes the price level from the radix tree (`RadixPriceTree.remove`, which reverts
`PriceLevelMissing` when `leaves[rank] == 0`), then repairs the cached bounds from `grandparent`
upwards (`_repair(grandparent, isBuy, false)`).

`AsyncFiller._remove(id)` looks up order `id` (in `self`), selects its price level
`book.bidLevels[price]` or `book.askLevels[price]` (by `isBuy`), removes the order's priority key
from the level (`EligiblePrice.remove`), clears `priorityOrderIds[priorityKey]`, decrements the
level's `orderCount` and the book's `openOrderCount` (checked: underflow is `panic 0x11`), and if
the level is now empty removes the price from `book.bids`/`book.asks` (`RadixPriceTree.remove`).
It never writes `self`; all writes go through `book_set`. It returns `()`.
-/

namespace AsyncSwap.Swarm.Remove

open AsyncSwap.Swarm.Repair

variable {σ : Type}

/-- **Invariant / revert characterisation.** If every accessor and the comparison `le` keep `Q`
and fail only with `P`-errors, and `P` accepts `PriceLevelMissing` and the loop-bound revert,
then `EligiblePrice.remove` keeps `Q` and fails only with `P`-errors. -/
theorem remove_good (ext : Ext σ) (tree_get : M σ RadixPriceTree.Tree)
    (tree_set : RadixPriceTree.Tree → M σ Unit) (bounds_get : M σ (Nat → EligiblePrice.Ratio))
    (bounds_set : (Nat → EligiblePrice.Ratio) → M σ Unit) (rank : Nat) (isBuy : Bool)
    (Q : σ → Prop) (P : Revert → Prop)
    (htg : Good Q P tree_get) (hts : ∀ t, Good Q P (tree_set t))
    (hbg : Good Q P bounds_get) (hbs : ∀ f, Good Q P (bounds_set f))
    (hle : ∀ a b, Good Q P (ext.fn_EligiblePrice_le_12578 a b))
    (hpm : P ⟨"PriceLevelMissing"⟩) (hlb : P ⟨"loop bound"⟩) :
    Good Q P (EligiblePrice.remove ext tree_get tree_set bounds_get bounds_set rank isBuy) := by
  have hrep : ∀ c, Good Q P (EligiblePrice.«_repair» ext tree_get
      (fun x => tree_set x) bounds_get (fun x => bounds_set x) c isBuy false) := fun c =>
    repair_good ext _ _ _ _ c isBuy false Q P htg hbg (fun f => hbs f) hle hlb
  unfold EligiblePrice.remove RadixPriceTree.remove RadixPriceTree.«_freeNode»
  repeat' (first | (with_reducible apply hts) | (with_reducible apply hrep) | good_step)

/-- **Reverts.** If the accessors and the comparison never revert, `EligiblePrice.remove` can
revert only with `PriceLevelMissing` or `"loop bound"`. -/
theorem remove_reverts_only (ext : Ext σ) (tree_get : M σ RadixPriceTree.Tree)
    (tree_set : RadixPriceTree.Tree → M σ Unit) (bounds_get : M σ (Nat → EligiblePrice.Ratio))
    (bounds_set : (Nat → EligiblePrice.Ratio) → M σ Unit) (rank : Nat) (isBuy : Bool)
    (htg : ∀ r s, ∃ v s', tree_get r s = .ok (v, s'))
    (hts : ∀ t r s, ∃ s', tree_set t r s = .ok ((), s'))
    (hbg : ∀ r s, ∃ v s', bounds_get r s = .ok (v, s'))
    (hbs : ∀ f r s, ∃ s', bounds_set f r s = .ok ((), s'))
    (hle : ∀ a b r s, ∃ v s', ext.fn_EligiblePrice_le_12578 a b r s = .ok (v, s'))
    (r : Env) (s : σ) (e : Revert)
    (h : EligiblePrice.remove ext tree_get tree_set bounds_get bounds_set rank isBuy r s =
      .error e) :
    e = ⟨"PriceLevelMissing"⟩ ∨ e = ⟨"loop bound"⟩ := by
  have hg := remove_good ext tree_get tree_set bounds_get bounds_set rank isBuy
    (fun _ => True) (fun e => e = ⟨"PriceLevelMissing"⟩ ∨ e = ⟨"loop bound"⟩)
    (by intro r s _; obtain ⟨v, s', hh⟩ := htg r s; simp [hh])
    (by intro t r s _; obtain ⟨s', hh⟩ := hts t r s; simp [hh])
    (by intro r s _; obtain ⟨v, s', hh⟩ := hbg r s; simp [hh])
    (by intro f r s _; obtain ⟨s', hh⟩ := hbs f r s; simp [hh])
    (by intro a b r s _; obtain ⟨v, s', hh⟩ := hle a b r s; simp [hh])
    (Or.inl rfl) (Or.inr rfl) r s trivial
  rw [h] at hg
  exact hg

/-- **Guard: missing price level.** If `tree_get` is a pure read of a tree `T` and
`T.leaves rank = 0`, `EligiblePrice.remove` reverts with `PriceLevelMissing`. -/
theorem remove_reverts_missing (ext : Ext σ) (tree_get : M σ RadixPriceTree.Tree)
    (tree_set : RadixPriceTree.Tree → M σ Unit) (bounds_get : M σ (Nat → EligiblePrice.Ratio))
    (bounds_set : (Nat → EligiblePrice.Ratio) → M σ Unit) (rank : Nat) (isBuy : Bool)
    (T : RadixPriceTree.Tree) (r : Env) (s : σ)
    (htg : ∀ r' s', tree_get r' s' = .ok (T, s'))
    (h0 : T.leaves rank = 0) :
    EligiblePrice.remove ext tree_get tree_set bounds_get bounds_set rank isBuy r s =
      .error ⟨"PriceLevelMissing"⟩ := by
  unfold EligiblePrice.remove RadixPriceTree.remove
  simp [run_bind, run_throw, htg, h0]

/-- **Frame: storage is written only through `tree_set` and `bounds_set`.** If the reads leave
the world unchanged and every `tree_set t` and `bounds_set f` leaves `view` unchanged, a
successful `EligiblePrice.remove` leaves `view` unchanged. -/
theorem remove_frame {τ : Type} (view : σ → τ) (ext : Ext σ)
    (tree_get : M σ RadixPriceTree.Tree)
    (tree_set : RadixPriceTree.Tree → M σ Unit) (bounds_get : M σ (Nat → EligiblePrice.Ratio))
    (bounds_set : (Nat → EligiblePrice.Ratio) → M σ Unit) (rank : Nat) (isBuy : Bool)
    (htg : ∀ r s v s', tree_get r s = .ok (v, s') → s' = s)
    (hbg : ∀ r s v s', bounds_get r s = .ok (v, s') → s' = s)
    (hle : ∀ a b r s v s', ext.fn_EligiblePrice_le_12578 a b r s = .ok (v, s') → s' = s)
    (hts : ∀ t r s s', tree_set t r s = .ok ((), s') → view s' = view s)
    (hbs : ∀ f r s s', bounds_set f r s = .ok ((), s') → view s' = view s)
    (r : Env) (s s' : σ) (u : Unit)
    (h : EligiblePrice.remove ext tree_get tree_set bounds_get bounds_set rank isBuy r s =
      .ok (u, s')) :
    view s' = view s := by
  have hg := remove_good ext tree_get tree_set bounds_get bounds_set rank isBuy
    (fun w => view w = view s) (fun _ => True)
    (by
      intro r w hw; revert hw
      cases hh : tree_get r w with
      | error e => intro _; trivial
      | ok p => obtain ⟨v, w'⟩ := p; intro hw; simp only; rw [htg r w v w' hh]; exact hw)
    (by
      intro t r w hw; revert hw
      cases hh : tree_set t r w with
      | error e => intro _; trivial
      | ok p => obtain ⟨v, w'⟩ := p; intro hw; simp only; rw [hts t r w w' hh]; exact hw)
    (by
      intro r w hw; revert hw
      cases hh : bounds_get r w with
      | error e => intro _; trivial
      | ok p => obtain ⟨v, w'⟩ := p; intro hw; simp only; rw [hbg r w v w' hh]; exact hw)
    (by
      intro f r w hw; revert hw
      cases hh : bounds_set f r w with
      | error e => intro _; trivial
      | ok p => obtain ⟨v, w'⟩ := p; intro hw; simp only; rw [hbs f r w w' hh]; exact hw)
    (by
      intro a b r w hw; revert hw
      cases hh : ext.fn_EligiblePrice_le_12578 a b r w with
      | error e => intro _; trivial
      | ok p => obtain ⟨v, w'⟩ := p; intro hw; simp only; rw [hle a b r w v w' hh]; exact hw)
    trivial trivial r s rfl
  rw [h] at hg
  exact hg

/-! ## `AsyncFiller._remove` -/

/-- Checked subtraction keeps any `Q` and fails only with `panic 0x11`. -/
theorem good_subc {Q : σ → Prop} {P : Revert → Prop} (a b : Nat) (hp : P (panic "0x11")) :
    Good Q P (subc a b : M σ Nat) := by
  unfold subc
  split
  · exact good_pure _
  · exact good_throw _ hp

/-- `Good` through a conditional *function* applied to an argument (the generated storage-ref
setters are `if c then fun x => … else fun x => …`). -/
theorem good_ite_app {Q : σ → Prop} {P : Revert → Prop} {α β : Type} (c : Prop) [Decidable c]
    {f g : α → M σ β} (x : α) (hf : Good Q P (f x)) (hg : Good Q P (g x)) :
    Good Q P ((if c then f else g) x) := by
  split <;> assumption

/-- `RadixPriceTree.remove` keeps `Q` and fails only with `P`-errors when its accessors do and
`P` accepts `PriceLevelMissing`. -/
theorem tree_remove_good (ext : Ext σ) (self_get : M σ RadixPriceTree.Tree)
    (self_set : RadixPriceTree.Tree → M σ Unit) (price : Nat)
    (Q : σ → Prop) (P : Revert → Prop)
    (hg : Good Q P self_get) (hs : ∀ t, Good Q P (self_set t))
    (hpm : P ⟨"PriceLevelMissing"⟩) :
    Good Q P (RadixPriceTree.remove ext self_get self_set price) := by
  unfold RadixPriceTree.remove RadixPriceTree.«_freeNode»
  repeat' (first | (with_reducible apply hs) | good_step)

/-- **Invariant / revert characterisation of `AsyncFiller._remove`.** For any state predicate `Q`
and error predicate `P`: if `self_get`, `book_get`, every `book_set b` and every comparison
`le a b` keep `Q` and fail only with `P`-errors, and `P` accepts `PriceLevelMissing`, the loop
bound and the arithmetic panic `0x11`, then `AsyncFiller._remove` keeps `Q` and fails only with
`P`-errors. (`self_set` needs no hypothesis: it is never called.) -/
theorem filler_remove_good (ext : Ext σ) (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (id : Nat)
    (Q : σ → Prop) (P : Revert → Prop)
    (hsg : Good Q P self_get) (hbg : Good Q P book_get) (hbs : ∀ b, Good Q P (book_set b))
    (hle : ∀ a b, Good Q P (ext.fn_EligiblePrice_le_12578 a b))
    (hpm : P ⟨"PriceLevelMissing"⟩) (hlb : P ⟨"loop bound"⟩) (hpa : P (panic "0x11")) :
    Good Q P (AsyncFiller.«_remove» ext self_get self_set book_get book_set id) := by
  unfold AsyncFiller.«_remove»
  dsimp only
  repeat' (first
    | (with_reducible apply hbs)
    | (with_reducible apply good_subc)
    | (with_reducible apply remove_good)
    | (with_reducible apply tree_remove_good)
    | (with_reducible apply good_ite_app)
    | good_step)

/-- **Reverts.** If the accessors and the comparison never fail, `AsyncFiller._remove` reverts only
with `PriceLevelMissing` (the order's price level or priority key is absent from its tree),
`"loop bound"` (the model's gas bound in `_repair`), or `panic 0x11` (underflow of the level's
`orderCount` or the book's `openOrderCount`). -/
theorem filler_remove_reverts_only (ext : Ext σ) (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (id : Nat)
    (hsg : ∀ r s, ∃ v s', self_get r s = .ok (v, s'))
    (hbg : ∀ r s, ∃ v s', book_get r s = .ok (v, s'))
    (hbs : ∀ b r s, ∃ s', book_set b r s = .ok ((), s'))
    (hle : ∀ a b r s, ∃ v s', ext.fn_EligiblePrice_le_12578 a b r s = .ok (v, s'))
    (r : Env) (s : σ) (e : Revert)
    (h : AsyncFiller.«_remove» ext self_get self_set book_get book_set id r s = .error e) :
    e = ⟨"PriceLevelMissing"⟩ ∨ e = ⟨"loop bound"⟩ ∨ e = panic "0x11" := by
  have hg := filler_remove_good ext self_get self_set book_get book_set id
    (fun _ => True)
    (fun e => e = ⟨"PriceLevelMissing"⟩ ∨ e = ⟨"loop bound"⟩ ∨ e = panic "0x11")
    (by intro r s _; obtain ⟨v, s', hh⟩ := hsg r s; simp [hh])
    (by intro r s _; obtain ⟨v, s', hh⟩ := hbg r s; simp [hh])
    (by intro b r s _; obtain ⟨s', hh⟩ := hbs b r s; simp [hh])
    (by intro a b r s _; obtain ⟨v, s', hh⟩ := hle a b r s; simp [hh])
    (Or.inl rfl) (Or.inr (Or.inl rfl)) (Or.inr (Or.inr rfl)) r s trivial
  rw [h] at hg
  exact hg

/-- **Frame: `AsyncFiller._remove` writes only through `book_set`.** If the reads (`self_get`,
`book_get`, `le`) leave the world unchanged and every `book_set b` leaves `view` unchanged, a
successful `AsyncFiller._remove` leaves `view` unchanged. -/
theorem filler_remove_frame {τ : Type} (view : σ → τ) (ext : Ext σ)
    (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (id : Nat)
    (hsg : ∀ r s v s', self_get r s = .ok (v, s') → s' = s)
    (hbg : ∀ r s v s', book_get r s = .ok (v, s') → s' = s)
    (hle : ∀ a b r s v s', ext.fn_EligiblePrice_le_12578 a b r s = .ok (v, s') → s' = s)
    (hbs : ∀ b r s s', book_set b r s = .ok ((), s') → view s' = view s)
    (r : Env) (s s' : σ) (u : Unit)
    (h : AsyncFiller.«_remove» ext self_get self_set book_get book_set id r s = .ok (u, s')) :
    view s' = view s := by
  have hg := filler_remove_good ext self_get self_set book_get book_set id
    (fun w => view w = view s) (fun _ => True)
    (by
      intro r w hw; revert hw
      cases hh : self_get r w with
      | error e => intro _; trivial
      | ok p => obtain ⟨v, w'⟩ := p; intro hw; simp only; rw [hsg r w v w' hh]; exact hw)
    (by
      intro r w hw; revert hw
      cases hh : book_get r w with
      | error e => intro _; trivial
      | ok p => obtain ⟨v, w'⟩ := p; intro hw; simp only; rw [hbg r w v w' hh]; exact hw)
    (by
      intro b r w hw; revert hw
      cases hh : book_set b r w with
      | error e => intro _; trivial
      | ok p => obtain ⟨v, w'⟩ := p; intro hw; simp only; rw [hbs b r w w' hh]; exact hw)
    (by
      intro a b r w hw; revert hw
      cases hh : ext.fn_EligiblePrice_le_12578 a b r w with
      | error e => intro _; trivial
      | ok p => obtain ⟨v, w'⟩ := p; intro hw; simp only; rw [hle a b r w v w' hh]; exact hw)
    trivial trivial trivial r s rfl
  rw [h] at hg
  exact hg

/-- **`self` is never written.** `AsyncFiller._remove` does not depend on its `self` setter. -/
theorem filler_remove_self_set_irrelevant (ext : Ext σ) (self_get : M σ AsyncFiller.State_)
    (ss₁ ss₂ : AsyncFiller.State_ → M σ Unit) (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (id : Nat) :
    AsyncFiller.«_remove» ext self_get ss₁ book_get book_set id =
      AsyncFiller.«_remove» ext self_get ss₂ book_get book_set id := rfl

/-- **Guard: the order's priority key is missing from its price level.** With pure reads of
`self = S` and `book = B`, let `L` be the order's level (`B.bidLevels price` for a buy,
`B.askLevels price` for a sell). If `L.priorityOrders.leaves (S.orders id).priorityKey = 0`,
`AsyncFiller._remove` reverts with `PriceLevelMissing` before writing anything. -/
theorem filler_remove_reverts_missing (ext : Ext σ) (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (id : Nat)
    (S : AsyncFiller.State_) (B : AsyncFiller.Book) (r : Env) (s : σ)
    (hsg : ∀ r' s', self_get r' s' = .ok (S, s'))
    (hbg : ∀ r' s', book_get r' s' = .ok (B, s'))
    (h0 : ((if (S.orders id).isBuy then B.bidLevels (S.orders id).price
            else B.askLevels (S.orders id).price).priorityOrders.leaves
            (S.orders id).priorityKey) = 0) :
    AsyncFiller.«_remove» ext self_get self_set book_get book_set id r s =
      .error ⟨"PriceLevelMissing"⟩ := by
  unfold AsyncFiller.«_remove»
  cases hb : (S.orders id).isBuy
  · rw [hb] at h0
    simp only [ite_false, Bool.false_eq_true] at h0
    simp [run_bind, hsg, hb]
    rw [remove_reverts_missing (T := (B.askLevels (S.orders id).price).priorityOrders)
      (htg := by intro r' s'; simp [hbg]) (h0 := h0)]
  · rw [hb] at h0
    simp only [ite_true] at h0
    simp [run_bind, hsg, hb]
    rw [remove_reverts_missing (T := (B.bidLevels (S.orders id).price).priorityOrders)
      (htg := by intro r' s'; simp [hbg]) (h0 := h0)]

end AsyncSwap.Swarm.Remove
