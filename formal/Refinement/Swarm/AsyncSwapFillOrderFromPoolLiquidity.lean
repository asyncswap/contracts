import Generated.AsyncSwap
import Refinement.Monad
import Mathlib.Tactic.CasesM

/-!
# `AsyncSwap.fillOrderFromPoolLiquidity`

`function fillOrderFromPoolLiquidity(AsyncOrder calldata order, bytes32 id) external`
(src/AsyncSwap.sol:401), through `AsyncMatching.fillFromPoolLiquidity` and `_swapAgainstPool`.

With `pid = order.key.toId()`, `S = asyncOrders[pid]`, `info = S.orders[id]` (all read at entry):

* reverts `NotSelf` unless `msg.sender = address(this)` (`fillOrderFromPoolLiquidity_notSelf`);
* reverts `OrderNotFound` when `info.amountIn = 0` (`fillOrderFromPoolLiquidity_notFound`);
* reverts `NoActiveLiquidity` when the pool's active liquidity reads `0`
  (`fillOrderFromPoolLiquidity_noLiquidity`);
* on success (`fillOrderFromPoolLiquidity_ok`, `_ok_full`): `burn(address(this), input, info.amountIn)`
  of the escrowed input claims; LP fee set to `3000`; one exact-input `swap(key, (zeroForOne,
  -info.amountIn, MIN+1 | MAX-1))`; LP fee restored to the fee read from `slot0`; the swap took
  exactly `info.amountIn` of input (`PartialLiquidityFill` otherwise), `info.amountIn < 2^127`, the
  output delta is positive and `out ≥ info.amountOutMin` (`LimitPriceNotMet` otherwise); then `out`
  of the output currency goes (`mint` if native, `take` otherwise) to `info.owner`, the stored maker
  read at entry; `_remove` (opaque in the model: the `RadixPriceTree` `PriceLevelMissing` guard and the
  `orderCount`/`openOrderCount` decrements live there); `orders[id] := default`; then the escrowed bid
  is settled with `address(this)` as the hook.

Footprint: its own writes are through the setters of `asyncOrders[pid]` and `priceBooks[pid]` only
(`selfSet_get`, `bookSet_get`, `delWorld_get`); everything else changes only via the external calls.
The order slot is cleared before the bid settlement (`delWorld_order`), so a re-entrant fill of the
same order from there reverts (`fillOrderFromPoolLiquidity_reentry_reverts`).
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.FillOrderFromPoolLiquidity

variable {σ : Type} (ext : Ext σ)

/-- `PoolIdLibrary.toId key` in the model. -/
def pidOf (key : PoolKey) : Nat :=
  ext.keccak [key.currency0, key.currency1, key.fee, toUnsigned 256 key.tickSpacing, key.hooks]

def selfGet (pid : Nat) : M σ AsyncFiller.State_ := do return ((ext.get (← get)).asyncOrders pid)
def selfSet (pid : Nat) : AsyncFiller.State_ → M σ Unit := fun x =>
  modify fun w => ext.set w (let s := ext.get w; { s with asyncOrders := upd (s.asyncOrders) pid x })
def bookGet (pid : Nat) : M σ AsyncFiller.Book := do return ((ext.get (← get)).priceBooks pid)
def bookSet (pid : Nat) : AsyncFiller.Book → M σ Unit := fun x =>
  modify fun w => ext.set w (let s := ext.get w; { s with priceBooks := upd (s.priceBooks) pid x })

theorem selfGet_run (pid : Nat) (env : Env) (w : σ) :
    selfGet ext pid env w = .ok ((ext.get w).asyncOrders pid, w) := rfl

theorem selfSet_run (pid : Nat) (x : AsyncFiller.State_) (env : Env) (w : σ) :
    selfSet ext pid x env w =
      .ok ((), ext.set w { ext.get w with asyncOrders := upd (ext.get w).asyncOrders pid x }) := rfl

