import Generated.TokenClaims
import Refinement.Monad
open FormalAst Refinement

namespace TokenClaims.Swarm.Redeem
variable {σ : Type} (ext : Ext σ)

/-- Guard 1 (`nonReentrant`): a redemption already in progress reverts `ReentrantRedemption`. -/
theorem redeem_reentrant (currency recipient amount : Nat) (env : Env) (w : σ)
    (h : (ext.get w).«_redeeming» = true) :
    TokenClaims.redeem ext currency recipient amount env w = .error ⟨"ReentrantRedemption"⟩ := by
  simp [TokenClaims.redeem, TokenClaims.nonReentrant, h]

/-- Guard 2: a zero recipient or a zero amount reverts `InvalidRedemption` (before any external call). -/
theorem redeem_invalid (currency recipient amount : Nat) (env : Env) (w : σ)
    (h : (ext.get w).«_redeeming» = false) (hz : recipient = 0 ∨ amount = 0) :
    TokenClaims.redeem ext currency recipient amount env w = .error ⟨"InvalidRedemption"⟩ := by
  rcases hz with hz | hz <;> simp [TokenClaims.redeem, TokenClaims.nonReentrant, h, hz]

/-- Success path: with both guards passed, `redeem` sets `_redeeming := true`, calls
`poolManager.unlock(abi.encode(msg.sender, currency, recipient, amount))`, propagates its revert,
and otherwise clears `_redeeming` in the world the call returned. Nothing else is written. -/
theorem redeem_call (currency recipient amount : Nat) (env : Env) (w : σ)
    (h : (ext.get w).«_redeeming» = false) (hr : recipient ≠ 0) (ha : amount ≠ 0) :
    TokenClaims.redeem ext currency recipient amount env w =
      (match ext.call_IPoolManager_unlock ext.poolManager
          (abiEncode [env.sender, currency, recipient, amount]) env
          (ext.set w { ext.get w with «_redeeming» := true }) with
        | .ok (_, w₂) => .ok ((), ext.set w₂ { ext.get w₂ with «_redeeming» := false })
        | .error e => .error e) := by
  simp only [TokenClaims.redeem, TokenClaims.nonReentrant, run_bind, run_get, run_pure,
    run_modify, h, Bool.false_eq_true, ite_false]
  cases hc : ext.call_IPoolManager_unlock ext.poolManager
      (abiEncode [env.sender, currency, recipient, amount]) env
      (ext.set w { ext.get w with «_redeeming» := true }) with
  | error e => simp [hr, ha, hc]
  | ok p => simp [hr, ha, hc]

/-- Revert characterization: `redeem` reverts without reaching the external call exactly when a
redemption is in progress or the recipient or amount is zero. -/
theorem redeem_guard_reverts (currency recipient amount : Nat) (env : Env) (w : σ) :
    ((ext.get w).«_redeeming» = true ∨ recipient = 0 ∨ amount = 0) →
    ∃ e, TokenClaims.redeem ext currency recipient amount env w = .error e := by
  intro hg
  cases hb : (ext.get w).«_redeeming» with
  | true => exact ⟨_, redeem_reentrant ext currency recipient amount env w hb⟩
  | false =>
    have hz : recipient = 0 ∨ amount = 0 := by
      rcases hg with hg | hg
      · rw [hb] at hg; cases hg
      · exact hg
    exact ⟨_, redeem_invalid ext currency recipient amount env w hb hz⟩

end TokenClaims.Swarm.Redeem
