import Generated.AsyncSwap
import Refinement.Monad

/-!
# `AsyncSwap.orderBookLevel`

`function orderBookLevel(PoolId poolId, bool isBuy, uint128 priceKey) external view
returns (bytes32 head, bytes32 tail, uint32 count)` (src/AsyncSwap.sol:280), which forwards to
`AsyncMatching.level(priceBooks[poolId], isBuy, priceKey)` → `AsyncFiller.level` (an internal
library function the model keeps opaque: `ext.fn_AsyncFiller_level_6002`).

* `orderBookLevel_eq` / `orderBookLevel_run`: the call *is* `AsyncFiller.level` run on the storage
  reference `priceBooks[poolId]` (getter `bookGet`, setter `bookSet`), with the arguments
  `isBuy, priceKey` passed through unchanged and its result returned as is.
* **Guards**: none of its own (`orderBookLevel_reverts_iff`): it reverts exactly when the callee does.
* **Footprint**: nothing written by this layer; if the callee is read-only (it is `view`), the
  whole call leaves the world unchanged (`orderBookLevel_readOnly`).
* **Return**: if the callee computes `F book isBuy price` from the book its getter reads (a `view`
  over `book`), the result is `F priceBooks[poolId] isBuy priceKey` and the state is unchanged
  (`orderBookLevel_view`); in particular it only depends on `priceBooks[poolId]`
  (`orderBookLevel_congr`).
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.OrderBookLevel

variable {σ : Type}

/-- Storage reference `priceBooks[poolId]`: getter. -/
def bookGet (ext : Ext σ) (pid : Nat) : M σ AsyncFiller.Book := do
  return ((ext.get (← get)).priceBooks pid)

/-- Storage reference `priceBooks[poolId]`: setter. -/
def bookSet (ext : Ext σ) (pid : Nat) : AsyncFiller.Book → M σ Unit := fun x =>
  modify fun w => ext.set w (let s := ext.get w; { s with priceBooks := upd (s.priceBooks) pid x })

def Preserves {α : Type} (p : M σ α) : Prop := ∀ env s r s', p env s = .ok (r, s') → s' = s

/-- `orderBookLevel` is exactly `AsyncFiller.level` on `priceBooks[poolId]`. -/
theorem orderBookLevel_eq (ext : Ext σ) (pid : Nat) (isBuy : Bool) (k : Nat) :
    AsyncSwap.orderBookLevel ext pid isBuy k =
      ext.fn_AsyncFiller_level_6002 (bookGet ext pid) (bookSet ext pid) isBuy k := by
  simp only [AsyncSwap.orderBookLevel, AsyncMatching.level]
  rfl

/-- Run form. -/
theorem orderBookLevel_run (ext : Ext σ) (pid : Nat) (isBuy : Bool) (k : Nat) (env : Env) (w : σ) :
    AsyncSwap.orderBookLevel ext pid isBuy k env w =
      ext.fn_AsyncFiller_level_6002 (bookGet ext pid) (bookSet ext pid) isBuy k env w := by
  rw [orderBookLevel_eq]

/-- **Guards.** No revert of its own: it reverts exactly when `AsyncFiller.level` does, with the
same reason. -/
theorem orderBookLevel_reverts_iff (ext : Ext σ) (pid : Nat) (isBuy : Bool) (k : Nat) (env : Env)
    (w : σ) (e : Revert) :
    AsyncSwap.orderBookLevel ext pid isBuy k env w = .error e ↔
      ext.fn_AsyncFiller_level_6002 (bookGet ext pid) (bookSet ext pid) isBuy k env w = .error e := by
  rw [orderBookLevel_run]

/-- **Footprint.** This layer writes nothing: if `AsyncFiller.level` (a `view`) is read-only, the
call leaves the world unchanged. -/
theorem orderBookLevel_readOnly (ext : Ext σ) (pid : Nat) (isBuy : Bool) (k : Nat)
    (hview : Preserves (ext.fn_AsyncFiller_level_6002 (bookGet ext pid) (bookSet ext pid) isBuy k))
    (env : Env) (w w' : σ) (r : Nat × Nat × Nat)
    (h : AsyncSwap.orderBookLevel ext pid isBuy k env w = .ok (r, w')) : w' = w := by
  rw [orderBookLevel_run] at h
  exact hview env w r w' h

/-- **Return.** If `AsyncFiller.level` is a view computing `F book isBuy price` from the book its
getter reads, `orderBookLevel` returns `F priceBooks[poolId] isBuy priceKey`, state unchanged,
never reverting. -/
theorem orderBookLevel_view (ext : Ext σ)
    (F : AsyncFiller.Book → Bool → Nat → Nat × Nat × Nat)
    (hlevel : ∀ (B : σ → AsyncFiller.Book) (g : M σ AsyncFiller.Book)
      (s : AsyncFiller.Book → M σ Unit) (isBuy : Bool) (k : Nat),
      (∀ env w, g env w = .ok (B w, w)) →
      ∀ env w, ext.fn_AsyncFiller_level_6002 g s isBuy k env w = .ok (F (B w) isBuy k, w))
    (pid : Nat) (isBuy : Bool) (k : Nat) (env : Env) (w : σ) :
    AsyncSwap.orderBookLevel ext pid isBuy k env w =
      .ok (F ((ext.get w).priceBooks pid) isBuy k, w) := by
  rw [orderBookLevel_run]
  exact hlevel (fun w => (ext.get w).priceBooks pid) _ _ isBuy k (fun _ _ => rfl) env w

/-- Under the same hypothesis, the answer only depends on `priceBooks[poolId]`. -/
theorem orderBookLevel_congr (ext : Ext σ)
    (F : AsyncFiller.Book → Bool → Nat → Nat × Nat × Nat)
    (hlevel : ∀ (B : σ → AsyncFiller.Book) (g : M σ AsyncFiller.Book)
      (s : AsyncFiller.Book → M σ Unit) (isBuy : Bool) (k : Nat),
      (∀ env w, g env w = .ok (B w, w)) →
      ∀ env w, ext.fn_AsyncFiller_level_6002 g s isBuy k env w = .ok (F (B w) isBuy k, w))
    (pid : Nat) (isBuy : Bool) (k : Nat) (env env' : Env) (w v : σ)
    (hb : (ext.get w).priceBooks pid = (ext.get v).priceBooks pid) :
    (AsyncSwap.orderBookLevel ext pid isBuy k env w).map Prod.fst =
      (AsyncSwap.orderBookLevel ext pid isBuy k env' v).map Prod.fst := by
  rw [orderBookLevel_view ext F hlevel, orderBookLevel_view ext F hlevel, hb]
  rfl

end AsyncSwap.Swarm.OrderBookLevel
