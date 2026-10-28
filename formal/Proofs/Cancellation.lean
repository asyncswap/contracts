import Specs.Router
import Proofs.Monad
open FormalAst Refinement
namespace Router.Current
variable {σ : Type} (ext : Ext σ)
theorem expired_cancel (order : AsyncOrder) (nonce deadline : Nat) (sig : List Nat)
    (env : Env) (w : σ) (h : env.timestamp > deadline) :
    Router.cancelWithSig ext order nonce deadline sig env w = .error ⟨"SignatureExpired"⟩ := by
  simp [Router.cancelWithSig, run_bind, run_read, run_throw, h]
end Router.Current
