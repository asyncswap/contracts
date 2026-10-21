import Generated.AsyncSwap
import Refinement.Monad

/-!
# `AsyncSwap.setOrderingMode`

`function setOrderingMode(PoolKey calldata key, OrderingMode mode) external onlyOwner`
(src/AsyncSwap.sol:247): reverts with `NotOwner` unless `msg.sender = owner`, then with
`InvalidOrderingModeChange` if the pool's book still has open orders; otherwise the only write is
`priceBooks[poolId].orderingMode := mode` with `poolId = key.toId()`.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm

variable {σ : Type} (ext : Ext σ)

/-- The pool id computed by `PoolIdLibrary.toId` in the model. -/
def setOrderingMode_poolId (key : PoolKey) : Nat :=
  ext.keccak [key.currency0, key.currency1, key.fee, toUnsigned 256 key.tickSpacing, key.hooks]

/-- Full characterization of `setOrderingMode`: owner guard, open-order guard, one write. -/
theorem setOrderingMode_run (key : PoolKey) (mode : Nat) (env : Env) (w : σ) :
    AsyncSwap.setOrderingMode ext key mode env w =
      if env.sender ≠ (ext.get w).owner then .error ⟨"NotOwner"⟩
      else if ((ext.get w).priceBooks (setOrderingMode_poolId ext key)).openOrderCount ≠ 0 then
        .error ⟨"InvalidOrderingModeChange"⟩
      else .ok ((), ext.set w { ext.get w with
        priceBooks := upd (ext.get w).priceBooks (setOrderingMode_poolId ext key)
          { (ext.get w).priceBooks (setOrderingMode_poolId ext key) with orderingMode := mode } }) := by
  by_cases h1 : env.sender = (ext.get w).owner <;>
  by_cases h2 : ((ext.get w).priceBooks (setOrderingMode_poolId ext key)).openOrderCount = 0 <;>
  simp_all [AsyncSwap.setOrderingMode, AsyncSwap.onlyOwner, AsyncMatching.setOrderingMode,
    AsyncFiller.setOrderingMode, PoolIdLibrary.toId, setOrderingMode_poolId]

/-- Non-owner callers revert with `NotOwner`. -/
theorem setOrderingMode_notOwner (key : PoolKey) (mode : Nat) (env : Env) (w : σ)
    (h : env.sender ≠ (ext.get w).owner) :
    AsyncSwap.setOrderingMode ext key mode env w = .error ⟨"NotOwner"⟩ := by
  rw [setOrderingMode_run]; simp [h]

/-- Any successful call was made by the owner. -/
theorem setOrderingMode_ok_owner (key : PoolKey) (mode : Nat) (env : Env) (w w' : σ)
    (hok : AsyncSwap.setOrderingMode ext key mode env w = .ok ((), w')) :
    env.sender = (ext.get w).owner := by
  by_cases h : env.sender = (ext.get w).owner
  · exact h
  · rw [setOrderingMode_notOwner ext key mode env w h] at hok
    cases hok

/-- Success iff owner and no open orders; then the only write is to `priceBooks[poolId]`. -/
theorem setOrderingMode_ok_iff (key : PoolKey) (mode : Nat) (env : Env) (w w' : σ) :
    AsyncSwap.setOrderingMode ext key mode env w = .ok ((), w') ↔
      env.sender = (ext.get w).owner ∧
      ((ext.get w).priceBooks (setOrderingMode_poolId ext key)).openOrderCount = 0 ∧
      w' = ext.set w { ext.get w with
        priceBooks := upd (ext.get w).priceBooks (setOrderingMode_poolId ext key)
          { (ext.get w).priceBooks (setOrderingMode_poolId ext key) with orderingMode := mode } } := by
  rw [setOrderingMode_run]
  by_cases h1 : env.sender = (ext.get w).owner <;>
  by_cases h2 : ((ext.get w).priceBooks (setOrderingMode_poolId ext key)).openOrderCount = 0 <;>
  simp [h1, h2, eq_comm]

/-- On success (lawful `ext`): every field except `priceBooks` is unchanged, every other
pool's book is unchanged, and the pool's book differs only in `orderingMode := mode`. -/
theorem setOrderingMode_ok_state (key : PoolKey) (mode : Nat) (env : Env) (w w' : σ)
    (hget : ∀ w s, ext.get (ext.set w s) = s)
    (hok : AsyncSwap.setOrderingMode ext key mode env w = .ok ((), w')) :
    (∃ pb, ext.get w' = { ext.get w with priceBooks := pb }) ∧
      (∀ p, p ≠ setOrderingMode_poolId ext key →
        (ext.get w').priceBooks p = (ext.get w).priceBooks p) ∧
      (ext.get w').priceBooks (setOrderingMode_poolId ext key) =
        { (ext.get w).priceBooks (setOrderingMode_poolId ext key) with orderingMode := mode } := by
  obtain ⟨-, -, rfl⟩ := (setOrderingMode_ok_iff ext key mode env w w').1 hok
  refine ⟨⟨_, by rw [hget]⟩, fun p hp => ?_, ?_⟩
  · simp [hget, upd, hp]
  · simp [hget, upd]

end AsyncSwap.Swarm
