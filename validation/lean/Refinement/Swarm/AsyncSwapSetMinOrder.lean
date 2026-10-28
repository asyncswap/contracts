import Generated.AsyncSwap
import Refinement.Monad
open FormalAst Refinement

/-!
# `AsyncSwap.setMinOrder` (src/AsyncSwap.sol:257)

```solidity
function setMinOrder(PoolKey calldata key, uint256 minimum) external onlyOwner {
    AsyncMatching.setMinOrder(priceBooks[key.toId()], key.toId(), minimum);
}
```

Closed form: run in environment `r` on world `s`, the call reverts with `NotOwner` unless
`r.sender = owner`, and otherwise returns `()` having written exactly
`priceBooks[id].minOrder := minimum`, where `id = keccak(key)` is the pool id.

The internal `AsyncFiller.setMinOrder(book, poolId, minimum)` has no guard of its own: it reads
the book, writes it back with only `minOrder` replaced, and emits `MinOrderSet`.
The library wrapper `AsyncMatching.setMinOrder` forwards to it unchanged.
-/

namespace AsyncSwap
variable {σ : Type} (ext : Ext σ)

/-! ## The internal `AsyncFiller.setMinOrder` -/

/-- Exact semantics of the internal `AsyncFiller.setMinOrder`: read the book through `book_get`,
then write `{book with minOrder := minimum}` through `book_set`; it reverts exactly when
the read or the write reverts. -/
theorem filler_setMinOrder_run (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (poolId minimum : Nat) (r : Env) (s : σ) :
    AsyncFiller.setMinOrder ext book_get book_set poolId minimum r s =
      (match book_get r s with
       | .ok (b, s₁) => book_set { b with minOrder := minimum } r s₁
       | .error e => .error e) := by
  unfold AsyncFiller.setMinOrder
  simp only [run_bind, run_pure]
  cases book_get r s with
  | error e => rfl
  | ok p =>
    obtain ⟨b, s₁⟩ := p
    simp only
    cases book_set { b with minOrder := minimum } r s₁ <;> rfl

/-- With a getter that only reads (`book_get r s = ok (b, s)`), the call is exactly the single
write `book_set {b with minOrder := minimum}`. -/
theorem filler_setMinOrder_of_read (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (poolId minimum : Nat) (r : Env) (s : σ)
    (b : AsyncFiller.Book) (hget : book_get r s = .ok (b, s)) :
    AsyncFiller.setMinOrder ext book_get book_set poolId minimum r s =
      book_set { b with minOrder := minimum } r s := by
  rw [filler_setMinOrder_run, hget]

/-- The result does not depend on `poolId` (used only in the emitted event). -/
theorem filler_setMinOrder_poolId_irrelevant (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (p q minimum : Nat) :
    AsyncFiller.setMinOrder ext book_get book_set p minimum =
      AsyncFiller.setMinOrder ext book_get book_set q minimum := rfl

/-- No guard of its own: when the read and the write both succeed, the call succeeds with the
setter's result. -/
theorem filler_setMinOrder_ok (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit)
    (poolId minimum : Nat) (r : Env) (s s₁ s₂ : σ) (b : AsyncFiller.Book)
    (hget : book_get r s = .ok (b, s₁))
    (hset : book_set { b with minOrder := minimum } r s₁ = .ok ((), s₂)) :
    AsyncFiller.setMinOrder ext book_get book_set poolId minimum r s = .ok ((), s₂) := by
  rw [filler_setMinOrder_run, hget]; exact hset

/-! ## The library wrapper `AsyncMatching.setMinOrder` -/

/-- Exact semantics of `AsyncMatching.setMinOrder`: no guard of its own; it reads the book
through `book_get`, then writes `{book with minOrder := minimum}` through `book_set`, and
reverts exactly when the read or the write reverts. It touches storage only through these. -/
theorem matching_setMinOrder_run (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (poolId minimum : Nat) (r : Env) (s : σ) :
    AsyncMatching.setMinOrder ext book_get book_set poolId minimum r s =
      (match book_get r s with
       | .ok (b, s₁) => book_set { b with minOrder := minimum } r s₁
       | .error e => .error e) := by
  unfold AsyncMatching.setMinOrder AsyncFiller.setMinOrder
  simp only [run_bind, run_pure]
  cases book_get r s with
  | error e => rfl
  | ok p =>
    obtain ⟨b, s₁⟩ := p
    simp only [run_bind, run_pure]
    cases book_set { b with minOrder := minimum } r s₁ <;> rfl

/-- `AsyncMatching.setMinOrder` equals the internal `AsyncFiller.setMinOrder` it forwards to. -/
theorem matching_setMinOrder_eq_filler (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (poolId minimum : Nat) (r : Env) (s : σ) :
    AsyncMatching.setMinOrder ext book_get book_set poolId minimum r s =
      AsyncFiller.setMinOrder ext book_get book_set poolId minimum r s := by
  rw [matching_setMinOrder_run, filler_setMinOrder_run]

/-- With a getter that only reads, `AsyncMatching.setMinOrder` is exactly the single write
`book_set {b with minOrder := minimum}`. -/
theorem matching_setMinOrder_of_read (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (poolId minimum : Nat) (r : Env) (s : σ)
    (b : AsyncFiller.Book) (hget : book_get r s = .ok (b, s)) :
    AsyncMatching.setMinOrder ext book_get book_set poolId minimum r s =
      book_set { b with minOrder := minimum } r s := by
  rw [matching_setMinOrder_run, hget]

/-- Reverts propagate: if the read reverts with `e`, so does `AsyncMatching.setMinOrder`. -/
theorem matching_setMinOrder_get_error (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (poolId minimum : Nat) (r : Env) (s : σ) (e)
    (hget : book_get r s = .error e) :
    AsyncMatching.setMinOrder ext book_get book_set poolId minimum r s = .error e := by
  rw [matching_setMinOrder_run, hget]

/-- No guard of its own: when the read and the write succeed, `AsyncMatching.setMinOrder`
returns `()` in the setter's post-world. -/
theorem matching_setMinOrder_ok (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit)
    (poolId minimum : Nat) (r : Env) (s s₁ s₂ : σ) (b : AsyncFiller.Book)
    (hget : book_get r s = .ok (b, s₁))
    (hset : book_set { b with minOrder := minimum } r s₁ = .ok ((), s₂)) :
    AsyncMatching.setMinOrder ext book_get book_set poolId minimum r s = .ok ((), s₂) := by
  rw [matching_setMinOrder_run, hget]; exact hset

/-- The result of `AsyncMatching.setMinOrder` does not depend on `poolId`. -/
theorem matching_setMinOrder_poolId_irrelevant (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (p q minimum : Nat) :
    AsyncMatching.setMinOrder ext book_get book_set p minimum =
      AsyncMatching.setMinOrder ext book_get book_set q minimum := rfl

/-! ## The external `AsyncSwap.setMinOrder` -/

/-- The pool id `PoolIdLibrary.toId` computes for `key`. -/
def setMinOrderPoolId (key : PoolKey) : Nat :=
  ext.keccak [key.currency0, key.currency1, key.fee, toUnsigned 256 key.tickSpacing, key.hooks]

/-- The world after a successful call: only `priceBooks[id].minOrder` changes. -/
def setMinOrderPost (key : PoolKey) (minimum : Nat) (s : σ) : σ :=
  ext.set s { ext.get s with
    priceBooks := upd (ext.get s).priceBooks (setMinOrderPoolId ext key)
      { (ext.get s).priceBooks (setMinOrderPoolId ext key) with minOrder := minimum } }

/-- Exact semantics: guard `msg.sender == owner`, single write
`priceBooks[toId(key)].minOrder := minimum`. -/
theorem setMinOrder_run (key : PoolKey) (minimum : Nat) (r : Env) (s : σ) :
    AsyncSwap.setMinOrder ext key minimum r s =
      if r.sender = (ext.get s).owner then
        .ok ((), setMinOrderPost ext key minimum s)
      else .error ⟨"NotOwner"⟩ := by
  unfold AsyncSwap.setMinOrder AsyncSwap.onlyOwner AsyncMatching.setMinOrder
    AsyncFiller.setMinOrder PoolIdLibrary.toId setMinOrderPost setMinOrderPoolId
  by_cases h : r.sender = (ext.get s).owner <;> simp [h]

/-- Guard: a caller other than `owner` makes the call revert with `NotOwner`. -/
theorem setMinOrder_reverts_of_not_owner (key : PoolKey) (minimum : Nat) (r : Env) (s : σ)
    (h : r.sender ≠ (ext.get s).owner) :
    AsyncSwap.setMinOrder ext key minimum r s = .error ⟨"NotOwner"⟩ := by
  rw [setMinOrder_run]; simp [h]

/-- Effect: called by `owner`, it returns `()` and writes only the book's `minOrder`. -/
theorem setMinOrder_ok_of_owner (key : PoolKey) (minimum : Nat) (r : Env) (s : σ)
    (h : r.sender = (ext.get s).owner) :
    AsyncSwap.setMinOrder ext key minimum r s =
      .ok ((), setMinOrderPost ext key minimum s) := by
  rw [setMinOrder_run]; simp [h]

/-- The call succeeds iff the caller is `owner`; on success the post-world is the single write. -/
theorem setMinOrder_ok_iff (key : PoolKey) (minimum : Nat) (r : Env) (s s' : σ) (u : Unit) :
    AsyncSwap.setMinOrder ext key minimum r s = .ok (u, s') ↔
      r.sender = (ext.get s).owner ∧ s' = setMinOrderPost ext key minimum s := by
  rw [setMinOrder_run]
  by_cases h : r.sender = (ext.get s).owner
  · simp [h]; constructor <;> intro hh <;> simp_all
  · simp [h]

/-- Frame: on success (under a lawful `Ext`), the book of pool `toId(key)` has
`minOrder = minimum` and is otherwise unchanged, every other pool's book is unchanged,
and `owner` is unchanged. -/
theorem setMinOrder_frame (key : PoolKey) (minimum : Nat) (r : Env) (s s' : σ) (u : Unit)
    (hget : ∀ w st, ext.get (ext.set w st) = st)
    (hok : AsyncSwap.setMinOrder ext key minimum r s = .ok (u, s')) :
    (ext.get s').priceBooks (setMinOrderPoolId ext key) =
        { (ext.get s).priceBooks (setMinOrderPoolId ext key) with minOrder := minimum } ∧
      (∀ p, p ≠ setMinOrderPoolId ext key →
        (ext.get s').priceBooks p = (ext.get s).priceBooks p) ∧
      (ext.get s').owner = (ext.get s).owner := by
  obtain ⟨_, rfl⟩ := (setMinOrder_ok_iff ext key minimum r s s' u).1 hok
  refine ⟨?_, ?_, ?_⟩
  · simp [setMinOrderPost, hget, upd_same]
  · intro p hp; simp [setMinOrderPost, hget, upd_other _ _ _ _ hp]
  · simp [setMinOrderPost, hget]

end AsyncSwap
