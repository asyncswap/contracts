import Generated.AsyncSwap
import Refinement.Monad
import AsyncSwapProtocol.V2.Invariants
import AsyncSwapProtocol.V2.BalNonNeg
import AsyncSwapProtocol.V2.ClaimsNonNeg
import AsyncSwapProtocol.V2.Conservation
import AsyncSwapProtocol.V2.Settlement
import AsyncSwapProtocol.V2.SupplyNonNeg

/-!
# `AsyncSwap` (the hook): generated model ⟶ `AsyncSwapProtocol.V2`

`Generated/AsyncSwap.lean` is formal-ast's translation of `src/AsyncSwap.sol`. This file proves that
the defs the Foundry scripts call (`script/Trade.s.sol`: `setExecutor`, `isExecutor`) implement the
spec's `World.isExecutor` table and its `setExecutor` step, so every `step_*` invariant of
`AsyncSwapProtocol.V2` holds across a call of the contract's `setExecutor`.

The abstraction: the spec models one pool. The hook keeps one executor table per pool,
`asyncOrders[poolId].isExecutor[maker][executor]`; `executors ext w poolId` reads it out of the
world, and a spec `World` abstracts pool `poolId` when its `isExecutor` is that table.

`ext.get` / `ext.set` locate the hook's storage in the world. The only property used of them is
`ext.get (ext.set w s) = s` (reading back what was written).
-/

open FormalAst Refinement
open AsyncSwapProtocol.V2 Protocol

namespace AsyncSwap

variable {σ : Type} (ext : Ext σ)

/-- The executor table of pool `poolId` in the hook's storage. -/
def executors (w : σ) (poolId : Nat) : Nat → Nat → Bool :=
  ((ext.get w).asyncOrders poolId).isExecutor

