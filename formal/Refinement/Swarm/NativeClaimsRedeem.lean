import Generated.NativeClaims
import Refinement.Monad

/-!
# `NativeClaims.redeem`

`function redeem(address recipient, uint256 amount) external nonReentrant` (src/NativeClaims.sol:30).

* reverts `ReentrantRedemption` when `_redeeming` is already set (the modifier runs first);
* else reverts `InvalidRedemption` when `recipient == 0 || amount == 0`;
* else calls `poolManager.unlock(abi.encode(msg.sender, recipient, amount))` from a world where
  `_redeeming = true`, propagates any revert of that call, and on success clears `_redeeming`.

For the maintainer's "fill/burn somebody else's funds" concern: the owner word handed to the pool
manager is always `msg.sender` — no argument lets a caller name another owner — and any re-entry
into `redeem` during the call reverts.
-/

open FormalAst Refinement

namespace NativeClaims.Swarm

variable {σ : Type} (ext : Ext σ)

/-- The world the external call sees: `_redeeming` set by the modifier. -/
def locked (w : σ) : σ := ext.set w { ext.get w with «_redeeming» := true }

/-- Full characterization of a run (no lawfulness assumed on `ext`). -/
theorem redeem_run (env : Env) (w : σ) (recipient amount : Nat) :
    NativeClaims.redeem ext recipient amount env w =
      if (ext.get w).«_redeeming» = true then .error ⟨"ReentrantRedemption"⟩
      else if recipient = 0 ∨ amount = 0 then .error ⟨"InvalidRedemption"⟩
      else
        match ext.call_IPoolManager_unlock ext.poolManager
            (abiEncode [env.sender, recipient, amount]) env (locked ext w) with
        | .ok (_, w1) => .ok ((), ext.set w1 { ext.get w1 with «_redeeming» := false })
        | .error e => .error e := by
  unfold NativeClaims.redeem NativeClaims.nonReentrant locked
  by_cases h : (ext.get w).«_redeeming» = true
  · simp [h]
  · by_cases hg : recipient = 0 ∨ amount = 0
    · rcases hg with hg | hg <;> simp [h, hg]
    · have h1 : recipient ≠ 0 := fun e => hg (Or.inl e)
      have h2 : amount ≠ 0 := fun e => hg (Or.inr e)
      simp only [h, h1, h2, Bool.false_eq_true, ite_false, run_bind, run_get, run_modify,
        run_read, run_pure, run_ite, run_throw, beq_iff_eq, Bool.or_eq_true, or_self]
      cases ext.call_IPoolManager_unlock ext.poolManager (abiEncode [env.sender, recipient, amount])
          env (ext.set w { ext.get w with «_redeeming» := true }) with
      | error e => rfl
      | ok p => rfl

/-- Guard 1 (the modifier): a re-entrant call reverts with `ReentrantRedemption`. -/
theorem redeem_reentrant (env : Env) (w : σ) (recipient amount : Nat)
    (h : (ext.get w).«_redeeming» = true) :
    NativeClaims.redeem ext recipient amount env w = .error ⟨"ReentrantRedemption"⟩ := by
  rw [redeem_run]; simp [h]

/-- Guard 2: a zero recipient or a zero amount reverts with `InvalidRedemption`. -/
theorem redeem_invalid (env : Env) (w : σ) (recipient amount : Nat)
    (h : (ext.get w).«_redeeming» = false) (hg : recipient = 0 ∨ amount = 0) :
    NativeClaims.redeem ext recipient amount env w = .error ⟨"InvalidRedemption"⟩ := by
  rw [redeem_run]; simp [h, hg]

