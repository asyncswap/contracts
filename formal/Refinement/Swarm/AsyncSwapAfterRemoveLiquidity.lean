import Generated.AsyncSwap
import Refinement.Monad

/-!
# `BaseHook.afterRemoveLiquidity` (AsyncSwap, src/BaseHook.sol:120)

AsyncSwap does not override `_afterRemoveLiquidity`, so the hook never succeeds:
* reverts `NotPoolManager` unless `msg.sender = poolManager` (guard, ImmutableState.sol:16);
* otherwise reverts `HookNotImplemented` (BaseHook.sol:131).
Hence it has no successful run: no storage writes, no return value, no external calls.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm

variable {σ : Type} (ext : Ext σ)

/-- Guard 1: a caller other than the pool manager reverts `NotPoolManager`. -/
theorem afterRemoveLiquidity_notPoolManager (sender : Nat) (key : PoolKey)
    (params : ModifyLiquidityParams) (delta feesAccrued : Int) (hookData : List Nat)
    (env : Env) (w : σ) (h : env.sender ≠ ext.poolManager) :
    BaseHook.afterRemoveLiquidity ext sender key params delta feesAccrued hookData env w
      = .error ⟨"NotPoolManager"⟩ := by
  simp [BaseHook.afterRemoveLiquidity, ImmutableState.onlyPoolManager, h]

/-- Past the guard, the unimplemented hook reverts `HookNotImplemented`. -/
theorem afterRemoveLiquidity_hookNotImplemented (sender : Nat) (key : PoolKey)
    (params : ModifyLiquidityParams) (delta feesAccrued : Int) (hookData : List Nat)
    (env : Env) (w : σ) (h : env.sender = ext.poolManager) :
    BaseHook.afterRemoveLiquidity ext sender key params delta feesAccrued hookData env w
      = .error ⟨"HookNotImplemented"⟩ := by
  simp [BaseHook.afterRemoveLiquidity, ImmutableState.onlyPoolManager,
    BaseHook.«_afterRemoveLiquidity», h]

/-- Exact behaviour: it always reverts, with the error determined by the caller. -/
theorem afterRemoveLiquidity_spec (sender : Nat) (key : PoolKey)
    (params : ModifyLiquidityParams) (delta feesAccrued : Int) (hookData : List Nat)
    (env : Env) (w : σ) :
    BaseHook.afterRemoveLiquidity ext sender key params delta feesAccrued hookData env w
      = .error (if env.sender = ext.poolManager then ⟨"HookNotImplemented"⟩
                else ⟨"NotPoolManager"⟩) := by
  by_cases h : env.sender = ext.poolManager
  · simp only [afterRemoveLiquidity_hookNotImplemented ext sender key params delta feesAccrued
      hookData env w h, h, ite_true]
  · simp only [afterRemoveLiquidity_notPoolManager ext sender key params delta feesAccrued
      hookData env w h, h, ite_false]

/-- No successful run: hence no storage writes and no return value. -/
theorem afterRemoveLiquidity_never_ok (sender : Nat) (key : PoolKey)
    (params : ModifyLiquidityParams) (delta feesAccrued : Int) (hookData : List Nat)
    (env : Env) (w : σ) (r : Nat × Int) (w' : σ) :
    BaseHook.afterRemoveLiquidity ext sender key params delta feesAccrued hookData env w
      ≠ .ok (r, w') := by
  rw [afterRemoveLiquidity_spec]
  intro h; cases h

end AsyncSwap.Swarm
