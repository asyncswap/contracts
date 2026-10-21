import Generated.AsyncSwap
import Refinement.Monad

/-!
# `AsyncSwap.receive`

`receive() external payable` (src/AsyncSwap.sol:606):
`tstore(PENDING_NATIVE_DEPOSIT_SLOT, add(tload(PENDING_NATIVE_DEPOSIT_SLOT), callvalue()))`.

* no guards: it never reverts (`receive_never_reverts`);
* on success it returns `()` and its only write is `transient[PENDING_NATIVE_DEPOSIT_SLOT]`,
  which becomes `(pending + msg.value) mod 2^256` (EVM `add`) (`receive_run`, `receive_frame`);
* no external calls.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.Receive

variable {σ : Type} (ext : Ext σ)

/-- The per-tx native deposit ledger, `tload(PENDING_NATIVE_DEPOSIT_SLOT)`. -/
def pending (w : σ) : Nat := (ext.get w).transient AsyncSwap.PENDING_NATIVE_DEPOSIT_SLOT

/-- The world after `tstore(PENDING_NATIVE_DEPOSIT_SLOT, v)`. -/
def tstoreWorld (w : σ) (v : Nat) : σ :=
  ext.set w (let s := ext.get w;
    { s with «transient» := upd s.«transient» AsyncSwap.PENDING_NATIVE_DEPOSIT_SLOT v })

/-- **Exact run.** `receive` always succeeds, returns `()`, and leaves the world with the ledger
slot set to `yadd pending msg.value`. -/
theorem receive_run (env : Env) (w : σ) :
    AsyncSwap.«_1952» ext env w = .ok ((), tstoreWorld ext w (yadd (pending ext w) env.value)) :=
  rfl

/-- **Guards.** There are none: `receive` never reverts. -/
theorem receive_never_reverts (env : Env) (w : σ) (e : Revert) :
    AsyncSwap.«_1952» ext env w ≠ .error e := by
  rw [receive_run]; intro h; cases h

/-- **Success.** Any successful outcome is exactly the ledger bump. -/
theorem receive_ok (env : Env) (w w' : σ) (r : Unit)
    (h : AsyncSwap.«_1952» ext env w = .ok (r, w')) :
    w' = tstoreWorld ext w (yadd (pending ext w) env.value) := by
  rw [receive_run] at h; cases h; rfl

/-- **Footprint.** With a lawful `ext` (`get ∘ set = id`), the ledger becomes
`(pending + msg.value) mod 2^256`, and all other storage (every declared field and every other
transient slot) is unchanged. -/
theorem receive_frame (hget : ∀ w s, ext.get (ext.set w s) = s) (env : Env) (w w' : σ) (r : Unit)
    (h : AsyncSwap.«_1952» ext env w = .ok (r, w')) :
    pending ext w' = (pending ext w + env.value) % W ∧
    (ext.get w').asyncOrders = (ext.get w).asyncOrders ∧
    (ext.get w').priceBooks = (ext.get w).priceBooks ∧
    (ext.get w').owner = (ext.get w).owner ∧
    (ext.get w').pendingOwner = (ext.get w).pendingOwner ∧
    (ext.get w').nonceUsed = (ext.get w).nonceUsed ∧
    (ext.get w').«_nameFallback» = (ext.get w).«_nameFallback» ∧
    (ext.get w').«_versionFallback» = (ext.get w).«_versionFallback» ∧
    ∀ k, k ≠ AsyncSwap.PENDING_NATIVE_DEPOSIT_SLOT →
      (ext.get w').transient k = (ext.get w).transient k := by
  have hw := receive_ok ext env w w' r h
  subst hw
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;> simp [tstoreWorld, pending, hget, upd, yadd]
  intro k hk; simp [hk]

end AsyncSwap.Swarm.Receive
