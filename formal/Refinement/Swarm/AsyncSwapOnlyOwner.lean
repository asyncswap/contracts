import Generated.AsyncSwap
import Refinement.Monad

/-!
# `AsyncSwap.onlyOwner`

The modifier `if (msg.sender != owner) revert NotOwner(); _;` (src/AsyncSwap.sol:111).
It reverts with `NotOwner` exactly when `msg.sender ≠ owner`, before running the body and
without touching storage; otherwise it runs the body `k` on the unchanged world, so the modifier
itself writes nothing.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm

variable {σ α : Type} [Inhabited α] (ext : Ext σ)

/-- Non-owner: `onlyOwner` reverts with `NotOwner`, whatever the body does. -/
theorem onlyOwner_notOwner (k : M σ α) (env : Env) (w : σ) (h : env.sender ≠ (ext.get w).owner) :
    AsyncSwap.onlyOwner ext k env w = .error ⟨"NotOwner"⟩ := by
  simp [AsyncSwap.onlyOwner, h]

/-- Owner: `onlyOwner` is exactly the body, run on the unchanged world. -/
theorem onlyOwner_owner (k : M σ α) (env : Env) (w : σ) (h : env.sender = (ext.get w).owner) :
    AsyncSwap.onlyOwner ext k env w = k env w := by
  simp only [AsyncSwap.onlyOwner, h, bne_self_eq_false, run_bind, run_read, run_get, run_pure,
    run_ite, Bool.false_eq_true, ite_false]
  cases k env w <;> rfl

/-- The full characterization: the modifier is a guard on `msg.sender = owner` in front of `k`. -/
theorem onlyOwner_run (k : M σ α) (env : Env) (w : σ) :
    AsyncSwap.onlyOwner ext k env w =
      if env.sender = (ext.get w).owner then k env w else .error ⟨"NotOwner"⟩ := by
  split
  · next h => exact onlyOwner_owner ext k env w h
  · next h => exact onlyOwner_notOwner ext k env w h

/-- Reverts with `NotOwner` iff `msg.sender ≠ owner`, for a body that never reverts with `NotOwner`. -/
theorem onlyOwner_reverts_NotOwner_iff (k : M σ α) (env : Env) (w : σ)
    (hk : k env w ≠ .error ⟨"NotOwner"⟩) :
    AsyncSwap.onlyOwner ext k env w = .error ⟨"NotOwner"⟩ ↔ env.sender ≠ (ext.get w).owner := by
  rw [onlyOwner_run]
  by_cases h : env.sender = (ext.get w).owner <;> simp [h, hk]

/-- On success the modifier adds no write: the final world is the one the body produced from `w`. -/
theorem onlyOwner_ok (k : M σ α) (env : Env) (w w' : σ) (a : α)
    (hok : AsyncSwap.onlyOwner ext k env w = .ok (a, w')) :
    env.sender = (ext.get w).owner ∧ k env w = .ok (a, w') := by
  rw [onlyOwner_run] at hok
  split at hok
  · next h => exact ⟨h, hok⟩
  · cases hok

/-- With a trivial body, the modifier leaves storage unchanged when it passes. -/
theorem onlyOwner_pure_storage (a : α) (env : Env) (w w' : σ) (b : α)
    (hok : AsyncSwap.onlyOwner ext (pure a) env w = .ok (b, w')) : w' = w ∧ b = a := by
  obtain ⟨-, hk⟩ := onlyOwner_ok ext (pure a) env w w' b hok
  simp at hk
  exact ⟨hk.2.symm, hk.1.symm⟩

end AsyncSwap.Swarm
