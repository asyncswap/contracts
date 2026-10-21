import Generated.AsyncSwap
import Refinement.Monad

/-!
# `AsyncSwap.cancelOrder`

`function cancelOrder(AsyncOrder calldata order) external` (src/AsyncSwap.sol:429), through
`AsyncMatching.cancel` → `AsyncFiller.cancel`.

With `pid = order.key.toId()`, `id = keccak(chainid, pid, owner, zeroForOne, salt)`,
`S = asyncOrders[pid]`, `info = S.orders[id]`:

* reverts `NotAuthorizedExecutor` unless `msg.sender = order.owner` or `S.isExecutor[owner][sender]`;
* reverts `OrderNotFound` when `info.amountIn = 0`;
* otherwise runs, in order: the `_remove` (opaque in the model: `RadixPriceTree`'s
  `PriceLevelMissing` guard and the `orderCount`/`openOrderCount` decrements live there) on
  `asyncOrders[pid]`/`priceBooks[pid]`; `orders[id] := default`;
  `poolManager.burn(address(this), input, info.amountIn)`; `mint` (native input) or `take` (ERC20
  input) of exactly `info.amountIn` of the input currency to `order.owner`; `settlePriorityFee`
  with the paid (escrowed) bid, `address(this)` as the hook.

For the maintainer's "fill/cancel your own order to sweep other users' funds" concern:
* the amount refunded is the *stored* `info.amountIn` read from storage before any external call,
  never a caller-supplied field (`order.amountIn` is not used);
* it goes to `order.owner` only, and `id` hashes `order.owner`, `zeroForOne` and the pool key, so
  a caller can only touch an order recorded under its own address (or one that authorised it as
  executor), in the pool and input currency it was recorded with;
* the claim burned (from the hook) equals the amount paid out, in the same currency;
* the order slot is cleared before the first external call, so cancelling the same order again
  (including re-entrantly from the burn) reverts (`cancelOrder_reentry_reverts`).
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.CancelOrder

variable {σ : Type} (ext : Ext σ)

/-- `PoolIdLibrary.toId key` in the model. -/
def poolId (key : PoolKey) : Nat :=
  ext.keccak [key.currency0, key.currency1, key.fee, toUnsigned 256 key.tickSpacing, key.hooks]

/-- `AsyncOrderLibrary.orderId order` in the model. -/
def orderId (env : Env) (order : AsyncOrder) : Nat :=
  ext.keccak [env.chainid, poolId ext order.key, order.owner, ybool order.zeroForOne, order.salt]

/-- The order's input currency. -/
def inputOf (order : AsyncOrder) : Nat :=
  if order.zeroForOne then order.key.currency0 else order.key.currency1

def selfGet (pid : Nat) : M σ AsyncFiller.State_ := do return ((ext.get (← get)).asyncOrders pid)
def selfSet (pid : Nat) : AsyncFiller.State_ → M σ Unit := fun x =>
  modify fun w => ext.set w (let s := ext.get w; { s with asyncOrders := upd (s.asyncOrders) pid x })
def bookGet (pid : Nat) : M σ AsyncFiller.Book := do return ((ext.get (← get)).priceBooks pid)
def bookSet (pid : Nat) : AsyncFiller.Book → M σ Unit := fun x =>
  modify fun w => ext.set w (let s := ext.get w; { s with priceBooks := upd (s.priceBooks) pid x })

/-- Everything `cancelOrder` does once both guards pass. -/
def tail (order : AsyncOrder) (pid id amt fee : Nat) : M σ Unit := do
  ext.fn_AsyncFiller_remove_6902 (selfGet ext pid) (selfSet ext pid) (bookGet ext pid) (bookSet ext pid) id
  let s ← selfGet ext pid
  selfSet ext pid { s with orders := upd s.orders id default }
  let s ← selfGet ext pid
  ext.call_IPoolManager_burn s.poolManager (← read).self (inputOf order) amt
  let s ← selfGet ext pid
  if inputOf order = 0 then
    ext.call_IPoolManager_mint s.poolManager order.owner (inputOf order) amt
  else
    ext.call_IPoolManager_take s.poolManager (inputOf order) order.owner amt
  AsyncFiller.settlePriorityFee ext (selfGet ext pid) (selfSet ext pid) order.key id order.owner fee
    (← read).self

