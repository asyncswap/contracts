import Generated.AsyncSwap
import Refinement.Monad
import Refinement.Swarm.AsyncSwapMatchBook

/-!
# `AsyncSwap.matchNewOrder`

`function matchNewOrder(AsyncOrder calldata order) external returns (uint8 matched)`
(src/AsyncSwap.sol:363), through `AsyncMatching.matchIncoming` (src/libraries/AsyncMatching.sol:148).

With `id = tload(PENDING_MATCH_ID_SLOT)`, `executor = address(tload(PENDING_MATCH_EXECUTOR_SLOT))`,
`pid = order.key.toId()` and `w0` the world after both transient slots are zeroed (`clearWorld`):

* **Run** (`matchNewOrder_run`): it first consumes the pending match (`tstore(…, 0)` on both slots),
  then
  - reverts (`NotAuthorizedExecutor`) when `id = 0` or `msg.sender ≠ executor`
    (`matchNewOrder_unauthorized`);
  - reverts (`OrderNotFound`) when `asyncOrders[pid].orders[id].owner ≠ order.owner`
    (`matchNewOrder_wrongOwner`);
  - runs `AsyncMatching.matchIncoming` on exactly `asyncOrders[pid]` / `priceBooks[pid]` with
    `incomingId = id`, `hook = address(this)` (it reverts when the stored order has `amountIn = 0`,
    `matchNewOrder_emptyOrder`; the `RadixPriceTree` guards sit in the opaque tree calls);
  - if the order still has `amountIn ≠ 0`, makes the self-call
    `this.fillOrderFromPoolLiquidity(order, id)` with exactly `order` and the pending `id`; a revert
    of that call is caught and rolled back to the world after matching;
  - returns the `matched` count of `matchIncoming`.
* **Success** (`matchNewOrder_ok`): a success came from the pending executor, with a pending
  `id ≠ 0` whose stored owner is `order.owner`, and returns `matched ≤ MAX_MATCHES_PER_CALL = 8`,
  so the unchecked `uint8 ++matched` never wraps.
* **Consumed pending match** (`clearWorld_frame`, `matchNewOrder_reentry_reverts`): in `w0` both
  transient slots read 0 and no other storage changed, so any re-entrant `matchNewOrder` made from
  `w0` reverts.
* **Footprint**: the function's own storage writes are the two transient clears and the
  `asyncOrders[pid]` / `priceBooks[pid]` setters handed to the library
  (`AsyncSwap.Swarm.MatchBook.selfSet_frame` / `bookSet_frame`); the rest is the opaque external
  calls (`Ext`).
-/

open FormalAst Refinement
open AsyncSwap.Swarm.MatchBook (Returns returns_pure returns_bind returns_bind_any returns_ite
  stepVal returns_forIn_range selfGet selfSet bookGet bookSet poolId)

namespace AsyncSwap.Swarm.MatchNewOrder

variable {σ : Type} (ext : Ext σ)

private theorem ite_pos' {α : Type} {c : Prop} [Decidable c] (h : c) (a b : α) :
    (if c then a else b) = a := by simp [h]
private theorem ite_neg' {α : Type} {c : Prop} [Decidable c] (h : ¬c) (a b : α) :
    (if c then a else b) = b := by simp [h]

/-- `try … catch` in the model's monad: a reverted body is rolled back to the starting world. -/
private theorem run_tryCatch' {α : Type} (x : M σ α) (h : Revert → M σ α) (r : Env) (s : σ) :
    (tryCatch x h : M σ α) r s =
      (match x r s with | .ok p => .ok p | .error e => h e r s) := by
  show (tryCatchThe Revert (x r s) (fun e => h e r s)) = _
  cases x r s <;> rfl

/-- The pending match id (transient). -/
def pendingId (w : σ) : Nat := (ext.get w).transient AsyncSwap.PENDING_MATCH_ID_SLOT

/-- The pending match executor (transient, cast to `address`). -/
def pendingExecutor (w : σ) : Nat :=
  (ext.get w).transient AsyncSwap.PENDING_MATCH_EXECUTOR_SLOT % 2 ^ 160

/-- The world after `tstore(PENDING_MATCH_ID_SLOT, 0); tstore(PENDING_MATCH_EXECUTOR_SLOT, 0)`. -/
def clearWorld (w : σ) : σ :=
  let w1 := ext.set w { ext.get w with
    transient := upd (ext.get w).transient AsyncSwap.PENDING_MATCH_ID_SLOT 0 }
  ext.set w1 { ext.get w1 with
    transient := upd (ext.get w1).transient AsyncSwap.PENDING_MATCH_EXECUTOR_SLOT 0 }

