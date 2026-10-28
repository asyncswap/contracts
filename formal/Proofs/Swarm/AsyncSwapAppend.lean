import Specs.AsyncSwap
import Proofs.Monad
import Proofs.Swarm.AsyncSwapRepair
import Proofs.Swarm.AsyncSwapRemove
import Proofs.Swarm.AsyncSwapRefreshExactPrice
open FormalAst Refinement

/-!
# `AsyncFiller._append` (src/AsyncSwap.sol)

`_append(id)` links order `id` into its price level (`book.bidLevels[price]` for a buy,
`book.askLevels[price]` for a sell): if the level is empty it inserts the price into the book's
`bids`/`asks` radix tree; it computes `priorityKey = _priorityKey(priorityFee, sequence)`, stores it
in `orders[id]`, inserts it into the level's `priorityOrders` tree, refreshes the level's exact
price cache (`refreshExactPrice`), records `priorityOrderIds[key] = id`, and increments the level's
`orderCount` (uint32, checked) and the book's `openOrderCount` (uint64, checked).

It has no `require` of its own. Its reverts come from checked arithmetic (`panic 0x11`: the two
counters, the `sequence` subtraction in `_priorityKey`, the bit counter in `_mostSignificantBit`),
from `RadixPriceTree.insert` / `_newNode` (`"NodeIdOverflow"`, `panic 0x31`, `panic 0x32`, and the
model's `"loop bound"`), and from `refreshExactPrice` (`"loop bound"`).

All storage is reached through the four accessors it is handed; the proofs use the Hoare-style
predicate `Good Q P` of `AsyncSwapRepair`, propagated syntactically through the body.
-/

namespace AsyncSwap.Swarm.Append

open AsyncSwap.Swarm.Repair AsyncSwap.Swarm.Remove AsyncSwap.Swarm.RefreshExactPrice

variable {σ : Type}

section lemmas
variable {Q : σ → Prop} {P : Revert → Prop}

/-- Checked addition keeps any `Q` and fails only with `panic 0x11`. -/
theorem good_addc (bits a b : Nat) (hp : P (panic "0x11")) : Good Q P (addc bits a b : M σ Nat) := by
  unfold addc
  split
  · exact good_pure _
  · exact good_throw _ hp

/-- Checked array index keeps any `Q` and fails only with `panic 0x32`. -/
theorem good_idx {α : Type} [Inhabited α] (l : List α) (i : Nat) (hp : P (panic "0x32")) :
    Good Q P (idx l i : M σ α) := by
  unfold idx
  split
  · exact good_pure _
  · exact good_throw _ hp

end lemmas

/-- `RadixPriceTree.insert` keeps `Q` and fails only with `P`-errors when its accessors do and `P`
accepts its reverts (`"loop bound"`, `"NodeIdOverflow"`, `panic 0x11/0x31/0x32`). -/
theorem insert_good (ext : Ext σ) (self_get : M σ RadixPriceTree.Tree)
    (self_set : RadixPriceTree.Tree → M σ Unit) (price : Nat)
    (Q : σ → Prop) (P : Revert → Prop)
    (hg : Good Q P self_get) (hs : ∀ t, Good Q P (self_set t))
    (hlb : P ⟨"loop bound"⟩) (hno : P ⟨"NodeIdOverflow"⟩)
    (h11 : P (panic "0x11")) (h31 : P (panic "0x31")) (h32 : P (panic "0x32")) :
    Good Q P (RadixPriceTree.insert ext self_get self_set price) := by
  unfold RadixPriceTree.insert RadixPriceTree.«_newNode» RadixPriceTree.«_bitSet»
    RadixPriceTree.«_mostSignificantBit»
  dsimp only
  repeat' (first
    | (with_reducible apply hs)
    | (with_reducible apply good_addc)
    | (with_reducible apply good_subc)
    | (with_reducible apply good_idx)
    | (with_reducible apply good_forIn_range)
    | good_step)

/-- **Invariant / revert characterisation of `AsyncFiller._append`.** For any state predicate `Q`
and error predicate `P`: if `self_get`, every `self_set x`, `book_get`, every `book_set b` and every
comparison `le a b` keep `Q` and fail only with `P`-errors, and `P` accepts `"loop bound"`,
`"NodeIdOverflow"` and the panics `0x11`, `0x31`, `0x32`, then `AsyncFiller.«_append»` keeps `Q`
and fails only with `P`-errors. -/
theorem append_good (ext : Ext σ) (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (id : Nat)
    (Q : σ → Prop) (P : Revert → Prop)
    (hsg : Good Q P self_get) (hss : ∀ x, Good Q P (self_set x))
    (hbg : Good Q P book_get) (hbs : ∀ b, Good Q P (book_set b))
    (hle : ∀ a b, Good Q P (ext.fn_EligiblePrice_le_12578 a b))
    (hlb : P ⟨"loop bound"⟩) (hno : P ⟨"NodeIdOverflow"⟩)
    (h11 : P (panic "0x11")) (h31 : P (panic "0x31")) (h32 : P (panic "0x32")) :
    Good Q P (AsyncFiller.«_append» ext self_get self_set book_get book_set id) := by
  unfold AsyncFiller.«_append» AsyncFiller.«_priorityKey»
  dsimp only
  repeat' (first
    | (with_reducible apply hbs)
    | (with_reducible apply hss)
    | (with_reducible apply good_addc)
    | (with_reducible apply good_subc)
    | (apply insert_good (hlb := hlb) (hno := hno) (h11 := h11) (h31 := h31) (h32 := h32))
    | (apply refreshExactPrice_good (hlb := hlb) (hle := hle))
    | (with_reducible apply good_ite_app)
    | good_step)

