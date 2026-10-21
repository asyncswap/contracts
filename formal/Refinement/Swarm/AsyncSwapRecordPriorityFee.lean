import Generated.AsyncSwap
import Refinement.Monad

/-!
# `AsyncSwap.recordPriorityFee`

`function recordPriorityFee(PoolKey calldata key, address maker, uint256 amount) external`
(src/AsyncSwap.sol:254), through `AsyncMatching.recordPriorityFee` → `AsyncFiller.recordPriorityFee`.

With `pid = key.toId()`, `id = tload(PENDING_MATCH_ID_SLOT)`,
`executor = address(tload(PENDING_MATCH_EXECUTOR_SLOT))`, `S = asyncOrders[pid]`, `info = S.orders[id]`:

* reverts (`NotAuthorizedExecutor`) when no match is pending (`id = 0`) or `msg.sender ≠ executor`;
* reverts (`OrderNotFound`) when `info.owner ≠ maker`;
* reverts `PriorityFeeNotEscrowed` when `info.amountIn = 0`, the bid is already escrowed,
  `info.priorityFee ≠ amount`, or `amount = 0`;
* otherwise: `poolManager.mint(address(this), numeraire, amount)` (the `take(..., claims = true)`
  of the escrowed bid as ERC-6909 claims held by this contract), then
  `orders[id].priorityFeeEscrowed := true`, then, in `PriorityFee` ordering mode (`= 1`), the
  `_remove`/`_append` re-queue of `id` on `asyncOrders[pid]`/`priceBooks[pid]` (opaque in the model:
  the `RadixPriceTree` guards and the `orderCount`/`openOrderCount` counters live there).

The model gives the first two guards (custom errors) the reason `""`; the third has
`"PriorityFeeNotEscrowed"`.

For the maintainer's "self-fill to sweep funds" concern:
* only the transient pending-match executor can call it, and only for the pending match's order id
  (both read from transient storage, never calldata), and only if the stored order's owner is the
  `maker` it names;
* the amount credited is *exactly* the order's stored `priorityFee` (the guard forces
  `amount = info.priorityFee`), always to `address(this)`, in the immutable numeraire: no third
  party is paid and nothing leaves the protocol;
* outside the opaque re-queue, the only storage write is that one order's `priorityFeeEscrowed`
  flag, `false → true` (`flagWorld_frame`), so the same bid can never be escrowed (and so counted)
  twice (`recordPriorityFee_twice_reverts`).
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.RecordPriorityFee

private theorem ite_pos' {α : Type} {c : Prop} [Decidable c] (h : c) (a b : α) :
    (if c then a else b) = a := by simp [h]
private theorem ite_neg' {α : Type} {c : Prop} [Decidable c] (h : ¬c) (a b : α) :
    (if c then a else b) = b := by simp [h]

variable {σ : Type} (ext : Ext σ)

/-- `PoolIdLibrary.toId key` in the model. -/
def poolId (key : PoolKey) : Nat :=
  ext.keccak [key.currency0, key.currency1, key.fee, toUnsigned 256 key.tickSpacing, key.hooks]

/-- The pending match id (transient). -/
def pendingId (w : σ) : Nat := (ext.get w).transient AsyncSwap.PENDING_MATCH_ID_SLOT

/-- The pending match executor (transient, cast to `address`). -/
def pendingExecutor (w : σ) : Nat :=
  (ext.get w).transient AsyncSwap.PENDING_MATCH_EXECUTOR_SLOT % 2 ^ 160

def selfGet (pid : Nat) : M σ AsyncFiller.State_ := do return ((ext.get (← get)).asyncOrders pid)
def selfSet (pid : Nat) : AsyncFiller.State_ → M σ Unit := fun x =>
  modify fun w => ext.set w (let s := ext.get w; { s with asyncOrders := upd (s.asyncOrders) pid x })
def bookGet (pid : Nat) : M σ AsyncFiller.Book := do return ((ext.get (← get)).priceBooks pid)
def bookSet (pid : Nat) : AsyncFiller.Book → M σ Unit := fun x =>
  modify fun w => ext.set w (let s := ext.get w; { s with priceBooks := upd (s.priceBooks) pid x })

