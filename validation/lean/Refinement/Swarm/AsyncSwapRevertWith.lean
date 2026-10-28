import Generated.AsyncSwap
open FormalAst

/-!
# `CustomRevert.revertWith(bytes4 selector, uint160 value)` (overload used by AsyncSwap),
generated def `AsyncSwap.CustomRevert.revertWith`

The Solidity body is a single assembly block that stores `selector` and `value` in scratch
memory and executes `revert(0, 0x24)`. The generated model renders it as an unconditional
`throw ⟨"revert"⟩`.

Closed form: for every `selector`, `value`, environment and state, the call reverts with
reason `"revert"`. There is no success path, so it commits no storage write, returns nothing
and makes no external call.
-/

namespace AsyncSwap.Swarm.RevertWith
open AsyncSwap
variable {σ : Type} (ext : Ext σ)

/-- Exact semantics: `revertWith(selector, value)` always reverts with reason `"revert"`. -/
theorem revertWith_run (selector value : Nat) (r : Env) (s : σ) :
    CustomRevert.revertWith ext selector value r s = Except.error ⟨"revert"⟩ := by
  rfl

/-- No success path: no outcome `.ok (u, s')` is reachable, so no state `s'` is ever
committed (empty footprint) and nothing is returned. -/
theorem revertWith_never_succeeds (selector value : Nat) (r : Env) (s : σ)
    (res : Unit × σ) :
    CustomRevert.revertWith ext selector value r s ≠ Except.ok res := by
  rw [revertWith_run]; simp

/-- The revert is independent of the arguments, the environment and the state. -/
theorem revertWith_uniform (sel₁ val₁ sel₂ val₂ : Nat) (r₁ r₂ : Env) (s₁ s₂ : σ) :
    CustomRevert.revertWith ext sel₁ val₁ r₁ s₁ =
      CustomRevert.revertWith ext sel₂ val₂ r₂ s₂ := by
  rw [revertWith_run, revertWith_run]

end AsyncSwap.Swarm.RevertWith
