import Generated.AsyncSwap
import Refinement.Monad

/-!
# `AsyncSwap.tryFillOrderFromPoolLiquidity`

`function tryFillOrderFromPoolLiquidity(AsyncOrder calldata order) external returns (bool filled)`
(src/AsyncSwap.sol:385).

* It reverts (`NotAuthorizedExecutor`) unless `msg.sender` is an executor that `order.owner`
  authorised on the order's pool;
* then reverts (`OrderNotFound`) if the stored order `orders[orderId(order)]` has `amountIn = 0`;
* otherwise it makes the self-call `this.fillOrderFromPoolLiquidity(order, id)` with exactly that
  `order` and the id `keccak(chainid, poolId, owner, zeroForOne, salt)` it just checked. If the call
  succeeds it returns `true` with the call's final world; if it reverts it returns `false` and the
  world is the starting one (try/catch rolls the reverted call back).

So the function writes no storage of its own: anything it changes comes from
`fillOrderFromPoolLiquidity` (which re-checks the executor itself), and a caller can only drive it
to fill an order that exists, by an executor its owner authorised.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.TryFill

variable {σ : Type} (ext : Ext σ)

/-- `try … catch` in the model's monad: a reverted body is rolled back to the starting world. -/
@[simp] theorem run_tryCatch {α : Type} (x : M σ α) (h : Revert → M σ α) (r : Env) (s : σ) :
    (tryCatch x h : M σ α) r s =
      (match x r s with | .ok p => .ok p | .error e => h e r s) := by
  show (tryCatchThe Revert (x r s) (fun e => h e r s)) = _
  cases x r s <;> rfl

/-- The pool id `order.key.toId()`. -/
def poolId (order : AsyncOrder) : Nat :=
  ext.keccak [order.key.currency0, order.key.currency1, order.key.fee,
    toUnsigned 256 order.key.tickSpacing, order.key.hooks]

/-- The order id `order.orderId()`. -/
def orderIdOf (env : Env) (order : AsyncOrder) : Nat :=
  ext.keccak [env.chainid, poolId ext order, order.owner, ybool order.zeroForOne, order.salt]

/-- Whole behaviour of the function. -/
theorem tryFillOrderFromPoolLiquidity_eq (order : AsyncOrder) (env : Env) (w : σ) :
    AsyncSwap.tryFillOrderFromPoolLiquidity ext order env w =
      if ((ext.get w).asyncOrders (poolId ext order)).isExecutor order.owner env.sender = false then
        .error ⟨""⟩
      else if (((ext.get w).asyncOrders (poolId ext order)).orders
          (orderIdOf ext env order)).amountIn = 0 then
        .error ⟨""⟩
      else
        match ext.call_AsyncSwap_fillOrderFromPoolLiquidity env.self order
            (orderIdOf ext env order) env w with
        | .ok (_, w') => .ok (true, w')
        | .error _ => .ok (false, w) := by
  unfold AsyncSwap.tryFillOrderFromPoolLiquidity AsyncOrderLibrary.orderId PoolIdLibrary.toId
  simp only [run_bind, run_pure, run_read, run_get, run_ite, run_throw, run_tryCatch]
  by_cases hx : ((ext.get w).asyncOrders (poolId ext order)).isExecutor order.owner env.sender = true
  · by_cases ha : (((ext.get w).asyncOrders (poolId ext order)).orders
        (orderIdOf ext env order)).amountIn = 0
    · simp_all [poolId, orderIdOf]
    · simp only [poolId, orderIdOf] at hx ha
      simp only [hx, ha, Bool.not_true, Bool.false_eq_true, ite_false, beq_iff_eq, poolId,
        orderIdOf]
      cases ext.call_AsyncSwap_fillOrderFromPoolLiquidity env.self order _ env w <;> rfl
  · simp only [poolId] at hx
    simp [hx, poolId]

/-- Guard 1: a caller `order.owner` hasn't authorised as executor on the pool is rejected. -/
theorem tryFillOrderFromPoolLiquidity_notExecutor (order : AsyncOrder) (env : Env) (w : σ)
    (h : ((ext.get w).asyncOrders (poolId ext order)).isExecutor order.owner env.sender = false) :
    AsyncSwap.tryFillOrderFromPoolLiquidity ext order env w = .error ⟨""⟩ := by
  rw [tryFillOrderFromPoolLiquidity_eq]
  simp [h]

/-- Guard 2: an order that isn't stored (`amountIn = 0`) is rejected. -/
theorem tryFillOrderFromPoolLiquidity_notFound (order : AsyncOrder) (env : Env) (w : σ)
    (h : (((ext.get w).asyncOrders (poolId ext order)).orders
          (orderIdOf ext env order)).amountIn = 0) :
    AsyncSwap.tryFillOrderFromPoolLiquidity ext order env w = .error ⟨""⟩ := by
  rw [tryFillOrderFromPoolLiquidity_eq]
  split <;> simp_all

/-- Both guards pass: the result is exactly the caught self-call — `true` with the call's world,
or `false` with the starting world. -/
theorem tryFillOrderFromPoolLiquidity_pass (order : AsyncOrder) (env : Env) (w : σ)
    (hx : ((ext.get w).asyncOrders (poolId ext order)).isExecutor order.owner env.sender = true)
    (ha : (((ext.get w).asyncOrders (poolId ext order)).orders
          (orderIdOf ext env order)).amountIn ≠ 0) :
    AsyncSwap.tryFillOrderFromPoolLiquidity ext order env w =
        match ext.call_AsyncSwap_fillOrderFromPoolLiquidity env.self order
            (orderIdOf ext env order) env w with
        | .ok (_, w') => .ok (true, w')
        | .error _ => .ok (false, w) := by
  rw [tryFillOrderFromPoolLiquidity_eq]
  simp only [hx, ha, Bool.true_eq_false, ite_false]

