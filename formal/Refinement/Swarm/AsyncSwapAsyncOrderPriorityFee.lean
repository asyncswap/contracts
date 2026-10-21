import Generated.AsyncSwap
import Refinement.Monad

/-!
# `AsyncSwap.asyncOrderPriorityFee`

`function asyncOrderPriorityFee(PoolId poolId, bytes32 orderId) external view returns (uint256)`
(src/AsyncSwap.sol:239): no guards, never reverts, reads only `asyncOrders`, writes nothing,
makes no external calls, and returns `AsyncFiller.paidPriorityFee(asyncOrders[poolId].orders[orderId])`,
i.e. `info.priorityFeeEscrowed ? info.priorityFee : 0`.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm

variable {σ : Type} (ext : Ext σ)

/-- Full characterization: in any environment and world, `asyncOrderPriorityFee` succeeds,
leaves the world untouched, and returns the escrowed priority fee (or 0 if none is escrowed). -/
theorem asyncOrderPriorityFee_run (poolId orderId : Nat) (env : Env) (w : σ) :
    AsyncSwap.asyncOrderPriorityFee ext poolId orderId env w
      = .ok ((if (((ext.get w).asyncOrders poolId).orders orderId).priorityFeeEscrowed then
                (((ext.get w).asyncOrders poolId).orders orderId).priorityFee else 0), w) := by
  unfold AsyncSwap.asyncOrderPriorityFee AsyncFiller.paidPriorityFee
  cases h : (((ext.get w).asyncOrders poolId).orders orderId).priorityFeeEscrowed <;>
    simp [h] <;> rfl

/-- It never reverts. -/
theorem asyncOrderPriorityFee_never_reverts (poolId orderId : Nat) (env : Env) (w : σ) :
    ¬ ∃ e, AsyncSwap.asyncOrderPriorityFee ext poolId orderId env w = .error e := by
  rw [asyncOrderPriorityFee_run]; simp

/-- Success characterization: the result is the paid priority fee and the world is unchanged
(empty write footprint). -/
theorem asyncOrderPriorityFee_ok_iff (poolId orderId : Nat) (env : Env) (w w' : σ) (a : Nat) :
    AsyncSwap.asyncOrderPriorityFee ext poolId orderId env w = .ok (a, w') ↔
      a = (if (((ext.get w).asyncOrders poolId).orders orderId).priorityFeeEscrowed then
              (((ext.get w).asyncOrders poolId).orders orderId).priorityFee else 0) ∧ w' = w := by
  rw [asyncOrderPriorityFee_run]
  constructor
  · intro h; cases h; exact ⟨rfl, rfl⟩
  · rintro ⟨rfl, rfl⟩; rfl

/-- Not escrowed ⇒ returns 0. -/
theorem asyncOrderPriorityFee_not_escrowed (poolId orderId : Nat) (env : Env) (w : σ)
    (h : (((ext.get w).asyncOrders poolId).orders orderId).priorityFeeEscrowed = false) :
    AsyncSwap.asyncOrderPriorityFee ext poolId orderId env w = .ok (0, w) := by
  rw [asyncOrderPriorityFee_run, h]; rfl

/-- Escrowed ⇒ returns the stored `priorityFee`. -/
theorem asyncOrderPriorityFee_escrowed (poolId orderId : Nat) (env : Env) (w : σ)
    (h : (((ext.get w).asyncOrders poolId).orders orderId).priorityFeeEscrowed = true) :
    AsyncSwap.asyncOrderPriorityFee ext poolId orderId env w
      = .ok ((((ext.get w).asyncOrders poolId).orders orderId).priorityFee, w) := by
  rw [asyncOrderPriorityFee_run, h]; rfl

/-- The result depends only on `asyncOrders` (read footprint). -/
theorem asyncOrderPriorityFee_reads_only_asyncOrders (poolId orderId : Nat) (env env' : Env)
    (w₁ w₂ : σ) (h : (ext.get w₁).asyncOrders = (ext.get w₂).asyncOrders) :
    (AsyncSwap.asyncOrderPriorityFee ext poolId orderId env w₁).map Prod.fst
      = (AsyncSwap.asyncOrderPriorityFee ext poolId orderId env' w₂).map Prod.fst := by
  rw [asyncOrderPriorityFee_run, asyncOrderPriorityFee_run, h]; rfl

end AsyncSwap.Swarm
