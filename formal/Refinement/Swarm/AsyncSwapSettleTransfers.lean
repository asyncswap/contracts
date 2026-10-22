import Generated.AsyncSwap
import Refinement.Monad
import Refinement.Swarm.AsyncSwapTransferEscrow

/-!
# `AsyncMatching._settleTransfers`

`_settleTransfers(State storage self, PoolKey memory key, bytes32 firstId, bytes32 secondId,
MatchAmounts memory amounts, address hook)` (internal, src/AsyncSwap.sol, library `AsyncMatching`).

It reads both orders from `self` at entry, works out which one is the sell and which the buy, and
makes exactly two `_transferEscrow` calls:

1. the sell order's input currency, `amounts.assetAmount` of it, from the hook's escrow to the
   buy order's owner;
2. the buy order's input currency, `amounts.quoteAmount` of it, from the hook's escrow to the
   sell order's owner.

It has no guard and no storage write of its own: it reverts exactly when one of the legs reverts,
and on success the final world is the one the second leg left.

`self` is a getter/setter pair; the theorems assume the getter is a pure read of the world
(`self_get env w = .ok (g w, w)`), which is how every caller instantiates it.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.SettleTransfers

open AsyncSwap.Swarm.TransferEscrow

variable {σ : Type} (ext : Ext σ)

/-- Input currency of an order in pool `key`. -/
def inputOf (key : PoolKey) (o : AsyncFiller.OrderInfo) : Nat :=
  if o.zeroForOne then key.currency0 else key.currency1

/-- The sell side's input currency (paid to the buyer). -/
def sellInput (s : AsyncFiller.State_) (key : PoolKey) (firstId secondId : Nat) : Nat :=
  if (s.orders firstId).isBuy then inputOf key (s.orders secondId) else inputOf key (s.orders firstId)

/-- The buy side's input currency (paid to the seller). -/
def buyInput (s : AsyncFiller.State_) (key : PoolKey) (firstId secondId : Nat) : Nat :=
  if (s.orders firstId).isBuy then inputOf key (s.orders firstId) else inputOf key (s.orders secondId)

/-- The sell order's owner. -/
def sellOwner (s : AsyncFiller.State_) (firstId secondId : Nat) : Nat :=
  if (s.orders firstId).isBuy then (s.orders secondId).owner else (s.orders firstId).owner

/-- The buy order's owner. -/
def buyOwner (s : AsyncFiller.State_) (firstId secondId : Nat) : Nat :=
  if (s.orders firstId).isBuy then (s.orders firstId).owner else (s.orders secondId).owner

