import Generated.AsyncSwap
import Refinement.Monad

/-!
# `AsyncFiller.settleOrderPriorityFee`

`function settleOrderPriorityFee(State storage self, PoolKey memory key, bytes32 id, address hook)
internal` (src/AsyncSwap.sol, library `AsyncFiller`): no guards of its own, no writes of its own,
no external calls of its own. It reads `self.orders[id]` and hands
`settlePriorityFee(self, key, id, info.owner, paidPriorityFee(info), hook)` everything; any revert,
write or external call comes from `settlePriorityFee`.

`self` is a storage pointer, passed as a getter/setter pair. The theorems assume the getter is a
pure read of the world (`self_get env w = .ok (g w, w)`), which is how every caller instantiates it
(`asyncOrders[poolId]`).
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.SettleOrderPriorityFee

variable {σ : Type} (ext : Ext σ)

/-- The fee `paidPriorityFee` reports for an order: the escrowed bid, or 0. -/
def paidFee (info : AsyncFiller.OrderInfo) : Nat :=
  if info.priorityFeeEscrowed then info.priorityFee else 0

/-- Full characterization: `settleOrderPriorityFee` behaves exactly as
`settlePriorityFee` called on the same storage with `maker = self.orders[id].owner` and
`amount = paidPriorityFee(self.orders[id])` (read from the world at entry). It adds no guard,
no write and no external call of its own. -/
theorem settleOrderPriorityFee_run (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (g : σ → AsyncFiller.State_)
    (hget : ∀ env w, self_get env w = .ok (g w, w))
    (key : PoolKey) (id hook : Nat) (env : Env) (w : σ) :
    AsyncFiller.settleOrderPriorityFee ext self_get self_set key id hook env w =
      AsyncFiller.settlePriorityFee ext (do return (← self_get)) (fun x => do self_set x) key id
        ((g w).orders id).owner (paidFee ((g w).orders id)) hook env w := by
  unfold AsyncFiller.settleOrderPriorityFee AsyncFiller.paidPriorityFee paidFee
  simp only [bind_pure_unit, run_bind, hget, run_pure]
  cases h : ((g w).orders id).priorityFeeEscrowed <;> simp [h, hget]

/-- Without an escrowed bid (`paidPriorityFee = 0`) it is a no-op: it succeeds and leaves the
world unchanged. -/
theorem settleOrderPriorityFee_not_escrowed (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (g : σ → AsyncFiller.State_)
    (hget : ∀ env w, self_get env w = .ok (g w, w))
    (key : PoolKey) (id hook : Nat) (env : Env) (w : σ)
    (h : ((g w).orders id).priorityFeeEscrowed = false) :
    AsyncFiller.settleOrderPriorityFee ext self_get self_set key id hook env w = .ok ((), w) := by
  rw [settleOrderPriorityFee_run ext self_get self_set g hget]
  simp [paidFee, h, AsyncFiller.settlePriorityFee]

/-- A zero escrowed bid is also a no-op. -/
theorem settleOrderPriorityFee_zero_fee (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (g : σ → AsyncFiller.State_)
    (hget : ∀ env w, self_get env w = .ok (g w, w))
    (key : PoolKey) (id hook : Nat) (env : Env) (w : σ)
    (h : ((g w).orders id).priorityFee = 0) :
    AsyncFiller.settleOrderPriorityFee ext self_get self_set key id hook env w = .ok ((), w) := by
  rw [settleOrderPriorityFee_run ext self_get self_set g hget]
  have : paidFee ((g w).orders id) = 0 := by unfold paidFee; split <;> simp_all
  rw [this]
  simp [AsyncFiller.settlePriorityFee]

/-- With an escrowed bid, it settles exactly `self.orders[id].priorityFee` on behalf of the
order's owner. -/
theorem settleOrderPriorityFee_escrowed (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (g : σ → AsyncFiller.State_)
    (hget : ∀ env w, self_get env w = .ok (g w, w))
    (key : PoolKey) (id hook : Nat) (env : Env) (w : σ)
    (h : ((g w).orders id).priorityFeeEscrowed = true) :
    AsyncFiller.settleOrderPriorityFee ext self_get self_set key id hook env w =
      AsyncFiller.settlePriorityFee ext (do return (← self_get)) (fun x => do self_set x) key id
        ((g w).orders id).owner ((g w).orders id).priorityFee hook env w := by
  rw [settleOrderPriorityFee_run ext self_get self_set g hget]
  simp [paidFee, h]

end AsyncSwap.Swarm.SettleOrderPriorityFee
