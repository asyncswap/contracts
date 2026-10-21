import Generated.AsyncSwap
import Refinement.Monad

/-!
# `BaseHook.beforeAddLiquidity` (AsyncSwap, src/BaseHook.sol:61)

* Guard: reverts `NotPoolManager` unless `msg.sender = poolManager` (ImmutableState.sol:16).
* Otherwise returns `beforeAddLiquidity.selector = 0x259982e5` (from the pure
  `AsyncSwap._beforeAddLiquidity`) and leaves the state unchanged (footprint: writes nothing).
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.BeforeAddLiquidity

variable {σ : Type} (ext : Ext σ)

/-- Guard: a caller other than the pool manager reverts `NotPoolManager`. -/
theorem beforeAddLiquidity_notPoolManager (sender : Nat) (key : PoolKey)
    (params : ModifyLiquidityParams) (hd : List Nat) (env : Env) (w : σ)
    (h : env.sender ≠ ext.poolManager) :
    BaseHook.beforeAddLiquidity ext sender key params hd env w = .error ⟨"NotPoolManager"⟩ := by
  simp [BaseHook.beforeAddLiquidity, ImmutableState.onlyPoolManager, h]

/-- Success: from the pool manager it returns the selector `0x259982e5` and writes nothing. -/
theorem beforeAddLiquidity_ok (sender : Nat) (key : PoolKey)
    (params : ModifyLiquidityParams) (hd : List Nat) (env : Env) (w : σ)
    (h : env.sender = ext.poolManager) :
    BaseHook.beforeAddLiquidity ext sender key params hd env w = .ok (0x259982e5, w) := by
  simp [BaseHook.beforeAddLiquidity, ImmutableState.onlyPoolManager,
    AsyncSwap.«_beforeAddLiquidity», h]

/-- Full spec: reverts iff the caller is not the pool manager; otherwise returns the selector
with the state unchanged. -/
theorem beforeAddLiquidity_spec (sender : Nat) (key : PoolKey)
    (params : ModifyLiquidityParams) (hd : List Nat) (env : Env) (w : σ) :
    BaseHook.beforeAddLiquidity ext sender key params hd env w =
      if env.sender = ext.poolManager then .ok (0x259982e5, w)
      else .error ⟨"NotPoolManager"⟩ := by
  by_cases h : env.sender = ext.poolManager
  · simp only [h, ↓reduceIte]
    exact beforeAddLiquidity_ok ext sender key params hd env w h
  · simp only [h, ↓reduceIte]
    exact beforeAddLiquidity_notPoolManager ext sender key params hd env w h

/-- Footprint: any successful run leaves the state unchanged and returns the selector. -/
theorem beforeAddLiquidity_frame (sender : Nat) (key : PoolKey)
    (params : ModifyLiquidityParams) (hd : List Nat) (env : Env) (w w' : σ) (r : Nat)
    (h : BaseHook.beforeAddLiquidity ext sender key params hd env w = .ok (r, w')) :
    w' = w ∧ r = 0x259982e5 ∧ env.sender = ext.poolManager := by
  rw [beforeAddLiquidity_spec] at h
  split at h
  · cases h; exact ⟨rfl, rfl, by assumption⟩
  · cases h

end AsyncSwap.Swarm.BeforeAddLiquidity