/-- The world after `setExecutor(poolId, executor, allow)` from `sender`: the generated def's one write. -/
def setExecutorWorld (w : σ) (poolId sender executor : Nat) (allow : Bool) : σ :=
  let s := ext.get w
  let pool := s.asyncOrders poolId
  let pool' := { pool with isExecutor := upd pool.isExecutor sender (upd (pool.isExecutor sender) executor allow) }
  ext.set w { s with asyncOrders := upd s.asyncOrders poolId pool' }

/-! ## `isExecutor` -/

/-- **`AsyncSwap.isExecutor` reads the spec's `World.isExecutor`.** It never reverts and writes nothing;
it returns entry `(maker, executor)` of the pool's table, the table every spec guard reads
(`createHookGuard`, `fillGuard`, `cancelHookGuard`). -/
theorem isExecutor_refines (poolId maker executor : Nat) (env : Env) (w : σ)
    (W : World) (hW : W.isExecutor = executors ext w poolId) :
    AsyncSwap.isExecutor ext poolId maker executor env w = .ok (W.isExecutor maker executor, w) := by
  simp [AsyncSwap.isExecutor, hW, executors]

/-! ## `setExecutor` -/

/-- `AsyncSwap.setExecutor` never reverts: its one effect is the table write, keyed by `msg.sender`. -/
theorem setExecutor_run (poolId executor : Nat) (allow : Bool) (env : Env) (w : σ) :
    AsyncSwap.setExecutor ext poolId executor allow env w
      = .ok ((), setExecutorWorld ext w poolId env.sender executor allow) := by
  simp [AsyncSwap.setExecutor, setExecutorWorld]

/-- **`AsyncSwap.setExecutor` refines the spec's `setExecutor` step.** If the spec world abstracts pool
`poolId` before the call, the spec step from `msg.sender` succeeds, and its result abstracts the pool
after the call. -/
theorem setExecutor_refines (hget : ∀ w s, ext.get (ext.set w s) = s) (cfg : Config)
    (poolId executor : Nat) (allow : Bool) (env : Env) (w w' : σ)
    (h : AsyncSwap.setExecutor ext poolId executor allow env w = .ok ((), w'))
    (W : World) (hW : W.isExecutor = executors ext w poolId) :
    step cfg W (.setExecutor env.sender executor allow) = some { W with isExecutor := executors ext w' poolId } := by
  rw [setExecutor_run] at h
  cases h
  simp only [step, Protocol.setExecutor, Tx.setExecutor, Tx.start, Option.some.injEq, World.mk.injEq]
  refine ⟨trivial, trivial, trivial, trivial, trivial, trivial, trivial, trivial, ?_, trivial, trivial, trivial,
    trivial, trivial⟩
  funext m e
  simp only [executors, setExecutorWorld, hget, upd, hW, Function.update_apply]
  by_cases hm : m = env.sender <;> by_cases he : e = executor <;> simp [hm, he, upd]

/-- `AsyncSwap.setExecutor` touches only the caller's row of pool `poolId`'s executor table: other pools,
the pool's orders, the price books, ownership and nonces are unchanged. -/
theorem setExecutor_frame (poolId executor : Nat) (allow : Bool) (env : Env) (w w' : σ)
    (hget : ∀ w s, ext.get (ext.set w s) = s)
    (h : AsyncSwap.setExecutor ext poolId executor allow env w = .ok ((), w')) :
    (∀ p, p ≠ poolId → (ext.get w').asyncOrders p = (ext.get w).asyncOrders p)
    ∧ ((ext.get w').asyncOrders poolId).orders = ((ext.get w).asyncOrders poolId).orders
    ∧ (∀ m, m ≠ env.sender → executors ext w' poolId m = executors ext w poolId m)
    ∧ (ext.get w').priceBooks = (ext.get w).priceBooks
    ∧ (ext.get w').owner = (ext.get w).owner
    ∧ (ext.get w').pendingOwner = (ext.get w).pendingOwner
    ∧ (ext.get w').nonceUsed = (ext.get w).nonceUsed := by
  rw [setExecutor_run] at h
  cases h
  refine ⟨fun p hp => ?_, ?_, fun m hm => ?_, ?_, ?_, ?_, ?_⟩ <;>
    simp_all [setExecutorWorld, executors, upd]

/-! ## The spec's invariants carry over

Each `step_*` theorem of `AsyncSwapProtocol.V2` is stated for any `step cfg W a = some W'`.
`setExecutor_refines` supplies that step for a call of the contract's `setExecutor`, so each
invariant holds of the world abstracting the pool after the call. -/

section Invariants

variable (hget : ∀ w s, ext.get (ext.set w s) = s) (cfg : Config) (poolId executor : Nat) (allow : Bool)
  (env : Env) (w w' : σ) (h : AsyncSwap.setExecutor ext poolId executor allow env w = .ok ((), w'))
  (W : World) (hW : W.isExecutor = executors ext w poolId)
include hget cfg h hW

/-- Escrow (`Invariants.lean`, `step_escrow`) across `AsyncSwap.setExecutor`. -/
theorem setExecutor_escrow (hE : Escrow cfg W) :
    Escrow cfg { W with isExecutor := executors ext w' poolId } :=
  step_escrow hE (setExecutor_refines ext hget cfg poolId executor allow env w w' h W hW)
    (by simp) (by simp) (by simp)

/-- Balances stay non-negative (`BalNonNeg.lean`, `step_bal_nonneg`) across `AsyncSwap.setExecutor`. -/
theorem setExecutor_bal_nonneg (hN : BalNonNeg cfg W) :
    BalNonNeg cfg { W with isExecutor := executors ext w' poolId } :=
  step_bal_nonneg (setExecutor_refines ext hget cfg poolId executor allow env w w' h W hW)
    (by simp) (by simp) (by simp) hN

/-- Claims stay non-negative (`ClaimsNonNeg.lean`, `step_claims_nonneg`) across `AsyncSwap.setExecutor`. -/
theorem setExecutor_claims_nonneg (hE : Escrow cfg W) (hN : ClaimsNonNeg cfg W) :
    ClaimsNonNeg cfg { W with isExecutor := executors ext w' poolId } :=
  step_claims_nonneg hE (setExecutor_refines ext hget cfg poolId executor allow env w w' h W hW)
    (by simp) (by simp) (by simp) hN

/-- PoolManager backing (`Settlement.lean`, `step_backing`) across `AsyncSwap.setExecutor`. -/
theorem setExecutor_backing (hb : Backing cfg W) (hu : Users cfg W) :
    Backing cfg { W with isExecutor := executors ext w' poolId } :=
  step_backing hb hu (setExecutor_refines ext hget cfg poolId executor allow env w w' h W hW)
    (by simp) (by simp) (by simp)

/-- Token conservation (`Conservation.lean`, `step_conservation`) across `AsyncSwap.setExecutor`. -/
theorem setExecutor_conservation {S : Finset Address} (hpm : cfg.pm ∈ S) (hhook : cfg.hook ∈ S)
    (hrouter : cfg.router ∈ S) (hM : Makers S W) :
    ∀ c, total c S { W with isExecutor := executors ext w' poolId } = total c S W :=
  step_conservation hpm hhook hrouter hM (setExecutor_refines ext hget cfg poolId executor allow env w w' h W hW)
    (by simp) (by simp) (by simp)

/-- Pool reserves stay non-negative (`SupplyNonNeg.lean`, `step_reserves_nonneg`) across
`AsyncSwap.setExecutor`. -/
theorem setExecutor_reserves_nonneg (hR : ReservesNonNeg W) :
    ReservesNonNeg { W with isExecutor := executors ext w' poolId } :=
  step_reserves_nonneg (setExecutor_refines ext hget cfg poolId executor allow env w w' h W hW) hR

end Invariants

end AsyncSwap
