import Specs.AsyncSwap
import Proofs.Monad
open FormalAst Refinement

namespace AsyncSwap
variable {σ : Type} (ext : Ext σ)

def setExecutorPost (poolId executor : Nat) (allow : Bool) (r : Env) (s : σ) : σ :=
  ext.set s { ext.get s with
    asyncOrders := upd (ext.get s).asyncOrders poolId
      { (ext.get s).asyncOrders poolId with
        isExecutor := upd ((ext.get s).asyncOrders poolId).isExecutor r.sender
          (upd (((ext.get s).asyncOrders poolId).isExecutor r.sender) executor allow) } }

theorem setExecutor_run (poolId executor : Nat) (allow : Bool) (r : Env) (s : σ) :
    AsyncSwap.setExecutor ext poolId executor allow r s =
      .ok ((), setExecutorPost ext poolId executor allow r s) := by
  unfold AsyncSwap.setExecutor setExecutorPost
  simp

theorem setExecutor_ok_iff (poolId executor : Nat) (allow : Bool) (r : Env)
    (s s' : σ) (u : Unit) :
    AsyncSwap.setExecutor ext poolId executor allow r s = .ok (u, s') ↔
      u = () ∧ s' = setExecutorPost ext poolId executor allow r s := by
  rw [setExecutor_run]
  constructor
  · intro h
    cases h
    exact ⟨rfl, rfl⟩
  · rintro ⟨rfl, rfl⟩
    rfl

theorem setExecutor_frame (poolId executor : Nat) (allow : Bool) (r : Env)
    (s s' : σ) (u : Unit)
    (hget : ∀ w st, ext.get (ext.set w st) = st)
    (hok : AsyncSwap.setExecutor ext poolId executor allow r s = .ok (u, s')) :
    ext.get s' = { ext.get s with
      asyncOrders := upd (ext.get s).asyncOrders poolId
        { (ext.get s).asyncOrders poolId with
          isExecutor := upd ((ext.get s).asyncOrders poolId).isExecutor r.sender
            (upd (((ext.get s).asyncOrders poolId).isExecutor r.sender) executor allow) } } ∧
      (((ext.get s').asyncOrders poolId).isExecutor r.sender) executor = allow := by
  obtain ⟨_, rfl⟩ := (setExecutor_ok_iff ext poolId executor allow r s s' u).1 hok
  simp [setExecutorPost, hget, upd_same]

end AsyncSwap
