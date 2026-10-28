import Generated.AsyncSwap
import Refinement.Monad

/-!
# Plan item 231: `AsyncFiller.mostPermissiveAtPrice`

The theorems are about the generated def `AsyncSwap.AsyncFiller.mostPermissiveAtPrice`
(`Generated/AsyncSwap.lean`), which translates the conditional storage reference
`isBuy ? book.bidLevels[price] : book.askLevels[price]`.

Solidity: `AsyncFiller.mostPermissiveAtPrice(Book storage book, bool isBuy, uint256 price)`
returns `level.exactBounds[level.priorityOrders.root]` for the selected level.
-/

open FormalAst Refinement

namespace AsyncSwap

namespace Swarm.MostPermissiveAtPrice

/-- The price level the function reads: `bidLevels[price]` for a buy, `askLevels[price]` otherwise. -/
def sel (b : AsyncFiller.Book) (isBuy : Bool) (price : Nat) : AsyncFiller.PriceLevel :=
  if isBuy then b.bidLevels price else b.askLevels price

/-- Success and footprint: when the book getter is a pure read of `b`, the function succeeds,
leaves the world unchanged (writes nothing), and returns the exact bound stored at the root of the
selected level's priority tree. -/
theorem mostPermissiveAtPrice_of_read {σ : Type} (ext : Ext σ)
    (book_get : M σ AsyncFiller.Book) (book_set : AsyncFiller.Book → M σ Unit)
    (isBuy : Bool) (price : Nat) (r : Env) (s : σ) (b : AsyncFiller.Book)
    (hget : book_get r s = .ok (b, s)) :
    AsyncFiller.mostPermissiveAtPrice ext book_get book_set isBuy price r s
      = .ok ((sel b isBuy price).exactBounds (sel b isBuy price).priorityOrders.root, s) := by
  unfold AsyncFiller.mostPermissiveAtPrice sel
  cases isBuy <;> simp [hget]

/-- No guards of its own: the function reverts exactly when (and with the error that) its
storage getter does. -/
theorem mostPermissiveAtPrice_error {σ : Type} (ext : Ext σ)
    (book_get : M σ AsyncFiller.Book) (book_set : AsyncFiller.Book → M σ Unit)
    (isBuy : Bool) (price : Nat) (r : Env) (s : σ) (e : Revert)
    (hget : book_get r s = .error e) :
    AsyncFiller.mostPermissiveAtPrice ext book_get book_set isBuy price r s = .error e := by
  unfold AsyncFiller.mostPermissiveAtPrice
  cases isBuy <;> simp [hget]

/-- Under a pure-read getter the function never reverts. -/
theorem mostPermissiveAtPrice_no_revert {σ : Type} (ext : Ext σ)
    (book_get : M σ AsyncFiller.Book) (book_set : AsyncFiller.Book → M σ Unit)
    (isBuy : Bool) (price : Nat) (r : Env) (s : σ) (b : AsyncFiller.Book)
    (hget : book_get r s = .ok (b, s)) (e : Revert) :
    AsyncFiller.mostPermissiveAtPrice ext book_get book_set isBuy price r s ≠ .error e := by
  rw [mostPermissiveAtPrice_of_read ext book_get book_set isBuy price r s b hget]
  intro h; cases h

/-- The setter is never used: the result is independent of `book_set` (no writes). -/
theorem mostPermissiveAtPrice_book_set_irrelevant {σ : Type} (ext : Ext σ)
    (book_get : M σ AsyncFiller.Book) (bs bs' : AsyncFiller.Book → M σ Unit)
    (isBuy : Bool) (price : Nat) :
    AsyncFiller.mostPermissiveAtPrice ext book_get bs isBuy price
      = AsyncFiller.mostPermissiveAtPrice ext book_get bs' isBuy price := rfl

/-- Instantiated on contract storage: reading `priceBooks[poolId]` of this contract's state, the
function returns `level.exactBounds[level.priorityOrders.root]` and leaves the world unchanged. -/
theorem mostPermissiveAtPrice_storage {σ : Type} (ext : Ext σ)
    (book_set : AsyncFiller.Book → M σ Unit)
    (poolId : Nat) (isBuy : Bool) (price : Nat) (r : Env) (s : σ) :
    AsyncFiller.mostPermissiveAtPrice ext
        (do return (ext.get (← get)).priceBooks poolId) book_set isBuy price r s
      = .ok ((sel ((ext.get s).priceBooks poolId) isBuy price).exactBounds
               (sel ((ext.get s).priceBooks poolId) isBuy price).priorityOrders.root, s) :=
  mostPermissiveAtPrice_of_read ext _ book_set isBuy price r s _ (by simp)

end Swarm.MostPermissiveAtPrice

end AsyncSwap
