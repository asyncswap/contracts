import Generated.AsyncSwap
import Refinement.Monad
open FormalAst Refinement

/-!
# `AsyncMatching._payouts` (src/AsyncSwap.sol)

`_payouts(key, buyId, sellId)` is a view: it reads `orders[sellId]` and `orders[buyId]` (four reads of
`self_get`) and builds a `Payouts` record with
* `sellInput = orders[sellId].zeroForOne ? key.currency0 : key.currency1`,
* `buyInput  = orders[buyId].zeroForOne  ? key.currency0 : key.currency1`,
* `sellOwner = orders[sellId].owner`, `buyOwner = orders[buyId].owner`,
* `sellRefund = buyRefund = 0` (left at their default).

It has no guard and no external call; it never calls `self_set`, so it writes no storage.
-/

namespace AsyncSwap.Swarm.Payouts

variable {σ : Type}

/-- The input currency of an order: `currency0` when it sells token0 (`zeroForOne`), else `currency1`. -/
def inputCurrency (key : PoolKey) (o : AsyncFiller.OrderInfo) : Nat :=
  if o.zeroForOne then key.currency0 else key.currency1

/-- **Exact outcome.** When the order-map read is pure at `(r, s)` and yields `st`, `_payouts`
succeeds, leaves the state `s` unchanged (no storage write) and returns the owners and input
currencies of the two orders, with both refunds `0`. -/
theorem payouts_run (ext : Ext σ) (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (key : PoolKey) (buyId sellId : Nat)
    (r : Env) (s : σ) (st : AsyncFiller.State_) (hsg : self_get r s = .ok (st, s)) :
    AsyncMatching.«_payouts» ext self_get self_set key buyId sellId r s
      = .ok ({ sellOwner := (st.orders sellId).owner
               buyOwner := (st.orders buyId).owner
               sellInput := inputCurrency key (st.orders sellId)
               buyInput := inputCurrency key (st.orders buyId)
               sellRefund := 0
               buyRefund := 0 }, s) := by
  unfold AsyncMatching.«_payouts»
  simp only [run_bind, hsg, run_pure]
  rfl

/-- **Reverts only through the read.** If reading the order map reverts with `e`, so does
`_payouts`, with the same error; `_payouts` raises no revert of its own. -/
theorem payouts_error (ext : Ext σ) (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (key : PoolKey) (buyId sellId : Nat)
    (r : Env) (s : σ) (e : Revert) (hsg : self_get r s = .error e) :
    AsyncMatching.«_payouts» ext self_get self_set key buyId sellId r s = .error e := by
  unfold AsyncMatching.«_payouts»
  simp only [run_bind, hsg]

/-- **No revert of its own.** If the read is pure at `(r, s)`, `_payouts` never reverts there. -/
theorem payouts_no_revert (ext : Ext σ) (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (key : PoolKey) (buyId sellId : Nat)
    (r : Env) (s : σ) (st : AsyncFiller.State_) (hsg : self_get r s = .ok (st, s)) (e : Revert) :
    AsyncMatching.«_payouts» ext self_get self_set key buyId sellId r s ≠ .error e := by
  rw [payouts_run ext self_get self_set key buyId sellId r s st hsg]
  simp

/-- **Footprint: no writes.** `_payouts` does not depend on the setter `self_set`: it never
writes the order map. -/
theorem payouts_self_set_irrelevant (ext : Ext σ) (self_get : M σ AsyncFiller.State_)
    (self_set self_set' : AsyncFiller.State_ → M σ Unit) (key : PoolKey) (buyId sellId : Nat) :
    AsyncMatching.«_payouts» ext self_get self_set key buyId sellId
      = AsyncMatching.«_payouts» ext self_get self_set' key buyId sellId := rfl

end AsyncSwap.Swarm.Payouts
