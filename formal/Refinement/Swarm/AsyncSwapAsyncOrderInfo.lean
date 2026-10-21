import Generated.AsyncSwap
import Refinement.Monad

/-!
# `AsyncSwap.asyncOrderInfo`

`function asyncOrderInfo(PoolId poolId, bytes32 orderId) external view
  returns (uint256 amountIn, uint256 amountOutMin)` (src/AsyncSwap.sol:229): no guards, never
reverts, reads only `asyncOrders`, writes nothing, makes no external calls, and returns
`(asyncOrders[poolId].orders[orderId].amountIn, asyncOrders[poolId].orders[orderId].amountOutMin)`.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm

variable {σ : Type} (ext : Ext σ)

/-- Full characterization: in any environment and world, `asyncOrderInfo` succeeds, leaves the
world untouched, and returns the stored `amountIn` and `amountOutMin` of the order. -/
theorem asyncOrderInfo_run (poolId orderId : Nat) (env : Env) (w : σ) :
    AsyncSwap.asyncOrderInfo ext poolId orderId env w
      = .ok (((((ext.get w).asyncOrders poolId).orders orderId).amountIn,
              (((ext.get w).asyncOrders poolId).orders orderId).amountOutMin), w) := rfl

/-- It never reverts (no guards). -/
theorem asyncOrderInfo_never_reverts (poolId orderId : Nat) (env : Env) (w : σ) :
    ¬ ∃ e, AsyncSwap.asyncOrderInfo ext poolId orderId env w = .error e := by
  rw [asyncOrderInfo_run]; simp

/-- Success characterization: the result is the stored pair and the world is unchanged
(empty write footprint). -/
theorem asyncOrderInfo_ok_iff (poolId orderId : Nat) (env : Env) (w w' : σ) (a b : Nat) :
    AsyncSwap.asyncOrderInfo ext poolId orderId env w = .ok ((a, b), w') ↔
      a = (((ext.get w).asyncOrders poolId).orders orderId).amountIn ∧
      b = (((ext.get w).asyncOrders poolId).orders orderId).amountOutMin ∧ w' = w := by
  rw [asyncOrderInfo_run]
  constructor
  · intro h; cases h; exact ⟨rfl, rfl, rfl⟩
  · rintro ⟨rfl, rfl, rfl⟩; rfl

/-- The result depends only on `asyncOrders` (read footprint), not on the environment or any
other storage. -/
theorem asyncOrderInfo_reads_only_asyncOrders (poolId orderId : Nat) (env env' : Env) (w₁ w₂ : σ)
    (h : (ext.get w₁).asyncOrders = (ext.get w₂).asyncOrders) :
    (AsyncSwap.asyncOrderInfo ext poolId orderId env w₁).map Prod.fst
      = (AsyncSwap.asyncOrderInfo ext poolId orderId env' w₂).map Prod.fst := by
  rw [asyncOrderInfo_run, asyncOrderInfo_run, h]; rfl

end AsyncSwap.Swarm
