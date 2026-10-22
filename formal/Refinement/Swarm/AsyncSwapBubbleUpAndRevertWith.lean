import Generated.AsyncSwap
import Refinement.Monad

/-!
# `CustomRevert.bubbleUpAndRevertWith` (AsyncSwap, v4-core CustomRevert.sol)

The Solidity is pure assembly: it builds a `WrappedError(revertingContract,
revertingFunctionSelector, revertReason, additionalContext)` payload and `revert`s with it.
The slice lists no guards, no writes and no external calls.

* Revert condition: always (unconditional assembly `revert`), modelled as `revert`.
* Footprint: there is no successful run, so it writes no storage and returns nothing.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.BubbleUpAndRevertWith

variable {σ : Type} (ext : Ext σ)

/-- It reverts unconditionally, whatever the arguments, environment and world. -/
theorem bubbleUpAndRevertWith_reverts (c sel ctx : Nat) (env : Env) (w : σ) :
    CustomRevert.bubbleUpAndRevertWith ext c sel ctx env w = .error ⟨"revert"⟩ := by
  simp [CustomRevert.bubbleUpAndRevertWith]

/-- Same statement with the fully qualified name of the generated def. -/
theorem bubbleUpAndRevertWith_reverts' (c sel ctx : Nat) (env : Env) (w : σ) :
    AsyncSwap.CustomRevert.bubbleUpAndRevertWith ext c sel ctx env w = .error ⟨"revert"⟩ :=
  bubbleUpAndRevertWith_reverts ext c sel ctx env w

/-- Footprint: no successful run exists, so no storage is ever written and nothing returned. -/
theorem bubbleUpAndRevertWith_never_ok (c sel ctx : Nat) (env : Env) (w w' : σ) (u : Unit) :
    CustomRevert.bubbleUpAndRevertWith ext c sel ctx env w ≠ .ok (u, w') := by
  rw [bubbleUpAndRevertWith_reverts]
  simp

/-- The revert reason does not depend on the arguments or the state. -/
theorem bubbleUpAndRevertWith_indep (c sel ctx c' sel' ctx' : Nat) (env env' : Env) (w w' : σ) :
    CustomRevert.bubbleUpAndRevertWith ext c sel ctx env w
      = CustomRevert.bubbleUpAndRevertWith ext c' sel' ctx' env' w' := by
  rw [bubbleUpAndRevertWith_reverts, bubbleUpAndRevertWith_reverts]

end AsyncSwap.Swarm.BubbleUpAndRevertWith
