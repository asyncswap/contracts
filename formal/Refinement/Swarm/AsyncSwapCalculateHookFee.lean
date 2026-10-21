import Generated.AsyncSwap
import Refinement.Monad

/-!
# `AsyncSwap.calculateHookFee`

`function calculateHookFee(uint256) public pure returns (uint256)` (src/AsyncSwap.sol:310):
no guards, never reverts, reads and writes no storage, makes no external calls, and returns
`0` whatever its argument.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm

variable {σ : Type} (ext : Ext σ)

/-- Full characterization: for any argument, environment and world, `calculateHookFee`
succeeds with `0` and leaves the world untouched. -/
theorem calculateHookFee_run (x : Nat) (env : Env) (w : σ) :
    AsyncSwap.calculateHookFee ext x env w = .ok (0, w) := rfl

/-- It never reverts (no guards). -/
theorem calculateHookFee_never_reverts (x : Nat) (env : Env) (w : σ) :
    ¬ ∃ e, AsyncSwap.calculateHookFee ext x env w = .error e := by
  rw [calculateHookFee_run]; simp

/-- Success characterization: the fee is exactly `0` and the world is unchanged
(empty footprint). -/
theorem calculateHookFee_ok_iff (x : Nat) (env : Env) (w w' : σ) (fee : Nat) :
    AsyncSwap.calculateHookFee ext x env w = .ok (fee, w') ↔ fee = 0 ∧ w' = w := by
  rw [calculateHookFee_run]
  constructor
  · intro h; cases h; exact ⟨rfl, rfl⟩
  · rintro ⟨rfl, rfl⟩; rfl

/-- The result does not depend on the argument, the environment or the world. -/
theorem calculateHookFee_const (x y : Nat) (env env' : Env) (w : σ) :
    (AsyncSwap.calculateHookFee ext x env w).map Prod.fst =
      (AsyncSwap.calculateHookFee ext y env' w).map Prod.fst := rfl

end AsyncSwap.Swarm