/-- The world after `asyncOrders[pid].orders[id].priorityFeeEscrowed := true`. -/
def flagWorld (pid id : Nat) (w : σ) : σ :=
  let S := (ext.get w).asyncOrders pid
  ext.set w { ext.get w with
    asyncOrders := upd (ext.get w).asyncOrders pid
      { S with orders := upd S.orders id { S.orders id with priorityFeeEscrowed := true } } }

/-- What runs once the mint returns in world `w1`: set the flag, then (priority mode) re-queue. -/
def afterMint (pid id : Nat) (w1 : σ) : M σ Unit := fun env _ =>
  let w2 := flagWorld ext pid id w1
  if ((ext.get w2).priceBooks pid).orderingMode = 1 then
    (do
      ext.fn_AsyncFiller_remove_6902 (selfGet ext pid) (selfSet ext pid) (bookGet ext pid)
        (bookSet ext pid) id
      ext.fn_AsyncFiller_append_6737 (selfGet ext pid) (selfSet ext pid) (bookGet ext pid)
        (bookSet ext pid) id) env w2
  else .ok ((), w2)

/-- **Full characterization** of `AsyncSwap.recordPriorityFee`: three guards, the mint of exactly
`amount` numeraire claims to `address(this)`, then `afterMint`. -/
theorem recordPriorityFee_run (key : PoolKey) (maker amount : Nat) (env : Env) (w : σ) :
    AsyncSwap.recordPriorityFee ext key maker amount env w =
      let pid := poolId ext key
      let id := pendingId ext w
      let S := (ext.get w).asyncOrders pid
      let info := S.orders id
      if id = 0 ∨ env.sender ≠ pendingExecutor ext w then .error ⟨""⟩
      else if info.owner ≠ maker then .error ⟨""⟩
      else if info.amountIn = 0 ∨ info.priorityFeeEscrowed = true ∨ info.priorityFee ≠ amount
          ∨ amount = 0 then .error ⟨"PriorityFeeNotEscrowed"⟩
      else match ext.call_IPoolManager_mint S.poolManager env.self ext.numeraire amount env w with
        | .ok (_, w1) => afterMint ext pid id w1 env w1
        | .error e => .error e := by
  unfold poolId pendingId pendingExecutor
  simp only [AsyncSwap.recordPriorityFee, AsyncMatching.recordPriorityFee, AsyncFiller.recordPriorityFee,
    PoolIdLibrary.toId, CurrencySettler.take, CurrencyLibrary.toId,
    bind_pure_unit, bind_assoc, pure_bind]
  simp only [run_bind, run_pure, run_read, run_get, run_modify, run_throw, run_ite, ite_true]
  generalize ext.keccak [key.currency0, key.currency1, key.fee,
      toUnsigned 256 key.tickSpacing, key.hooks] = pid
  generalize (ext.get w).transient AsyncSwap.PENDING_MATCH_ID_SLOT = id
  generalize (ext.get w).transient AsyncSwap.PENDING_MATCH_EXECUTOR_SLOT % 2 ^ 160 = ex
  generalize ((ext.get w).asyncOrders pid).orders id = info
  generalize ext.call_IPoolManager_mint _ _ _ _ _ _ = m
  by_cases h1 : id = 0 ∨ env.sender ≠ ex
  · have b1 : (id == 0 || env.sender != ex) = true := by
      rcases h1 with h | h <;> simp [h]
    rw [ite_pos' h1]; simp only [b1, ite_true]
  have b1 : (id == 0 || env.sender != ex) = false := by
    simp only [not_or, Classical.not_not] at h1; simp [h1.1, h1.2]
  rw [ite_neg' h1]; simp only [b1, ite_false, Bool.false_eq_true]
  by_cases h2 : info.owner ≠ maker
  · have b2 : (info.owner != maker) = true := by simp [h2]
    rw [ite_pos' h2]; simp only [b2, ite_true]
  have b2 : (info.owner != maker) = false := by
    simp only [ne_eq, Classical.not_not] at h2; simp [h2]
  rw [ite_neg' h2]; simp only [b2, ite_false, Bool.false_eq_true]
  by_cases hg : info.amountIn = 0 ∨ info.priorityFeeEscrowed = true ∨ info.priorityFee ≠ amount ∨ amount = 0
  · rw [ite_pos' hg]
    cases hA : (info.amountIn == 0) <;> cases hE : info.priorityFeeEscrowed <;>
      cases hF : (info.priorityFee != amount) <;> cases hZ : (amount == 0) <;>
      simp only [Bool.not_true, Bool.not_false, Bool.or_true, Bool.or_false, ite_true, ite_false,
        Bool.false_eq_true] <;>
      first
        | rfl
        | (exfalso; simp only [beq_eq_false_iff_ne, bne_eq_false_iff_eq, ne_eq] at hA hF hZ
           rcases hg with h | h | h | h
           · exact hA h
           · rw [hE] at h; cases h
           · exact h hF
           · exact hZ h)
  · rw [ite_neg' hg]
    simp only [not_or, ne_eq, Classical.not_not, Bool.not_eq_true] at hg
    obtain ⟨ha, he, hf, hz⟩ := hg
    have ba : (info.amountIn == 0) = false := by simp [ha]
    have bf : (info.priorityFee != amount) = false := by simp [hf]
    have bz : (amount == 0) = false := by simp [hz]
    simp only [ba, he, bf, bz, Bool.not_false, Bool.false_or, ite_true, ite_false, Bool.false_eq_true]
    cases m with
    | error e => rfl
    | ok p =>
      obtain ⟨⟨⟩, w1⟩ := p
      simp only [afterMint, flagWorld, selfGet, bookGet, run_bind, beq_iff_eq]
      rfl

/-- **Access control.** Without a pending match, or from anyone but the pending executor, it
reverts. -/
theorem recordPriorityFee_unauthorized (key : PoolKey) (maker amount : Nat) (env : Env) (w : σ)
    (h : pendingId ext w = 0 ∨ env.sender ≠ pendingExecutor ext w) :
    AsyncSwap.recordPriorityFee ext key maker amount env w = .error ⟨""⟩ := by
  rw [recordPriorityFee_run]; simp only; rw [ite_pos' h]

/-- **Wrong maker.** Naming a `maker` other than the pending order's stored owner reverts. -/
theorem recordPriorityFee_wrong_maker (key : PoolKey) (maker amount : Nat) (env : Env) (w : σ)
    (h : (((ext.get w).asyncOrders (poolId ext key)).orders (pendingId ext w)).owner ≠ maker) :
    AsyncSwap.recordPriorityFee ext key maker amount env w = .error ⟨""⟩ := by
  rw [recordPriorityFee_run]; simp only
  by_cases h1 : pendingId ext w = 0 ∨ env.sender ≠ pendingExecutor ext w
  · rw [ite_pos' h1]
  · rw [ite_neg' h1, ite_pos' h]

/-- **Bid already escrowed.** Once the pending order's bid is escrowed, any further call reverts. -/
theorem recordPriorityFee_escrowed_reverts (key : PoolKey) (maker amount : Nat) (env : Env) (w : σ)
    (h : (((ext.get w).asyncOrders (poolId ext key)).orders (pendingId ext w)).priorityFeeEscrowed = true) :
    ∃ e, AsyncSwap.recordPriorityFee ext key maker amount env w = .error e := by
  rw [recordPriorityFee_run]; simp only
  split
  · exact ⟨_, rfl⟩
  split
  · exact ⟨_, rfl⟩
  rw [ite_pos' (Or.inr (Or.inl h))]
  exact ⟨_, rfl⟩

/-- **Amount pinned.** Any `amount` other than the order's stored `priorityFee` reverts. -/
theorem recordPriorityFee_amount_mismatch_reverts (key : PoolKey) (maker amount : Nat) (env : Env)
    (w : σ)
    (h : (((ext.get w).asyncOrders (poolId ext key)).orders (pendingId ext w)).priorityFee ≠ amount) :
    ∃ e, AsyncSwap.recordPriorityFee ext key maker amount env w = .error e := by
  rw [recordPriorityFee_run]; simp only
  split
  · exact ⟨_, rfl⟩
  split
  · exact ⟨_, rfl⟩
  rw [ite_pos' (Or.inr (Or.inr (Or.inl h)))]
  exact ⟨_, rfl⟩

/-- **Success.** A successful `recordPriorityFee` came from the pending executor, on the pending
order (`id ≠ 0`), owned by `maker`, live (`amountIn ≠ 0`), not yet escrowed, with
`amount = info.priorityFee ≠ 0`; it minted exactly `amount` numeraire claims to `address(this)` on
the pool's manager, then ran `afterMint` (flag, then re-queue in priority mode). -/
theorem recordPriorityFee_ok (key : PoolKey) (maker amount : Nat) (env : Env) (w w' : σ)
    (h : AsyncSwap.recordPriorityFee ext key maker amount env w = .ok ((), w')) :
    let pid := poolId ext key
    let id := pendingId ext w
    let S := (ext.get w).asyncOrders pid
    let info := S.orders id
    id ≠ 0 ∧ env.sender = pendingExecutor ext w ∧ info.owner = maker ∧ info.amountIn ≠ 0 ∧
    info.priorityFeeEscrowed = false ∧ info.priorityFee = amount ∧ amount ≠ 0 ∧
    ∃ w1, ext.call_IPoolManager_mint S.poolManager env.self ext.numeraire amount env w = .ok ((), w1) ∧
      afterMint ext pid id w1 env w1 = .ok ((), w') := by
  intro pid id S info
  rw [recordPriorityFee_run] at h
  simp only at h
  split at h
  · cases h
  rename_i h1
  split at h
  · cases h
  rename_i h2
  split at h
  · cases h
  rename_i h3
  simp only [not_or, ne_eq, Classical.not_not, Bool.not_eq_true] at h1 h2 h3
  obtain ⟨ha, he, hf, hz⟩ := h3
  refine ⟨h1.1, h1.2, h2, ha, he, hf, hz, ?_⟩
  split at h
  · rename_i a w1 hm
    cases a
    exact ⟨w1, hm, h⟩
  · cases h

/-- **Frame of the flag write.** With a lawful `ext` (`get ∘ set = id`), `flagWorld` sets exactly
`asyncOrders[pid].orders[id].priorityFeeEscrowed := true` and leaves every other order, every other
pool, every pool's manager and executors, the price books and the transient slots unchanged. -/
theorem flagWorld_frame (hget : ∀ w s, ext.get (ext.set w s) = s) (pid id : Nat) (w : σ) :
    let w2 := flagWorld ext pid id w
    (((ext.get w2).asyncOrders pid).orders id =
        { ((ext.get w).asyncOrders pid).orders id with priorityFeeEscrowed := true }) ∧
    (∀ p i, (p, i) ≠ (pid, id) →
        ((ext.get w2).asyncOrders p).orders i = ((ext.get w).asyncOrders p).orders i) ∧
    (∀ p, ((ext.get w2).asyncOrders p).poolManager = ((ext.get w).asyncOrders p).poolManager) ∧
    (∀ p, ((ext.get w2).asyncOrders p).isExecutor = ((ext.get w).asyncOrders p).isExecutor) ∧
    (ext.get w2).priceBooks = (ext.get w).priceBooks ∧
    (ext.get w2).transient = (ext.get w).transient := by
  intro w2
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_⟩
  · simp [w2, flagWorld, hget, upd]
  · intro p i hne
    by_cases hp : p = pid
    · subst hp
      have hi : i ≠ id := fun hi => hne (by rw [hi])
      simp [w2, flagWorld, hget, upd, hi]
    · simp [w2, flagWorld, hget, upd, hp]
  · intro p
    by_cases hp : p = pid
    · subst hp; simp [w2, flagWorld, hget, upd]
    · simp [w2, flagWorld, hget, upd, hp]
  · intro p
    by_cases hp : p = pid
    · subst hp; simp [w2, flagWorld, hget, upd]
    · simp [w2, flagWorld, hget, upd, hp]
  · simp [w2, flagWorld, hget]
  · simp [w2, flagWorld, hget]

/-- **No double escrow.** From the world right after the flag write (so from anything the re-queue
or a later call sees before the slot is rewritten), recording the bid of the same pending order in
the same pool again reverts, whoever calls and whatever `maker`/`amount` it passes. -/
theorem recordPriorityFee_twice_reverts (hget : ∀ w s, ext.get (ext.set w s) = s)
    (key : PoolKey) (maker amount : Nat) (env : Env) (w1 : σ) :
    ∃ e, AsyncSwap.recordPriorityFee ext key maker amount env
      (flagWorld ext (poolId ext key) (pendingId ext w1) w1) = .error e := by
  apply recordPriorityFee_escrowed_reverts
  have ht : pendingId ext (flagWorld ext (poolId ext key) (pendingId ext w1) w1) = pendingId ext w1 := by
    simp [pendingId, flagWorld, hget]
  rw [ht, (flagWorld_frame ext hget _ _ w1).1]

end AsyncSwap.Swarm.RecordPriorityFee
