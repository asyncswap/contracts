import Generated.AsyncSwap
open FormalAst

/-!
# `AsyncFiller.exactPrice` (src/AsyncSwap.sol)

No guards, empty write footprint, no external calls. Given a storage reference that only
reads (`order_get r s = ok (o, s)`), the call succeeds, leaves the state unchanged and returns
the limit price of the order as a ratio: `amountIn / amountOutMin` for a buy,
`amountOutMin / amountIn` for a sell. It reverts only when the storage read itself reverts,
and it never calls `order_set`.
-/

namespace AsyncSwap
namespace Swarm.ExactPrice
variable {σ : Type}

/-- The ratio `exactPrice` returns for an order. -/
def ratioOf (o : AsyncFiller.OrderInfo) : EligiblePrice.Ratio :=
  if o.isBuy then { numerator := o.amountIn, denominator := o.amountOutMin }
  else { numerator := o.amountOutMin, denominator := o.amountIn }

/-- With a read-only getter, `AsyncFiller.exactPrice` succeeds, leaves the state unchanged,
and returns `amountIn/amountOutMin` for a buy and `amountOutMin/amountIn` for a sell. -/
theorem exactPrice_of_read (ext : Ext σ) (order_get : M σ AsyncFiller.OrderInfo)
    (order_set : AsyncFiller.OrderInfo → M σ Unit) (r : Env) (s : σ)
    (o : AsyncFiller.OrderInfo) (hget : order_get r s = .ok (o, s)) :
    AsyncFiller.exactPrice ext order_get order_set r s = .ok (ratioOf o, s) := by
  unfold AsyncFiller.exactPrice ratioOf
  cases hb : o.isBuy <;>
    simp [bind, ReaderT.bind, StateT.bind, Except.bind, pure, ReaderT.pure, StateT.pure,
      Except.pure, hget, hb]

/-- Buy orders: the price is `amountIn / amountOutMin`. -/
theorem exactPrice_buy (ext : Ext σ) (order_get : M σ AsyncFiller.OrderInfo)
    (order_set : AsyncFiller.OrderInfo → M σ Unit) (r : Env) (s : σ)
    (o : AsyncFiller.OrderInfo) (hget : order_get r s = .ok (o, s)) (hb : o.isBuy = true) :
    AsyncFiller.exactPrice ext order_get order_set r s =
      .ok ({ numerator := o.amountIn, denominator := o.amountOutMin }, s) := by
  rw [exactPrice_of_read ext order_get order_set r s o hget]; simp [ratioOf, hb]

/-- Sell orders: the price is `amountOutMin / amountIn`. -/
theorem exactPrice_sell (ext : Ext σ) (order_get : M σ AsyncFiller.OrderInfo)
    (order_set : AsyncFiller.OrderInfo → M σ Unit) (r : Env) (s : σ)
    (o : AsyncFiller.OrderInfo) (hget : order_get r s = .ok (o, s)) (hb : o.isBuy = false) :
    AsyncFiller.exactPrice ext order_get order_set r s =
      .ok ({ numerator := o.amountOutMin, denominator := o.amountIn }, s) := by
  rw [exactPrice_of_read ext order_get order_set r s o hget]; simp [ratioOf, hb]

/-- No guard of its own: `AsyncFiller.exactPrice` reverts only if the first storage read does. -/
theorem exactPrice_error (ext : Ext σ) (order_get : M σ AsyncFiller.OrderInfo)
    (order_set : AsyncFiller.OrderInfo → M σ Unit) (r : Env) (s : σ) (e : Revert)
    (hget : order_get r s = .error e) :
    AsyncFiller.exactPrice ext order_get order_set r s = .error e := by
  unfold AsyncFiller.exactPrice
  simp [bind, ReaderT.bind, StateT.bind, Except.bind, hget]

/-- `AsyncFiller.exactPrice` never writes: its result does not depend on `order_set`. -/
theorem exactPrice_order_set_irrelevant (ext : Ext σ) (order_get : M σ AsyncFiller.OrderInfo)
    (f g : AsyncFiller.OrderInfo → M σ Unit) :
    AsyncFiller.exactPrice ext order_get f = AsyncFiller.exactPrice ext order_get g := rfl

end Swarm.ExactPrice
end AsyncSwap
