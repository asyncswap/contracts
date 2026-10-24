import Generated.AsyncSwap
import Refinement.Monad
open FormalAst Refinement
namespace AsyncSwap.CurrentFees
variable {σ : Type} (ext : Ext σ)
/-- Exact generated fee routing. The recipient is FeeVault regardless of LP liquidity.
Reads after the burn remain reads of the resulting world; no external purity is assumed. -/
theorem route (sg : M σ AsyncFiller.State_) (ss : AsyncFiller.State_ → M σ Unit)
    (key : PoolKey) (id maker amount hook : Nat) :
    AsyncFiller.settlePriorityFee ext sg ss key id maker amount hook = (do
      if amount == 0 then return ()
      let n ← sg
      let p ← sg
      CurrencySettler.settle ext n.numeraire p.poolManager hook amount true
      let n ← sg
      let p ← sg
      let v ← sg
      CurrencySettler.take ext n.numeraire p.poolManager v.feeVault amount true
      return ()) := by rfl
end AsyncSwap.CurrentFees
