import Specs.AsyncSwap

/-!
Helpers for `Refinement.Swarm.AsyncSwapUpdatePrice`: a guarded `Except` equals `ok`/`error`
exactly when the guard has the right value and the components agree. Used to identify the state
`minPriorityFee` returns with the state `checkMinimum` left (the fee computation writes nothing)
and to read off which revert a guarded `throw` produced.
-/

namespace AsyncSwap.Swarm.UpdatePriceFiller

theorem ite_err_ok_eq {ε α σ : Type} {c : Prop} [Decidable c] {e : ε} {v a : α} {t t' : σ} :
    ((if c then Except.error e else Except.ok (v, t)) = (Except.ok (a, t') : Except ε (α × σ))) ↔
      (¬c ∧ v = a ∧ t = t') := by
  by_cases hc : c <;> simp [hc]

theorem ite_err_ok_eq_err {ε β : Type} {c : Prop} [Decidable c] {x e : ε} {y : β} :
    ((if c then Except.error x else Except.ok y) = (Except.error e : Except ε β)) ↔ (c ∧ x = e) := by
  by_cases hc : c <;> simp [hc]

theorem ite_ok_err_eq_err {ε β : Type} {c : Prop} [Decidable c] {x e : ε} {y : β} :
    ((if c then Except.ok y else Except.error x) = (Except.error e : Except ε β)) ↔ (¬c ∧ x = e) := by
  by_cases hc : c <;> simp [hc]

/-- Rewrite a hypothesis `(if c then error else ok (v,t)) = ok (a,t')` into
`¬c ∧ v = a ∧ t = t'` and substitute `a := v`, `t' := t`. -/
syntax "fee_state_norm" : tactic
macro_rules
  | `(tactic| fee_state_norm) =>
    `(tactic| (simp only [AsyncSwap.Swarm.UpdatePriceFiller.ite_err_ok_eq] at *
               obtain ⟨-, hv, ht⟩ := ‹¬_ ∧ _ = _ ∧ _ = _›
               subst hv
               subst ht))

end AsyncSwap.Swarm.UpdatePriceFiller
