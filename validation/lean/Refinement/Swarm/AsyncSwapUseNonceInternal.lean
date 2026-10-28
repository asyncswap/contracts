import Generated.AsyncSwap
import Refinement.Monad

/-!
# `AsyncSwap._useNonce` (internal, src/AsyncSwap.sol)

`if (nonceUsed[maker][nonce]) revert NonceAlreadyUsed(); nonceUsed[maker][nonce] = true;`

* `_useNonce_reverts_used`: a spent nonce reverts `NonceAlreadyUsed`.
* `_useNonce_success`: a fresh nonce succeeds and the only write is `nonceUsed[maker][nonce] := true`.
* `_useNonce_ok_iff`: it succeeds exactly when the nonce is fresh.
* `_useNonce_frame`: on success the slot is spent, every other `nonceUsed` entry and every other
  storage field is unchanged.
* `_useNonce_no_replay`: two consecutive uses of the same `(maker, nonce)` always revert.
-/

namespace AsyncSwap.Swarm.UseNonceInternal
open FormalAst Refinement

theorem _useNonce_reverts_used {σ : Type} (ext : Ext σ) (maker nonce : Nat) (env : Env) (w : σ)
    (hu : (ext.get w).nonceUsed maker nonce = true) :
    AsyncSwap.«_useNonce» ext maker nonce env w = .error ⟨"NonceAlreadyUsed"⟩ := by
  simp [AsyncSwap.«_useNonce», hu]

theorem _useNonce_success {σ : Type} (ext : Ext σ) (maker nonce : Nat) (env : Env) (w : σ)
    (hu : (ext.get w).nonceUsed maker nonce = false) :
    AsyncSwap.«_useNonce» ext maker nonce env w =
      .ok ((), ext.set w { ext.get w with
        nonceUsed := upd (ext.get w).nonceUsed maker (upd ((ext.get w).nonceUsed maker) nonce true) }) := by
  simp [AsyncSwap.«_useNonce», hu]

theorem _useNonce_ok_iff {σ : Type} (ext : Ext σ) (maker nonce : Nat) (env : Env) (w : σ) :
    (∃ w', AsyncSwap.«_useNonce» ext maker nonce env w = .ok ((), w')) ↔
      (ext.get w).nonceUsed maker nonce = false := by
  constructor
  · rintro ⟨w', hw'⟩
    cases hu : (ext.get w).nonceUsed maker nonce
    · rfl
    · rw [_useNonce_reverts_used ext maker nonce env w hu] at hw'; cases hw'
  · intro hu
    exact ⟨_, _useNonce_success ext maker nonce env w hu⟩

theorem _useNonce_frame {σ : Type} (ext : Ext σ) (maker nonce : Nat) (env : Env) (w w' : σ)
    (hget : ∀ w s, ext.get (ext.set w s) = s)
    (h : AsyncSwap.«_useNonce» ext maker nonce env w = .ok ((), w')) :
    (ext.get w).nonceUsed maker nonce = false ∧
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
  have hu := (_useNonce_ok_iff ext maker nonce env w).mp ⟨w', h⟩
  rw [_useNonce_success ext maker nonce env w hu] at h
  cases h
  simp only [hget, and_true]
  refine ⟨hu, by simp [upd], ?_⟩
  intro a n han
  rcases han with ha | hn
  · simp [upd, ha]
  · by_cases ha : a = maker
    · subst ha; simp [upd, hn]
    · simp [upd, ha]

/-- Replay protection: after a successful use, using the same `(maker, nonce)` again reverts. -/
theorem _useNonce_no_replay {σ : Type} (ext : Ext σ) (maker nonce : Nat) (env env' : Env) (w w' : σ)
    (hget : ∀ w s, ext.get (ext.set w s) = s)
    (h : AsyncSwap.«_useNonce» ext maker nonce env w = .ok ((), w')) :
    AsyncSwap.«_useNonce» ext maker nonce env' w' = .error ⟨"NonceAlreadyUsed"⟩ :=
  _useNonce_reverts_used ext maker nonce env' w' (_useNonce_frame ext maker nonce env w w' hget h).2.1

end AsyncSwap.Swarm.UseNonceInternal
