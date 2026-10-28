import Specs.AsyncSwap
import Proofs.Monad

open FormalAst Refinement

namespace AsyncSwap.Swarm.AsyncOrderInfo

/-- The view succeeds for every environment and storage state, preserves storage,
and returns the stored order amounts. -/
theorem asyncOrderInfo_storage {σ : Type} (ext : Ext σ)
    (poolId orderId : Nat) (r : Env) (s : σ) :
    AsyncSwap.asyncOrderInfo ext poolId orderId r s =
      Except.ok (((((ext.get s).asyncOrders poolId).orders orderId).amountIn,
        (((ext.get s).asyncOrders poolId).orders orderId).amountOutMin), s) := by
  simp [AsyncSwap.asyncOrderInfo, bind, ReaderT.bind, StateT.bind, Except.bind,
    pure, ReaderT.pure, StateT.pure, Except.pure]

/-- The view has no revert branch: it always returns successfully. -/
theorem asyncOrderInfo_no_revert {σ : Type} (ext : Ext σ)
    (poolId orderId : Nat) (r : Env) (s : σ) (e : Revert) :
    AsyncSwap.asyncOrderInfo ext poolId orderId r s ≠ Except.error e := by
  rw [asyncOrderInfo_storage ext poolId orderId r s]
  intro h
  cases h

end AsyncSwap.Swarm.AsyncOrderInfo
