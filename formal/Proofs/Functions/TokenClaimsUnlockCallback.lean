import Specs.TokenClaims
import Proofs.Monad
open FormalAst Refinement

namespace TokenClaims.Swarm.UnlockCallback
variable {σ : Type} (ext : Ext σ)

/-- Guard: a caller other than the PoolManager reverts `OnlyPoolManager`, before any decode or call. -/
theorem unlockCallback_onlyPoolManager (data : List Nat) (env : Env) (w : σ)
    (h : env.sender ≠ ext.poolManager) :
    TokenClaims.unlockCallback ext data env w = .error ⟨"OnlyPoolManager"⟩ := by
  simp [TokenClaims.unlockCallback, h]

/-- Decode: from the PoolManager, calldata shorter than four words reverts `abi.decode`. -/
theorem unlockCallback_short (data : List Nat) (env : Env) (w : σ)
    (h : env.sender = ext.poolManager) (hl : data.length < 128) :
    TokenClaims.unlockCallback ext data env w = .error ⟨"abi.decode"⟩ := by
  simp only [TokenClaims.unlockCallback, abiWordAt, abiUint, CurrencyLibrary.toId, run_bind,
    run_read, run_ite, run_pure, run_throw, h, bne_self_eq_false, Bool.false_eq_true, ite_false,
    List.drop_zero]
  by_cases a1 : 0 + 32 ≤ data.length <;>
  by_cases a2 : bytesWord (data.take 32) < 2 ^ 160 <;>
  by_cases a3 : 32 + 32 ≤ data.length <;>
  by_cases a4 : bytesWord ((data.drop 32).take 32) < 2 ^ 160 <;>
  by_cases a5 : 64 + 32 ≤ data.length <;>
  by_cases a6 : bytesWord ((data.drop 64).take 32) < 2 ^ 160 <;>
  by_cases a7 : 96 + 32 ≤ data.length <;>
  first | omega | simp [a1, a2, a3, a4, a5, a6, a7]

/-- Decode: from the PoolManager, an `owner`, `currency` or `recipient` word that does not fit
160 bits reverts `abi.decode`. -/
theorem unlockCallback_badAddress (data : List Nat) (env : Env) (w : σ)
    (h : env.sender = ext.poolManager)
    (hb : 2 ^ 160 ≤ bytesWord (data.take 32) ∨ 2 ^ 160 ≤ bytesWord ((data.drop 32).take 32)
      ∨ 2 ^ 160 ≤ bytesWord ((data.drop 64).take 32)) :
    TokenClaims.unlockCallback ext data env w = .error ⟨"abi.decode"⟩ := by
  simp only [TokenClaims.unlockCallback, abiWordAt, abiUint, CurrencyLibrary.toId, run_bind,
    run_read, run_ite, run_pure, run_throw, h, bne_self_eq_false, Bool.false_eq_true, ite_false,
    List.drop_zero]
  have hb' : ¬ bytesWord (data.take 32) < 2 ^ 160 ∨ ¬ bytesWord ((data.drop 32).take 32) < 2 ^ 160
      ∨ ¬ bytesWord ((data.drop 64).take 32) < 2 ^ 160 := by
    rcases hb with hb | hb | hb
    · exact Or.inl (Nat.not_lt.mpr hb)
    · exact Or.inr (Or.inl (Nat.not_lt.mpr hb))
    · exact Or.inr (Or.inr (Nat.not_lt.mpr hb))
  by_cases a1 : 0 + 32 ≤ data.length <;>
  by_cases a2 : bytesWord (data.take 32) < 2 ^ 160 <;>
  by_cases a3 : 32 + 32 ≤ data.length <;>
  by_cases a4 : bytesWord ((data.drop 32).take 32) < 2 ^ 160 <;>
  by_cases a5 : 64 + 32 ≤ data.length <;>
  by_cases a6 : bytesWord ((data.drop 64).take 32) < 2 ^ 160 <;>
  by_cases a7 : 96 + 32 ≤ data.length <;>
  simp [a1, a2, a3, a4, a5, a6, a7] at hb' ⊢

