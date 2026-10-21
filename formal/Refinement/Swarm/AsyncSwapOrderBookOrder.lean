import Generated.AsyncSwap
import Refinement.Monad

/-!
# `AsyncSwap.orderBookOrder`

`function orderBookOrder(PoolId poolId, bytes32 orderId) external view returns (...)`
(src/AsyncSwap.sol:289).

* **Guards**: none — it never reverts (`orderBookOrder_never_reverts`).
* **Footprint**: writes nothing — the state is returned unchanged.
* **Return**: the seven fields `owner, amountIn, amountOutMin, price, isBuy, previous, next` of
  `asyncOrders[poolId].orders[orderId]` (`orderBookOrder_run`), so the answer depends only on that
  record (`orderBookOrder_congr`).
-/

open FormalAst

namespace AsyncSwap.Swarm.OrderBookOrder

variable {σ : Type}

/-- **Return + footprint.** Always succeeds, returns the fields of
`asyncOrders[poolId].orders[orderId]`, and leaves the world unchanged. -/
theorem orderBookOrder_run (ext : Ext σ) (pid oid : Nat) (env : Env) (w : σ) :
    AsyncSwap.orderBookOrder ext pid oid env w =
      .ok ((let o := ((ext.get w).asyncOrders pid).orders oid
            (o.owner, o.amountIn, o.amountOutMin, o.price, o.isBuy, o.previous, o.next)), w) := by
  rfl

/-- **Guards.** It never reverts. -/
theorem orderBookOrder_never_reverts (ext : Ext σ) (pid oid : Nat) (env : Env) (w : σ)
    (e : Revert) : AsyncSwap.orderBookOrder ext pid oid env w ≠ .error e := by
  rw [orderBookOrder_run]; intro h; cases h

/-- **Footprint.** No storage is written. -/
theorem orderBookOrder_readOnly (ext : Ext σ) (pid oid : Nat) (env : Env) (w w' : σ)
    (r : Nat × Nat × Nat × Nat × Bool × Nat × Nat)
    (h : AsyncSwap.orderBookOrder ext pid oid env w = .ok (r, w')) : w' = w := by
  rw [orderBookOrder_run] at h
  cases h; rfl

/-- The answer depends only on the order record `asyncOrders[poolId].orders[orderId]`. -/
theorem orderBookOrder_congr (ext : Ext σ) (pid oid : Nat) (env env' : Env) (w v : σ)
    (hb : ((ext.get w).asyncOrders pid).orders oid = ((ext.get v).asyncOrders pid).orders oid) :
    (AsyncSwap.orderBookOrder ext pid oid env w).map Prod.fst =
      (AsyncSwap.orderBookOrder ext pid oid env' v).map Prod.fst := by
  rw [orderBookOrder_run, orderBookOrder_run]
  simp only [hb]
  rfl

end AsyncSwap.Swarm.OrderBookOrder