/-- Full characterization: the asset leg (`sellInput → buyOwner`, `assetAmount`) from the entry
world, then the quote leg (`buyInput → sellOwner`, `quoteAmount`) from the world the first leg left
(with `poolManager` re-read there). All parties and currencies are read at entry. -/
theorem settleTransfers_run (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (g : σ → AsyncFiller.State_)
    (hget : ∀ env w, self_get env w = .ok (g w, w))
    (key : PoolKey) (firstId secondId : Nat) (amounts : AsyncFiller.MatchAmounts) (hook : Nat)
    (env : Env) (w : σ) :
    AsyncMatching.«_settleTransfers» ext self_get self_set key firstId secondId amounts hook env w =
      (match AsyncMatching.«_transferEscrow» ext (g w).poolManager (sellInput (g w) key firstId secondId)
          (buyOwner (g w) firstId secondId) amounts.assetAmount hook env w with
        | .error e => .error e
        | .ok (_, w1) => AsyncMatching.«_transferEscrow» ext (g w1).poolManager
            (buyInput (g w) key firstId secondId) (sellOwner (g w) firstId secondId)
            amounts.quoteAmount hook env w1) := by
  unfold AsyncMatching.«_settleTransfers» sellInput buyInput sellOwner buyOwner inputOf
  cases hb : ((g w).orders firstId).isBuy <;>
  · simp only [run_bind, hget, run_pure, hb, Bool.false_eq_true, ↓reduceIte]
    rcases AsyncMatching.«_transferEscrow» ext _ _ _ _ hook env w with e | ⟨u, w1⟩
    · simp
    · simp
      rcases AsyncMatching.«_transferEscrow» ext _ _ _ _ hook env w1 with _ | ⟨⟨⟩, _⟩ <;> rfl

/-- Revert characterization: it reverts exactly when the asset leg reverts, or that leg succeeds
and the quote leg reverts (each with its own reason). -/
theorem settleTransfers_reverts_iff (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (g : σ → AsyncFiller.State_)
    (hget : ∀ env w, self_get env w = .ok (g w, w))
    (key : PoolKey) (firstId secondId : Nat) (amounts : AsyncFiller.MatchAmounts) (hook : Nat)
    (env : Env) (w : σ) :
    (∃ e, AsyncMatching.«_settleTransfers» ext self_get self_set key firstId secondId amounts hook
        env w = .error e) ↔
      ((∃ e, AsyncMatching.«_transferEscrow» ext (g w).poolManager
          (sellInput (g w) key firstId secondId) (buyOwner (g w) firstId secondId)
          amounts.assetAmount hook env w = .error e) ∨
        ∃ u w1, AsyncMatching.«_transferEscrow» ext (g w).poolManager
          (sellInput (g w) key firstId secondId) (buyOwner (g w) firstId secondId)
          amounts.assetAmount hook env w = .ok (u, w1) ∧
          ∃ e, AsyncMatching.«_transferEscrow» ext (g w1).poolManager
            (buyInput (g w) key firstId secondId) (sellOwner (g w) firstId secondId)
            amounts.quoteAmount hook env w1 = .error e) := by
  rw [settleTransfers_run ext self_get self_set g hget]
  rcases AsyncMatching.«_transferEscrow» ext (g w).poolManager (sellInput (g w) key firstId secondId)
      (buyOwner (g w) firstId secondId) amounts.assetAmount hook env w with e | ⟨u, w1⟩ <;> simp

/-- Success: both legs are paid, and the hook's escrowed claims move one-for-one. Concretely, the
run consists of exactly four pool-manager calls, in order:
`burn(hook, sellInput, assetAmount)`, the payout of `assetAmount` of `sellInput` to the buyer,
`burn(hook, buyInput, quoteAmount)`, the payout of `quoteAmount` of `buyInput` to the seller.
Every burned amount equals the amount paid out in the same currency; nothing else changes. -/
theorem settleTransfers_ok (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (g : σ → AsyncFiller.State_)
    (hget : ∀ env w, self_get env w = .ok (g w, w))
    (key : PoolKey) (firstId secondId : Nat) (amounts : AsyncFiller.MatchAmounts) (hook : Nat)
    (env : Env) (w w' : σ) (r : Unit)
    (hok : AsyncMatching.«_settleTransfers» ext self_get self_set key firstId secondId amounts hook
      env w = .ok (r, w')) :
    ∃ w1 w2 w3,
      (∃ u, ext.call_IPoolManager_burn (g w).poolManager hook (sellInput (g w) key firstId secondId)
        amounts.assetAmount env w = .ok (u, w1)) ∧
      (∃ u, payout ext (g w).poolManager (sellInput (g w) key firstId secondId)
        (buyOwner (g w) firstId secondId) amounts.assetAmount env w1 = .ok (u, w2)) ∧
      (∃ u, ext.call_IPoolManager_burn (g w2).poolManager hook (buyInput (g w) key firstId secondId)
        amounts.quoteAmount env w2 = .ok (u, w3)) ∧
      payout ext (g w2).poolManager (buyInput (g w) key firstId secondId)
        (sellOwner (g w) firstId secondId) amounts.quoteAmount env w3 = .ok (r, w') := by
  rw [settleTransfers_run ext self_get self_set g hget] at hok
  rcases h1 : AsyncMatching.«_transferEscrow» ext (g w).poolManager
      (sellInput (g w) key firstId secondId) (buyOwner (g w) firstId secondId)
      amounts.assetAmount hook env w with e | ⟨u, w2⟩
  · simp [h1] at hok
  · simp only [h1] at hok
    obtain ⟨w1, hb1, hp1⟩ := transferEscrow_ok ext _ _ _ _ _ env w w2 u h1
    obtain ⟨w3, hb2, hp2⟩ := transferEscrow_ok ext _ _ _ _ _ env w2 w' r hok
    exact ⟨w1, w2, w3, hb1, ⟨u, hp1⟩, hb2, hp2⟩

/-- Same as `settleTransfers_ok` when the first leg leaves `self.poolManager` unchanged (it is
immutable after initialization): both legs go to the same pool manager. -/
theorem settleTransfers_ok_same_manager (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (g : σ → AsyncFiller.State_)
    (hget : ∀ env w, self_get env w = .ok (g w, w))
    (key : PoolKey) (firstId secondId : Nat) (amounts : AsyncFiller.MatchAmounts) (hook : Nat)
    (env : Env) (w w' : σ) (r : Unit)
    (hpm : ∀ w2, AsyncMatching.«_transferEscrow» ext (g w).poolManager
      (sellInput (g w) key firstId secondId) (buyOwner (g w) firstId secondId)
      amounts.assetAmount hook env w = .ok ((), w2) → (g w2).poolManager = (g w).poolManager)
    (hok : AsyncMatching.«_settleTransfers» ext self_get self_set key firstId secondId amounts hook
      env w = .ok (r, w')) :
    ∃ w2, AsyncMatching.«_transferEscrow» ext (g w).poolManager
        (sellInput (g w) key firstId secondId) (buyOwner (g w) firstId secondId)
        amounts.assetAmount hook env w = .ok ((), w2) ∧
      AsyncMatching.«_transferEscrow» ext (g w).poolManager
        (buyInput (g w) key firstId secondId) (sellOwner (g w) firstId secondId)
        amounts.quoteAmount hook env w2 = .ok (r, w') := by
  rw [settleTransfers_run ext self_get self_set g hget] at hok
  rcases h1 : AsyncMatching.«_transferEscrow» ext (g w).poolManager
      (sellInput (g w) key firstId secondId) (buyOwner (g w) firstId secondId)
      amounts.assetAmount hook env w with e | ⟨u, w2⟩
  · simp [h1] at hok
  · simp only [h1] at hok
    cases u
    exact ⟨w2, rfl, by rw [← hpm w2 h1]; exact hok⟩

end AsyncSwap.Swarm.SettleTransfers
