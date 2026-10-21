import Generated.AsyncSwap
import Refinement.Monad

/-!
# `BaseHook.beforeRemoveLiquidity` (AsyncSwap, src/BaseHook.sol:79)

AsyncSwap does not override `_beforeRemoveLiquidity`, so the hook never succeeds:
* reverts `NotPoolManager` unless `msg.sender = poolManager` (guard, ImmutableState.sol:16);
* otherwise reverts `HookNotImplemented` (BaseHook.sol:93).
Hence it has no successful run: no storage writes, no return value, no external calls.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm

variable {σ : Type} (ext : Ext σ)

/-- Guard 1: a caller other than the pool manager reverts `NotPoolManager`. -/
theorem beforeRemoveLiquidity_notPoolManager (sender : Nat) (key : PoolKey)
    (params : ModifyLiquidityParams) (hookData : List Nat) (env : Env) (w : σ)
    (h : env.sender ≠ ext.poolManager) :
    BaseHook.beforeRemoveLiquidity ext sender key params hookData env w
      = .error ⟨"NotPoolManager"⟩ := by
  simp [BaseHook.beforeRemoveLiquidity, ImmutableState.onlyPoolManager, h]

/-- Past the guard, the unimplemented hook reverts `HookNotImplemented`. -/
theorem beforeRemoveLiquidity_hookNotImplemented (sender : Nat) (key : PoolKey)
    (params : ModifyLiquidityParams) (hookData : List Nat) (env : Env) (w : σ)
    (h : env.sender = ext.poolManager) :
    BaseHook.beforeRemoveLiquidity ext sender key params hookData env w
      = .error ⟨"HookNotImplemented"⟩ := by
  simp [BaseHook.beforeRemoveLiquidity, ImmutableState.onlyPoolManager,
    BaseHook.«_beforeRemoveLiquidity», h]

/-- Exact behaviour: it always reverts, with the error determined by the caller. -/
theorem beforeRemoveLiquidity_spec (sender : Nat) (key : PoolKey)
    (params : ModifyLiquidityParams) (hookData : List Nat) (env : Env) (w : σ) :
    BaseHook.beforeRemoveLiquidity ext sender key params hookData env w
      = .error (if env.sender = ext.poolManager then ⟨"HookNotImplemented"⟩
                else ⟨"NotPoolManager"⟩) := by
  by_cases h : env.sender = ext.poolManager
  · simp only [beforeRemoveLiquidity_hookNotImplemented ext sender key params hookData env w h,
      h, ite_true]
  · simp only [beforeRemoveLiquidity_notPoolManager ext sender key params hookData env w h,
      h, ite_false]

/-- No successful run: hence no storage writes and no return value. -/
theorem beforeRemoveLiquidity_never_ok (sender : Nat) (key : PoolKey)
    (params : ModifyLiquidityParams) (hookData : List Nat) (env : Env) (w : σ)
    (r : Nat) (w' : σ) :
    BaseHook.beforeRemoveLiquidity ext sender key params hookData env w ≠ .ok (r, w') := by
  rw [beforeRemoveLiquidity_spec]
  intro h; cases h

end AsyncSwap.Swarm
