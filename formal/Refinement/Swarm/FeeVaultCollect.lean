import Generated.FeeVault
import Refinement.Monad

/-!
# `FeeVault.collect`

`function collect(Currency currency, address recipient) external` (src/FeeVault.sol:27).

* reads `hook.owner()` (a staticcall; its revert propagates);
* reverts `Unauthorized` when `msg.sender != hook.owner()`;
* else reverts `ZeroAddress` when `recipient == 0`;
* else calls `poolManager.unlock(abi.encode(currency, recipient))` on the unchanged world and
  propagates its revert; on success the final world is exactly that call's world.

FeeVault has no storage (`State` is empty), so its own footprint is nothing: the only effect is the
pool-manager call. For the maintainer's "drain via a crafted order" concern: nobody but the hook's
owner can reach the `unlock` that pays fees out, so an order maker or filler cannot route protocol
fees to themselves through this entry point.

(Inside `namespace FeeVault.Swarm`, `FeeVault.collect` resolves to the generated
`FeeVault.FeeVault.collect`.)
-/

open FormalAst Refinement

namespace FeeVault.Swarm

variable {σ : Type} (ext : Ext σ)

/-- Full characterization of a run (no assumptions on `ext`). -/
theorem collect_run (env : Env) (w : σ) (currency recipient : Nat) :
    FeeVault.collect ext currency recipient env w =
      match ext.view_IFeeOwner_owner env w ext.hook with
      | .error e => .error e
      | .ok o =>
        if env.sender ≠ o then .error ⟨"Unauthorized"⟩
        else if recipient = 0 then .error ⟨"ZeroAddress"⟩
        else
          match ext.call_IPoolManager_unlock ext.poolManager (abiEncode [currency, recipient]) env w with
          | .ok (_, w1) => .ok ((), w1)
          | .error e => .error e := by
  unfold FeeVault.collect view
  cases hv : ext.view_IFeeOwner_owner env w ext.hook with
  | error e => simp [hv]
  | ok o =>
    by_cases hs : env.sender = o
    · subst hs
      by_cases hr : recipient = 0
      · simp [hv, hr]
      · simp only [run_bind, run_read, run_get, hv, run_pure, run_ite, run_throw, bne_self_eq_false,
          Bool.false_eq_true, ite_false, beq_iff_eq, hr, ne_eq, not_true_eq_false]
        cases ext.call_IPoolManager_unlock ext.poolManager (abiEncode [currency, recipient]) env w with
        | error e => rfl
        | ok p => rfl
    · simp [hv, hs]

/-- The owner view reverting makes `collect` revert with the same reason. -/
theorem collect_owner_view_reverts (env : Env) (w : σ) (currency recipient : Nat) (e : Revert)
    (hv : ext.view_IFeeOwner_owner env w ext.hook = .error e) :
    FeeVault.collect ext currency recipient env w = .error e := by
  rw [collect_run, hv]

/-- Guard 1: a caller other than `hook.owner()` reverts with `Unauthorized`. -/
theorem collect_unauthorized (env : Env) (w : σ) (currency recipient o : Nat)
    (hv : ext.view_IFeeOwner_owner env w ext.hook = .ok o) (hs : env.sender ≠ o) :
    FeeVault.collect ext currency recipient env w = .error ⟨"Unauthorized"⟩ := by
  rw [collect_run, hv]; simp [hs]

/-- Guard 2: the owner with a zero recipient reverts with `ZeroAddress`. -/
theorem collect_zero_recipient (env : Env) (w : σ) (currency : Nat)
    (hv : ext.view_IFeeOwner_owner env w ext.hook = .ok env.sender) :
    FeeVault.collect ext currency 0 env w = .error ⟨"ZeroAddress"⟩ := by
  rw [collect_run, hv]; simp

/-- Success: the caller is `hook.owner()`, the recipient is nonzero, and the pool manager was
unlocked with exactly `abi.encode(currency, recipient)` from the unchanged world; the final world is
that call's world (FeeVault writes no storage of its own). -/
theorem collect_ok (env : Env) (w w' : σ) (currency recipient : Nat)
    (hok : FeeVault.collect ext currency recipient env w = .ok ((), w')) :
    ext.view_IFeeOwner_owner env w ext.hook = .ok env.sender ∧ recipient ≠ 0 ∧
      ∃ r, ext.call_IPoolManager_unlock ext.poolManager (abiEncode [currency, recipient]) env w
        = .ok (r, w') := by
  rw [collect_run] at hok
  cases hv : ext.view_IFeeOwner_owner env w ext.hook with
  | error e => rw [hv] at hok; cases hok
  | ok o =>
    rw [hv] at hok
    by_cases hs : env.sender = o
    · subst hs
      by_cases hr : recipient = 0
      · simp [hr] at hok
      · simp only [ne_eq, not_true_eq_false, ite_false, hr] at hok
        refine ⟨rfl, hr, ?_⟩
        revert hok
        cases ext.call_IPoolManager_unlock ext.poolManager (abiEncode [currency, recipient]) env w with
        | error e => intro hok; cases hok
        | ok p => intro hok; cases hok; exact ⟨p.1, rfl⟩
    · simp [hs] at hok

/-- Access control in one line: any successful `collect` was sent by `hook.owner()`. -/
theorem collect_only_owner (env : Env) (w w' : σ) (currency recipient : Nat)
    (hok : FeeVault.collect ext currency recipient env w = .ok ((), w')) :
    ext.view_IFeeOwner_owner env w ext.hook = .ok env.sender :=
  (collect_ok ext env w w' currency recipient hok).1

/-- Revert characterization: `collect` reverts iff the owner view reverts, the caller isn't the
owner, the recipient is zero, or the `unlock` call reverts. -/
theorem collect_reverts_iff (env : Env) (w : σ) (currency recipient : Nat) :
    (∃ e, FeeVault.collect ext currency recipient env w = .error e) ↔
      ((∃ e, ext.view_IFeeOwner_owner env w ext.hook = .error e) ∨
       (∃ o, ext.view_IFeeOwner_owner env w ext.hook = .ok o ∧ env.sender ≠ o) ∨
       recipient = 0 ∨
       ∃ e, ext.call_IPoolManager_unlock ext.poolManager (abiEncode [currency, recipient]) env w
         = .error e) := by
  rw [collect_run]
  cases hv : ext.view_IFeeOwner_owner env w ext.hook with
  | error e => simp
  | ok o =>
    by_cases hs : env.sender = o
    · subst hs
      by_cases hr : recipient = 0
      · simp [hr]
      · simp only [ne_eq, not_true_eq_false, ite_false, hr, false_or, reduceCtorEq, exists_false,
          Except.ok.injEq]
        cases ext.call_IPoolManager_unlock ext.poolManager (abiEncode [currency, recipient]) env w with
        | error e => simp
        | ok p => simp
    · simp [hs]

end FeeVault.Swarm
