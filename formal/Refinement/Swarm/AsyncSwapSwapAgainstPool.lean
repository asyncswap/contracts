import Generated.AsyncSwap
import Refinement.Monad
import Refinement.Swarm.AsyncSwapFillOrderFromPoolLiquidity

/-!
# `AsyncMatching._swapAgainstPool`

Internal helper of `AsyncSwap.fillOrderFromPoolLiquidity` (src/AsyncSwap.sol). With
`pid = key.toId()`, `input = zeroForOne ? currency0 : currency1`:

* reverts `NoActiveLiquidity` when the pool's active liquidity reads `0`, before any external call
  (`swapAgainstPool_noLiquidity`);
* never succeeds when `amountIn ≥ 2^127` (`swapAgainstPool_amountIn_lt`, `SafeCast.toInt128`);
* on success (`swapAgainstPool_success`): liquidity `≠ 0`; `burn(hook, input, amountIn)`; slot0 read;
  LP fee set to `3000`; one exact-input `swap(key, (zeroForOne, -amountIn, MIN+1 | MAX-1), "")`;
  LP fee restored to the slot0 fee; the input delta is exactly `-amountIn`, the output delta is
  positive and the returned `out = uint128(outputDelta) ≥ amountOutMin`;
* `swapAgainstPool_spec`: once those external calls succeed (and `amountIn < 2^127`), the result is
  exactly `PartialLiquidityFill` / `LimitPriceNotMet` / `ok (uint128(outputDelta))`, in that order.

It writes no storage of its own: the final state is the one the last external call
(`updateDynamicLPFee` restoring the fee) leaves.
-/

open FormalAst Refinement
open AsyncSwap.Swarm.FillOrderFromPoolLiquidity

namespace AsyncSwap.Swarm.SwapAgainstPool

variable {σ : Type} (ext : Ext σ)

/-- Guard 1: no active liquidity ⇒ `NoActiveLiquidity`, before any external call. -/
theorem swapAgainstPool_noLiquidity (manager : Nat) (key : PoolKey) (zfo : Bool)
    (amtIn amtOutMin hook : Nat) (env : Env) (w w0 : σ)
    (hL : StateLibrary.getLiquidity ext manager (pidOf ext key) env w = .ok (0, w0)) :
    AsyncMatching.«_swapAgainstPool» ext manager key zfo amtIn amtOutMin hook env w
      = .error ⟨"NoActiveLiquidity"⟩ := by
  unfold AsyncMatching.«_swapAgainstPool» PoolIdLibrary.toId
  simp only [pidOf] at hL
  simp only [run_bind, run_pure, hL, run_ite, run_throw, beq_iff_eq, ite_true]

