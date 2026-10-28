import Specs.AsyncSwap
import Proofs.Monad

/-!
# `AsyncSwap.useNonce` (src/AsyncSwap.sol:603)

Guards: `asyncOrders[poolId].isExecutor[maker][msg.sender]` (else `NotAuthorizedExecutor`),
`!nonceUsed[maker][nonce]` (else `NonceAlreadyUsed`). Footprint: writes only `nonceUsed[maker][nonce] := true`.
-/

namespace AsyncSwap
open FormalAst Refinement

/-- Not an authorized executor of `maker` on `poolId`: reverts (`NotAuthorizedExecutor`). -/
theorem useNonce_reverts_not_executor {σ : Type} (ext : Ext σ) (poolId maker nonce : Nat)
    (env : Env) (w : σ)
    (h : ((ext.get w).asyncOrders poolId).isExecutor maker env.sender = false) :
    AsyncSwap.useNonce ext poolId maker nonce env w = .error ⟨""⟩ := by
  simp [AsyncSwap.useNonce, h]

/-- Authorized executor but the nonce is already spent: reverts `NonceAlreadyUsed`. -/
theorem useNonce_reverts_used {σ : Type} (ext : Ext σ) (poolId maker nonce : Nat)
    (env : Env) (w : σ)
    (hx : ((ext.get w).asyncOrders poolId).isExecutor maker env.sender = true)
    (hu : (ext.get w).nonceUsed maker nonce = true) :
    AsyncSwap.useNonce ext poolId maker nonce env w = .error ⟨"NonceAlreadyUsed"⟩ := by
  simp [AsyncSwap.useNonce, AsyncSwap.«_useNonce», hx, hu]

/-- Success: the only write is `nonceUsed[maker][nonce] := true`; returns `()`. -/
theorem useNonce_success {σ : Type} (ext : Ext σ) (poolId maker nonce : Nat)
    (env : Env) (w : σ)
    (hx : ((ext.get w).asyncOrders poolId).isExecutor maker env.sender = true)
    (hu : (ext.get w).nonceUsed maker nonce = false) :
    AsyncSwap.useNonce ext poolId maker nonce env w =
      .ok ((), ext.set w { ext.get w with
        nonceUsed := upd (ext.get w).nonceUsed maker (upd ((ext.get w).nonceUsed maker) nonce true) }) := by
  simp [AsyncSwap.useNonce, AsyncSwap.«_useNonce», hx, hu]

/-- `useNonce` succeeds exactly when the caller is an executor of `maker` on `poolId`
and the nonce is unspent. -/
theorem useNonce_ok_iff {σ : Type} (ext : Ext σ) (poolId maker nonce : Nat)
    (env : Env) (w : σ) :
    (∃ w', AsyncSwap.useNonce ext poolId maker nonce env w = .ok ((), w')) ↔
      (((ext.get w).asyncOrders poolId).isExecutor maker env.sender = true ∧
        (ext.get w).nonceUsed maker nonce = false) := by
  constructor
  · rintro ⟨w', hw'⟩
    cases hx : ((ext.get w).asyncOrders poolId).isExecutor maker env.sender
    · rw [useNonce_reverts_not_executor ext poolId maker nonce env w hx] at hw'
      cases hw'
    · cases hu : (ext.get w).nonceUsed maker nonce
      · exact ⟨rfl, rfl⟩
      · rw [useNonce_reverts_used ext poolId maker nonce env w hx hu] at hw'
        cases hw'
  · rintro ⟨hx, hu⟩
    exact ⟨_, useNonce_success ext poolId maker nonce env w hx hu⟩

/-- Frame: on success (with `ext.get (ext.set w s) = s`), `nonceUsed[maker][nonce]` becomes `true`,
every other `nonceUsed` entry and every other storage field is unchanged. -/
theorem useNonce_frame {σ : Type} (ext : Ext σ) (poolId maker nonce : Nat)
    (env : Env) (w w' : σ)
    (hget : ∀ w s, ext.get (ext.set w s) = s)
    (h : AsyncSwap.useNonce ext poolId maker nonce env w = .ok ((), w')) :
    (ext.get w').nonceUsed maker nonce = true ∧
    (∀ a n, (a ≠ maker ∨ n ≠ nonce) → (ext.get w').nonceUsed a n = (ext.get w).nonceUsed a n) ∧
    (ext.get w').asyncOrders = (ext.get w).asyncOrders ∧
    (ext.get w').priceBooks = (ext.get w).priceBooks ∧
    (ext.get w').owner = (ext.get w).owner ∧
    (ext.get w').pendingOwner = (ext.get w).pendingOwner ∧
    (ext.get w').defaultMinOrder = (ext.get w).defaultMinOrder ∧
    (ext.get w').«_nameFallback» = (ext.get w).«_nameFallback» ∧
    (ext.get w').«_versionFallback» = (ext.get w).«_versionFallback» ∧
    (ext.get w').«transient» = (ext.get w).«transient» := by
  obtain ⟨hx, hu⟩ := (useNonce_ok_iff ext poolId maker nonce env w).mp ⟨w', h⟩
  rw [useNonce_success ext poolId maker nonce env w hx hu] at h
  cases h
  simp only [hget, and_true]
  refine ⟨by simp [upd], ?_⟩
  intro a n han
  rcases han with ha | hn
  · simp [upd, ha]
  · by_cases ha : a = maker
    · subst ha; simp [upd, hn]
    · simp [upd, ha]

end AsyncSwap
