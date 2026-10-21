import Generated.AsyncSwap
import Refinement.Monad

/-!
# `AsyncMatching.setOrderingMode` called directly

`AsyncMatching.setOrderingMode(Book storage book, PoolId, OrderingMode)` is `public`, so the
library is deployed and linked, and anyone can call it. Its only write goes through the `book`
storage reference (`book_set` in the model). A direct CALL to the library account runs in the
library's own storage, not in AsyncSwap's (and solc's library call guard reverts any
non-view direct call anyway). So it cannot change any pool's `priceBooks[_].orderingMode`.
Only `AsyncSwap.setOrderingMode` passes accessors into `priceBooks`, and that path is owner-gated
(see `AsyncSwapSetOrderingMode.lean`).

Below: (1) a frame lemma saying that if `book_get` only reads and `book_set` preserves a
projection `f`, a successful call preserves `f`; (2) the two-account case, where the hook's
storage is `σS` and the library's storage is `σL`, and accessors that touch only the library
account leave the hook's state, and so every pool's ordering mode, unchanged.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm

variable {σ : Type} (ext : Ext σ)

/-- Frame: the library function only changes state through `book_set`. -/
theorem asyncMatching_setOrderingMode_frame {τ : Type} (f : σ → τ)
    (book_get : M σ AsyncFiller.Book) (book_set : AsyncFiller.Book → M σ Unit)
    (poolId mode : Nat) (env : Env) (w w' : σ)
    (hget : ∀ w, ∃ b, book_get env w = .ok (b, w))
    (hset : ∀ b w w', book_set b env w = .ok ((), w') → f w' = f w)
    (hok : AsyncMatching.setOrderingMode ext book_get book_set poolId mode env w = .ok ((), w')) :
    f w' = f w := by
  obtain ⟨b, hb⟩ := hget w
  simp only [AsyncMatching.setOrderingMode, AsyncFiller.setOrderingMode] at hok
  by_cases h0 : b.openOrderCount = 0
  · cases hs : book_set { b with orderingMode := mode } env w with
    | error e => simp_all [bind, StateT.bind, ReaderT.bind, Except.bind]
    | ok r =>
      obtain ⟨u, w''⟩ := r
      have : w'' = w' := by
        simp_all [bind, StateT.bind, ReaderT.bind, Except.bind, pure, StateT.pure, ReaderT.pure,
          Except.pure]
      subst this
      exact hset _ _ _ hs
  · simp_all [bind, StateT.bind, ReaderT.bind, Except.bind]

/-- Two accounts: hook storage `σS`, library storage `σL`. A direct call to the library with
accessors into the library account (they read and write `.2` only) leaves AsyncSwap's storage,
and so every pool's book and ordering mode, unchanged. -/
theorem asyncMatching_setOrderingMode_direct_noPoolChange {σS σL : Type}
    (extS : Ext σS) (ext2 : Ext (σS × σL))
    (book_get : M (σS × σL) AsyncFiller.Book) (book_set : AsyncFiller.Book → M (σS × σL) Unit)
    (poolId mode : Nat) (env : Env) (w w' : σS × σL)
    (hget : ∀ w, ∃ b, book_get env w = .ok (b, w))
    (hset : ∀ b w w', book_set b env w = .ok ((), w') → w'.1 = w.1)
    (hok : AsyncMatching.setOrderingMode ext2 book_get book_set poolId mode env w = .ok ((), w')) :
    w'.1 = w.1 ∧
      ∀ p, ((extS.get w'.1).priceBooks p).orderingMode = ((extS.get w.1).priceBooks p).orderingMode := by
  have h := asyncMatching_setOrderingMode_frame ext2 Prod.fst book_get book_set poolId mode env w w'
    hget hset hok
  exact ⟨h, fun p => by rw [h]⟩

end AsyncSwap.Swarm