/-- The generated body of `fillFromPoolLiquidity` after the pool swap returned `amountOut`. -/
def tail (pid : Nat) (key : PoolKey) (id maker hook amountOut : Nat) : M σ Unit := do
  let __t6 ← AsyncFiller.paidPriorityFee ext (do return (((← selfGet ext pid)).orders id)) (fun x => do selfSet ext pid ({ ((← selfGet ext pid)) with orders := upd (((← selfGet ext pid)).orders) id (x) }))
  let priorityFee : Nat := __t6
  let __t7 ← selfGet ext pid
  let output : Nat := (if (((__t7).orders id)).zeroForOne then (key).currency1 else (key).currency0)
  let __t8 ← selfGet ext pid
  let __t9 ← CurrencyLibrary.isAddressZero ext output
  CurrencySettler.take ext output ((__t8).poolManager) maker amountOut __t9
  ext.fn_AsyncFiller_remove_6902 (do return (← selfGet ext pid)) (fun x => do selfSet ext pid (x)) (do return (← bookGet ext pid)) (fun x => do bookSet ext pid (x)) id
  let __t10 ← selfGet ext pid
  selfSet ext pid ({ (__t10) with orders := upd ((__t10).orders) id (default) })
  AsyncFiller.settlePriorityFee ext (do return (← selfGet ext pid)) (fun x => do selfSet ext pid (x)) key id maker priorityFee hook
  return ()

/-! ## Unfolding -/

/-- The `NotSelf` guard, then `AsyncMatching.fillFromPoolLiquidity` on `asyncOrders[pid]` /
`priceBooks[pid]` with the maker `orders[id].owner` read at entry and `address(this)` as hook. -/
theorem fillOrderFromPoolLiquidity_eq (order : AsyncOrder) (id : Nat) (env : Env) (w : σ) :
    AsyncSwap.fillOrderFromPoolLiquidity ext order id env w =
      if env.sender ≠ env.self then .error ⟨"NotSelf"⟩
      else AsyncMatching.fillFromPoolLiquidity ext (selfGet ext (pidOf ext order.key))
        (selfSet ext (pidOf ext order.key)) (bookGet ext (pidOf ext order.key))
        (bookSet ext (pidOf ext order.key)) order.key id
        ((((ext.get w).asyncOrders (pidOf ext order.key)).orders id).owner) env.self env w := by
  unfold AsyncSwap.fillOrderFromPoolLiquidity PoolIdLibrary.toId
  simp only [run_bind, run_pure, run_read, run_get, run_ite, run_throw, bne_iff_ne, ne_eq]
  by_cases h : env.sender = env.self
  · simp only [h, not_true_eq_false, ite_false]
    split
    · rename_i a s' hh; cases a; exact hh.symm
    · rename_i e hh; exact hh.symm
  · simp [h]

/-- `fillFromPoolLiquidity`: `OrderNotFound` guard, the pool swap, then `tail`. -/
theorem fill_eq (pid : Nat) (key : PoolKey) (id maker hook : Nat) (env : Env) (w : σ) :
    AsyncMatching.fillFromPoolLiquidity ext (selfGet ext pid) (selfSet ext pid) (bookGet ext pid)
        (bookSet ext pid) key id maker hook env w =
      (if (((ext.get w).asyncOrders pid).orders id).amountIn = 0 then .error ⟨""⟩
       else match AsyncMatching._swapAgainstPool ext ((ext.get w).asyncOrders pid).poolManager key
            (((ext.get w).asyncOrders pid).orders id).zeroForOne
            (((ext.get w).asyncOrders pid).orders id).amountIn
            (((ext.get w).asyncOrders pid).orders id).amountOutMin hook env w with
         | .ok (out, w1) => tail ext pid key id maker hook out env w1
         | .error e => .error e) := by
  unfold AsyncMatching.fillFromPoolLiquidity
  simp only [run_bind, run_pure, run_ite, run_throw, selfGet_run, beq_iff_eq]
  by_cases h0 : (((ext.get w).asyncOrders pid).orders id).amountIn = 0
  · simp [h0]
  · simp only [h0, ite_false]
    cases AsyncMatching._swapAgainstPool ext ((ext.get w).asyncOrders pid).poolManager key
            (((ext.get w).asyncOrders pid).orders id).zeroForOne
            (((ext.get w).asyncOrders pid).orders id).amountIn
            (((ext.get w).asyncOrders pid).orders id).amountOutMin hook env w with
    | error e => rfl
    | ok p =>
      obtain ⟨out, w1⟩ := p
      simp only [tail, run_bind, run_pure, selfGet_run]