/-- **Reverts.** If the accessors and the comparison never fail, `AsyncFiller.«_append»` reverts
only with `"loop bound"`, `"NodeIdOverflow"`, `panic 0x11`, `panic 0x31` or `panic 0x32`. -/
theorem append_reverts_only (ext : Ext σ) (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (id : Nat)
    (hsg : ∀ r s, ∃ v s', self_get r s = .ok (v, s'))
    (hss : ∀ x r s, ∃ s', self_set x r s = .ok ((), s'))
    (hbg : ∀ r s, ∃ v s', book_get r s = .ok (v, s'))
    (hbs : ∀ b r s, ∃ s', book_set b r s = .ok ((), s'))
    (hle : ∀ a b r s, ∃ v s', ext.fn_EligiblePrice_le_12578 a b r s = .ok (v, s'))
    (r : Env) (s : σ) (e : Revert)
    (h : AsyncFiller.«_append» ext self_get self_set book_get book_set id r s = .error e) :
    e = ⟨"loop bound"⟩ ∨ e = ⟨"NodeIdOverflow"⟩ ∨ e = panic "0x11" ∨ e = panic "0x31" ∨
      e = panic "0x32" := by
  have hg := append_good ext self_get self_set book_get book_set id (fun _ => True)
    (fun e => e = ⟨"loop bound"⟩ ∨ e = ⟨"NodeIdOverflow"⟩ ∨ e = panic "0x11" ∨
      e = panic "0x31" ∨ e = panic "0x32")
    (by intro r s _; obtain ⟨v, s', hh⟩ := hsg r s; simp [hh])
    (by intro x r s _; obtain ⟨s', hh⟩ := hss x r s; simp [hh])
    (by intro r s _; obtain ⟨v, s', hh⟩ := hbg r s; simp [hh])
    (by intro b r s _; obtain ⟨s', hh⟩ := hbs b r s; simp [hh])
    (by intro a b r s _; obtain ⟨v, s', hh⟩ := hle a b r s; simp [hh])
    (Or.inl rfl) (Or.inr (Or.inl rfl)) (Or.inr (Or.inr (Or.inl rfl)))
    (Or.inr (Or.inr (Or.inr (Or.inl rfl)))) (Or.inr (Or.inr (Or.inr (Or.inr rfl))))
    r s trivial
  rw [h] at hg
  exact hg

/-- **Frame: storage is written only through `self_set` and `book_set`.** If the reads
(`self_get`, `book_get`, `le`) leave the world unchanged and every `self_set x` and `book_set b`
leaves `view` unchanged, a successful `AsyncFiller.«_append»` leaves `view` unchanged. -/
theorem append_frame {τ : Type} (view : σ → τ) (ext : Ext σ)
    (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (id : Nat)
    (hsg : ∀ r s v s', self_get r s = .ok (v, s') → s' = s)
    (hss : ∀ x r s s', self_set x r s = .ok ((), s') → view s' = view s)
    (hbg : ∀ r s v s', book_get r s = .ok (v, s') → s' = s)
    (hbs : ∀ b r s s', book_set b r s = .ok ((), s') → view s' = view s)
    (hle : ∀ a b r s v s', ext.fn_EligiblePrice_le_12578 a b r s = .ok (v, s') → s' = s)
    (r : Env) (s s' : σ) (u : Unit)
    (h : AsyncFiller.«_append» ext self_get self_set book_get book_set id r s = .ok (u, s')) :
    view s' = view s := by
  have hg := append_good ext self_get self_set book_get book_set id
    (fun w => view w = view s) (fun _ => True)
    (by
      intro r w hw; revert hw
      cases hh : self_get r w with
      | error e => intro _; trivial
      | ok p => obtain ⟨v, w'⟩ := p; intro hw; simp only; rw [hsg r w v w' hh]; exact hw)
    (by
      intro x r w hw; revert hw
      cases hh : self_set x r w with
      | error e => intro _; trivial
      | ok p => obtain ⟨v, w'⟩ := p; intro hw; simp only; rw [hss x r w w' hh]; exact hw)
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
    trivial trivial trivial trivial trivial r s rfl
  rw [h] at hg
  exact hg

end AsyncSwap.Swarm.Append
