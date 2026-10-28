import Generated.AsyncSwap
import Refinement.Monad
open FormalAst Refinement

namespace AsyncSwap.CloseOrder
variable {σ : Type} (ext : Ext σ)

/-- Normal form of `_closeOrder`: read the order's fee and owner, remove the order from the book
(`AsyncFiller._remove`), zero `orders[id]`, then (only if the fee read before deletion is nonzero)
forfeit it to the fee vault with one `IERC6909Claims.transfer`. No guard of its own. -/
theorem closeOrder_eq (sg : M σ AsyncFiller.State_) (ss : AsyncFiller.State_ → M σ Unit)
    (bg : M σ AsyncFiller.Book) (bs : AsyncFiller.Book → M σ Unit)
    (key : PoolKey) (id hook : Nat) :
    AsyncFiller.«_closeOrder» ext sg ss bg bs key id hook = (do
      let t1 ← sg
      let _ ← sg
      AsyncFiller.«_remove» ext (do return (← sg)) (fun x => do ss (x))
        (do return (← bg)) (fun x => do bs (x)) id
      let t3 ← sg
      ss ({ t3 with orders := upd (t3.orders) id (default) })
      if ((t1.orders id).priorityFee == 0) then return ()
      let p ← sg
      let v ← sg
      let n ← sg
      let _ ← ext.call_IERC6909Claims_transfer p.poolManager v.feeVault n.numeraire
        (t1.orders id).priorityFee
      return ()) := by
  simp only [AsyncFiller.«_closeOrder», AsyncFiller.settlePriorityFee, CurrencyLibrary.toId,
    pure_bind]
  congr 1; funext t1; congr 1; funext _; congr 1; funext _; congr 1; funext t3; congr 1; funext _
  split <;> simp

/-- Run-level specification of `_closeOrder`, for storage accessors that read and write a state
component without failing. It reverts exactly when `_remove` or the fee transfer reverts; on
success it writes `orders[id] := default` on top of `_remove`'s effects, and makes the transfer
(poolManager, feeVault, numeraire, priorityFee-before-deletion) iff that fee is nonzero. -/
theorem closeOrder_run (view : σ → AsyncFiller.State_) (put : AsyncFiller.State_ → σ → σ)
    (sg : M σ AsyncFiller.State_) (ss : AsyncFiller.State_ → M σ Unit)
    (bg : M σ AsyncFiller.Book) (bs : AsyncFiller.Book → M σ Unit)
    (hg : ∀ r s, sg r s = .ok (view s, s)) (hs : ∀ x r s, ss x r s = .ok ((), put x s))
    (key : PoolKey) (id hook : Nat) (r : Env) (s : σ) :
    AsyncFiller.«_closeOrder» ext sg ss bg bs key id hook r s =
      (match AsyncFiller.«_remove» ext (do return (← sg)) (fun x => do ss (x))
          (do return (← bg)) (fun x => do bs (x)) id r s with
       | .error e => .error e
       | .ok (_, s₁) =>
         let s₂ := put { view s₁ with orders := upd ((view s₁).orders) id (default) } s₁
         if ((view s).orders id).priorityFee = 0 then .ok ((), s₂)
         else
           match ext.call_IERC6909Claims_transfer (view s₂).poolManager (view s₂).feeVault
               (view s₂).numeraire ((view s).orders id).priorityFee r s₂ with
           | .error e => .error e
           | .ok (_, s₃) => .ok ((), s₃)) := by
  rw [closeOrder_eq]
  simp only [run_bind, hg, hs]
  cases AsyncFiller.«_remove» ext sg (fun x => ss x) bg (fun x => bs x) id r s with
  | error e => rfl
  | ok p =>
    obtain ⟨_, s₁⟩ := p
    by_cases h0 : ((view s).orders id).priorityFee = 0
    · simp [h0]
    · simp only [h0, beq_iff_eq, ite_false, run_bind, hg]
      generalize ext.call_IERC6909Claims_transfer _ _ _ _ r _ = T
      cases T <;> rfl

end AsyncSwap.CloseOrder
