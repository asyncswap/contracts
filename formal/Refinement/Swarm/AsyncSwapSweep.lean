import Generated.AsyncSwap
import Refinement.Monad
import Refinement.Swarm.AsyncSwapOnlyOwner

/-!
# `AsyncSwap.sweep`

`function sweep(Currency currency, address to) external onlyOwner` (src/AsyncSwap.sol:175).
It reverts with `NotOwner` unless `msg.sender = owner`, then with `ZeroAddress` if `to = 0`.
Otherwise it reads this contract's balance of `currency` (a view: the world is unchanged) and hands
it to the opaque `CurrencyLibrary.transfer`. `sweep` itself writes no storage: on success the final
world is exactly what the transfer produced from the starting world, so whenever the transfer leaves
our storage alone, so does `sweep`.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm

variable {σ : Type} (ext : Ext σ)

/-- `balanceOfSelf` is a pure read: when it succeeds, the world is unchanged. -/
theorem balanceOfSelf_noWrite (currency : Nat) (env : Env) (w w' : σ) (b : Nat)
    (h : CurrencyLibrary.balanceOfSelf ext currency env w = .ok (b, w')) : w' = w := by
  unfold CurrencyLibrary.balanceOfSelf CurrencyLibrary.isAddressZero view at h
  by_cases hc : currency = CurrencyLibrary.ADDRESS_ZERO
  · simp [hc] at h
    exact h.2.symm
  · simp [hc] at h
    revert h
    cases ext.view_IERC20Minimal_balanceOf env w currency env.self with
    | ok v => intro h; simp at h; exact h.2.symm
    | error r => intro h; simp at h

/-- Non-owner: `sweep` reverts with `NotOwner`. -/
theorem sweep_notOwner (currency to : Nat) (env : Env) (w : σ)
    (h : env.sender ≠ (ext.get w).owner) :
    AsyncSwap.sweep ext currency to env w = .error ⟨"NotOwner"⟩ := by
  unfold AsyncSwap.sweep
  exact onlyOwner_notOwner ext _ env w h

/-- Owner but `to = 0`: `sweep` reverts with `ZeroAddress`. -/
theorem sweep_zeroTo (currency : Nat) (env : Env) (w : σ)
    (h : env.sender = (ext.get w).owner) :
    AsyncSwap.sweep ext currency 0 env w = .error ⟨"ZeroAddress"⟩ := by
  unfold AsyncSwap.sweep
  rw [onlyOwner_owner ext _ env w h]
  simp

/-- `sweep` reverts unless `msg.sender = owner` and `to ≠ 0`. -/
theorem sweep_reverts_unless (currency to : Nat) (env : Env) (w : σ)
    (h : ¬ (env.sender = (ext.get w).owner ∧ to ≠ 0)) :
    ∃ e, AsyncSwap.sweep ext currency to env w = .error e := by
  by_cases ho : env.sender = (ext.get w).owner
  · have hz : to = 0 := Classical.byContradiction fun hz => h ⟨ho, hz⟩
    subst hz
    exact ⟨_, sweep_zeroTo ext currency env w ho⟩
  · exact ⟨_, sweep_notOwner ext currency to env w ho⟩

/-- Owner and `to ≠ 0`: `sweep` is exactly "read the balance, then transfer it", with no write of
its own. -/
theorem sweep_run (currency to : Nat) (env : Env) (w : σ)
    (ho : env.sender = (ext.get w).owner) (hto : to ≠ 0) :
    AsyncSwap.sweep ext currency to env w =
      (match CurrencyLibrary.balanceOfSelf ext currency env w with
       | .ok (amount, w1) => ext.fn_CurrencyLibrary_transfer_4290 currency to amount env w1
       | .error e => .error e) := by
  unfold AsyncSwap.sweep
  rw [onlyOwner_owner ext _ env w ho]
  have : (to == 0) = false := by simpa using hto
  simp only [this, run_bind, run_ite, Bool.false_eq_true, ite_false, run_pure]
  cases CurrencyLibrary.balanceOfSelf ext currency env w with
  | error e => rfl
  | ok p =>
    obtain ⟨amount, w1⟩ := p
    simp only
    cases ext.fn_CurrencyLibrary_transfer_4290 currency to amount env w1 <;> rfl

/-- On success: the caller is the owner, `to ≠ 0`, and the final world is the one the transfer of
the full balance produced from the *starting* world — `sweep` writes no storage of its own. -/
theorem sweep_ok (currency to : Nat) (env : Env) (w w' : σ) (u : Unit)
    (hok : AsyncSwap.sweep ext currency to env w = .ok (u, w')) :
    env.sender = (ext.get w).owner ∧ to ≠ 0 ∧
      ∃ amount, CurrencyLibrary.balanceOfSelf ext currency env w = .ok (amount, w) ∧
        ext.fn_CurrencyLibrary_transfer_4290 currency to amount env w = .ok ((), w') := by
  by_cases ho : env.sender = (ext.get w).owner
  · by_cases hto : to = 0
    · subst hto; rw [sweep_zeroTo ext currency env w ho] at hok; cases hok
    · refine ⟨ho, hto, ?_⟩
      rw [sweep_run ext currency to env w ho hto] at hok
      revert hok
      cases hb : CurrencyLibrary.balanceOfSelf ext currency env w with
      | error e => intro hok; cases hok
      | ok p =>
        obtain ⟨amount, w1⟩ := p
        have hw1 := balanceOfSelf_noWrite ext currency env w w1 amount hb
        subst hw1
        intro hok
        exact ⟨amount, rfl, hok⟩
  · rw [sweep_notOwner ext currency to env w ho] at hok; cases hok

/-- Writes no storage: if the (opaque) token transfer leaves this contract's storage unchanged,
then a successful `sweep` leaves it unchanged too. -/
theorem sweep_storage_unchanged (currency to : Nat) (env : Env) (w w' : σ) (u : Unit)
    (htransfer : ∀ amount v v', ext.fn_CurrencyLibrary_transfer_4290 currency to amount env v = .ok ((), v') →
      ext.get v' = ext.get v)
    (hok : AsyncSwap.sweep ext currency to env w = .ok (u, w')) :
    ext.get w' = ext.get w := by
  obtain ⟨-, -, amount, -, ht⟩ := sweep_ok ext currency to env w w' u hok
  exact htransfer amount w w' ht

end AsyncSwap.Swarm