/-- Success path: from the PoolManager, with well-formed calldata `(owner, currency, recipient, amount)`,
`unlockCallback` calls `poolManager.burn(owner, currency, amount)` (`toId` is the identity) in the
caller's world, then `poolManager.take(currency, recipient, amount)` in the world `burn` returned, and
returns empty bytes in the world `take` returned; a revert of either call propagates. It writes no
storage of its own. -/
theorem unlockCallback_success (data : List Nat) (env : Env) (w : σ)
    (h : env.sender = ext.poolManager) (hl : 128 ≤ data.length)
    (ho : bytesWord (data.take 32) < 2 ^ 160)
    (hc : bytesWord ((data.drop 32).take 32) < 2 ^ 160)
    (hr : bytesWord ((data.drop 64).take 32) < 2 ^ 160) :
    TokenClaims.unlockCallback ext data env w =
      (match ext.call_IPoolManager_burn ext.poolManager (bytesWord (data.take 32))
          (bytesWord ((data.drop 32).take 32)) (bytesWord ((data.drop 96).take 32)) env w with
        | .ok (_, w₁) =>
          (match ext.call_IPoolManager_take ext.poolManager (bytesWord ((data.drop 32).take 32))
              (bytesWord ((data.drop 64).take 32)) (bytesWord ((data.drop 96).take 32)) env w₁ with
            | .ok (_, w₂) => .ok ([], w₂)
            | .error e => .error e)
        | .error e => .error e) := by
  have h1 : 0 + 32 ≤ data.length := by omega
  have h2 : 32 + 32 ≤ data.length := by omega
  have h3 : 64 + 32 ≤ data.length := by omega
  have h4 : 96 + 32 ≤ data.length := by omega
  simp only [TokenClaims.unlockCallback, abiWordAt, abiUint, CurrencyLibrary.toId, run_bind,
    run_read, run_ite, run_pure, run_throw, h, bne_self_eq_false, Bool.false_eq_true, ite_false,
    h1, h2, h3, h4, ite_true, ho, hc, hr, List.drop_zero]
  cases hb : ext.call_IPoolManager_burn ext.poolManager (bytesWord (data.take 32))
      (bytesWord ((data.drop 32).take 32)) (bytesWord ((data.drop 96).take 32)) env w with
  | error e => rfl
  | ok p =>
    cases ht : ext.call_IPoolManager_take ext.poolManager (bytesWord ((data.drop 32).take 32))
        (bytesWord ((data.drop 64).take 32)) (bytesWord ((data.drop 96).take 32)) env p.2 with
    | error e => simp [ht]
    | ok q => simp [ht]

/-- Revert characterization: `unlockCallback` reverts before either external call exactly when the
caller is not the PoolManager, the calldata is shorter than four words, or one of the three address
words does not fit 160 bits; otherwise its result is that of `burn` then `take`. -/
theorem unlockCallback_reverts_iff_guards (data : List Nat) (env : Env) (w : σ) :
    (env.sender ≠ ext.poolManager ∨ data.length < 128 ∨ 2 ^ 160 ≤ bytesWord (data.take 32)
      ∨ 2 ^ 160 ≤ bytesWord ((data.drop 32).take 32) ∨ 2 ^ 160 ≤ bytesWord ((data.drop 64).take 32)) →
    ∃ e, TokenClaims.unlockCallback ext data env w = .error e := by
  intro hg
  by_cases hs : env.sender = ext.poolManager
  · rcases hg with hg | hg | hg
    · exact absurd hs hg
    · exact ⟨_, unlockCallback_short ext data env w hs hg⟩
    · exact ⟨_, unlockCallback_badAddress ext data env w hs hg⟩
  · exact ⟨_, unlockCallback_onlyPoolManager ext data env w hs⟩

end TokenClaims.Swarm.UnlockCallback
