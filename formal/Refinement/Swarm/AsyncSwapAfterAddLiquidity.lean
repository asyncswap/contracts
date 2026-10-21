import Generated.AsyncSwap
import Refinement.Monad

/-!
# `BaseHook.afterAddLiquidity` (AsyncSwap, src/BaseHook.sol:97)

* Guard: reverts `NotPoolManager` unless `msg.sender = poolManager` (ImmutableState.sol:16).
* Otherwise the body `_afterAddLiquidity` is not overridden by AsyncSwap and reverts
  `HookNotImplemented` (src/BaseHook.sol:108). So the function never succeeds: it writes
  nothing and returns nothing (footprint: writes nothing, no external calls).
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.AfterAddLiquidity

variable {σ : Type} (ext : Ext σ)

/-- Guard: a caller other than the pool manager reverts `NotPoolManager`. -/
theorem afterAddLiquidity_notPoolManager (sender : Nat) (key : PoolKey)
    (params : ModifyLiquidityParams) (delta fees : Int) (hd : List Nat) (env : Env) (w : σ)
    (h : env.sender ≠ ext.poolManager) :
    BaseHook.afterAddLiquidity ext sender key params delta fees hd env w =
      .error ⟨"NotPoolManager"⟩ := by
  simp [BaseHook.afterAddLiquidity, ImmutableState.onlyPoolManager, h]

/-- From the pool manager, the unimplemented hook body reverts `HookNotImplemented`. -/
theorem afterAddLiquidity_poolManager (sender : Nat) (key : PoolKey)
    (params : ModifyLiquidityParams) (delta fees : Int) (hd : List Nat) (env : Env) (w : σ)
    (h : env.sender = ext.poolManager) :
    BaseHook.afterAddLiquidity ext sender key params delta fees hd env w =
      .error ⟨"HookNotImplemented"⟩ := by
  simp [BaseHook.afterAddLiquidity, ImmutableState.onlyPoolManager,
    BaseHook.«_afterAddLiquidity», h]

/-- Full spec: the call always reverts, with `NotPoolManager` or `HookNotImplemented`. -/
theorem afterAddLiquidity_spec (sender : Nat) (key : PoolKey)
    (params : ModifyLiquidityParams) (delta fees : Int) (hd : List Nat) (env : Env) (w : σ) :
    BaseHook.afterAddLiquidity ext sender key params delta fees hd env w =
      if env.sender = ext.poolManager then .error ⟨"HookNotImplemented"⟩
      else .error ⟨"NotPoolManager"⟩ := by
  by_cases h : env.sender = ext.poolManager
  · simp only [h, ↓reduceIte]
    exact afterAddLiquidity_poolManager ext sender key params delta fees hd env w h
  · simp only [h, ↓reduceIte]
    exact afterAddLiquidity_notPoolManager ext sender key params delta fees hd env w h

/-- Footprint: there is no successful run, so no state is ever written. -/
theorem afterAddLiquidity_never_ok (sender : Nat) (key : PoolKey)
    (params : ModifyLiquidityParams) (delta fees : Int) (hd : List Nat) (env : Env)
    (w w' : σ) (r : Nat × Int) :
    BaseHook.afterAddLiquidity ext sender key params delta fees hd env w ≠ .ok (r, w') := by
  rw [afterAddLiquidity_spec]
  split <;> simp

end AsyncSwap.Swarm.AfterAddLiquidity
