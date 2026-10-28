import Generated.AsyncSwap
import Refinement.Monad
import Refinement.Swarm.AsyncSwapRepair
import Refinement.Swarm.AsyncSwapRefresh
import Refinement.Swarm.AsyncSwapRemove
import Refinement.Swarm.AsyncSwapExactPrice
open FormalAst Refinement

/-!
# `AsyncFiller.refreshExactPrice` (src/AsyncSwap.sol)

`refreshExactPrice(id)` looks up order `id` in `self`, selects its price level
(`book.bidLevels[price]` for a buy, `book.askLevels[price]` for a sell), computes the order's
exact limit price with `exactPrice` (`amountIn/amountOutMin` for a buy, `amountOutMin/amountIn`
for a sell) and hands it to `EligiblePrice.refresh(priorityKey, price, isBuy)` on that level's
`priorityOrders` tree and `exactBounds` cache.

It has no guard of its own; the only revert it can raise itself is the model's `"loop bound"`
from `_repair`. It never writes `self` (`self_set` is never used); every write goes through
`book_set`. It returns `()`.

The proofs use the Hoare-style predicate `Good Q P x` of `AsyncSwapRepair` (started in a
`Q`-state, `x` ends in a `Q`-state or fails with a `P`-error), propagated syntactically through
the body, closing the inner `refresh` call with `refresh_good`.
-/

namespace AsyncSwap.Swarm.RefreshExactPrice

open AsyncSwap.Swarm.Repair AsyncSwap.Swarm.Refresh AsyncSwap.Swarm.Remove
open AsyncSwap.Swarm.ExactPrice

variable {σ : Type}

/-- **Invariant / revert characterisation.** For any state predicate `Q` and error predicate `P`:
if `self_get`, `book_get`, every `book_set b` and every comparison `le a b` keep `Q` and fail only
with `P`-errors, and `P` accepts the loop-bound revert, then `AsyncFiller.refreshExactPrice` keeps
`Q` and fails only with `P`-errors. `self_set` needs no hypothesis: it is never called. -/
theorem refreshExactPrice_good (ext : Ext σ) (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (id : Nat)
    (Q : σ → Prop) (P : Revert → Prop)
    (hsg : Good Q P self_get) (hbg : Good Q P book_get) (hbs : ∀ b, Good Q P (book_set b))
    (hle : ∀ a b, Good Q P (ext.fn_EligiblePrice_le_12578 a b))
    (hlb : P ⟨"loop bound"⟩) :
    Good Q P (AsyncFiller.refreshExactPrice ext self_get self_set book_get book_set id) := by
  unfold AsyncFiller.refreshExactPrice AsyncFiller.exactPrice
  dsimp only
  repeat' (first
    | (with_reducible apply hbs)
    | (apply refresh_good (hlb := hlb) (hle := hle))
    | (with_reducible apply good_ite_app)
    | good_step)

