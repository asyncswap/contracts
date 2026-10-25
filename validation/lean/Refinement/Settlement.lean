import Generated.AsyncSwap
import Refinement.Monad
open FormalAst Refinement
namespace AsyncSwap.CurrentSettlement
variable {σ : Type} (ext : Ext σ)
/-- Generated matching delegates each credit to the explicit shared-memory adapter.
The generator leaves this helper opaque: this is not a proof of batch-memory refinement. -/
theorem transfer_run (manager currency recipient amount : Nat) (batch : ClaimTransfers.Batch)
    (env : Env) (w : σ) :
    AsyncMatching.«_transferEscrow» ext manager currency recipient amount batch env w =
    ext.fn_ClaimTransfers_credit_14389 batch manager currency recipient amount env w := by
  simp only [AsyncMatching.«_transferEscrow», run_bind, run_pure]
  cases h : ext.fn_ClaimTransfers_credit_14389 batch manager currency recipient amount env w with
  | error e => rfl
  | ok result => rcases result with ⟨⟨⟩, w'⟩; rfl

/-- The best-price lookup supplies the exact subtree extremum to the eligibility search.
The opaque helpers retain their explicit correctness obligations. -/
theorem best_exact (bg : M σ AsyncFiller.Book) (bs : AsyncFiller.Book → M σ Unit)
    (buy : Bool) (price : Nat) :
    AsyncFiller.bestAtPrice ext bg bs buy price = (do
      let bound ← ext.fn_AsyncFiller_mostPermissiveAtPrice_6913 (do return (← bg)) (fun x => do bs x) buy price
      let rank ← ext.fn_AsyncFiller_eligibleAtPrice_6878 (do return (← bg)) (fun x => do bs x) buy price bound
      return rank) := by rfl
end AsyncSwap.CurrentSettlement