/-- **Success.** Liquidity non-zero, input claims burned from `hook`, fee 3000 around one exact-input
swap of `amountIn`, fee restored; full fill; `0 < outputDelta`, `out = uint128(outputDelta) ≥
amountOutMin`. The final state is the one the fee restore leaves. -/
theorem swapAgainstPool_success (manager : Nat) (key : PoolKey) (zfo : Bool)
    (amtIn amtOutMin hook : Nat) (env : Env) (w w' : σ) (out : Nat)
    (h : AsyncMatching.«_swapAgainstPool» ext manager key zfo amtIn amtOutMin hook env w
      = .ok (out, w')) :
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
      amtOutMin ≤ out :=
  swapAgainstPool_ok ext manager key zfo amtIn amtOutMin hook env w w' out h

/-- Liquidity is non-zero and the output meets the minimum on every successful run. -/
theorem swapAgainstPool_ok_liquidity_min (manager : Nat) (key : PoolKey) (zfo : Bool)
    (amtIn amtOutMin hook : Nat) (env : Env) (w w' : σ) (out : Nat)
    (h : AsyncMatching.«_swapAgainstPool» ext manager key zfo amtIn amtOutMin hook env w
      = .ok (out, w')) :
    (∃ L w0, StateLibrary.getLiquidity ext manager (pidOf ext key) env w = .ok (L, w0) ∧ L ≠ 0) ∧
    amtOutMin ≤ out := by
  obtain ⟨L, w0, -, -, -, -, -, -, hL, hL0, -, -, -, -, -, -, -, -, -, hmin⟩ :=
    swapAgainstPool_success ext manager key zfo amtIn amtOutMin hook env w w' out h
  exact ⟨⟨L, w0, hL, hL0⟩, hmin⟩

/-- Guard: `amountIn ≥ 2^127` never succeeds (`SafeCast.toInt128`). -/
theorem swapAgainstPool_amountIn_lt (manager : Nat) (key : PoolKey) (zfo : Bool)
    (amtIn amtOutMin hook : Nat) (env : Env) (w : σ) (h127 : 2 ^ 127 ≤ amtIn) :
    ∀ r, AsyncMatching.«_swapAgainstPool» ext manager key zfo amtIn amtOutMin hook env w ≠ .ok r := by
  rintro ⟨out, w'⟩ h
  obtain ⟨-, -, -, -, -, -, -, -, -, -, -, -, -, -, -, hlt, -⟩ :=
    swapAgainstPool_success ext manager key zfo amtIn amtOutMin hook env w w' out h
  omega

/-- **Exact behaviour after the external calls.** When the liquidity read is non-zero, the burn, the
slot0 read, the fee set, the swap and the fee restore succeed, and `amountIn < 2^127`, the function
reverts `PartialLiquidityFill` unless the input delta is `-amountIn`, then `LimitPriceNotMet` unless
`0 < outputDelta` and `uint128(outputDelta) ≥ amountOutMin`, and otherwise returns
`uint128(outputDelta)` in the state the fee restore left. -/
theorem swapAgainstPool_spec (manager : Nat) (key : PoolKey) (zfo : Bool)
    (amtIn amtOutMin hook : Nat) (env : Env) (w w0 w1 w2 w3 w4 w' : σ) (L : Nat)
    (slot0 : Nat × Int × Nat × Nat) (delta : Int)
    (hL : StateLibrary.getLiquidity ext manager (pidOf ext key) env w = .ok (L, w0)) (hL0 : L ≠ 0)
    (hb : ext.call_IPoolManager_burn manager hook (if zfo then key.currency0 else key.currency1) amtIn
      env w0 = .ok ((), w1))
    (hs : StateLibrary.getSlot0 ext manager (pidOf ext key) env w1 = .ok (slot0, w2))
    (hf : ext.call_IPoolManager_updateDynamicLPFee manager key 3000 env w2 = .ok ((), w3))
    (hsw : ext.call_IPoolManager_swap manager key
        { zeroForOne := zfo, amountSpecified := -(amtIn : Int),
          sqrtPriceLimitX96 := if zfo then TickMath.MIN_SQRT_PRICE + 1 else TickMath.MAX_SQRT_PRICE - 1 }
        [] env w3 = .ok (delta, w4))
    (hr : ext.call_IPoolManager_updateDynamicLPFee manager key slot0.2.2.2 env w4 = .ok ((), w'))
    (h127 : amtIn < 2 ^ 127) :
    AsyncMatching.«_swapAgainstPool» ext manager key zfo amtIn amtOutMin hook env w =
      if (if zfo then amount0 delta else amount1 delta) ≠ -(amtIn : Int) then
        .error ⟨"PartialLiquidityFill"⟩
      else if (if zfo then amount1 delta else amount0 delta) ≤ 0 ∨
          toUnsigned 128 (if zfo then amount1 delta else amount0 delta) < amtOutMin then
        .error ⟨"LimitPriceNotMet"⟩
      else .ok (toUnsigned 128 (if zfo then amount1 delta else amount0 delta), w') := by
  have h256 : toSigned 256 amtIn = (amtIn : Int) := toSigned256_small amtIn h127
  have h128 : wrapI 128 (amtIn : Int) = (amtIn : Int) := wrapI128_small amtIn h127
  have hf256 : fits 256 (-(amtIn : Int)) = true := by
    unfold fits smin smax; simp only [decide_eq_true_eq, Nat.reducePow, Nat.reduceSub] at h127 ⊢
    omega
  have hf128 : fits 128 (-(amtIn : Int)) = true := by
    unfold fits smin smax; simp only [decide_eq_true_eq, Nat.reducePow, Nat.reduceSub] at h127 ⊢
    omega
  have hge : ¬ (amtIn ≥ 1 <<< 127) := by
    simp only [Nat.shiftLeft_eq, Nat.one_mul]; omega
  have hneg : ¬ ((amtIn : Int) < 0) := by omega
  have hL0' : ¬ (L = 0) := hL0
  have hmin : TickMath.MIN_SQRT_PRICE + 1 < 2 ^ 160 := by unfold TickMath.MIN_SQRT_PRICE; decide
  have hmax : 1 ≤ TickMath.MAX_SQRT_PRICE := by unfold TickMath.MAX_SQRT_PRICE; decide
  unfold AsyncMatching.«_swapAgainstPool» CurrencySettler.settle CurrencyLibrary.toId SafeCast.toInt256
    SafeCast.toInt128 negcI BalanceDeltaLibrary.amount0 BalanceDeltaLibrary.amount1 PoolIdLibrary.toId
  simp only [pidOf, amount0, amount1] at hL hs ⊢
  simp only [bind_pure_unit, ite_true, pure_bind]
  simp only [run_bind, run_pure, run_ite, run_throw, beq_iff_eq, bne_iff_ne, hL, hL0', ite_false,
    h256, h128, hf256, hf128, hge, hneg, decide_false, Bool.false_eq_true,
    AsyncMatching.POOL_LIQUIDITY_FILL_FEE]
  cases zfo
  · simp only [Bool.false_eq_true, ite_false, ite_true, subc] at hb hsw ⊢
    simp only [hb, hs, hf, Bool.or_eq_true, decide_eq_true_eq, run_ite, hmax, ite_true, run_pure, hsw, hr]
  · simp only [ite_true, addc] at hb hsw ⊢
    simp only [hb, hs, hf, Bool.or_eq_true, decide_eq_true_eq, run_ite, hmin, ite_true, run_pure, hsw, hr]

end AsyncSwap.Swarm.SwapAgainstPool
