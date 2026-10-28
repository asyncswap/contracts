import Specs.TokenClaims
import Proofs.Monad
open FormalAst Refinement
namespace TokenClaims.Current
variable {σ : Type} (ext : Ext σ)
theorem callback_authorized (data : List Nat) (env : Env) (w : σ)
    (h : env.sender ≠ ext.poolManager) :
    TokenClaims.unlockCallback ext data env w = .error ⟨"OnlyPoolManager"⟩ := by
  simp [TokenClaims.unlockCallback, run_bind, run_read, run_throw, h]
end TokenClaims.Current
