import Generated.AsyncSwap
import Refinement.Monad

/-!
# `AsyncSwap.getHookPermissions`

`function getHookPermissions() public pure` (src/AsyncSwap.sol:193): no guards, never reverts,
reads and writes no storage, makes no external calls, and returns the fixed permission set
with exactly `beforeInitialize`, `beforeAddLiquidity`, `beforeSwap` and
`beforeSwapReturnDelta` enabled.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm

variable {σ : Type} (ext : Ext σ)

/-- The permission set the hook advertises. -/
def hookPerms : Hooks.Permissions :=
  { beforeInitialize := true, afterInitialize := false, beforeAddLiquidity := true,
    afterAddLiquidity := false, beforeRemoveLiquidity := false, afterRemoveLiquidity := false,
    beforeSwap := true, afterSwap := false, beforeDonate := false, afterDonate := false,
    beforeSwapReturnDelta := true, afterSwapReturnDelta := false,
    afterAddLiquidityReturnDelta := false, afterRemoveLiquidityReturnDelta := false }

/-- Full characterization: in any environment and world, `getHookPermissions` succeeds,
leaves the world untouched, and returns `hookPerms`. -/
theorem getHookPermissions_run (env : Env) (w : σ) :
    AsyncSwap.getHookPermissions ext env w = .ok (hookPerms, w) := rfl

/-- It never reverts. -/
theorem getHookPermissions_never_reverts (env : Env) (w : σ) :
    ¬ ∃ e, AsyncSwap.getHookPermissions ext env w = .error e := by
  rw [getHookPermissions_run]; simp

/-- Success characterization: the result is exactly `hookPerms` and the world is unchanged
(empty footprint). -/
theorem getHookPermissions_ok_iff (env : Env) (w w' : σ) (p : Hooks.Permissions) :
    AsyncSwap.getHookPermissions ext env w = .ok (p, w') ↔ p = hookPerms ∧ w' = w := by
  rw [getHookPermissions_run]
  constructor
  · intro h; cases h; exact ⟨rfl, rfl⟩
  · rintro ⟨rfl, rfl⟩; rfl

/-- Field by field: only the four `before*` flags the hook implements are set. -/
theorem getHookPermissions_fields (env : Env) (w w' : σ) (p : Hooks.Permissions)
    (h : AsyncSwap.getHookPermissions ext env w = .ok (p, w')) :
    w' = w ∧
    p.beforeInitialize = true ∧ p.afterInitialize = false ∧
    p.beforeAddLiquidity = true ∧ p.afterAddLiquidity = false ∧
    p.beforeRemoveLiquidity = false ∧ p.afterRemoveLiquidity = false ∧
    p.beforeSwap = true ∧ p.afterSwap = false ∧
    p.beforeDonate = false ∧ p.afterDonate = false ∧
    p.beforeSwapReturnDelta = true ∧ p.afterSwapReturnDelta = false ∧
    p.afterAddLiquidityReturnDelta = false ∧ p.afterRemoveLiquidityReturnDelta = false := by
  obtain ⟨rfl, rfl⟩ := (getHookPermissions_ok_iff ext env w w' p).1 h
  exact ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

end AsyncSwap.Swarm
