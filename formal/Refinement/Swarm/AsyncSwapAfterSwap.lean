import Generated.AsyncSwap
import Refinement.Monad

/-!
# `BaseHook.afterSwap` (AsyncSwap, src/BaseHook.sol:160)

AsyncSwap does not override `_afterSwap`, so the hook never succeeds:
* reverts `NotPoolManager` unless `msg.sender = poolManager` (guard, ImmutableState.sol:16);
* otherwise reverts `HookNotImplemented` (BaseHook.sol:170).
Hence it has no successful run: no storage writes, no return value, no external calls.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm

variable {σ : Type} (ext : Ext σ)

/-- Guard 1: a caller other than the pool manager reverts `NotPoolManager`. -/
theorem afterSwap_notPoolManager (sender : Nat) (key : PoolKey)
    (params : SwapParams) (delta : Int) (hookData : List Nat)
    (env : Env) (w : σ) (h : env.sender ≠ ext.poolManager) :
    BaseHook.afterSwap ext sender key params delta hookData env w
      = .error ⟨"NotPoolManager"⟩ := by
  simp [BaseHook.afterSwap, ImmutableState.onlyPoolManager, h]

/-- Past the guard, the unimplemented hook reverts `HookNotImplemented`. -/
theorem afterSwap_hookNotImplemented (sender : Nat) (key : PoolKey)
    (params : SwapParams) (delta : Int) (hookData : List Nat)
    (env : Env) (w : σ) (h : env.sender = ext.poolManager) :
    BaseHook.afterSwap ext sender key params delta hookData env w
      = .error ⟨"HookNotImplemented"⟩ := by
  simp [BaseHook.afterSwap, ImmutableState.onlyPoolManager, BaseHook.«_afterSwap», h]

/-- Exact behaviour: it always reverts, with the error determined by the caller. -/
theorem afterSwap_spec (sender : Nat) (key : PoolKey)
    (params : SwapParams) (delta : Int) (hookData : List Nat)
    (env : Env) (w : σ) :
    BaseHook.afterSwap ext sender key params delta hookData env w
      = .error (if env.sender = ext.poolManager then ⟨"HookNotImplemented"⟩
                else ⟨"NotPoolManager"⟩) := by
  by_cases h : env.sender = ext.poolManager
  · simp only [afterSwap_hookNotImplemented ext sender key params delta hookData env w h,
      h, ite_true]
  · simp only [afterSwap_notPoolManager ext sender key params delta hookData env w h,
      h, ite_false]

/-- No successful run: hence no storage writes and no return value. -/
theorem afterSwap_never_ok (sender : Nat) (key : PoolKey)
    (params : SwapParams) (delta : Int) (hookData : List Nat)
    (env : Env) (w : σ) (r : Nat × Int) (w' : σ) :
    BaseHook.afterSwap ext sender key params delta hookData env w ≠ .ok (r, w') := by
  rw [afterSwap_spec]
  intro h; cases h

end AsyncSwap.Swarm