/-- On success: both guards held, and either the self-call to `fillOrderFromPoolLiquidity` with
this exact `order` and its checked id succeeded (result `true`, world = the call's world), or it
reverted (result `false`, world unchanged). The function writes no storage of its own. -/
theorem tryFillOrderFromPoolLiquidity_ok (order : AsyncOrder) (env : Env) (w w' : σ) (b : Bool)
    (hok : AsyncSwap.tryFillOrderFromPoolLiquidity ext order env w = .ok (b, w')) :
    ((ext.get w).asyncOrders (poolId ext order)).isExecutor order.owner env.sender = true ∧
    (((ext.get w).asyncOrders (poolId ext order)).orders (orderIdOf ext env order)).amountIn ≠ 0 ∧
    ((b = true ∧ ext.call_AsyncSwap_fillOrderFromPoolLiquidity env.self order
        (orderIdOf ext env order) env w = .ok ((), w')) ∨
     (b = false ∧ w' = w ∧ ∃ e, ext.call_AsyncSwap_fillOrderFromPoolLiquidity env.self order
        (orderIdOf ext env order) env w = .error e)) := by
  cases hx : ((ext.get w).asyncOrders (poolId ext order)).isExecutor order.owner env.sender with
  | false => rw [tryFillOrderFromPoolLiquidity_notExecutor ext order env w hx] at hok; cases hok
  | true =>
    by_cases ha : (((ext.get w).asyncOrders (poolId ext order)).orders
        (orderIdOf ext env order)).amountIn = 0
    · rw [tryFillOrderFromPoolLiquidity_notFound ext order env w ha] at hok; cases hok
    · rw [tryFillOrderFromPoolLiquidity_pass ext order env w hx ha] at hok
      refine ⟨rfl, ha, ?_⟩
      revert hok
      cases ext.call_AsyncSwap_fillOrderFromPoolLiquidity env.self order
          (orderIdOf ext env order) env w with
      | ok p =>
        obtain ⟨u, w1⟩ := p
        intro hok; cases hok; exact Or.inl ⟨rfl, rfl⟩
      | error e =>
        intro hok; cases hok; exact Or.inr ⟨rfl, rfl, e, rfl⟩

/-- It reverts exactly when one of its two guards fails (a reverting fill is caught, not bubbled). -/
theorem tryFillOrderFromPoolLiquidity_reverts_iff (order : AsyncOrder) (env : Env) (w : σ) :
    (∃ e, AsyncSwap.tryFillOrderFromPoolLiquidity ext order env w = .error e) ↔
      (((ext.get w).asyncOrders (poolId ext order)).isExecutor order.owner env.sender = false ∨
       (((ext.get w).asyncOrders (poolId ext order)).orders
          (orderIdOf ext env order)).amountIn = 0) := by
  constructor
  · rintro ⟨e, he⟩
    cases hx : ((ext.get w).asyncOrders (poolId ext order)).isExecutor order.owner env.sender with
    | false => exact Or.inl rfl
    | true =>
      by_cases ha : (((ext.get w).asyncOrders (poolId ext order)).orders
          (orderIdOf ext env order)).amountIn = 0
      · exact Or.inr ha
      · rw [tryFillOrderFromPoolLiquidity_pass ext order env w hx ha] at he
        revert he
        cases ext.call_AsyncSwap_fillOrderFromPoolLiquidity env.self order _ env w <;>
          intro he <;> cases he
  · rintro (h | h)
    · exact ⟨_, tryFillOrderFromPoolLiquidity_notExecutor ext order env w h⟩
    · exact ⟨_, tryFillOrderFromPoolLiquidity_notFound ext order env w h⟩

/-- A `false` result leaves the world exactly as it was. -/
theorem tryFillOrderFromPoolLiquidity_false_noop (order : AsyncOrder) (env : Env) (w w' : σ)
    (hok : AsyncSwap.tryFillOrderFromPoolLiquidity ext order env w = .ok (false, w')) :
    w' = w := by
  obtain ⟨-, -, h | h⟩ := tryFillOrderFromPoolLiquidity_ok ext order env w w' false hok
  · cases h.1
  · exact h.2.1

/-- No write of its own: if the self-call leaves this contract's storage unchanged whenever it
succeeds, so does `tryFillOrderFromPoolLiquidity`. -/
theorem tryFillOrderFromPoolLiquidity_storage (order : AsyncOrder) (env : Env) (w w' : σ) (b : Bool)
    (hcall : ∀ v', ext.call_AsyncSwap_fillOrderFromPoolLiquidity env.self order
        (orderIdOf ext env order) env w = .ok ((), v') → ext.get v' = ext.get w)
    (hok : AsyncSwap.tryFillOrderFromPoolLiquidity ext order env w = .ok (b, w')) :
    ext.get w' = ext.get w := by
  obtain ⟨-, -, h | h⟩ := tryFillOrderFromPoolLiquidity_ok ext order env w w' b hok
  · exact hcall w' h.2
  · rw [h.2.1]

end AsyncSwap.Swarm.TryFill