/-! ## Guards -/

/-- Guard 1: only the contract itself may call it. -/
theorem fillOrderFromPoolLiquidity_notSelf (order : AsyncOrder) (id : Nat) (env : Env) (w : σ)
    (h : env.sender ≠ env.self) :
    AsyncSwap.fillOrderFromPoolLiquidity ext order id env w = .error ⟨"NotSelf"⟩ := by
  rw [fillOrderFromPoolLiquidity_eq]; simp [h]

/-- Guard 2: an order with no stored input reverts (`OrderNotFound`, rendered `""` in the model). -/
theorem fillOrderFromPoolLiquidity_notFound (order : AsyncOrder) (id : Nat) (env : Env) (w : σ)
    (hs : env.sender = env.self)
    (h0 : (((ext.get w).asyncOrders (pidOf ext order.key)).orders id).amountIn = 0) :
    AsyncSwap.fillOrderFromPoolLiquidity ext order id env w = .error ⟨""⟩ := by
  rw [fillOrderFromPoolLiquidity_eq, fill_eq]; simp [hs, h0]

/-- Guard 3: with no active liquidity in the pool the swap is never attempted: `NoActiveLiquidity`. -/
theorem fillOrderFromPoolLiquidity_noLiquidity (order : AsyncOrder) (id : Nat) (env : Env) (w w0 : σ)
    (hs : env.sender = env.self)
    (h0 : (((ext.get w).asyncOrders (pidOf ext order.key)).orders id).amountIn ≠ 0)
    (hL : StateLibrary.getLiquidity ext ((ext.get w).asyncOrders (pidOf ext order.key)).poolManager
      (pidOf ext order.key) env w = .ok (0, w0)) :
    AsyncSwap.fillOrderFromPoolLiquidity ext order id env w = .error ⟨"NoActiveLiquidity"⟩ := by
  rw [fillOrderFromPoolLiquidity_eq, fill_eq]
  simp only [hs, ne_eq, not_true_eq_false, ite_false, h0]
  unfold AsyncMatching._swapAgainstPool PoolIdLibrary.toId
  simp only [pidOf] at hL ⊢
  simp only [run_bind, run_pure, hL, run_ite, run_throw, beq_iff_eq, ite_true]

/-! ## The pool swap -/

theorem toSigned256_small (x : Nat) (h : x < 2 ^ 127) : toSigned 256 x = (x : Int) := by
  have h1 : x < 2 ^ 256 := Nat.lt_trans h (by decide)
  have h2 : x < 2 ^ 255 := Nat.lt_trans h (by decide)
  unfold toSigned wrapI
  have : (x : Int) % ((2 ^ 256 : Nat) : Int) = x := Int.emod_eq_of_lt (by omega) (by exact_mod_cast h1)
  simp only [this]
  simp only [Nat.reducePow, Nat.reduceSub] at h2 ⊢
  rw [ite_eq_right_iff]; omega

theorem wrapI128_small (x : Nat) (h : x < 2 ^ 127) : wrapI 128 (x : Int) = (x : Int) := by
  have h1 : x < 2 ^ 128 := Nat.lt_trans h (by decide)
  unfold wrapI
  have : (x : Int) % ((2 ^ 128 : Nat) : Int) = x := Int.emod_eq_of_lt (by omega) (by exact_mod_cast h1)
  simp only [this]
  simp only [Nat.reducePow, Nat.reduceSub] at h ⊢
  rw [ite_eq_right_iff]; omega

