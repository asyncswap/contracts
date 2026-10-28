import Specs.AsyncSwap
import Proofs.Monad

open FormalAst Refinement

namespace Refinement.Swarm.AsyncSwapTradeFee

theorem tradeFee_eq {σ : Type} (ext : Ext σ) (amount : Nat) :
    AsyncFiller.tradeFee ext amount =
      (do
        let fee ← mulDivRnd amount AsyncFiller.TRADE_FEE_BPS 10000 1
        pure fee) := by
  rfl

theorem tradeFee_success {σ : Type} (ext : Ext σ) (amount : Nat)
    (env : Env) (s s' : σ) (fee : Nat)
    (h : AsyncFiller.tradeFee ext amount env s = .ok (fee, s')) :
    mulDivRnd amount AsyncFiller.TRADE_FEE_BPS 10000 1 env s = .ok (fee, s') := by
  simpa [AsyncFiller.tradeFee] using h

theorem tradeFee_footprint {σ : Type} (ext : Ext σ) (amount : Nat)
    (env : Env) (s s' : σ) (fee : Nat)
    (h : AsyncFiller.tradeFee ext amount env s = .ok (fee, s')) :
    s' = s := by
  simp [AsyncFiller.tradeFee, mulDivRnd, mulDivCeil, mulDivFloor,
    addc] at h ⊢
  split at h <;> simp_all

end Refinement.Swarm.AsyncSwapTradeFee
