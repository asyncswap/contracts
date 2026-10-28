import Specs.AsyncSwap
import Proofs.Monad
open FormalAst Refinement
namespace AsyncSwap.CurrentFees
variable {σ : Type} (ext : Ext σ)
/-- Non-batched fees transfer existing claims directly to FeeVault, independently of LP liquidity.
The external transfer and its possible failure remain explicit. -/
theorem route (sg : M σ AsyncFiller.State_) (ss : AsyncFiller.State_ → M σ Unit)
    (key : PoolKey) (id maker amount hook : Nat) :
    AsyncFiller.settlePriorityFee ext sg ss key id maker amount hook = (do
      if amount == 0 then return ()
      let p ← sg
      let v ← sg
      let n ← sg
      let token ← CurrencyLibrary.toId ext n.numeraire
      let _ ← ext.call_IERC6909Claims_transfer p.poolManager v.feeVault token amount
      return ()) := by rfl
end AsyncSwap.CurrentFees
