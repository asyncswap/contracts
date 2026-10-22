import Generated.AsyncSwap
import Refinement.Monad
import Refinement.Swarm.AsyncSwapUpdatePrice
import Refinement.Swarm.AsyncSwapPriorityKey

/-!
# `AsyncFiller.addOrder` and `AsyncMatching.addOrder`

`function addOrder(Pool storage self, Book storage book, NewOrder memory order) internal`
(the `AsyncFiller` library), run on pool `pid`: `self = asyncOrders[pid]`, `book = priceBooks[pid]`.

With `B = priceBooks[pid]`:

* reverts `InvalidOrderingModeChange` when `B.orderingMode = 0` and `priorityFee ≠ 0`;
* reverts `PriorityFeeTooSmall` when `B.orderingMode = 1` and `priorityFee < MIN_PRIORITY_FEE`;
* reverts `PriorityFeeTooLarge` when `priorityFee > MAX_PRIORITY_FEE = 2^64 − 1`;
* reverts when `_priceKey(isBuy, amountIn, amountOutMin)` reverts (zero divisor / mulDiv overflow);
* panics `0x11` when `B.nextSequence + 1` does not fit uint64;
* otherwise writes `priceBooks[pid].nextSequence := seq = B.nextSequence + 1` and
  `asyncOrders[pid].orders[id] := newOrder …` (price key in `[1, 2^128)`, `previous = next = 0`,
  `sequence = seq`, `priorityFee`, `priorityKey = _priorityKey(0, seq) = 2^64 − 1 − seq`,
  `priorityFeeEscrowed = (priorityFee = 0)`), then hands `id` to `_append` (opaque in the model).

No external call, no token movement; every other order, pool, book field and storage slot is
unchanged before `_append`.