/-- Full characterization of `AsyncSwap.cancelOrder`: two guards, then `tail`. -/
theorem cancelOrder_run (order : AsyncOrder) (env : Env) (w : σ) :
    AsyncSwap.cancelOrder ext order env w =
      let S := (ext.get w).asyncOrders (poolId ext order.key)
      let info := S.orders (orderId ext env order)
      if env.sender ≠ order.owner ∧ S.isExecutor order.owner env.sender = false then
        .error ⟨"NotAuthorizedExecutor"⟩
      else if info.amountIn = 0 then .error ⟨"OrderNotFound"⟩
      else tail ext order (poolId ext order.key) (orderId ext env order) info.amountIn
        (if info.priorityFeeEscrowed then info.priorityFee else 0) env w := by
  unfold tail selfGet selfSet bookGet bookSet orderId poolId inputOf
  simp only [AsyncSwap.cancelOrder, AsyncMatching.cancel, AsyncFiller.cancel, AsyncOrderLibrary.orderId,
    PoolIdLibrary.toId, AsyncFiller.paidPriorityFee, CurrencySettler.settle, CurrencySettler.take,
    CurrencyLibrary.toId, CurrencyLibrary.isAddressZero, CurrencyLibrary.ADDRESS_ZERO,
    bind_pure_unit, bind_assoc, pure_bind]
  simp only [run_bind, run_pure, run_read, run_get, run_modify, run_throw, run_ite]
  generalize ext.keccak [order.key.currency0, order.key.currency1, order.key.fee,
    toUnsigned 256 order.key.tickSpacing, order.key.hooks] = pid
  generalize ext.keccak [env.chainid, pid, order.owner, ybool order.zeroForOne, order.salt] = oid
  by_cases h1 : env.sender = order.owner <;>
  by_cases h2 : ((ext.get w).asyncOrders pid).isExecutor order.owner env.sender <;>
  by_cases h3 : (((ext.get w).asyncOrders pid).orders oid).amountIn = 0 <;>
  by_cases h4 : (((ext.get w).asyncOrders pid).orders oid).priorityFeeEscrowed <;>
  by_cases h5 : (if order.zeroForOne = true then order.key.currency0 else order.key.currency1) = 0 <;>
  simp [h1, h2, h3, h4, h5]

/-- Guard 1: a caller that is neither the order's owner nor an executor the owner authorised in
this pool reverts `NotAuthorizedExecutor` (whatever order it submits). -/
theorem cancelOrder_unauthorized (order : AsyncOrder) (env : Env) (w : σ)
    (hs : env.sender ≠ order.owner)
    (hx : ((ext.get w).asyncOrders (poolId ext order.key)).isExecutor order.owner env.sender = false) :
    AsyncSwap.cancelOrder ext order env w = .error ⟨"NotAuthorizedExecutor"⟩ := by
  rw [cancelOrder_run]; simp [hs, hx]

/-- Guard 2: an authorised caller cancelling an order with no stored input reverts `OrderNotFound`. -/
theorem cancelOrder_notFound (order : AsyncOrder) (env : Env) (w : σ)
    (ha : env.sender = order.owner ∨
      ((ext.get w).asyncOrders (poolId ext order.key)).isExecutor order.owner env.sender = true)
    (h0 : (((ext.get w).asyncOrders (poolId ext order.key)).orders (orderId ext env order)).amountIn = 0) :
    AsyncSwap.cancelOrder ext order env w = .error ⟨"OrderNotFound"⟩ := by
  rw [cancelOrder_run]
  rcases ha with ha | ha <;> simp [ha, h0]

theorem selfGet_run (pid : Nat) (env : Env) (w : σ) :
    selfGet ext pid env w = .ok ((ext.get w).asyncOrders pid, w) := rfl

theorem selfSet_run (pid : Nat) (x : AsyncFiller.State_) (env : Env) (w : σ) :
    selfSet ext pid x env w =
      .ok ((), ext.set w { ext.get w with asyncOrders := upd (ext.get w).asyncOrders pid x }) := rfl

/-- The world after `orders[id] := default` in pool `pid`. -/
def delWorld (pid id : Nat) (w : σ) : σ :=
  let S := (ext.get w).asyncOrders pid
  ext.set w { ext.get w with
    asyncOrders := upd (ext.get w).asyncOrders pid { S with orders := upd S.orders id default } }

