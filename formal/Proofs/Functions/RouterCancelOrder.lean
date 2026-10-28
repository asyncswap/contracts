import Specs.Router
import Proofs.Monad

open FormalAst Refinement

namespace Router.Swarm.RouterCancelOrder

variable {σ : Type}

theorem cancelOrder_run (ext : Ext σ) (order : AsyncOrder) (env : Env) (s : σ) :
    Router.cancelOrder ext order env s =
      if !(env.sender == order.owner) then
        .error ⟨"Only owner can cancel"⟩
      else
        let s₁ := ext.set s (let st := ext.get s;
          { st with «transient» := upd st.«transient» Router.USER_LOCATION env.sender })
        match ext.call_IPoolManager_unlock ext.POOLMANAGER
          (abiEncode [2, order.key.currency0, order.key.currency1, order.key.fee,
            toUnsigned 256 order.key.tickSpacing, order.key.hooks, order.owner,
            ybool order.zeroForOne, order.amountIn, order.amountOutMin,
            order.priorityFee, order.sqrtPrice, order.salt, 0]) env s₁ with
        | .error r => .error r
        | .ok (_, s₂) => .ok ((), s₂) := by
  by_cases h : env.sender = order.owner
  · simp only [Router.cancelOrder, Refinement.run_bind, Refinement.run_read,
      Refinement.run_ite, h, Bool.not_true, ↓reduceIte]
    generalize hc : ext.call_IPoolManager_unlock ext.POOLMANAGER
      (abiEncode [2, order.key.currency0, order.key.currency1, order.key.fee,
        toUnsigned 256 order.key.tickSpacing, order.key.hooks, order.owner,
        ybool order.zeroForOne, order.amountIn, order.amountOutMin,
        order.priorityFee, order.sqrtPrice, order.salt, 0]) env
      (ext.set s (let st := ext.get s;
        { st with «transient» := upd st.«transient» Router.USER_LOCATION env.sender })) = r
    rw [← h] at hc ⊢
    cases r <;> simp [hc]
  · simp [Router.cancelOrder, h]

end Router.Swarm.RouterCancelOrder
