import Generated.AsyncSwap
import Refinement.Monad

/-!
# `AsyncSwap.asyncOrder`

`function asyncOrder(PoolId poolId, bytes32 orderId) external view returns (uint256 amountIn)`
(src/AsyncSwap.sol:224): no guards, never reverts, reads only `asyncOrders`, writes nothing,
makes no external calls, and returns `asyncOrders[poolId].orders[orderId].amountIn`.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm

variable {σ : Type} (ext : Ext σ)

/-- Full characterization: in any environment and world, `asyncOrder` succeeds, leaves the
world untouched, and returns the stored `amountIn` of the order. -/
theorem asyncOrder_run (poolId orderId : Nat) (env : Env) (w : σ) :
    AsyncSwap.asyncOrder ext poolId orderId env w
      = .ok ((((ext.get w).asyncOrders poolId).orders orderId).amountIn, w) := rfl

/-- It never reverts. -/
theorem asyncOrder_never_reverts (poolId orderId : Nat) (env : Env) (w : σ) :
    ¬ ∃ e, AsyncSwap.asyncOrder ext poolId orderId env w = .error e := by
  rw [asyncOrder_run]; simp

/-- Success characterization: the result is the stored `amountIn` and the world is unchanged
(empty footprint). -/
theorem asyncOrder_ok_iff (poolId orderId : Nat) (env : Env) (w w' : σ) (a : Nat) :
    AsyncSwap.asyncOrder ext poolId orderId env w = .ok (a, w') ↔
      a = (((ext.get w).asyncOrders poolId).orders orderId).amountIn ∧ w' = w := by
  rw [asyncOrder_run]
  constructor
  · intro h; cases h; exact ⟨rfl, rfl⟩
  · rintro ⟨rfl, rfl⟩; rfl

/-- The result depends only on `asyncOrders` (read footprint): two worlds that agree on
`asyncOrders` give the same answer. -/
theorem asyncOrder_reads_only_asyncOrders (poolId orderId : Nat) (env env' : Env) (w₁ w₂ : σ)
    (h : (ext.get w₁).asyncOrders = (ext.get w₂).asyncOrders) :
    (AsyncSwap.asyncOrder ext poolId orderId env w₁).map Prod.fst
      = (AsyncSwap.asyncOrder ext poolId orderId env' w₂).map Prod.fst := by
  rw [asyncOrder_run, asyncOrder_run, h]; rfl

end AsyncSwap.Swarm
