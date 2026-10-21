import Generated.AsyncSwap
import Refinement.Monad

/-!
# `BaseHook.afterDonate` (AsyncSwap, src/BaseHook.sol:198)

* Guard: reverts `NotPoolManager` unless `msg.sender = poolManager` (ImmutableState.sol:16).
* Otherwise it calls the non-overridden `BaseHook._afterDonate`, which reverts
  `HookNotImplemented`. So the function never succeeds: it has no successful run, hence
  writes nothing and returns nothing (footprint: writes nothing, no external calls).
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.AfterDonate

variable {σ : Type} (ext : Ext σ)

/-- Guard: a caller other than the pool manager reverts `NotPoolManager`. -/
theorem afterDonate_notPoolManager (sender : Nat) (key : PoolKey) (a0 a1 : Nat)
    (hd : List Nat) (env : Env) (w : σ) (h : env.sender ≠ ext.poolManager) :
    BaseHook.afterDonate ext sender key a0 a1 hd env w = .error ⟨"NotPoolManager"⟩ := by
  simp [BaseHook.afterDonate, ImmutableState.onlyPoolManager, h]

/-- From the pool manager, the unimplemented hook reverts `HookNotImplemented`. -/
theorem afterDonate_poolManager (sender : Nat) (key : PoolKey) (a0 a1 : Nat)
    (hd : List Nat) (env : Env) (w : σ) (h : env.sender = ext.poolManager) :
    BaseHook.afterDonate ext sender key a0 a1 hd env w = .error ⟨"HookNotImplemented"⟩ := by
  simp [BaseHook.afterDonate, ImmutableState.onlyPoolManager,
    BaseHook.«_afterDonate», h]

/-- Full spec: it always reverts, with `NotPoolManager` or `HookNotImplemented`. -/
theorem afterDonate_spec (sender : Nat) (key : PoolKey) (a0 a1 : Nat)
    (hd : List Nat) (env : Env) (w : σ) :
    BaseHook.afterDonate ext sender key a0 a1 hd env w =
      if env.sender = ext.poolManager then .error ⟨"HookNotImplemented"⟩
      else .error ⟨"NotPoolManager"⟩ := by
  by_cases h : env.sender = ext.poolManager
  · simp only [h, ↓reduceIte]
    exact afterDonate_poolManager ext sender key a0 a1 hd env w h
  · simp only [h, ↓reduceIte]
    exact afterDonate_notPoolManager ext sender key a0 a1 hd env w h

/-- Footprint: there is no successful run (so no storage is ever written). -/
theorem afterDonate_never_ok (sender : Nat) (key : PoolKey) (a0 a1 : Nat)
    (hd : List Nat) (env : Env) (w w' : σ) (r : Nat) :
    BaseHook.afterDonate ext sender key a0 a1 hd env w ≠ .ok (r, w') := by
  rw [afterDonate_spec]
  split <;> simp

end AsyncSwap.Swarm.AfterDonate
