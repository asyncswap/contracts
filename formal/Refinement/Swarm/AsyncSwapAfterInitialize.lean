import Generated.AsyncSwap
import Refinement.Monad

/-!
# `BaseHook.afterInitialize` (AsyncSwap, src/BaseHook.sol:48)

AsyncSwap does not override `_afterInitialize`, so the hook never succeeds:
* reverts `NotPoolManager` unless `msg.sender = poolManager` (guard, ImmutableState.sol:16);
* otherwise reverts `HookNotImplemented` (BaseHook.sol:56).
Hence it has no successful run: no storage writes, no return value, no external calls.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm

variable {σ : Type} (ext : Ext σ)

/-- Guard 1: a caller other than the pool manager reverts `NotPoolManager`. -/
theorem afterInitialize_notPoolManager (sender : Nat) (key : PoolKey) (sqrtPriceX96 : Nat)
    (tick : Int) (env : Env) (w : σ) (h : env.sender ≠ ext.poolManager) :
    BaseHook.afterInitialize ext sender key sqrtPriceX96 tick env w = .error ⟨"NotPoolManager"⟩ := by
  simp [BaseHook.afterInitialize, ImmutableState.onlyPoolManager, h]

/-- Past the guard, the unimplemented hook reverts `HookNotImplemented`. -/
theorem afterInitialize_hookNotImplemented (sender : Nat) (key : PoolKey) (sqrtPriceX96 : Nat)
    (tick : Int) (env : Env) (w : σ) (h : env.sender = ext.poolManager) :
    BaseHook.afterInitialize ext sender key sqrtPriceX96 tick env w
      = .error ⟨"HookNotImplemented"⟩ := by
  simp [BaseHook.afterInitialize, ImmutableState.onlyPoolManager, BaseHook.«_afterInitialize», h]

/-- Exact behaviour: it always reverts, with the error determined by the caller. -/
theorem afterInitialize_spec (sender : Nat) (key : PoolKey) (sqrtPriceX96 : Nat)
    (tick : Int) (env : Env) (w : σ) :
    BaseHook.afterInitialize ext sender key sqrtPriceX96 tick env w
      = .error (if env.sender = ext.poolManager then ⟨"HookNotImplemented"⟩
                else ⟨"NotPoolManager"⟩) := by
  by_cases h : env.sender = ext.poolManager
  · simp only [afterInitialize_hookNotImplemented ext sender key sqrtPriceX96 tick env w h, h,
      ite_true]
  · simp only [afterInitialize_notPoolManager ext sender key sqrtPriceX96 tick env w h, h,
      ite_false]

/-- No successful run: hence no storage writes and no return value. -/
theorem afterInitialize_never_ok (sender : Nat) (key : PoolKey) (sqrtPriceX96 : Nat)
    (tick : Int) (env : Env) (w : σ) (r : Nat) (w' : σ) :
    BaseHook.afterInitialize ext sender key sqrtPriceX96 tick env w ≠ .ok (r, w') := by
  rw [afterInitialize_spec]
  intro h; cases h

end AsyncSwap.Swarm