`AsyncMatching.addOrder(self, book, order)` (the matching book's entry) is exactly
`AsyncFiller.addOrder` on the fields of the `NewOrder` struct, for any storage accessors; all the
results above transfer to it (section at the end).
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.AddOrder

variable {σ : Type} (ext : Ext σ)

def selfGet (pid : Nat) : M σ AsyncFiller.State_ := do return ((ext.get (← get)).asyncOrders pid)
def selfSet (pid : Nat) : AsyncFiller.State_ → M σ Unit := fun x =>
  modify fun w => ext.set w (let s := ext.get w; { s with asyncOrders := upd (s.asyncOrders) pid x })
def bookGet (pid : Nat) : M σ AsyncFiller.Book := do return ((ext.get (← get)).priceBooks pid)
def bookSet (pid : Nat) : AsyncFiller.Book → M σ Unit := fun x =>
  modify fun w => ext.set w (let s := ext.get w; { s with priceBooks := upd (s.priceBooks) pid x })

/-- The order record `addOrder` stores. -/
def newOrder (owner amountIn amountOutMin : Nat) (isBuy zeroForOne : Bool) (fee p seq : Nat) :
    AsyncFiller.OrderInfo :=
  { owner := owner, amountIn := amountIn, amountOutMin := amountOutMin, price := p, previous := 0,
    next := 0, isBuy := isBuy, zeroForOne := zeroForOne, sequence := seq,
    priorityFee := fee % 2 ^ 64, priorityKey := 2 ^ 64 - 1 - seq, priorityFeeEscrowed := (fee == 0) }

def bookW (pid seq : Nat) (s : AsyncSwap.State) : AsyncSwap.State :=
  { s with priceBooks := upd s.priceBooks pid ({ (s.priceBooks pid) with nextSequence := seq }) }

def orderW (pid id : Nat) (o : AsyncFiller.OrderInfo) (s : AsyncSwap.State) : AsyncSwap.State :=
  { s with asyncOrders := upd s.asyncOrders pid ({ (s.asyncOrders pid) with orders := upd (s.asyncOrders pid).orders id o }) }

/-- The world after the two writes (book's `nextSequence`, then `orders[id]`). -/
def addWrite (pid id : Nat) (o : AsyncFiller.OrderInfo) (seq : Nat) (w : σ) : σ :=
  let w1 := ext.set w (bookW pid seq (ext.get w))
  ext.set w1 (orderW pid id o (ext.get w1))

/-- The contract storage after the writes. -/
def addState (G : AsyncSwap.State) (pid id : Nat) (o : AsyncFiller.OrderInfo) (seq : Nat) :
    AsyncSwap.State :=
  orderW pid id o (bookW pid seq G)

theorem priorityKey_zero (seq : Nat) (env : Env) (w : σ) :
    AsyncSwap.AsyncFiller.«_priorityKey» ext 0 seq env w
      = if seq ≤ 2 ^ 64 - 1 then .ok (2 ^ 64 - 1 - seq, w) else .error (panic "0x11") := by
  rw [AsyncSwap.Swarm.PriorityKey.priorityKey_spec]
  simp [shlw]

/-- **Full characterization** of `AsyncFiller.addOrder` on pool `pid`: three fee/mode guards,
then `_priceKey`, then the checked uint64 sequence bump, then the two writes and `_append`. -/
theorem addOrder_run (pid id owner aIn aOut : Nat) (isBuy zfo : Bool) (fee : Nat) (env : Env) (w : σ) :
    AsyncFiller.addOrder ext (selfGet ext pid) (selfSet ext pid) (bookGet ext pid) (bookSet ext pid)
        id owner aIn aOut isBuy zfo fee env w =
      let B := (ext.get w).priceBooks pid
      if B.orderingMode = 0 ∧ fee ≠ 0 then .error ⟨"InvalidOrderingModeChange"⟩
      else if B.orderingMode = 1 ∧ fee < AsyncFiller.MIN_PRIORITY_FEE then .error ⟨"PriorityFeeTooSmall"⟩
      else if fee > AsyncFiller.MAX_PRIORITY_FEE then .error ⟨"PriorityFeeTooLarge"⟩
      else match AsyncFiller.«_priceKey» ext isBuy aIn aOut env w with
        | .error e => .error e
        | .ok (p, w0) =>
          let seq := ((ext.get w0).priceBooks pid).nextSequence + 1
          if seq < 2 ^ 64 then
            ext.fn_AsyncFiller_append_6737 (selfGet ext pid) (selfSet ext pid) (bookGet ext pid)
              (bookSet ext pid) id env
              (addWrite ext pid id (newOrder owner aIn aOut isBuy zfo fee p seq) seq w0)
          else .error (panic "0x11") := by
  simp only [AsyncFiller.addOrder, bind_pure_unit]
  by_cases h1 : ((ext.get w).priceBooks pid).orderingMode = 0 ∧ fee ≠ 0
  · simp [selfGet, bookGet, h1]
  · by_cases h2 : ((ext.get w).priceBooks pid).orderingMode = 1 ∧ fee < AsyncFiller.MIN_PRIORITY_FEE
    · simp [selfGet, bookGet, h2]
    · by_cases h3 : fee > AsyncFiller.MAX_PRIORITY_FEE
      · simp [selfGet, bookGet, h3]
      · simp only [h1, h2, h3, ite_false]
        simp only [run_bind, bookGet, selfGet, run_get, run_pure, run_ite, run_throw]
        have hb1 : (((ext.get w).priceBooks pid).orderingMode == 0 && fee != 0) = false := by
          by_cases hm : ((ext.get w).priceBooks pid).orderingMode = 0 <;> simp_all
        have hb2 : (((ext.get w).priceBooks pid).orderingMode == 1 &&
            decide (fee < AsyncFiller.MIN_PRIORITY_FEE)) = false := by
          by_cases hm : ((ext.get w).priceBooks pid).orderingMode = 1 <;> simp_all
        simp only [hb1, hb2, decide_false, Bool.false_eq_true, ite_false]
        rcases AsyncFiller.«_priceKey» ext isBuy aIn aOut env w with e | ⟨p, w0⟩
        · rfl
        · simp only
          by_cases hs : ((ext.get w0).priceBooks pid).nextSequence + 1 < 18446744073709551616
          · have hs' : ((ext.get w0).priceBooks pid).nextSequence + 1 ≤ 18446744073709551615 := by
              omega
            simp [addc, hs, hs', bookSet, selfSet, priorityKey_zero, addWrite, bookW, orderW,
              newOrder] <;> rfl
          · simp [addc, hs]

/-- Guard 1: in FIFO mode (`orderingMode = 0`) a nonzero priority fee reverts. -/
theorem addOrder_invalidMode (pid id owner aIn aOut : Nat) (isBuy zfo : Bool) (fee : Nat)
    (env : Env) (w : σ) (hm : ((ext.get w).priceBooks pid).orderingMode = 0) (hf : fee ≠ 0) :
    AsyncFiller.addOrder ext (selfGet ext pid) (selfSet ext pid) (bookGet ext pid) (bookSet ext pid)
        id owner aIn aOut isBuy zfo fee env w = .error ⟨"InvalidOrderingModeChange"⟩ := by
  rw [addOrder_run]; simp [hm, hf]

/-- Guard 2: in priority mode (`orderingMode = 1`) a fee below `MIN_PRIORITY_FEE` reverts. -/
theorem addOrder_feeTooSmall (pid id owner aIn aOut : Nat) (isBuy zfo : Bool) (fee : Nat)
    (env : Env) (w : σ) (hm : ((ext.get w).priceBooks pid).orderingMode = 1)
    (hf : fee < AsyncFiller.MIN_PRIORITY_FEE) :
    AsyncFiller.addOrder ext (selfGet ext pid) (selfSet ext pid) (bookGet ext pid) (bookSet ext pid)
        id owner aIn aOut isBuy zfo fee env w = .error ⟨"PriorityFeeTooSmall"⟩ := by
  rw [addOrder_run]; simp [hm, hf]

/-- Guard 3: a fee above `MAX_PRIORITY_FEE = 2^64 − 1` reverts (once guards 1–2 pass). -/
theorem addOrder_feeTooLarge (pid id owner aIn aOut : Nat) (isBuy zfo : Bool) (fee : Nat)
    (env : Env) (w : σ)
    (h1 : ¬ (((ext.get w).priceBooks pid).orderingMode = 0 ∧ fee ≠ 0))
    (h2 : ¬ (((ext.get w).priceBooks pid).orderingMode = 1 ∧ fee < AsyncFiller.MIN_PRIORITY_FEE))
    (hf : fee > AsyncFiller.MAX_PRIORITY_FEE) :
    AsyncFiller.addOrder ext (selfGet ext pid) (selfSet ext pid) (bookGet ext pid) (bookSet ext pid)
        id owner aIn aOut isBuy zfo fee env w = .error ⟨"PriorityFeeTooLarge"⟩ := by
  rw [addOrder_run]; simp only [h1, h2, hf, ite_false, ite_true]

/-- Guard 4: with the fee checks passing and `_priceKey` succeeding, a sequence counter at
`2^64 − 1` panics `0x11` (checked uint64 increment). -/
theorem addOrder_seqOverflow (pid id owner aIn aOut : Nat) (isBuy zfo : Bool) (fee p : Nat)
    (env : Env) (w : σ)
    (h1 : ¬ (((ext.get w).priceBooks pid).orderingMode = 0 ∧ fee ≠ 0))
    (h2 : ¬ (((ext.get w).priceBooks pid).orderingMode = 1 ∧ fee < AsyncFiller.MIN_PRIORITY_FEE))
    (h3 : ¬ fee > AsyncFiller.MAX_PRIORITY_FEE)
    (hp : AsyncFiller.«_priceKey» ext isBuy aIn aOut env w = .ok (p, w))
    (hs : 2 ^ 64 ≤ ((ext.get w).priceBooks pid).nextSequence + 1) :
    AsyncFiller.addOrder ext (selfGet ext pid) (selfSet ext pid) (bookGet ext pid) (bookSet ext pid)
        id owner aIn aOut isBuy zfo fee env w = .error (panic "0x11") := by
  rw [addOrder_run]
  have : ¬ (((ext.get w).priceBooks pid).nextSequence + 1 < 2 ^ 64) := by omega
  simp only [h1, h2, h3, ite_false, hp, this]

/-- With a lawful `ext` (`get ∘ set = id`), the storage after the writes is `addState`. -/
theorem get_addWrite (hget : ∀ w s, ext.get (ext.set w s) = s) (pid id : Nat)
    (o : AsyncFiller.OrderInfo) (seq : Nat) (w : σ) :
    ext.get (addWrite ext pid id o seq w) = addState (ext.get w) pid id o seq := by
  simp [addWrite, addState, hget]

/-- **Success.** A successful `addOrder` passed the three fee/mode guards; `_priceKey` returned a
key `p ∈ [1, 2^128)` without touching storage; `seq = nextSequence + 1` fits uint64; the storage
handed to `_append` is exactly `addState` (the new order at `id`, the bumped sequence) and
`_append` then produced the final state. -/
theorem addOrder_ok (hget : ∀ w s, ext.get (ext.set w s) = s)
    (pid id owner aIn aOut : Nat) (isBuy zfo : Bool) (fee : Nat) (env : Env) (w w' : σ)
    (h : AsyncFiller.addOrder ext (selfGet ext pid) (selfSet ext pid) (bookGet ext pid)
      (bookSet ext pid) id owner aIn aOut isBuy zfo fee env w = .ok ((), w')) :
    let B := (ext.get w).priceBooks pid
    let seq := B.nextSequence + 1
    ¬ (B.orderingMode = 0 ∧ fee ≠ 0) ∧
    ¬ (B.orderingMode = 1 ∧ fee < AsyncFiller.MIN_PRIORITY_FEE) ∧
    fee ≤ AsyncFiller.MAX_PRIORITY_FEE ∧ seq < 2 ^ 64 ∧
    ∃ p w1, AsyncFiller.«_priceKey» ext isBuy aIn aOut env w = .ok (p, w) ∧
      1 ≤ p ∧ p < 2 ^ 128 ∧
      ext.get w1 = addState (ext.get w) pid id (newOrder owner aIn aOut isBuy zfo fee p seq) seq ∧
      ext.fn_AsyncFiller_append_6737 (selfGet ext pid) (selfSet ext pid) (bookGet ext pid)
        (bookSet ext pid) id env w1 = .ok ((), w') := by
  intro B seq
  rw [addOrder_run] at h
  simp only at h
  split at h
  · cases h
  · rename_i h1
    split at h
    · cases h
    · rename_i h2
      split at h
      · cases h
      · rename_i h3
        refine ⟨h1, h2, by omega, ?_⟩
        split at h
        · cases h
        · rename_i p w0 hp
          obtain ⟨rfl, hp1, hp2⟩ := AsyncSwap.Swarm.UpdatePrice.priceKey_ok ext _ _ _ _ _ _ _ hp
          split at h
          · rename_i hs
            exact ⟨hs, p, _, hp, hp1, hp2, get_addWrite ext hget _ _ _ _ _, h⟩
          · cases h

/-! ## What `addState` changes -/

/-- The stored order is exactly `newOrder …`: given owner, input, minimum output, side and
direction, price key `p`, unlinked (`previous = next = 0`), fresh sequence, fee truncated to 64 bits,
priority key `2^64 − 1 − seq` (fee 0 until escrowed) and `priorityFeeEscrowed = (fee = 0)`. -/
theorem addState_order (G : AsyncSwap.State) (pid id owner aIn aOut : Nat) (isBuy zfo : Bool)
    (fee p seq : Nat) :
    let o := ((addState G pid id (newOrder owner aIn aOut isBuy zfo fee p seq) seq).asyncOrders pid).orders id
    o.owner = owner ∧ o.amountIn = aIn ∧ o.amountOutMin = aOut ∧ o.price = p ∧
      o.previous = 0 ∧ o.next = 0 ∧ o.isBuy = isBuy ∧ o.zeroForOne = zfo ∧ o.sequence = seq ∧
      o.priorityFee = fee % 2 ^ 64 ∧ o.priorityKey = 2 ^ 64 - 1 - seq ∧
      o.priorityFeeEscrowed = (fee == 0) := by
  simp [addState, orderW, bookW, upd, newOrder]

/-- The book's sequence counter becomes `seq`; every other field of the book is unchanged. -/
theorem addState_book (G : AsyncSwap.State) (pid id : Nat) (o : AsyncFiller.OrderInfo) (seq : Nat) :
    let B := G.priceBooks pid
    let B' := (addState G pid id o seq).priceBooks pid
    B'.nextSequence = seq ∧ B'.openOrderCount = B.openOrderCount ∧
      B'.orderingMode = B.orderingMode ∧ B'.bids = B.bids ∧ B'.asks = B.asks ∧
      B'.bidLevels = B.bidLevels ∧ B'.askLevels = B.askLevels := by
  simp [addState, orderW, bookW, upd]

/-- Every other order of the pool is untouched, as are the pool's other fields. -/
theorem addState_other_order (G : AsyncSwap.State) (pid id : Nat) (o : AsyncFiller.OrderInfo)
    (seq j : Nat) (hj : j ≠ id) :
    ((addState G pid id o seq).asyncOrders pid).orders j = (G.asyncOrders pid).orders j ∧
    ((addState G pid id o seq).asyncOrders pid).poolManager = (G.asyncOrders pid).poolManager ∧
    ((addState G pid id o seq).asyncOrders pid).numeraire = (G.asyncOrders pid).numeraire ∧
    ((addState G pid id o seq).asyncOrders pid).feeVault = (G.asyncOrders pid).feeVault ∧
    ((addState G pid id o seq).asyncOrders pid).isExecutor = (G.asyncOrders pid).isExecutor := by
  simp [addState, orderW, bookW, upd, hj]

/-- Every other pool (orders and book) is untouched. -/
theorem addState_other_pool (G : AsyncSwap.State) (pid id : Nat) (o : AsyncFiller.OrderInfo)
    (seq q : Nat) (hq : q ≠ pid) :
    (addState G pid id o seq).asyncOrders q = G.asyncOrders q ∧
      (addState G pid id o seq).priceBooks q = G.priceBooks q := by
  simp [addState, orderW, bookW, upd, hq]

/-- All other storage is untouched. -/
theorem addState_frame (G : AsyncSwap.State) (pid id : Nat) (o : AsyncFiller.OrderInfo) (seq : Nat) :
    let G' := addState G pid id o seq
    G'.owner = G.owner ∧ G'.pendingOwner = G.pendingOwner ∧ G'.nonceUsed = G.nonceUsed ∧
      G'.transient = G.transient ∧ G'.«_nameFallback» = G.«_nameFallback» ∧
      G'.«_versionFallback» = G.«_versionFallback» := by
  simp [addState, orderW, bookW]

/-! ## `AsyncMatching.addOrder` -/

/-- **Delegation.** For any storage accessors, `AsyncMatching.addOrder` is exactly
`AsyncFiller.addOrder` on the fields of the `NewOrder` struct (same pool, same book). -/
theorem matching_addOrder_eq (sg : M σ AsyncFiller.State_) (ss : AsyncFiller.State_ → M σ Unit)
    (bg : M σ AsyncFiller.Book) (bs : AsyncFiller.Book → M σ Unit) (order : AsyncFiller.NewOrder) :
    AsyncMatching.addOrder ext sg ss bg bs order =
      AsyncFiller.addOrder ext sg ss bg bs order.id order.owner order.amountIn order.amountOutMin
        order.isBuy order.zeroForOne order.priorityFee := by
  simp only [AsyncMatching.addOrder, bind_pure, bind_pure_unit]

/-- **Full characterization** of `AsyncMatching.addOrder` on pool `pid`. -/
theorem matching_addOrder_run (pid : Nat) (order : AsyncFiller.NewOrder) (env : Env) (w : σ) :
    AsyncMatching.addOrder ext (selfGet ext pid) (selfSet ext pid) (bookGet ext pid)
        (bookSet ext pid) order env w =
      let B := (ext.get w).priceBooks pid
      let fee := order.priorityFee
      if B.orderingMode = 0 ∧ fee ≠ 0 then .error ⟨"InvalidOrderingModeChange"⟩
      else if B.orderingMode = 1 ∧ fee < AsyncFiller.MIN_PRIORITY_FEE then .error ⟨"PriorityFeeTooSmall"⟩
      else if fee > AsyncFiller.MAX_PRIORITY_FEE then .error ⟨"PriorityFeeTooLarge"⟩
      else match AsyncFiller.«_priceKey» ext order.isBuy order.amountIn order.amountOutMin env w with
        | .error e => .error e
        | .ok (p, w0) =>
          let seq := ((ext.get w0).priceBooks pid).nextSequence + 1
          if seq < 2 ^ 64 then
            ext.fn_AsyncFiller_append_6737 (selfGet ext pid) (selfSet ext pid) (bookGet ext pid)
              (bookSet ext pid) order.id env
              (addWrite ext pid order.id (newOrder order.owner order.amountIn order.amountOutMin
                order.isBuy order.zeroForOne fee p seq) seq w0)
          else .error (panic "0x11") := by
  rw [matching_addOrder_eq, addOrder_run]

/-- Guard 1 for `AsyncMatching.addOrder`: FIFO mode with a nonzero fee reverts. -/
theorem matching_addOrder_invalidMode (pid : Nat) (order : AsyncFiller.NewOrder) (env : Env) (w : σ)
    (hm : ((ext.get w).priceBooks pid).orderingMode = 0) (hf : order.priorityFee ≠ 0) :
    AsyncMatching.addOrder ext (selfGet ext pid) (selfSet ext pid) (bookGet ext pid)
        (bookSet ext pid) order env w = .error ⟨"InvalidOrderingModeChange"⟩ := by
  rw [matching_addOrder_eq]; exact addOrder_invalidMode ext _ _ _ _ _ _ _ _ _ _ hm hf

/-- Guard 2 for `AsyncMatching.addOrder`: priority mode with a fee below the minimum reverts. -/
theorem matching_addOrder_feeTooSmall (pid : Nat) (order : AsyncFiller.NewOrder) (env : Env) (w : σ)
    (hm : ((ext.get w).priceBooks pid).orderingMode = 1)
    (hf : order.priorityFee < AsyncFiller.MIN_PRIORITY_FEE) :
    AsyncMatching.addOrder ext (selfGet ext pid) (selfSet ext pid) (bookGet ext pid)
        (bookSet ext pid) order env w = .error ⟨"PriorityFeeTooSmall"⟩ := by
  rw [matching_addOrder_eq]; exact addOrder_feeTooSmall ext _ _ _ _ _ _ _ _ _ _ hm hf

/-- Guard 3 for `AsyncMatching.addOrder`: a fee above `MAX_PRIORITY_FEE` reverts. -/
theorem matching_addOrder_feeTooLarge (pid : Nat) (order : AsyncFiller.NewOrder) (env : Env) (w : σ)
    (h1 : ¬ (((ext.get w).priceBooks pid).orderingMode = 0 ∧ order.priorityFee ≠ 0))
    (h2 : ¬ (((ext.get w).priceBooks pid).orderingMode = 1 ∧
      order.priorityFee < AsyncFiller.MIN_PRIORITY_FEE))
    (hf : order.priorityFee > AsyncFiller.MAX_PRIORITY_FEE) :
    AsyncMatching.addOrder ext (selfGet ext pid) (selfSet ext pid) (bookGet ext pid)
        (bookSet ext pid) order env w = .error ⟨"PriorityFeeTooLarge"⟩ := by
  rw [matching_addOrder_eq]; exact addOrder_feeTooLarge ext _ _ _ _ _ _ _ _ _ _ h1 h2 hf

/-- Guard 4 for `AsyncMatching.addOrder`: the checked uint64 sequence bump panics `0x11`. -/
theorem matching_addOrder_seqOverflow (pid : Nat) (order : AsyncFiller.NewOrder) (p : Nat)
    (env : Env) (w : σ)
    (h1 : ¬ (((ext.get w).priceBooks pid).orderingMode = 0 ∧ order.priorityFee ≠ 0))
    (h2 : ¬ (((ext.get w).priceBooks pid).orderingMode = 1 ∧
      order.priorityFee < AsyncFiller.MIN_PRIORITY_FEE))
    (h3 : ¬ order.priorityFee > AsyncFiller.MAX_PRIORITY_FEE)
    (hp : AsyncFiller.«_priceKey» ext order.isBuy order.amountIn order.amountOutMin env w = .ok (p, w))
    (hs : 2 ^ 64 ≤ ((ext.get w).priceBooks pid).nextSequence + 1) :
    AsyncMatching.addOrder ext (selfGet ext pid) (selfSet ext pid) (bookGet ext pid)
        (bookSet ext pid) order env w = .error (panic "0x11") := by
  rw [matching_addOrder_eq]; exact addOrder_seqOverflow ext _ _ _ _ _ _ _ _ _ _ _ h1 h2 h3 hp hs

/-- **Success** of `AsyncMatching.addOrder`: guards passed, `_priceKey` gave `p ∈ [1, 2^128)`
without touching storage, `seq` fits uint64, the storage handed to `_append(order.id)` is exactly
`addState` (new order at `order.id`, bumped sequence), and `_append` produced the final state. -/
theorem matching_addOrder_ok (hget : ∀ w s, ext.get (ext.set w s) = s)
    (pid : Nat) (order : AsyncFiller.NewOrder) (env : Env) (w w' : σ)
    (h : AsyncMatching.addOrder ext (selfGet ext pid) (selfSet ext pid) (bookGet ext pid)
      (bookSet ext pid) order env w = .ok ((), w')) :
    let B := (ext.get w).priceBooks pid
    let seq := B.nextSequence + 1
    let fee := order.priorityFee
    ¬ (B.orderingMode = 0 ∧ fee ≠ 0) ∧
    ¬ (B.orderingMode = 1 ∧ fee < AsyncFiller.MIN_PRIORITY_FEE) ∧
    fee ≤ AsyncFiller.MAX_PRIORITY_FEE ∧ seq < 2 ^ 64 ∧
    ∃ p w1, AsyncFiller.«_priceKey» ext order.isBuy order.amountIn order.amountOutMin env w
        = .ok (p, w) ∧
      1 ≤ p ∧ p < 2 ^ 128 ∧
      ext.get w1 = addState (ext.get w) pid order.id
        (newOrder order.owner order.amountIn order.amountOutMin order.isBuy order.zeroForOne
          fee p seq) seq ∧
      ext.fn_AsyncFiller_append_6737 (selfGet ext pid) (selfSet ext pid) (bookGet ext pid)
        (bookSet ext pid) order.id env w1 = .ok ((), w') := by
  rw [matching_addOrder_eq] at h
  exact addOrder_ok ext hget _ _ _ _ _ _ _ _ _ _ _ h

end AsyncSwap.Swarm.AddOrder