/-- **Reverts.** If the accessors and the comparison never fail, `AsyncFiller.refreshExactPrice`
can revert only with the model's `"loop bound"`: it has no guard of its own. -/
theorem refreshExactPrice_reverts_only_loop_bound (ext : Ext σ)
    (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (id : Nat)
    (hsg : ∀ r s, ∃ v s', self_get r s = .ok (v, s'))
    (hbg : ∀ r s, ∃ v s', book_get r s = .ok (v, s'))
    (hbs : ∀ b r s, ∃ s', book_set b r s = .ok ((), s'))
    (hle : ∀ a b r s, ∃ v s', ext.fn_EligiblePrice_le_12578 a b r s = .ok (v, s'))
    (r : Env) (s : σ) (e : Revert)
    (h : AsyncFiller.refreshExactPrice ext self_get self_set book_get book_set id r s =
      .error e) :
    e = ⟨"loop bound"⟩ := by
  have hg := refreshExactPrice_good ext self_get self_set book_get book_set id
    (fun _ => True) (fun e => e = ⟨"loop bound"⟩)
    (by intro r s _; obtain ⟨v, s', hh⟩ := hsg r s; simp [hh])
    (by intro r s _; obtain ⟨v, s', hh⟩ := hbg r s; simp [hh])
    (by intro b r s _; obtain ⟨s', hh⟩ := hbs b r s; simp [hh])
    (by intro a b r s _; obtain ⟨v, s', hh⟩ := hle a b r s; simp [hh])
    rfl r s trivial
  rw [h] at hg
  exact hg

/-- **Frame: storage is written only through `book_set`.** If the reads (`self_get`,
`book_get`, `le`) leave the world unchanged and every `book_set b` leaves `view` unchanged, a
successful `AsyncFiller.refreshExactPrice` leaves `view` unchanged. With `view` = the filler's
`self` state (orders, …) this says the function writes nothing but the book. -/
theorem refreshExactPrice_frame {τ : Type} (view : σ → τ) (ext : Ext σ)
    (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (id : Nat)
    (hsg : ∀ r s v s', self_get r s = .ok (v, s') → s' = s)
    (hbg : ∀ r s v s', book_get r s = .ok (v, s') → s' = s)
    (hle : ∀ a b r s v s', ext.fn_EligiblePrice_le_12578 a b r s = .ok (v, s') → s' = s)
    (hbs : ∀ b r s s', book_set b r s = .ok ((), s') → view s' = view s)
    (r : Env) (s s' : σ) (u : Unit)
    (h : AsyncFiller.refreshExactPrice ext self_get self_set book_get book_set id r s =
      .ok (u, s')) :
    view s' = view s := by
  have hg := refreshExactPrice_good ext self_get self_set book_get book_set id
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
    trivial r s rfl
  rw [h] at hg
  exact hg

/-- **`self_set` is never used**: `AsyncFiller.refreshExactPrice` does not depend on the `self`
setter, so it never writes the filler's order state. -/
theorem refreshExactPrice_self_set_irrelevant (ext : Ext σ) (self_get : M σ AsyncFiller.State_)
    (ss₁ ss₂ : AsyncFiller.State_ → M σ Unit) (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (id : Nat) :
    AsyncFiller.refreshExactPrice ext self_get ss₁ book_get book_set id =
      AsyncFiller.refreshExactPrice ext self_get ss₂ book_get book_set id := rfl

/-! ## The hand-off to `EligiblePrice.refresh` -/

/-- The order's price level: `book.bidLevels[p]` for a buy, `book.askLevels[p]` for a sell. -/
def levelGet (book_get : M σ AsyncFiller.Book) (isBuy : Bool) (p : Nat) :
    M σ AsyncFiller.PriceLevel :=
  if isBuy then (do return (((← book_get)).bidLevels p))
  else (do return (((← book_get)).askLevels p))

/-- Writing the order's price level back into the book. -/
def levelSet (book_get : M σ AsyncFiller.Book) (book_set : AsyncFiller.Book → M σ Unit)
    (isBuy : Bool) (p : Nat) : AsyncFiller.PriceLevel → M σ Unit :=
  if isBuy then (fun x => do book_set ({ ((← book_get)) with bidLevels := upd (((← book_get)).bidLevels) p (x) }))
  else (fun x => do book_set ({ ((← book_get)) with askLevels := upd (((← book_get)).askLevels) p (x) }))

/-- **Hand-off.** If `self_get` is a pure read of `S`, `AsyncFiller.refreshExactPrice id` behaves
exactly as `EligiblePrice.refresh` on the order's price level (`priorityOrders` tree and
`exactBounds` cache, read and written through `book_get`/`book_set`), with
`rank = (S.orders id).priorityKey`, `price = ratioOf (S.orders id)` and `isBuy = (S.orders id).isBuy`:
same result, same final state, same revert. -/
theorem refreshExactPrice_eq (ext : Ext σ) (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (id : Nat)
    (S : AsyncFiller.State_) (hself : ∀ r s, self_get r s = .ok (S, s)) (r : Env) (s : σ) :
    let G := levelGet book_get (S.orders id).isBuy (S.orders id).price
    let W := levelSet book_get book_set (S.orders id).isBuy (S.orders id).price
    AsyncFiller.refreshExactPrice ext self_get self_set book_get book_set id r s =
      EligiblePrice.refresh ext
        (do return ((← G)).priorityOrders)
        (fun x => do W ({ ((← G)) with priorityOrders := x }))
        (do return ((← G)).exactBounds)
        (fun x => do W ({ ((← G)) with exactBounds := x }))
        (S.orders id).priorityKey (ratioOf (S.orders id)) (S.orders id).isBuy r s := by
  intro G W
  have hx := exactPrice_of_read ext (do return ((← self_get)).orders id)
    (fun x => do self_set ({ ((← self_get)) with orders := upd (((← self_get)).orders) id (x) }))
    r s (S.orders id) (by simp [run_bind, hself])
  simp only [G, W, levelGet, levelSet]
  unfold AsyncFiller.refreshExactPrice
  simp only [run_bind, hself, hx]
  split <;> rename_i h <;> rw [h] <;> rfl

end AsyncSwap.Swarm.RefreshExactPrice