/-- Success implies both guards passed and the pool-manager call succeeded, with exactly
`abi.encode(msg.sender, recipient, amount)` as payload (the owner is always the caller), from the
locked world; the final world is that call's world with `_redeeming` cleared. -/
theorem redeem_ok (env : Env) (w w' : σ) (recipient amount : Nat)
    (hok : NativeClaims.redeem ext recipient amount env w = .ok ((), w')) :
    (ext.get w).«_redeeming» = false ∧ recipient ≠ 0 ∧ amount ≠ 0 ∧
      ∃ r w1, ext.call_IPoolManager_unlock ext.poolManager
          (abiEncode [env.sender, recipient, amount]) env (locked ext w) = .ok (r, w1) ∧
        w' = ext.set w1 { ext.get w1 with «_redeeming» := false } := by
  rw [redeem_run] at hok
  by_cases h : (ext.get w).«_redeeming» = true
  · simp [h] at hok
  · by_cases hg : recipient = 0 ∨ amount = 0
    · simp [h, hg] at hok
    · simp only [h, hg, ite_false, Bool.false_eq_true] at hok
      refine ⟨by simpa using h, fun e => hg (Or.inl e), fun e => hg (Or.inr e), ?_⟩
      revert hok
      cases ext.call_IPoolManager_unlock ext.poolManager (abiEncode [env.sender, recipient, amount])
          env (locked ext w) with
      | error e => intro hok; cases hok
      | ok p => intro hok; cases hok; exact ⟨p.1, p.2, rfl, rfl⟩

/-- Revert characterization: `redeem` reverts iff `_redeeming`, or a zero argument, or the
pool-manager call (made with owner = `msg.sender`) reverts. -/
theorem redeem_reverts_iff (env : Env) (w : σ) (recipient amount : Nat) :
    (∃ e, NativeClaims.redeem ext recipient amount env w = .error e) ↔
      ((ext.get w).«_redeeming» = true ∨ recipient = 0 ∨ amount = 0 ∨
        ∃ e, ext.call_IPoolManager_unlock ext.poolManager
          (abiEncode [env.sender, recipient, amount]) env (locked ext w) = .error e) := by
  rw [redeem_run]
  by_cases h : (ext.get w).«_redeeming» = true
  · simp [h]
  · by_cases hg : recipient = 0 ∨ amount = 0
    · rcases hg with hg | hg <;> simp [h, hg]
    · have h1 : recipient ≠ 0 := fun e => hg (Or.inl e)
      have h2 : amount ≠ 0 := fun e => hg (Or.inr e)
      simp only [h, h1, h2, ite_false, Bool.false_eq_true, false_or]
      cases ext.call_IPoolManager_unlock ext.poolManager (abiEncode [env.sender, recipient, amount])
          env (locked ext w) with
      | error e => simp
      | ok p => simp

/-- Footprint, through a lawful `ext`: the call runs with `_redeeming = true` (so any re-entry into
`redeem` reverts, by `redeem_reentrant`), and on success `_redeeming` is `false` again (it is the
contract's only storage field). -/
theorem redeem_ok_state (env : Env) (w w' : σ) (recipient amount : Nat)
    (hget : ∀ w s, ext.get (ext.set w s) = s)
    (hok : NativeClaims.redeem ext recipient amount env w = .ok ((), w')) :
    (ext.get (locked ext w)).«_redeeming» = true ∧ (ext.get w').«_redeeming» = false := by
  obtain ⟨-, -, -, r, w1, -, rfl⟩ := redeem_ok ext env w w' recipient amount hok
  exact ⟨by simp [locked, hget], by simp [hget]⟩

/-- Re-entrancy: any nested `NativeClaims.redeem` run from the locked world the call sees reverts. -/
theorem redeem_nested_reverts (env' : Env) (w : σ) (r' a' : Nat)
    (hget : ∀ w s, ext.get (ext.set w s) = s) :
    NativeClaims.redeem ext r' a' env' (locked ext w) = .error ⟨"ReentrantRedemption"⟩ :=
  redeem_reentrant ext env' _ r' a' (by simp [locked, hget])

end NativeClaims.Swarm
