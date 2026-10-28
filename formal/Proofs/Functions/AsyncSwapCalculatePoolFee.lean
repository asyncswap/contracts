import Specs.AsyncSwap
import Proofs.Monad

open FormalAst Refinement

namespace AsyncSwap
namespace Refinement.Swarm.AsyncSwapCalculatePoolFee

/-- The pure fee calculation always succeeds, returns zero, and preserves storage. -/
theorem calculatePoolFee_success {σ : Type} (ext : Ext σ)
    (arg0 arg1 : Nat) (env : Env) (s : σ) :
    AsyncSwap.calculatePoolFee ext arg0 arg1 env s = .ok (0, s) := by
  simp [AsyncSwap.calculatePoolFee, bind, ReaderT.bind, StateT.bind,
    Except.bind, pure, ReaderT.pure, StateT.pure, Except.pure]

end Refinement.Swarm.AsyncSwapCalculatePoolFee
end AsyncSwap
