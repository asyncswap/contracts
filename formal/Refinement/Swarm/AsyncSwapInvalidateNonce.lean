import Generated.AsyncSwap
import Refinement.Monad

/-!
# `AsyncSwap.invalidateNonce`

`function invalidateNonce(uint256 nonce) external` (src/AsyncSwap.sol:576): reverts with
`NonceAlreadyUsed` iff `nonceUsed[msg.sender][nonce]`; otherwise sets exactly that entry to `true`
and leaves every other entry (other nonces of the caller, every other maker) and every other field
unchanged.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm

variable {σ : Type} (ext : Ext σ)

/-- Full characterization (no lawfulness assumed on `ext`): one guard, then one write. -/
theorem invalidateNonce_run (env : Env) (w : σ) (nonce : Nat) :
    AsyncSwap.invalidateNonce ext nonce env w =
      if (ext.get w).nonceUsed env.sender nonce = true then .error ⟨"NonceAlreadyUsed"⟩
      else
        .ok ((), ext.set w { ext.get w with
          nonceUsed := upd (ext.get w).nonceUsed env.sender
            (upd ((ext.get w).nonceUsed env.sender) nonce true) }) := by
  by_cases h : (ext.get w).nonceUsed env.sender nonce = true <;>
  simp [AsyncSwap.invalidateNonce, h]

/-- Reverts (with some reason) exactly when `nonceUsed[msg.sender][nonce]` is already set. -/
theorem invalidateNonce_reverts_iff (env : Env) (w : σ) (nonce : Nat) :
    (∃ e, AsyncSwap.invalidateNonce ext nonce env w = .error e) ↔
      (ext.get w).nonceUsed env.sender nonce = true := by
  rw [invalidateNonce_run]
  by_cases h : (ext.get w).nonceUsed env.sender nonce = true <;> simp [h]

/-- The revert reason is `NonceAlreadyUsed`. -/
theorem invalidateNonce_used (env : Env) (w : σ) (nonce : Nat)
    (h : (ext.get w).nonceUsed env.sender nonce = true) :
    AsyncSwap.invalidateNonce ext nonce env w = .error ⟨"NonceAlreadyUsed"⟩ := by
  rw [invalidateNonce_run]; simp [h]

/-- Succeeds exactly when the nonce is unused. -/
theorem invalidateNonce_ok_iff (env : Env) (w : σ) (nonce : Nat) :
    (∃ w', AsyncSwap.invalidateNonce ext nonce env w = .ok ((), w')) ↔
      (ext.get w).nonceUsed env.sender nonce = false := by
  rw [invalidateNonce_run]
  by_cases h : (ext.get w).nonceUsed env.sender nonce = true <;> simp_all

/-- On success, read back through a lawful `ext` (`get ∘ set = id`): the caller's `nonce` is now
used, every other `(maker, n)` entry is unchanged, and so is every other storage field. -/
theorem invalidateNonce_ok_state (env : Env) (w w' : σ) (nonce : Nat)
    (hget : ∀ w s, ext.get (ext.set w s) = s)
    (hok : AsyncSwap.invalidateNonce ext nonce env w = .ok ((), w')) :
    (ext.get w).nonceUsed env.sender nonce = false ∧
      (ext.get w').nonceUsed env.sender nonce = true ∧
      (∀ maker n, (maker ≠ env.sender ∨ n ≠ nonce) →
        (ext.get w').nonceUsed maker n = (ext.get w).nonceUsed maker n) ∧
      ext.get w' = { ext.get w with nonceUsed := (ext.get w').nonceUsed } := by
  rw [invalidateNonce_run] at hok
  by_cases h : (ext.get w).nonceUsed env.sender nonce = true
  · simp [h] at hok
  · simp only [h, Bool.false_eq_true, ↓reduceIte] at hok
    cases hok
    refine ⟨by simpa using h, by simp [hget, upd], ?_, by simp [hget]⟩
    intro maker n hne
    rcases hne with hm | hn
    · simp [hget, upd, hm]
    · by_cases hm : maker = env.sender
      · subst hm; simp [hget, upd, hn]
      · simp [hget, upd, hm]

/-- Other callers' nonces are untouched: for any `maker ≠ msg.sender`, the whole row
`nonceUsed[maker]` is unchanged on success. -/
theorem invalidateNonce_other_maker (env : Env) (w w' : σ) (nonce maker : Nat)
    (hget : ∀ w s, ext.get (ext.set w s) = s)
    (hok : AsyncSwap.invalidateNonce ext nonce env w = .ok ((), w'))
    (hm : maker ≠ env.sender) :
    (ext.get w').nonceUsed maker = (ext.get w).nonceUsed maker := by
  funext n
  exact (invalidateNonce_ok_state ext env w w' nonce hget hok).2.2.1 maker n (Or.inl hm)

end AsyncSwap.Swarm
