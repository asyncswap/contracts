/-!
# Running the generated models

Every generated def is a program in `FormalAst.M σ = ReaderT Env (StateT σ (Except Revert))`.
These lemmas evaluate such a program applied to an environment and a world, so `simp` can reduce a
generated def to its guards and its writes. They are stated over any `ReaderT ρ (StateT σ (Except ε))`
so they serve every generated module (each carries its own copy of the `FormalAst` prelude).
-/

namespace Refinement

variable {ρ σ ε α β : Type}

@[simp] theorem run_bind (x : ReaderT ρ (StateT σ (Except ε)) α) (f : α → ReaderT ρ (StateT σ (Except ε)) β)
    (r : ρ) (s : σ) :
    (x >>= f) r s = (match x r s with | .ok (a, s') => f a r s' | .error e => .error e) := by
  show (do let (a, s') ← x r s; f a r s') = _
  cases x r s <;> rfl

@[simp] theorem run_pure (a : α) (r : ρ) (s : σ) :
    (pure a : ReaderT ρ (StateT σ (Except ε)) α) r s = .ok (a, s) := rfl

@[simp] theorem run_read (r : ρ) (s : σ) :
    (read : ReaderT ρ (StateT σ (Except ε)) ρ) r s = .ok (r, s) := rfl

@[simp] theorem run_readThe (r : ρ) (s : σ) :
    (readThe ρ : ReaderT ρ (StateT σ (Except ε)) ρ) r s = .ok (r, s) := rfl

@[simp] theorem run_get (r : ρ) (s : σ) :
    (get : ReaderT ρ (StateT σ (Except ε)) σ) r s = .ok (s, s) := rfl

@[simp] theorem run_modify (f : σ → σ) (r : ρ) (s : σ) :
    (modify f : ReaderT ρ (StateT σ (Except ε)) PUnit) r s = .ok (⟨⟩, f s) := rfl

@[simp] theorem run_throw (e : ε) (r : ρ) (s : σ) :
    (throw e : ReaderT ρ (StateT σ (Except ε)) α) r s = .error e := rfl

@[simp] theorem run_ite (c : Prop) [Decidable c] (x y : ReaderT ρ (StateT σ (Except ε)) α) (r : ρ) (s : σ) :
    (if c then x else y) r s = if c then x r s else y r s := by
  split <;> rfl

end Refinement

namespace Refinement
variable {ρ σ ε α β : Type}

@[simp] theorem run_map (f : α → β) (x : ReaderT ρ (StateT σ (Except ε)) α) (r : ρ) (s : σ) :
    (f <$> x) r s = (match x r s with | .ok (a, s') => .ok (f a, s') | .error e => .error e) := by
  show (do let (a, s') ← x r s; pure (f a, s')) = _
  cases x r s <;> rfl

end Refinement

namespace Refinement
variable {ε α : Type}

/-- A guarded step (`if c then pure x else throw e`, run) succeeds exactly when its guard holds. -/
@[simp] theorem ite_ok_error_eq_ok (c : Prop) [Decidable c] (x y : α) (e : ε) :
    ((if c then Except.ok x else Except.error e) = Except.ok y) ↔ c ∧ x = y := by
  split <;> simp_all

end Refinement