/-- **Full characterization** of `AsyncSwap.matchNewOrder`. -/
theorem matchNewOrder_run (order : AsyncOrder) (env : Env) (w : σ) :
    AsyncSwap.matchNewOrder ext order env w =
      let pid := poolId ext order.key
      let id := pendingId ext w
      let w0 := clearWorld ext w
      if id = 0 ∨ env.sender ≠ pendingExecutor ext w then .error ⟨""⟩
      else if (((ext.get w0).asyncOrders pid).orders id).owner ≠ order.owner then .error ⟨""⟩
      else match AsyncMatching.matchIncoming ext (selfGet ext pid) (selfSet ext pid)
          (bookGet ext pid) (bookSet ext pid) order.key id env.self env w0 with
        | .error e => .error e
        | .ok (n, w1) =>
          if (((ext.get w1).asyncOrders pid).orders id).amountIn ≠ 0 then
            match ext.call_AsyncSwap_fillOrderFromPoolLiquidity env.self order id env w1 with
            | .ok (_, w2) => .ok (n, w2)
            | .error _ => .ok (n, w1)
          else .ok (n, w1) := by
  unfold pendingId pendingExecutor clearWorld poolId
  simp only [AsyncSwap.matchNewOrder, PoolIdLibrary.toId]
  simp only [run_bind, run_pure, run_read, run_get, run_modify, run_throw, run_ite,
    run_tryCatch']
  generalize ext.keccak [order.key.currency0, order.key.currency1, order.key.fee,
      toUnsigned 256 order.key.tickSpacing, order.key.hooks] = pid
  generalize hid : (ext.get w).transient AsyncSwap.PENDING_MATCH_ID_SLOT = id
  generalize (ext.get w).transient AsyncSwap.PENDING_MATCH_EXECUTOR_SLOT % 2 ^ 160 = ex
  by_cases h1 : id = 0 ∨ env.sender ≠ ex
  · have b1 : (id == 0 || env.sender != ex) = true := by
      rcases h1 with h | h <;> simp [h]
    rw [ite_pos' h1]; simp only [b1, ite_true]
  have b1 : (id == 0 || env.sender != ex) = false := by
    simp only [not_or, Classical.not_not] at h1; simp [h1.1, h1.2]
  rw [ite_neg' h1]; simp only [b1, ite_false, Bool.false_eq_true]
  generalize ext.set (ext.set w _) _ = w0
  by_cases h2 : (((ext.get w0).asyncOrders pid).orders id).owner ≠ order.owner
  · have b2 : ((((ext.get w0).asyncOrders pid).orders id).owner != order.owner) = true := by
      simp [h2]
    rw [ite_pos' h2]; simp only [b2, ite_true]
  have b2 : ((((ext.get w0).asyncOrders pid).orders id).owner != order.owner) = false := by
    simp only [ne_eq, Classical.not_not] at h2; simp [h2]
  rw [ite_neg' h2]; simp only [b2, ite_false, Bool.false_eq_true]
  have hm : AsyncMatching.matchIncoming ext
      (do return ((ext.get (← get)).asyncOrders pid))
      (fun x => modify fun w => ext.set w (let s := ext.get w; { s with asyncOrders := upd (s.asyncOrders) pid x }))
      (do return ((ext.get (← get)).priceBooks pid))
      (fun x => modify fun w => ext.set w (let s := ext.get w; { s with priceBooks := upd (s.priceBooks) pid x }))
      order.key id env.self =
      AsyncMatching.matchIncoming ext (selfGet ext pid) (selfSet ext pid)
        (bookGet ext pid) (bookSet ext pid) order.key id env.self := rfl
  rw [hm]
  cases AsyncMatching.matchIncoming ext (selfGet ext pid) (selfSet ext pid)
      (bookGet ext pid) (bookSet ext pid) order.key id env.self env w0 with
  | error e => rfl
  | ok p =>
    obtain ⟨n, w1⟩ := p
    simp only
    by_cases h3 : (((ext.get w1).asyncOrders pid).orders id).amountIn ≠ 0
    · have b3 : ((((ext.get w1).asyncOrders pid).orders id).amountIn != 0) = true := by simp [h3]
      rw [ite_pos' h3]; simp only [b3, ite_true]
      cases ext.call_AsyncSwap_fillOrderFromPoolLiquidity env.self order id env w1 <;> rfl
    · have b3 : ((((ext.get w1).asyncOrders pid).orders id).amountIn != 0) = false := by
        simp only [ne_eq, Classical.not_not] at h3; simp [h3]
      rw [ite_neg' h3]; simp only [b3, ite_false, Bool.false_eq_true]

/-! ## Guards -/

/-- **Access control.** Without a pending match, or from anyone but the pending executor, it
reverts. -/
theorem matchNewOrder_unauthorized (order : AsyncOrder) (env : Env) (w : σ)
    (h : pendingId ext w = 0 ∨ env.sender ≠ pendingExecutor ext w) :
    AsyncSwap.matchNewOrder ext order env w = .error ⟨""⟩ := by
  rw [matchNewOrder_run]; simp only; rw [ite_pos' h]

/-- **Frame of the transient clears.** With a lawful `ext`, `clearWorld` zeroes both pending-match
slots and leaves every other transient slot and all persistent storage unchanged. -/
theorem clearWorld_frame (hget : ∀ w s, ext.get (ext.set w s) = s) (w : σ) :
    let w0 := clearWorld ext w
    (ext.get w0).transient AsyncSwap.PENDING_MATCH_ID_SLOT = 0 ∧
    (ext.get w0).transient AsyncSwap.PENDING_MATCH_EXECUTOR_SLOT = 0 ∧
    (∀ k, k ≠ AsyncSwap.PENDING_MATCH_ID_SLOT → k ≠ AsyncSwap.PENDING_MATCH_EXECUTOR_SLOT →
      (ext.get w0).transient k = (ext.get w).transient k) ∧
    (ext.get w0).asyncOrders = (ext.get w).asyncOrders ∧
    (ext.get w0).priceBooks = (ext.get w).priceBooks ∧
    (ext.get w0).owner = (ext.get w).owner ∧
    (ext.get w0).pendingOwner = (ext.get w).pendingOwner ∧
    (ext.get w0).nonceUsed = (ext.get w).nonceUsed := by
  intro w0
  have hne : AsyncSwap.PENDING_MATCH_ID_SLOT ≠ AsyncSwap.PENDING_MATCH_EXECUTOR_SLOT := by
    simp [AsyncSwap.PENDING_MATCH_ID_SLOT, AsyncSwap.PENDING_MATCH_EXECUTOR_SLOT]
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
  · simp [w0, clearWorld, hget, upd, hne]
  · simp [w0, clearWorld, hget, upd]
  · intro k h1 h2; simp [w0, clearWorld, hget, upd, h1, h2]
  all_goals simp [w0, clearWorld, hget]

/-- **Wrong owner.** With a lawful `ext`, an `order` whose `owner` isn't the stored owner of the
pending order id reverts (whoever calls). -/
theorem matchNewOrder_wrongOwner (hget : ∀ w s, ext.get (ext.set w s) = s)
    (order : AsyncOrder) (env : Env) (w : σ)
    (h : (((ext.get w).asyncOrders (poolId ext order.key)).orders (pendingId ext w)).owner ≠
      order.owner) :
    AsyncSwap.matchNewOrder ext order env w = .error ⟨""⟩ := by
  rw [matchNewOrder_run]; simp only
  rw [(clearWorld_frame ext hget w).2.2.2.1]
  by_cases h1 : pendingId ext w = 0 ∨ env.sender ≠ pendingExecutor ext w
  · rw [ite_pos' h1]
  · rw [ite_neg' h1, ite_pos' h]

/-- `AsyncMatching.matchIncoming` reverts when the incoming order is empty (`amountIn = 0`). -/
theorem matchIncoming_empty (pid : Nat) (key : PoolKey) (id hook : Nat) (env : Env) (w : σ)
    (h : (((ext.get w).asyncOrders pid).orders id).amountIn = 0) :
    AsyncMatching.matchIncoming ext (selfGet ext pid) (selfSet ext pid) (bookGet ext pid)
      (bookSet ext pid) key id hook env w = .error ⟨""⟩ := by
  simp only [AsyncMatching.matchIncoming, run_bind, run_pure, run_throw, run_ite]
  have hs : selfGet ext pid env w = .ok ((ext.get w).asyncOrders pid, w) := rfl
  rw [hs]; simp only [h, beq_self_eq_true, ite_true]

/-- **Empty order.** With a lawful `ext`, if the pending order has `amountIn = 0`, the call reverts
(at the latest at `matchIncoming`'s `incoming.amountIn == 0` guard). -/
theorem matchNewOrder_emptyOrder (hget : ∀ w s, ext.get (ext.set w s) = s)
    (order : AsyncOrder) (env : Env) (w : σ)
    (h : (((ext.get w).asyncOrders (poolId ext order.key)).orders (pendingId ext w)).amountIn = 0) :
    ∃ e, AsyncSwap.matchNewOrder ext order env w = .error e := by
  rw [matchNewOrder_run]; simp only
  split
  · exact ⟨_, rfl⟩
  split
  · exact ⟨_, rfl⟩
  have h' := h
  rw [← (clearWorld_frame ext hget w).2.2.2.1] at h'
  rw [matchIncoming_empty ext _ _ _ _ env _ h']
  exact ⟨_, rfl⟩

/-- **Re-entry.** With a lawful `ext`, from the world right after the pending match is consumed,
`matchNewOrder` reverts for every caller and every order. -/
theorem matchNewOrder_reentry_reverts (hget : ∀ w s, ext.get (ext.set w s) = s)
    (order : AsyncOrder) (env : Env) (w : σ) :
    AsyncSwap.matchNewOrder ext order env (clearWorld ext w) = .error ⟨""⟩ := by
  apply matchNewOrder_unauthorized
  left
  exact (clearWorld_frame ext hget w).1

/-! ## Return bound -/

private theorem returns_throw {α : Type} (e : Revert) (Q : α → Prop) :
    Returns (throw e : M σ α) Q := by
  intro env w a w' h
  rw [run_throw] at h
  cases h

/-- `AsyncMatching.matchIncoming`, for any accessors, returns at most `MAX_MATCHES_PER_CALL`. -/
theorem matchIncoming_le (sg : M σ AsyncFiller.State_) (ss : AsyncFiller.State_ → M σ Unit)
    (bg : M σ AsyncFiller.Book) (bs : AsyncFiller.Book → M σ Unit) (key : PoolKey) (id hook : Nat) :
    Returns (AsyncMatching.matchIncoming ext sg ss bg bs key id hook)
      (fun n => n ≤ AsyncMatching.MAX_MATCHES_PER_CALL) := by
  unfold AsyncMatching.matchIncoming
  refine returns_bind_any (fun S => ?_)
  refine returns_ite (fun _ => returns_throw _ _) (fun _ => ?_)
  refine returns_bind (R := fun b : Nat × Bool => b.1 ≤ AsyncMatching.MAX_MATCHES_PER_CALL) ?_ ?_
  · refine returns_forIn_range (σ := σ) (β := Nat × Bool)
      (fun b => b.1 ≤ AsyncMatching.MAX_MATCHES_PER_CALL) _ _ _ ?_ (Nat.zero_le _)
    intro i b hb
    repeat' (first
      | ((with_reducible apply returns_ite) <;> intro _)
      | ((with_reducible apply returns_bind_any); intro _)
      | (with_reducible apply returns_pure))
    all_goals simp only [stepVal]
    all_goals first
      | exact hb
      | (exfalso; simp_all; done)
      | (simp only [decide_eq_true_eq, Bool.not_eq_true'] at *; simp only [addw,
          AsyncMatching.MAX_MATCHES_PER_CALL, Nat.reducePow] at *; omega)
  · intro b hb
    dsimp only
    exact returns_ite (fun _ => returns_bind_any fun _ => returns_pure hb)
      (fun _ => returns_pure hb)

/-- **Success.** With a lawful `ext`, a successful `matchNewOrder` was called by the pending
executor, with a pending `id ≠ 0` whose stored owner is `order.owner`, and returns at most
`MAX_MATCHES_PER_CALL = 8` matches. -/
theorem matchNewOrder_ok (hget : ∀ w s, ext.get (ext.set w s) = s)
    (order : AsyncOrder) (env : Env) (w : σ) (n : Nat) (w' : σ)
    (h : AsyncSwap.matchNewOrder ext order env w = .ok (n, w')) :
    pendingId ext w ≠ 0 ∧ env.sender = pendingExecutor ext w ∧
    (((ext.get w).asyncOrders (poolId ext order.key)).orders (pendingId ext w)).owner =
      order.owner ∧
    n ≤ AsyncMatching.MAX_MATCHES_PER_CALL := by
  rw [matchNewOrder_run] at h; simp only at h
  rw [(clearWorld_frame ext hget w).2.2.2.1] at h
  split at h
  · cases h
  rename_i h1
  split at h
  · cases h
  rename_i h2
  simp only [not_or, ne_eq, Classical.not_not] at h1 h2
  refine ⟨h1.1, h1.2, h2, ?_⟩
  split at h
  · cases h
  rename_i n1 w1 hm
  have hle := matchIncoming_le ext _ _ _ _ _ _ _ env _ n1 w1 hm
  split at h
  · split at h
    · simp only [Except.ok.injEq, Prod.mk.injEq] at h
      exact h.1 ▸ hle
    · simp only [Except.ok.injEq, Prod.mk.injEq] at h
      exact h.1 ▸ hle
  · simp only [Except.ok.injEq, Prod.mk.injEq] at h
    exact h.1 ▸ hle

end AsyncSwap.Swarm.MatchNewOrder
