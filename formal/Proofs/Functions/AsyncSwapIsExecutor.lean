import Specs.AsyncSwap
import Proofs.Monad

open FormalAst Refinement

namespace AsyncSwap
namespace Refinement.Swarm.AsyncSwapIsExecutor

/-- The view succeeds for every environment and storage state, preserves storage,
and returns the executor flag stored for the maker in the selected pool. -/
theorem isExecutor_storage {σ : Type} (ext : Ext σ)
    (poolId maker executor : Nat) (r : Env) (s : σ) :
    AsyncSwap.isExecutor ext poolId maker executor r s =
      Except.ok (((ext.get s).asyncOrders poolId).isExecutor maker executor, s) := by
  simp [AsyncSwap.isExecutor, bind, ReaderT.bind, StateT.bind, Except.bind,
    pure, ReaderT.pure, StateT.pure, Except.pure]

/-- The view has no revert branch: it always returns successfully. -/
theorem isExecutor_no_revert {σ : Type} (ext : Ext σ)
    (poolId maker executor : Nat) (r : Env) (s : σ) (e : Revert) :
    AsyncSwap.isExecutor ext poolId maker executor r s ≠ Except.error e := by
  rw [isExecutor_storage ext poolId maker executor r s]
  intro h
  cases h

end Refinement.Swarm.AsyncSwapIsExecutor
end AsyncSwap