/-- The steps of `tail`, each from the world the previous one left. -/
theorem tail_ok (order : AsyncOrder) (pid id amt fee : Nat) (env : Env) (w w' : σ)
    (h : tail ext order pid id amt fee env w = .ok ((), w')) :
    ∃ w1 w3 w4,
      ext.fn_AsyncFiller_remove_6902 (selfGet ext pid) (selfSet ext pid) (bookGet ext pid)
        (bookSet ext pid) id env w = .ok ((), w1) ∧
      ext.call_IPoolManager_burn ((ext.get (delWorld ext pid id w1)).asyncOrders pid).poolManager
        env.self (inputOf order) amt env (delWorld ext pid id w1) = .ok ((), w3) ∧
      (if inputOf order = 0 then
        ext.call_IPoolManager_mint ((ext.get w3).asyncOrders pid).poolManager order.owner
          (inputOf order) amt env w3
      else
        ext.call_IPoolManager_take ((ext.get w3).asyncOrders pid).poolManager (inputOf order)
          order.owner amt env w3) = .ok ((), w4) ∧
      AsyncFiller.settlePriorityFee ext (selfGet ext pid) (selfSet ext pid) order.key id order.owner
        fee env.self env w4 = .ok ((), w') := by
  simp only [tail, run_bind, selfGet_run, selfSet_run, run_read, run_ite] at h
  split at h
  next a w1 hr =>
    cases a
    split at h
    next b w3 hb =>
      cases b
      split at h
      next hz =>
        split at h
        next c w4 hm =>
          cases c
          exact ⟨w1, w3, w4, hr, hb, by simpa [hz] using hm, h⟩
        next => cases h
      next hz =>
        split at h
        next c w4 hm =>
          cases c
          exact ⟨w1, w3, w4, hr, hb, by simpa [hz] using hm, h⟩
        next => cases h
    next => cases h
  next => cases h

/-- **Success.** A successful `cancelOrder` was authorised (owner or the owner's executor) on an
order with stored input `amt ≠ 0`, and it ran exactly: `_remove`; clear `orders[id]`;
`burn(address(this), input, amt)`; `mint`/`take` of the same `amt` of the same `input` to
`order.owner`; settle the escrowed bid. `amt` is read from storage at entry, not from calldata. -/
theorem cancelOrder_ok (order : AsyncOrder) (env : Env) (w w' : σ)
    (h : AsyncSwap.cancelOrder ext order env w = .ok ((), w')) :
    let pid := poolId ext order.key
    let id := orderId ext env order
    let info := ((ext.get w).asyncOrders pid).orders id
    (env.sender = order.owner ∨ ((ext.get w).asyncOrders pid).isExecutor order.owner env.sender = true) ∧
    info.amountIn ≠ 0 ∧
    ∃ w1 w3 w4,
      ext.fn_AsyncFiller_remove_6902 (selfGet ext pid) (selfSet ext pid) (bookGet ext pid)
        (bookSet ext pid) id env w = .ok ((), w1) ∧
      ext.call_IPoolManager_burn ((ext.get (delWorld ext pid id w1)).asyncOrders pid).poolManager
        env.self (inputOf order) info.amountIn env (delWorld ext pid id w1) = .ok ((), w3) ∧
      (if inputOf order = 0 then
        ext.call_IPoolManager_mint ((ext.get w3).asyncOrders pid).poolManager order.owner
          (inputOf order) info.amountIn env w3
      else
        ext.call_IPoolManager_take ((ext.get w3).asyncOrders pid).poolManager (inputOf order)
          order.owner info.amountIn env w3) = .ok ((), w4) ∧
      AsyncFiller.settlePriorityFee ext (selfGet ext pid) (selfSet ext pid) order.key id order.owner
        (if info.priorityFeeEscrowed then info.priorityFee else 0) env.self env w4 = .ok ((), w') := by
  intro pid id info
  rw [cancelOrder_run] at h
  simp only at h
  split at h
  · cases h
  · rename_i hg
    split at h
    · cases h
    · rename_i h0
      refine ⟨?_, h0, tail_ok ext order pid id _ _ env w w' h⟩
      by_cases hs : env.sender = order.owner
      · exact Or.inl hs
      · right; simpa [hs] using hg

/-- With a lawful `ext` (`get ∘ set = id`), the world handed to the first external call (the burn)
already has `orders[id]` cleared. -/
theorem delWorld_order (hget : ∀ w s, ext.get (ext.set w s) = s) (pid id : Nat) (w : σ) :
    ((ext.get (delWorld ext pid id w)).asyncOrders pid).orders id = default := by
  simp [delWorld, hget, upd]

/-- **No double refund.** From the world the burn sees (and so from anything that re-enters during
it, or any later transaction before the slot is rewritten), cancelling the same order again
reverts: either the caller is unauthorised or the order is gone (`OrderNotFound`). -/
theorem cancelOrder_reentry_reverts (hget : ∀ w s, ext.get (ext.set w s) = s)
    (order : AsyncOrder) (env env' : Env) (w1 : σ) (hc : env'.chainid = env.chainid) :
    ∃ e, AsyncSwap.cancelOrder ext order env'
      (delWorld ext (poolId ext order.key) (orderId ext env order) w1) = .error e := by
  have hid : orderId ext env' order = orderId ext env order := by simp [orderId, hc]
  have h0 : (((ext.get (delWorld ext (poolId ext order.key) (orderId ext env order) w1)).asyncOrders
      (poolId ext order.key)).orders (orderId ext env' order)).amountIn = 0 := by
    rw [hid, delWorld_order ext hget]; rfl
  rw [cancelOrder_run]
  simp only [h0]
  split <;> exact ⟨_, rfl⟩

end AsyncSwap.Swarm.CancelOrder
