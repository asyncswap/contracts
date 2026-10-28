import Specs.TokenClaims
import Proofs.Monad
open FormalAst Refinement

namespace TokenClaims.Swarm.NonReentrant
variable {σ α : Type} [Inhabited α] (ext : Ext σ)

/-- Guard: if a redemption is already in progress (`_redeeming = true`), the modifier reverts
`ReentrantRedemption` without running the body or writing storage. -/
theorem nonReentrant_reverts (k : M σ α) (env : Env) (w : σ)
    (h : (ext.get w).«_redeeming» = true) :
    TokenClaims.nonReentrant ext k env w = .error ⟨"ReentrantRedemption"⟩ := by
  simp [TokenClaims.nonReentrant, h]

/-- Success path / footprint: with `_redeeming = false`, the modifier sets `_redeeming := true`,
runs the body in that world, propagates the body's revert unchanged, and otherwise returns the
body's result with `_redeeming` reset to `false` in the world the body left. No other storage
is written by the modifier itself. -/
theorem nonReentrant_run (k : M σ α) (env : Env) (w : σ)
    (h : (ext.get w).«_redeeming» = false) :
    TokenClaims.nonReentrant ext k env w =
      (match k env (ext.set w { ext.get w with «_redeeming» := true }) with
        | .ok (a, w₂) => .ok (a, ext.set w₂ { ext.get w₂ with «_redeeming» := false })
        | .error e => .error e) := by
  simp only [TokenClaims.nonReentrant, run_bind, run_get, run_pure, run_modify, h,
    Bool.false_eq_true, ite_false]
  cases k env (ext.set w { ext.get w with «_redeeming» := true }) with
  | error e => simp
  | ok p => obtain ⟨a, w₂⟩ := p; simp

/-- Revert characterization: the modifier reverts exactly when the guard fires or the body
(run with the lock set) reverts. -/
theorem nonReentrant_ok_iff (k : M σ α) (env : Env) (w : σ) :
    (∃ r, TokenClaims.nonReentrant ext k env w = .ok r) ↔
      ((ext.get w).«_redeeming» = false ∧
        ∃ r, k env (ext.set w { ext.get w with «_redeeming» := true }) = .ok r) := by
  cases hb : (ext.get w).«_redeeming» with
  | true => simp [nonReentrant_reverts ext k env w hb]
  | false =>
    rw [nonReentrant_run ext k env w hb]
    cases k env (ext.set w { ext.get w with «_redeeming» := true }) with
    | error e => simp
    | ok p => obtain ⟨a, w₂⟩ := p; simp

end TokenClaims.Swarm.NonReentrant
