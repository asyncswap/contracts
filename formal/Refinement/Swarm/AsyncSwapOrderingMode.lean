import Generated.AsyncSwap
import Refinement.Monad

/-!
# `AsyncSwap.orderingMode` (src/AsyncSwap.sol:243)

External view with no guards: it never reverts, writes nothing (the world is returned unchanged)
and returns `priceBooks[poolId].orderingMode` read from the hook's storage. No external calls.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm

variable {σ : Type} (ext : Ext σ)

/-- Exact run: never reverts, returns `priceBooks[poolId].orderingMode`, leaves the world unchanged. -/
theorem orderingMode_run (poolId : Nat) (env : Env) (w : σ) :
    AsyncSwap.orderingMode ext poolId env w
      = .ok (((ext.get w).priceBooks poolId).orderingMode, w) := by
  simp [AsyncSwap.orderingMode]

/-- No guards: the call never reverts. -/
theorem orderingMode_never_reverts (poolId : Nat) (env : Env) (w : σ) (e : Revert) :
    AsyncSwap.orderingMode ext poolId env w ≠ .error e := by
  rw [orderingMode_run]; simp

/-- Footprint: on success the world is unchanged (writes nothing). -/
theorem orderingMode_frame (poolId : Nat) (env : Env) (w w' : σ) (r : Nat)
    (h : AsyncSwap.orderingMode ext poolId env w = .ok (r, w')) : w' = w := by
  rw [orderingMode_run] at h; cases h; rfl

/-- Return value: on success it is the stored ordering mode of the pool's price book. -/
theorem orderingMode_result (poolId : Nat) (env : Env) (w w' : σ) (r : Nat)
    (h : AsyncSwap.orderingMode ext poolId env w = .ok (r, w')) :
    r = ((ext.get w).priceBooks poolId).orderingMode := by
  rw [orderingMode_run] at h; cases h; rfl

end AsyncSwap.Swarm
