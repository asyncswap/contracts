import Generated.AsyncSwap
import Refinement.Monad
open FormalAst Refinement
namespace AsyncSwap.CurrentSettlement
variable {σ : Type} (ext : Ext σ)
/-- Book settlement burns escrow and credits the recipient in the same currency and amount.
No underlying token transfer occurs in this generated path. External failure remains explicit. -/
theorem transfer_run (manager currency recipient amount hook : Nat) (env : Env) (w : σ) :
    AsyncMatching.«_transferEscrow» ext manager currency recipient amount hook env w =
    (match ext.call_IPoolManager_burn manager hook currency amount env w with
    | .error e => .error e
    | .ok (_, w1) =>
      match ext.call_IPoolManager_mint manager recipient currency amount env w1 with
      | .error e => .error e
      | .ok (_, w2) => .ok ((), w2)) := by
  simp only [AsyncMatching.«_transferEscrow», CurrencySettler.settle, CurrencySettler.take,
    CurrencyLibrary.toId, run_bind, run_pure, ite_true]
  cases hb : ext.call_IPoolManager_burn manager hook currency amount env w with
  | error e => rfl
  | ok v =>
    rcases v with ⟨u, w1⟩
    cases hm : ext.call_IPoolManager_mint manager recipient currency amount env w1 with
    | error e => simp [hm]
    | ok v => rcases v with ⟨u2, w2⟩; simp [hm]

/-- The best-price lookup supplies the exact subtree extremum to the eligibility search.
The opaque helpers retain their explicit correctness obligations. -/
theorem best_exact (bg : M σ AsyncFiller.Book) (bs : AsyncFiller.Book → M σ Unit)
    (buy : Bool) (price : Nat) :
    AsyncFiller.bestAtPrice ext bg bs buy price = (do
      let bound ← ext.fn_AsyncFiller_mostPermissiveAtPrice_6924 (do return (← bg)) (fun x => do bs x) buy price
      let rank ← ext.fn_AsyncFiller_eligibleAtPrice_6889 (do return (← bg)) (fun x => do bs x) buy price bound
      return rank) := by rfl
end AsyncSwap.CurrentSettlement