theorem ite_error_ok_eq_ok {ε α : Type} (c : Prop) [Decidable c] (x y : α) (e : ε) :
    ((if c then Except.error e else Except.ok x) = Except.ok y) ↔ ¬c ∧ x = y := by
  split <;> simp_all

/-- `BalanceDelta.amount0()` / `amount1()` as the model computes them. -/
def amount0 (d : Int) : Int := toSigned 128 (ysar 128 (toUnsigned 256 d))
def amount1 (d : Int) : Int := toSigned 128 (ysignextend 15 (toUnsigned 256 d))

/-- A successful `_swapAgainstPool`: liquidity is non-zero; the escrowed input claims are burned
from `hook`; the fee is set to 3000 and restored afterwards; one exact-input swap of `amtIn`; the
swap consumed exactly `amtIn`; the output is positive and at least `amtOutMin`. -/
theorem swapAgainstPool_ok (manager : Nat) (key : PoolKey) (zfo : Bool) (amtIn amtOutMin hook : Nat)
    (env : Env) (w w' : σ) (out : Nat)
    (h : AsyncMatching._swapAgainstPool ext manager key zfo amtIn amtOutMin hook env w = .ok (out, w')) :
    ∃ (L : Nat) (w0 w1 w2 w3 w4 : σ) (slot0 : Nat × Int × Nat × Nat) (delta : Int),
      StateLibrary.getLiquidity ext manager (pidOf ext key) env w = .ok (L, w0) ∧ L ≠ 0 ∧
      ext.call_IPoolManager_burn manager hook (if zfo then key.currency0 else key.currency1) amtIn env w0
        = .ok ((), w1) ∧
      StateLibrary.getSlot0 ext manager (pidOf ext key) env w1 = .ok (slot0, w2) ∧
      ext.call_IPoolManager_updateDynamicLPFee manager key 3000 env w2 = .ok ((), w3) ∧
      ext.call_IPoolManager_swap manager key
        { zeroForOne := zfo, amountSpecified := -(amtIn : Int),
          sqrtPriceLimitX96 := if zfo then TickMath.MIN_SQRT_PRICE + 1 else TickMath.MAX_SQRT_PRICE - 1 }
        [] env w3 = .ok (delta, w4) ∧
      ext.call_IPoolManager_updateDynamicLPFee manager key slot0.2.2.2 env w4 = .ok ((), w') ∧
      amtIn < 2 ^ 127 ∧
      (if zfo then amount0 delta else amount1 delta) = -(amtIn : Int) ∧
      0 < (if zfo then amount1 delta else amount0 delta) ∧
      out = toUnsigned 128 (if zfo then amount1 delta else amount0 delta) ∧
      amtOutMin ≤ out := by
  unfold AsyncMatching._swapAgainstPool CurrencySettler.settle CurrencyLibrary.toId SafeCast.toInt256
    SafeCast.toInt128 CustomRevert.revertWith negcI addc subc BalanceDeltaLibrary.amount0
    BalanceDeltaLibrary.amount1 PoolIdLibrary.toId at h
  simp only [bind_pure_unit, ite_true, pure_bind] at h
  simp only [run_bind, run_pure, run_ite, run_throw, beq_iff_eq, bne_iff_ne] at h
  simp only [pidOf, amount0, amount1]
  cases zfo <;>
  simp only [Bool.false_eq_true, ite_true, ite_false, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE,
    Nat.reduceAdd, Nat.reduceSub, Nat.reducePow, Nat.reduceLT, Nat.reduceLeDiff,
    AsyncMatching.POOL_LIQUIDITY_FILL_FEE] at h ⊢ <;>
  repeat (split at h <;> try (cases h; done))
  all_goals
    simp only [ite_ok_error_eq_ok, ite_error_ok_eq_ok, Except.ok.injEq, Prod.mk.injEq, decide_eq_true_eq,
      Nat.shiftLeft_eq, Nat.reducePow, Nat.one_mul, ge_iff_le, Nat.not_le, Nat.not_lt, ne_eq,
      Decidable.not_not, Bool.or_eq_true, not_or, Int.not_le, Int.not_lt] at *
    cases_type* And
    subst_vars
    have h127 : amtIn < 2 ^ 127 := by simp only [Nat.reducePow]; assumption
    simp only [toSigned256_small amtIn h127, wrapI128_small amtIn h127] at *
    exact ⟨_, _, _, _, _, _, _, _, ‹_›, ‹_›, ‹_›, ‹_›, ‹_›, ‹_›, ‹_›, ‹_›, Eq.symm ‹_›, ‹_›, rfl, ‹_›⟩

/-! ## After the swap -/

/-- The world after `orders[id] := default` in pool `pid`. -/
def delWorld (pid id : Nat) (w : σ) : σ :=
  let S := (ext.get w).asyncOrders pid
  ext.set w { ext.get w with
    asyncOrders := upd (ext.get w).asyncOrders pid { S with orders := upd S.orders id default } }

/-- The steps of `tail`, each from the world the previous one left. -/
theorem tail_ok (pid : Nat) (key : PoolKey) (id maker hook out : Nat) (env : Env) (w1 w' : σ)
    (h : tail ext pid key id maker hook out env w1 = .ok ((), w')) :
    let S := (ext.get w1).asyncOrders pid
    let info := S.orders id
    let output := if info.zeroForOne then key.currency1 else key.currency0
    ∃ w2 w3 : σ,
      (if output = 0 then ext.call_IPoolManager_mint S.poolManager maker output out env w1
       else ext.call_IPoolManager_take S.poolManager output maker out env w1) = .ok ((), w2) ∧
      ext.fn_AsyncFiller_remove_6902 (selfGet ext pid) (selfSet ext pid) (bookGet ext pid)
        (bookSet ext pid) id env w2 = .ok ((), w3) ∧
      AsyncFiller.settlePriorityFee ext (selfGet ext pid) (selfSet ext pid) key id maker
        (if info.priorityFeeEscrowed then info.priorityFee else 0) hook env (delWorld ext pid id w3)
        = .ok ((), w') := by
  intro S info output
  simp only [tail, bind_pure_unit, AsyncFiller.paidPriorityFee, CurrencySettler.take,
    CurrencyLibrary.isAddressZero, CurrencyLibrary.toId, CurrencyLibrary.ADDRESS_ZERO] at h
  simp only [run_bind, run_pure, run_ite, selfGet_run, selfSet_run, beq_iff_eq] at h
  have hp : (if (((ext.get w1).asyncOrders pid).orders id).priorityFeeEscrowed = true then
        (Except.ok ((((ext.get w1).asyncOrders pid).orders id).priorityFee, w1) : Except Revert (Nat × σ))
      else Except.ok (0, w1)) = Except.ok (if info.priorityFeeEscrowed then info.priorityFee else 0, w1) := by
    split <;> rfl
  rw [hp] at h
  simp only at h
  split at h
  · rename_i u w2 h2
    split at h
    · rename_i u' w3 h3
      exact ⟨w2, w3, h2, h3, h⟩
    · cases h
  · cases h

/-! ## Success -/

/-- **Success.** A successful `fillOrderFromPoolLiquidity` was a self-call on a stored order
(`amountIn ≠ 0`, read at entry), the pool swap succeeded returning `out ≥ amountOutMin`, and `tail`
ran from the swap's world: `out` of the output currency paid to the stored maker, `_remove`,
`orders[id] := default`, bid settlement. -/
theorem fillOrderFromPoolLiquidity_ok (order : AsyncOrder) (id : Nat) (env : Env) (w w' : σ)
    (h : AsyncSwap.fillOrderFromPoolLiquidity ext order id env w = .ok ((), w')) :
    let pid := pidOf ext order.key
    let S := (ext.get w).asyncOrders pid
    let info := S.orders id
    env.sender = env.self ∧ info.amountIn ≠ 0 ∧
    ∃ (out : Nat) (w1 : σ),
      AsyncMatching._swapAgainstPool ext S.poolManager order.key info.zeroForOne info.amountIn
        info.amountOutMin env.self env w = .ok (out, w1) ∧
      info.amountOutMin ≤ out ∧
      tail ext pid order.key id info.owner env.self out env w1 = .ok ((), w') := by
  intro pid S info
  rw [fillOrderFromPoolLiquidity_eq] at h
  by_cases hs : env.sender = env.self
  · simp only [hs, ne_eq, not_true_eq_false, ite_false] at h
    rw [fill_eq] at h
    by_cases h0 : info.amountIn = 0
    · simp only [info, S, pid] at h0; simp [h0] at h
    · refine ⟨hs, h0, ?_⟩
      simp only [info, S, pid] at h0
      simp only [h0, ite_false] at h
      split at h
      · rename_i out w1 hsw
        obtain ⟨-, -, -, -, -, -, -, -, -, -, -, -, -, -, -, -, -, -, -, hmin⟩ :=
          swapAgainstPool_ok ext _ _ _ _ _ _ env w w1 out hsw
        exact ⟨out, w1, hsw, hmin, h⟩
      · cases h
  · simp [hs] at h

/-- **Full fill at or above the limit, paid to the stored maker.** On success, the pool swap
consumed exactly the stored `amountIn` (burned from this contract's claims) and produced `out ≥
amountOutMin`, and `out` of the output currency went to `orders[id].owner` as read at entry. -/
theorem fillOrderFromPoolLiquidity_ok_full (order : AsyncOrder) (id : Nat) (env : Env) (w w' : σ)
    (h : AsyncSwap.fillOrderFromPoolLiquidity ext order id env w = .ok ((), w')) :
    let pid := pidOf ext order.key
    let S := (ext.get w).asyncOrders pid
    let info := S.orders id
    let zfo := info.zeroForOne
    env.sender = env.self ∧ info.amountIn ≠ 0 ∧ info.amountIn < 2 ^ 127 ∧
    ∃ (L : Nat) (w0 w1 w2 w3 w4 w5 w6 w7 : σ) (slot0 : Nat × Int × Nat × Nat) (delta : Int),
      StateLibrary.getLiquidity ext S.poolManager pid env w = .ok (L, w0) ∧ L ≠ 0 ∧
      ext.call_IPoolManager_burn S.poolManager env.self
        (if zfo then order.key.currency0 else order.key.currency1) info.amountIn env w0 = .ok ((), w1) ∧
      StateLibrary.getSlot0 ext S.poolManager pid env w1 = .ok (slot0, w2) ∧
      ext.call_IPoolManager_updateDynamicLPFee S.poolManager order.key 3000 env w2 = .ok ((), w3) ∧
      ext.call_IPoolManager_swap S.poolManager order.key
        { zeroForOne := zfo, amountSpecified := -(info.amountIn : Int),
          sqrtPriceLimitX96 := if zfo then TickMath.MIN_SQRT_PRICE + 1 else TickMath.MAX_SQRT_PRICE - 1 }
        [] env w3 = .ok (delta, w4) ∧
      ext.call_IPoolManager_updateDynamicLPFee S.poolManager order.key slot0.2.2.2 env w4 = .ok ((), w5) ∧
      (if zfo then amount0 delta else amount1 delta) = -(info.amountIn : Int) ∧
      0 < (if zfo then amount1 delta else amount0 delta) ∧
      info.amountOutMin ≤ toUnsigned 128 (if zfo then amount1 delta else amount0 delta) ∧
      let S5 := (ext.get w5).asyncOrders pid
      let info5 := S5.orders id
      let out := toUnsigned 128 (if zfo then amount1 delta else amount0 delta)
      let output := if info5.zeroForOne then order.key.currency1 else order.key.currency0
      (if output = 0 then ext.call_IPoolManager_mint S5.poolManager info.owner output out env w5
       else ext.call_IPoolManager_take S5.poolManager output info.owner out env w5) = .ok ((), w6) ∧
      ext.fn_AsyncFiller_remove_6902 (selfGet ext pid) (selfSet ext pid) (bookGet ext pid)
        (bookSet ext pid) id env w6 = .ok ((), w7) ∧
      AsyncFiller.settlePriorityFee ext (selfGet ext pid) (selfSet ext pid) order.key id info.owner
        (if info5.priorityFeeEscrowed then info5.priorityFee else 0) env.self env (delWorld ext pid id w7)
        = .ok ((), w') := by
  intro pid S info zfo
  obtain ⟨hs, h0, out, w5, hsw, -, ht⟩ := fillOrderFromPoolLiquidity_ok ext order id env w w' h
  obtain ⟨L, w0, w1, w2, w3, w4, slot0, delta, hL, hL0, hb, hs0, hf, hswap, hf2, h127, hin, hpos,
    hout, hmin⟩ := swapAgainstPool_ok ext _ _ _ _ _ _ env w w5 out hsw
  obtain ⟨w6, w7, hpay, hrem, hset⟩ := tail_ok ext _ _ _ _ _ _ env w5 w' ht
  subst hout
  exact ⟨hs, h0, h127, L, w0, w1, w2, w3, w4, w5, w6, w7, slot0, delta, hL, hL0, hb, hs0, hf, hswap,
    hf2, hin, hpos, hmin, hpay, hrem, hset⟩

/-! ## Footprint of its own writes -/

/-- The `asyncOrders[pid]` setter handed to `_remove` / `settlePriorityFee` writes only that slot. -/
theorem selfSet_get (hget : ∀ w s, ext.get (ext.set w s) = s) (pid : Nat) (x : AsyncFiller.State_)
    (env : Env) (w w' : σ) (h : selfSet ext pid x env w = .ok ((), w')) :
    ext.get w' = { ext.get w with asyncOrders := upd (ext.get w).asyncOrders pid x } := by
  rw [selfSet_run] at h; cases h; rw [hget]

/-- The `priceBooks[pid]` setter handed to `_remove` writes only that slot. -/
theorem bookSet_get (hget : ∀ w s, ext.get (ext.set w s) = s) (pid : Nat) (x : AsyncFiller.Book)
    (env : Env) (w w' : σ) (h : bookSet ext pid x env w = .ok ((), w')) :
    ext.get w' = { ext.get w with priceBooks := upd (ext.get w).priceBooks pid x } := by
  simp only [bookSet, run_modify] at h; cases h; rw [hget]

/-- The direct delete `orders[id] := default` writes only `asyncOrders[pid].orders[id]`. -/
theorem delWorld_get (hget : ∀ w s, ext.get (ext.set w s) = s) (pid id : Nat) (w : σ) :
    let S := (ext.get w).asyncOrders pid
    ext.get (delWorld ext pid id w) = { ext.get w with
      asyncOrders := upd (ext.get w).asyncOrders pid { S with orders := upd S.orders id default } } := by
  simp [delWorld, hget]

/-- The order slot is cleared before the bid settlement's external calls. -/
theorem delWorld_order (hget : ∀ w s, ext.get (ext.set w s) = s) (pid id : Nat) (w : σ) :
    ((ext.get (delWorld ext pid id w)).asyncOrders pid).orders id = default := by
  simp [delWorld, hget, upd]

/-- A re-entrant fill of the same `id` from the world after the delete (where the bid settlement's
external calls run) finds `amountIn = 0` and reverts. -/
theorem fillOrderFromPoolLiquidity_reentry_reverts (hget : ∀ w s, ext.get (ext.set w s) = s)
    (order : AsyncOrder) (id : Nat) (env : Env) (w : σ) :
    ∃ e, AsyncSwap.fillOrderFromPoolLiquidity ext order id env
      (delWorld ext (pidOf ext order.key) id w) = .error e := by
  by_cases hs : env.sender = env.self
  · refine ⟨_, fillOrderFromPoolLiquidity_notFound ext order id env _ hs ?_⟩
    rw [delWorld_order ext hget]; rfl
  · exact ⟨_, fillOrderFromPoolLiquidity_notSelf ext order id env _ hs⟩

end AsyncSwap.Swarm.FillOrderFromPoolLiquidity
