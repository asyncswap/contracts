import Generated.AsyncSwap
import Refinement.Monad

/-!
# `AsyncSwap.acceptOwnership`

`function acceptOwnership() external` (src/AsyncSwap.sol:163): reverts with `NotOwner` unless
`msg.sender = pendingOwner`; otherwise writes `owner := msg.sender`, then `pendingOwner := 0`,
and nothing else.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm

variable {σ : Type} (ext : Ext σ)

/-- Full characterization of `acceptOwnership` (no lawfulness assumed on `ext`): one guard,
then the two writes in order. -/
theorem acceptOwnership_run (env : Env) (w : σ) :
    AsyncSwap.acceptOwnership ext env w =
      if env.sender ≠ (ext.get w).pendingOwner then .error ⟨"NotOwner"⟩
      else
        let w1 := ext.set w { ext.get w with owner := env.sender }
        .ok ((), ext.set w1 { ext.get w1 with pendingOwner := 0 }) := by
  by_cases h : env.sender = (ext.get w).pendingOwner <;>
  simp [AsyncSwap.acceptOwnership, h]

/-- Callers other than `pendingOwner` revert with `NotOwner`. -/
theorem acceptOwnership_notPending (env : Env) (w : σ)
    (h : env.sender ≠ (ext.get w).pendingOwner) :
    AsyncSwap.acceptOwnership ext env w = .error ⟨"NotOwner"⟩ := by
  rw [acceptOwnership_run]; simp [h]

/-- Reverts (with some reason) exactly when `msg.sender ≠ pendingOwner`. -/
theorem acceptOwnership_reverts_iff (env : Env) (w : σ) :
    (∃ e, AsyncSwap.acceptOwnership ext env w = .error e) ↔
      env.sender ≠ (ext.get w).pendingOwner := by
  rw [acceptOwnership_run]
  by_cases h : env.sender = (ext.get w).pendingOwner <;> simp [h]

/-- With a lawful `ext` (`get ∘ set = id`, `set` overwrites), success happens iff
`msg.sender = pendingOwner`, and the resulting world is a single write of
`owner := msg.sender, pendingOwner := 0` with every other field unchanged. -/
theorem acceptOwnership_ok_iff (env : Env) (w w' : σ)
    (hget : ∀ w s, ext.get (ext.set w s) = s)
    (hset : ∀ w s t, ext.set (ext.set w s) t = ext.set w t) :
    AsyncSwap.acceptOwnership ext env w = .ok ((), w') ↔
      env.sender = (ext.get w).pendingOwner ∧
        w' = ext.set w { ext.get w with owner := env.sender, pendingOwner := 0 } := by
  rw [acceptOwnership_run]
  by_cases h : env.sender = (ext.get w).pendingOwner <;> simp [h, hget, hset, eq_comm]

/-- On success, read back through a lawful `ext`: `owner = msg.sender` (the old
`pendingOwner`) and `pendingOwner = 0`. Needs only `get ∘ set = id`. -/
theorem acceptOwnership_ok_state (env : Env) (w w' : σ)
    (hget : ∀ w s, ext.get (ext.set w s) = s)
    (hok : AsyncSwap.acceptOwnership ext env w = .ok ((), w')) :
    env.sender = (ext.get w).pendingOwner ∧
      ext.get w' = { ext.get w with owner := env.sender, pendingOwner := 0 } ∧
      (ext.get w').owner = env.sender ∧ (ext.get w').pendingOwner = 0 := by
  rw [acceptOwnership_run] at hok
  by_cases h : env.sender = (ext.get w).pendingOwner
  · simp [h, hget] at hok
    subst hok
    simp [h, hget]
  · simp [h] at hok

end AsyncSwap.Swarm
