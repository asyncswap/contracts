import Generated.AsyncSwap
import Refinement.Monad

/-!
# `AsyncSwap.transferOwnership`

`function transferOwnership(address newOwner) external onlyOwner` (src/AsyncSwap.sol:156):
reverts with `NotOwner` unless `msg.sender = owner`, then with `ZeroAddress` if `newOwner = 0`;
otherwise it writes exactly `pendingOwner := newOwner` and nothing else (in particular `owner`
is unchanged).
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm

variable {σ : Type} (ext : Ext σ)

/-- Full characterization of `transferOwnership`: two guards in order, then one write. -/
theorem transferOwnership_run (newOwner : Nat) (env : Env) (w : σ) :
    AsyncSwap.transferOwnership ext newOwner env w =
      if env.sender ≠ (ext.get w).owner then .error ⟨"NotOwner"⟩
      else if newOwner = 0 then .error ⟨"ZeroAddress"⟩
      else .ok ((), ext.set w { ext.get w with pendingOwner := newOwner }) := by
  by_cases h1 : env.sender = (ext.get w).owner <;>
  by_cases h2 : newOwner = 0 <;>
  simp [AsyncSwap.transferOwnership, AsyncSwap.onlyOwner, h1, h2]

/-- Non-owner callers revert with `NotOwner`. -/
theorem transferOwnership_notOwner (newOwner : Nat) (env : Env) (w : σ)
    (h : env.sender ≠ (ext.get w).owner) :
    AsyncSwap.transferOwnership ext newOwner env w = .error ⟨"NotOwner"⟩ := by
  rw [transferOwnership_run]; simp [h]

/-- The owner passing the zero address reverts with `ZeroAddress`. -/
theorem transferOwnership_zero (env : Env) (w : σ)
    (h : env.sender = (ext.get w).owner) :
    AsyncSwap.transferOwnership ext 0 env w = .error ⟨"ZeroAddress"⟩ := by
  rw [transferOwnership_run]; simp [h]

/-- Success iff `msg.sender = owner` and `newOwner ≠ 0`; then the only write is
`pendingOwner := newOwner`. -/
theorem transferOwnership_ok_iff (newOwner : Nat) (env : Env) (w w' : σ) :
    AsyncSwap.transferOwnership ext newOwner env w = .ok ((), w') ↔
      env.sender = (ext.get w).owner ∧ newOwner ≠ 0 ∧
        w' = ext.set w { ext.get w with pendingOwner := newOwner } := by
  rw [transferOwnership_run]
  by_cases h1 : env.sender = (ext.get w).owner <;>
  by_cases h2 : newOwner = 0 <;> simp [h1, h2, eq_comm]

/-- Reverts (with some reason) exactly when the guards fail. -/
theorem transferOwnership_reverts_iff (newOwner : Nat) (env : Env) (w : σ) :
    (∃ e, AsyncSwap.transferOwnership ext newOwner env w = .error e) ↔
      (env.sender ≠ (ext.get w).owner ∨ newOwner = 0) := by
  rw [transferOwnership_run]
  by_cases h1 : env.sender = (ext.get w).owner <;>
  by_cases h2 : newOwner = 0 <;> simp [h1, h2]

/-- On success, read back through a lawful `ext`: `pendingOwner = newOwner` and `owner` is
unchanged, as is every other field. -/
theorem transferOwnership_ok_state (newOwner : Nat) (env : Env) (w w' : σ)
    (hget : ∀ w s, ext.get (ext.set w s) = s)
    (hok : AsyncSwap.transferOwnership ext newOwner env w = .ok ((), w')) :
    ext.get w' = { ext.get w with pendingOwner := newOwner } ∧
      (ext.get w').pendingOwner = newOwner ∧ (ext.get w').owner = (ext.get w).owner := by
  obtain ⟨-, -, rfl⟩ := (transferOwnership_ok_iff ext newOwner env w w').1 hok
  simp [hget]

end AsyncSwap.Swarm
