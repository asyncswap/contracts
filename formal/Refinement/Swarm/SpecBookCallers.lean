import Refinement.Swarm.SpecBook
import Refinement.Swarm.AsyncSwapBestOrder
import Refinement.Swarm.AsyncSwapOrderBookLevel
import Refinement.Swarm.AsyncSwapUpdatePriceWithSig
import Refinement.Swarm.AsyncSwapAddOrder
import Refinement.Swarm.AsyncSwapUpdatePrice
import Refinement.Swarm.AsyncSwapCancelOrder
import Refinement.Swarm.AsyncSwapRecordPriorityFee

/-!
# Callers of the order book's opaque functions, under the named specs

The existing proofs about the callers of `_remove`, `_append`, `bestAtPrice` and `level` either
take an ad-hoc hypothesis about the opaque function (`hba`, `hview`/`hlevel`, `KeepsNonces`) or
leave its run in their conclusion. Here each such theorem gets an `_of_spec` version that takes the
named assumption of `SpecBook.lean` instead (the old hypothesis is derived from it), and the
success theorems of `addOrder`, `updatePrice`, `cancelOrder` and `recordPriorityFee` get the
opaque call replaced by what the spec says it does.

Theorems of `AsyncSwapExecuteOrder`, `AsyncSwapFillOrderFromPoolLiquidity`, `AsyncSwapReduceAfterMatch`
and `AsyncSwapMatchBook`/`MatchNewOrder` take no hypothesis about these functions; their conclusions
mention `_remove`/`_append` runs, which `remove_canonical` / `append_canonical` turn into the spec's
effect directly.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.SpecBook

open AsyncSwap.Swarm.FillerRemove (Queue)

variable {σ : Type} (ext : Ext σ)

/-! ## The canonical pointers, as every caller writes them -/

/-- `_remove` on `asyncOrders[pid]`/`priceBooks[pid]` (any accessors that run as those plain reads
and writes, e.g. each caller file's `selfGet`/`selfSet`/`bookGet`/`bookSet`, by `rfl`). -/
theorem remove_canonical (hget : ∀ w s, ext.get (ext.set w s) = s) (hR : RemoveSpec ext)
    (pid : Nat) {sg : M σ AsyncFiller.State_} {ss : AsyncFiller.State_ → M σ Unit}
    {bg : M σ AsyncFiller.Book} {bs : AsyncFiller.Book → M σ Unit}
    (h1 : ∀ env w, sg env w = .ok (cg ext pid w, w))
    (h2 : ∀ x env w, ss x env w = .ok ((), css ext pid w x))
    (h3 : ∀ env w, bg env w = .ok (cbg ext pid w, w))
    (h4 : ∀ x env w, bs x env w = .ok ((), cbs ext pid w x))
    (id : Nat) (env : Env) (w w1 : σ)
    (hr : ext.fn_AsyncFiller_remove_6902 sg ss bg bs id env w = .ok ((), w1)) :
    let S := (ext.get w).asyncOrders pid
    let B := (ext.get w).priceBooks pid
    RemoveOk S B id ∧ (ext.get w1).asyncOrders pid = removeState S B id ∧
      (ext.get w1).priceBooks pid = removeBook S B id ∧
      Writes (css ext pid) (cbs ext pid) w w1 := by
  have L := lawful_canonical ext hget pid h1 h2 h3 h4
  obtain ⟨hw, hS, hB⟩ := hR.post L id env w w1 hr
  exact ⟨(hR.ok_iff L id env w).1 ⟨w1, hr⟩, hS, hB, hw⟩

/-- `_append` on `asyncOrders[pid]`/`priceBooks[pid]`. -/
theorem append_canonical (hget : ∀ w s, ext.get (ext.set w s) = s) (hA : AppendSpec ext)
    (pid : Nat) {sg : M σ AsyncFiller.State_} {ss : AsyncFiller.State_ → M σ Unit}
    {bg : M σ AsyncFiller.Book} {bs : AsyncFiller.Book → M σ Unit}
    (h1 : ∀ env w, sg env w = .ok (cg ext pid w, w))
    (h2 : ∀ x env w, ss x env w = .ok ((), css ext pid w x))
    (h3 : ∀ env w, bg env w = .ok (cbg ext pid w, w))
    (h4 : ∀ x env w, bs x env w = .ok ((), cbs ext pid w x))
    (id : Nat) (env : Env) (w w' : σ)
    (hr : ext.fn_AsyncFiller_append_6737 sg ss bg bs id env w = .ok ((), w')) :
    let S := (ext.get w).asyncOrders pid
    let B := (ext.get w).priceBooks pid
    let o := S.orders id
    let L := levels B o.isBuy o.price
    B.orderingMode < 2 ∧ L.orderCount + 1 < 2 ^ 32 ∧ B.openOrderCount + 1 < 2 ^ 64 ∧
    Writes (css ext pid) (cbs ext pid) w w' ∧
    ∃ T1 T2,
      (if L.orderCount = 0 then TreeInserted (side B o.isBuy) T1 o.price
       else T1 = side B o.isBuy) ∧
      (if B.orderingMode = 1 then TreeInserted L.priorityOrders T2 (prioKey o)
       else T2 = L.priorityOrders) ∧
      (ext.get w').asyncOrders pid = appendState S B id ∧
      (ext.get w').priceBooks pid = appendBook S B id T1 T2 :=
  hA.post (lawful_canonical ext hget pid h1 h2 h3 h4) id env w w' hr

/-! ## `AsyncSwap.bestOrder` (`AsyncSwapBestOrder.lean`) -/

/-- `bestOrder_readOnly`, with `BestAtPriceSpec` in place of `hba`. -/
theorem bestOrder_readOnly_of_spec (h : BestAtPriceSpec ext) (pid : Nat) (isBuy : Bool)
    (env : Env) (w w' : σ) (r : Bool × Nat × Nat × Nat)
    (hr : AsyncSwap.bestOrder ext pid isBuy env w = .ok (r, w')) : w' = w :=
  BestOrder.bestOrder_readOnly ext pid isBuy
    (fun _ _ _ _ _ hb => h.readOnly (bg := fun w => (ext.get w).priceBooks pid) (fun _ _ => rfl) hb)
    env w w' r hr

/-- `bestOrder_ok` with `bestAtPrice` replaced by its spec: an empty side gives
`(false, 0, 0, 0)`; otherwise the best price is the first leaf `c` of the walk, the order id is
`bestAtPriceOf` at that price (FIFO: the level's head; priority mode: the id under the level's
highest key), the maker is that order's owner, and nothing is written. -/
theorem bestOrder_ok_of_spec (h : BestAtPriceSpec ext) (pid : Nat) (isBuy : Bool) (env : Env)
    (w w' : σ) (r : Bool × Nat × Nat × Nat)
    (hr : AsyncSwap.bestOrder ext pid isBuy env w = .ok (r, w')) :
    w' = w ∧
    ((BestOrder.tree ext pid isBuy w).root = 0 ∧ r = (false, 0, 0, 0) ∨
    (BestOrder.tree ext pid isBuy w).root ≠ 0 ∧ ∃ n < loopBound, ∃ c id,
      c = BestOrder.walkN (BestOrder.tree ext pid isBuy w) isBuy n
        (BestOrder.tree ext pid isBuy w).root ∧
      ((BestOrder.tree ext pid isBuy w).nodes c).leaf = true ∧
      bestAtPriceOf ((ext.get w).priceBooks pid) isBuy
        ((BestOrder.tree ext pid isBuy w).nodes c).price = .ok id ∧
      r = (true, ((BestOrder.tree ext pid isBuy w).nodes c).price, id,
        (((ext.get w).asyncOrders pid).orders id).owner)) := by
  have hw := bestOrder_readOnly_of_spec ext h pid isBuy env w w' r hr
  refine ⟨hw, ?_⟩
  rw [hw] at hr
  rcases BestOrder.bestOrder_ok ext pid isBuy env w w r hr with ⟨h0, hr0, -⟩ | ⟨h0, n, hn, c, id, hc, hl, -, hb, hrr⟩
  · exact Or.inl ⟨h0, hr0⟩
  · right
    rw [h.run (bget := BestOrder.bookGet ext pid) (bg := fun w => (ext.get w).priceBooks pid)
      (fun _ _ => rfl)] at hb
    exact ⟨h0, n, hn, c, id, hc, hl, (liftR_ok hb).1, hrr⟩

/-! ## `AsyncSwap.orderBookLevel` (`AsyncSwapOrderBookLevel.lean`) -/

/-- `orderBookLevel_readOnly`, with `LevelSpec` in place of `hview`. -/
theorem orderBookLevel_readOnly_of_spec (h : LevelSpec ext) (pid : Nat) (isBuy : Bool) (k : Nat)
    (env : Env) (w w' : σ) (r : Nat × Nat × Nat)
    (hr : AsyncSwap.orderBookLevel ext pid isBuy k env w = .ok (r, w')) : w' = w :=
  OrderBookLevel.orderBookLevel_readOnly ext pid isBuy k
    (fun _ _ _ _ hb => h.readOnly (bg := fun w => (ext.get w).priceBooks pid) (fun _ _ => rfl) hb)
    env w w' r hr

/-- `orderBookLevel_view` under `LevelSpec`: the call returns `levelOf priceBooks[poolId]`
(it can revert, on an out-of-range mode byte or a walk past `loopBound`, so the old `hlevel`
hypothesis, which says it never does, is not what the bytecode gives). -/
theorem orderBookLevel_run_of_spec (h : LevelSpec ext) (pid : Nat) (isBuy : Bool) (k : Nat)
    (env : Env) (w : σ) :
    AsyncSwap.orderBookLevel ext pid isBuy k env w =
      liftR (levelOf ((ext.get w).priceBooks pid) isBuy k) w := by
  rw [OrderBookLevel.orderBookLevel_run]
  exact h.run (bg := fun w => (ext.get w).priceBooks pid) (fun _ _ => rfl) isBuy k env w

/-- `orderBookLevel_view`'s FIFO case: `(head, tail, orderCount)` of the level, state unchanged. -/
theorem orderBookLevel_fifo_of_spec (h : LevelSpec ext) (pid : Nat) (isBuy : Bool) (k : Nat)
    (env : Env) (w : σ) (hm : ((ext.get w).priceBooks pid).orderingMode = 0) :
    let L := levels ((ext.get w).priceBooks pid) isBuy k
    AsyncSwap.orderBookLevel ext pid isBuy k env w = .ok ((L.head, L.tail, L.orderCount), w) := by
  rw [orderBookLevel_run_of_spec ext h]; simp [levelOf, hm, liftR]

theorem liftR_map_fst {α : Type} (r : Except Revert α) (w : σ) :
    (liftR r w).map Prod.fst = r := by
  cases r <;> rfl

/-- `orderBookLevel_congr`, with `LevelSpec` in place of `hlevel`: the answer (or revert) depends
only on `priceBooks[poolId]`. -/
theorem orderBookLevel_congr_of_spec (h : LevelSpec ext) (pid : Nat) (isBuy : Bool) (k : Nat)
    (env env' : Env) (w v : σ) (hb : (ext.get w).priceBooks pid = (ext.get v).priceBooks pid) :
    (AsyncSwap.orderBookLevel ext pid isBuy k env w).map Prod.fst =
      (AsyncSwap.orderBookLevel ext pid isBuy k env' v).map Prod.fst := by
  rw [orderBookLevel_run_of_spec ext h, orderBookLevel_run_of_spec ext h, liftR_map_fst,
    liftR_map_fst, hb]

/-! ## `AsyncSwap.updatePriceWithSig` (`AsyncSwapUpdatePriceWithSig.lean`) -/

theorem keepsNonces_remove (hget : ∀ w s, ext.get (ext.set w s) = s) (hR : RemoveSpec ext)
    (pid id : Nat) :
    UpdatePriceWithSig.KeepsNonces ext (ext.fn_AsyncFiller_remove_6902 (UpdatePrice.selfGet ext pid)
      (UpdatePrice.selfSet ext pid) (UpdatePrice.bookGet ext pid) (UpdatePrice.bookSet ext pid) id) :=
  fun env s s' hr => (writes_frame ext hget pid
    (remove_canonical ext hget hR pid (fun _ _ => rfl) (fun _ _ _ => rfl) (fun _ _ => rfl)
      (fun _ _ _ => rfl) id env s s' hr).2.2.2).1

theorem keepsNonces_append (hget : ∀ w s, ext.get (ext.set w s) = s) (hA : AppendSpec ext)
    (pid id : Nat) :
    UpdatePriceWithSig.KeepsNonces ext (ext.fn_AsyncFiller_append_6737 (UpdatePrice.selfGet ext pid)
      (UpdatePrice.selfSet ext pid) (UpdatePrice.bookGet ext pid) (UpdatePrice.bookSet ext pid) id) :=
  fun env s s' hr => (writes_frame ext hget pid
    (append_canonical ext hget hA pid (fun _ _ => rfl) (fun _ _ _ => rfl) (fun _ _ => rfl)
      (fun _ _ _ => rfl) id env s s' hr).2.2.2.1).1

/-- `updatePriceWithSig_burns_nonce`, with `RemoveSpec`/`AppendSpec` in place of `hrem`/`happ`. -/
theorem updatePriceWithSig_burns_nonce_of_spec (hget : ∀ w s, ext.get (ext.set w s) = s)
    (hR : RemoveSpec ext) (hA : AppendSpec ext) (order : AsyncOrder) (n nonce deadline : Nat)
    (sig : List Nat) (env : Env) (w : σ)
    (hp : UpdatePriceWithSig.PureCallees ext order.owner sig) (w' : σ)
    (h : AsyncSwap.updatePriceWithSig ext order n nonce deadline sig env w = .ok ((), w')) :
    (ext.get w').nonceUsed = upd (ext.get w).nonceUsed order.owner
      (upd ((ext.get w).nonceUsed order.owner) nonce true) ∧
    ∀ (order' : AsyncOrder) n' deadline' sig' env', order'.owner = order.owner →
      ∃ e, AsyncSwap.updatePriceWithSig ext order' n' nonce deadline' sig' env' w' = .error e :=
  UpdatePriceWithSig.updatePriceWithSig_burns_nonce ext order n nonce deadline sig env w hget hp
    (keepsNonces_remove ext hget hR _ _) (keepsNonces_append ext hget hA _ _) w' h

/-! ## `AsyncFiller.addOrder` (`AsyncSwapAddOrder.lean`) -/

@[simp] theorem levels_nextSequence (B : AsyncFiller.Book) (b : Bool) (n : Nat) :
    levels { B with nextSequence := n } b = levels B b := by
  cases b <;> rfl

/-- **`addOrder_ok` with `_append` resolved.** A successful `addOrder` passed the guards, priced
the order at `p ∈ [1, 2^128)`, stored `newOrder` at `id` with `seq = nextSequence + 1`, and then
`_append` did what `AppendSpec` says, from that state (`S1`, `B1`): the final pool state is
`appendState S1 B1 id`, the final book `appendBook S1 B1 id T1 T2` (the side's tree got `p` when
the level was empty, the level's tree the order's key in priority mode), there was room in both
counters, and no other pool, nonce, owner or transient slot changed. -/
theorem addOrder_ok_of_spec (hget : ∀ w s, ext.get (ext.set w s) = s) (hA : AppendSpec ext)
    (pid id owner aIn aOut : Nat) (isBuy zfo : Bool) (fee : Nat) (env : Env) (w w' : σ)
    (h : AsyncFiller.addOrder ext (AddOrder.selfGet ext pid) (AddOrder.selfSet ext pid)
      (AddOrder.bookGet ext pid) (AddOrder.bookSet ext pid) id owner aIn aOut isBuy zfo fee env w
      = .ok ((), w')) :
    let B := (ext.get w).priceBooks pid
    let seq := B.nextSequence + 1
    ¬ (B.orderingMode = 0 ∧ fee ≠ 0) ∧
    ¬ (B.orderingMode = 1 ∧ fee < AsyncFiller.MIN_PRIORITY_FEE) ∧
    fee ≤ AsyncFiller.MAX_PRIORITY_FEE ∧ seq < 2 ^ 64 ∧
    ∃ p, AsyncFiller.«_priceKey» ext isBuy aIn aOut env w = .ok (p, w) ∧ 1 ≤ p ∧ p < 2 ^ 128 ∧
      let G1 := AddOrder.addState (ext.get w) pid id
        (AddOrder.newOrder owner aIn aOut isBuy zfo fee p seq) seq
      let S1 := G1.asyncOrders pid
      let B1 := G1.priceBooks pid
      let o := S1.orders id
      let L := levels B1 o.isBuy o.price
      B1.orderingMode < 2 ∧ L.orderCount + 1 < 2 ^ 32 ∧ B1.openOrderCount + 1 < 2 ^ 64 ∧
      (∃ T1 T2,
        (if L.orderCount = 0 then TreeInserted (side B1 o.isBuy) T1 o.price
         else T1 = side B1 o.isBuy) ∧
        (if B1.orderingMode = 1 then TreeInserted L.priorityOrders T2 (prioKey o)
         else T2 = L.priorityOrders) ∧
        (ext.get w').asyncOrders pid = appendState S1 B1 id ∧
        (ext.get w').priceBooks pid = appendBook S1 B1 id T1 T2) ∧
      (ext.get w').nonceUsed = (ext.get w).nonceUsed ∧ (ext.get w').owner = (ext.get w).owner ∧
      (ext.get w').transient = (ext.get w).transient ∧
      ∀ q, q ≠ pid → (ext.get w').asyncOrders q = (ext.get w).asyncOrders q ∧
        (ext.get w').priceBooks q = (ext.get w).priceBooks q := by
  intro B seq
  obtain ⟨g1, g2, g3, g4, p, w1, hp, hp1, hp2, hw1, ha⟩ :=
    AddOrder.addOrder_ok ext hget pid id owner aIn aOut isBuy zfo fee env w w' h
  refine ⟨g1, g2, g3, g4, p, hp, hp1, hp2, ?_⟩
  obtain ⟨m, c1, c2, hwr, T1, T2, t1, t2, hS, hB⟩ :=
    append_canonical ext hget hA pid (fun _ _ => rfl) (fun _ _ _ => rfl) (fun _ _ => rfl)
      (fun _ _ _ => rfl) id env w1 w' ha
  rw [hw1] at m c1 c2 t1 t2 hS hB
  obtain ⟨f1, f2, -, f4, -, -, f7⟩ := writes_frame ext hget pid hwr
  have fa := AddOrder.addState_frame (ext.get w) pid id
    (AddOrder.newOrder owner aIn aOut isBuy zfo fee p seq) seq
  rw [hw1] at f1 f2 f4 f7
  refine ⟨m, c1, c2, ⟨T1, T2, t1, t2, hS, hB⟩, ?_, ?_, ?_, ?_⟩
  · rw [f1]; exact fa.2.2.1
  · rw [f2]; exact fa.1
  · rw [f4]; exact fa.2.2.2.1
  · intro q hq
    rw [(f7 q hq).1, (f7 q hq).2]
    exact AddOrder.addState_other_pool _ _ _ _ _ _ hq

/-- **`addOrder` puts the new order at the back of its FIFO queue.** In FIFO mode, if the level at
the new order's price holds the queue `xs` (and `id ∉ xs`, `id ≠ 0`), after a successful
`addOrder` that level holds `xs ++ [id]`. -/
theorem addOrder_queue_of_spec (hget : ∀ w s, ext.get (ext.set w s) = s) (hA : AppendSpec ext)
    (pid id owner aIn aOut : Nat) (isBuy zfo : Bool) (fee : Nat) (env : Env) (w w' : σ)
    (h : AsyncFiller.addOrder ext (AddOrder.selfGet ext pid) (AddOrder.selfSet ext pid)
      (AddOrder.bookGet ext pid) (AddOrder.bookSet ext pid) id owner aIn aOut isBuy zfo fee env w
      = .ok ((), w'))
    (hm : ((ext.get w).priceBooks pid).orderingMode = 0) (hid : id ≠ 0) :
    ∃ p, AsyncFiller.«_priceKey» ext isBuy aIn aOut env w = .ok (p, w) ∧
      ∀ xs, Queue ((ext.get w).asyncOrders pid).orders
          (levels ((ext.get w).priceBooks pid) isBuy p) xs → id ∉ xs →
        Queue ((ext.get w').asyncOrders pid).orders
          (levels ((ext.get w').priceBooks pid) isBuy p) (xs ++ [id]) := by
  obtain ⟨-, -, -, -, p, w1, hp, -, -, hw1, ha⟩ :=
    AddOrder.addOrder_ok ext hget pid id owner aIn aOut isBuy zfo fee env w w' h
  refine ⟨p, hp, fun xs hq hx => ?_⟩
  have L := lawful_canonical ext hget pid (sg := AddOrder.selfGet ext pid)
    (ss := AddOrder.selfSet ext pid) (bg := AddOrder.bookGet ext pid)
    (bs := AddOrder.bookSet ext pid) (fun _ _ => rfl) (fun _ _ _ => rfl) (fun _ _ => rfl)
    (fun _ _ _ => rfl)
  obtain ⟨-, -, -, -, -, hpr, -, hib, -⟩ := AddOrder.addState_order (ext.get w) pid id owner aIn
    aOut isBuy zfo fee p ((ext.get w).priceBooks pid).nextSequence
  have hS1 : cg ext pid w1 = (AddOrder.addState (ext.get w) pid id
      (AddOrder.newOrder owner aIn aOut isBuy zfo fee p
        (((ext.get w).priceBooks pid).nextSequence + 1))
      (((ext.get w).priceBooks pid).nextSequence + 1)).asyncOrders pid := by
    simp only [cg, hw1]
  have hord : (cg ext pid w1).orders id = AddOrder.newOrder owner aIn aOut isBuy zfo fee p
      (((ext.get w).priceBooks pid).nextSequence + 1) := by
    rw [hS1]; simp [AddOrder.addState, AddOrder.orderW, AddOrder.bookW, upd]
  have hB1 : cbg ext pid w1 = { (ext.get w).priceBooks pid with
      nextSequence := ((ext.get w).priceBooks pid).nextSequence + 1 } := by
    simp only [cbg, hw1]; simp [AddOrder.addState, AddOrder.orderW, AddOrder.bookW, upd]
  have hos : (cg ext pid w1).orders = upd ((ext.get w).asyncOrders pid).orders id
      (AddOrder.newOrder owner aIn aOut isBuy zfo fee p
        (((ext.get w).priceBooks pid).nextSequence + 1)) := by
    rw [hS1]; simp [AddOrder.addState, AddOrder.orderW, AddOrder.bookW, upd]
  have hm1 : (cbg ext pid w1).orderingMode = 0 := by rw [hB1]; exact hm
  have hq1 : Queue (cg ext pid w1).orders (levelOfOrder (cg ext pid w1) (cbg ext pid w1) id) xs := by
    simp only [levelOfOrder, hord, AddOrder.newOrder, hB1, levels_nextSequence]
    rw [hos]
    exact queue_upd_out hq hx _
  have := append_queue hA L id env w1 w' hm1 hq1 hx hid ha
  have hord' : ((ext.get w1).asyncOrders pid).orders id = AddOrder.newOrder owner aIn aOut isBuy zfo
      fee p (((ext.get w).priceBooks pid).nextSequence + 1) := hord
  simp only [cg, cbg] at this
  rw [hord'] at this
  exact this

/-! ## `AsyncSwap.updatePrice` (`AsyncSwapUpdatePrice.lean`) -/

/-- **`updatePrice_ok` with both opaque calls resolved.** A successful `updatePrice` passed the
three guards, then `_remove` succeeded (`RemoveOk`) and left `removeState`/`removeBook`, then
`midState` was written, then `_append` succeeded and left `appendState`/`appendBook` from there;
nothing outside pool `pid` changed. -/
theorem updatePrice_ok_of_spec (hget : ∀ w s, ext.get (ext.set w s) = s) (hR : RemoveSpec ext)
    (hA : AppendSpec ext) (order : AsyncOrder) (n : Nat) (env : Env) (w w' : σ)
    (h : AsyncSwap.updatePrice ext order n env w = .ok ((), w')) :
    let pid := UpdatePrice.poolId ext order.key
    let id := UpdatePrice.orderId ext env order
    let S := (ext.get w).asyncOrders pid
    let B := (ext.get w).priceBooks pid
    env.sender = order.owner ∧ n ≠ 0 ∧ (S.orders id).amountIn ≠ 0 ∧ RemoveOk S B id ∧
    ∃ w1 w2 p,
      (ext.get w1).asyncOrders pid = removeState S B id ∧
      (ext.get w1).priceBooks pid = removeBook S B id ∧
      1 ≤ p ∧ p < 2 ^ 128 ∧ ((ext.get w1).priceBooks pid).nextSequence + 1 < 2 ^ 64 ∧
      ext.get w2 = UpdatePrice.midState (ext.get w1) pid id n p
        (((ext.get w1).priceBooks pid).nextSequence + 1) ∧
      (let S2 := (ext.get w2).asyncOrders pid
       let B2 := (ext.get w2).priceBooks pid
       let o := S2.orders id
       let L := levels B2 o.isBuy o.price
       B2.orderingMode < 2 ∧ L.orderCount + 1 < 2 ^ 32 ∧ B2.openOrderCount + 1 < 2 ^ 64 ∧
       ∃ T1 T2,
        (if L.orderCount = 0 then TreeInserted (side B2 o.isBuy) T1 o.price
         else T1 = side B2 o.isBuy) ∧
        (if B2.orderingMode = 1 then TreeInserted L.priorityOrders T2 (prioKey o)
         else T2 = L.priorityOrders) ∧
        (ext.get w').asyncOrders pid = appendState S2 B2 id ∧
        (ext.get w').priceBooks pid = appendBook S2 B2 id T1 T2) ∧
      (ext.get w').nonceUsed = (ext.get w).nonceUsed ∧
      ∀ q, q ≠ pid → (ext.get w').asyncOrders q = (ext.get w).asyncOrders q ∧
        (ext.get w').priceBooks q = (ext.get w).priceBooks q := by
  intro pid id S B
  obtain ⟨g1, g2, g3, w1, w2, p, hr, hp1, hp2, hs, hw2, ha⟩ :=
    UpdatePrice.updatePrice_ok ext hget order n env w w' h
  obtain ⟨rok, hS1, hB1, hw1⟩ := remove_canonical ext hget hR pid (fun _ _ => rfl)
    (fun _ _ _ => rfl) (fun _ _ => rfl) (fun _ _ _ => rfl) id env w w1 hr
  obtain ⟨m, c1, c2, hwa, T1, T2, t1, t2, hS, hB⟩ := append_canonical ext hget hA pid
    (fun _ _ => rfl) (fun _ _ _ => rfl) (fun _ _ => rfl) (fun _ _ _ => rfl) id env w2 w' ha
  refine ⟨g1, g2, g3, rok, w1, w2, p, hS1, hB1, hp1, hp2, hs, hw2,
    ⟨m, c1, c2, T1, T2, t1, t2, hS, hB⟩, ?_, ?_⟩
  · obtain ⟨-, -, f3, -⟩ := UpdatePrice.midState_frame (ext.get w1) pid id n p
      (((ext.get w1).priceBooks pid).nextSequence + 1)
    rw [(writes_frame ext hget pid hwa).1, hw2, f3, (writes_frame ext hget pid hw1).1]
  · intro q hq
    obtain ⟨m1, m2⟩ := UpdatePrice.midState_other_pool (ext.get w1) pid id n p
      (((ext.get w1).priceBooks pid).nextSequence + 1) q hq
    have a := ((writes_frame ext hget pid hwa).2.2.2.2.2.2 q hq)
    have r := ((writes_frame ext hget pid hw1).2.2.2.2.2.2 q hq)
    rw [a.1, a.2, hw2, m1, m2, r.1, r.2]
    exact ⟨rfl, rfl⟩

/-! ## `AsyncSwap.cancelOrder` (`AsyncSwapCancelOrder.lean`) -/

/-- **`cancelOrder_ok` with `_remove` resolved**: the world `w1` the rest of `cancelOrder` starts
from (and in which `orders[id]` is then cleared before the burn) has `removeState`/`removeBook`
of the entry state, and nothing outside pool `pid` changed by then. -/
theorem cancelOrder_ok_of_spec (hget : ∀ w s, ext.get (ext.set w s) = s) (hR : RemoveSpec ext)
    (order : AsyncOrder) (env : Env) (w w' : σ)
    (h : AsyncSwap.cancelOrder ext order env w = .ok ((), w')) :
    let pid := CancelOrder.poolId ext order.key
    let id := CancelOrder.orderId ext env order
    let S := (ext.get w).asyncOrders pid
    let B := (ext.get w).priceBooks pid
    let info := S.orders id
    (env.sender = order.owner ∨ S.isExecutor order.owner env.sender = true) ∧
    info.amountIn ≠ 0 ∧ RemoveOk S B id ∧
    ∃ w1 w3 w4,
      (ext.get w1).asyncOrders pid = removeState S B id ∧
      (ext.get w1).priceBooks pid = removeBook S B id ∧
      (ext.get w1).nonceUsed = (ext.get w).nonceUsed ∧
      (∀ q, q ≠ pid → (ext.get w1).asyncOrders q = (ext.get w).asyncOrders q ∧
        (ext.get w1).priceBooks q = (ext.get w).priceBooks q) ∧
      ext.call_IPoolManager_burn ((ext.get (CancelOrder.delWorld ext pid id w1)).asyncOrders pid).poolManager
        env.self (CancelOrder.inputOf order) info.amountIn env (CancelOrder.delWorld ext pid id w1)
        = .ok ((), w3) ∧
      (if CancelOrder.inputOf order = 0 then
        ext.call_IPoolManager_mint ((ext.get w3).asyncOrders pid).poolManager order.owner
          (CancelOrder.inputOf order) info.amountIn env w3
      else
        ext.call_IPoolManager_take ((ext.get w3).asyncOrders pid).poolManager
          (CancelOrder.inputOf order) order.owner info.amountIn env w3) = .ok ((), w4) ∧
      AsyncFiller.settlePriorityFee ext (CancelOrder.selfGet ext pid) (CancelOrder.selfSet ext pid)
        order.key id order.owner (if info.priorityFeeEscrowed then info.priorityFee else 0) env.self
        env w4 = .ok ((), w') := by
  intro pid id S B info
  obtain ⟨g1, g2, w1, w3, w4, hr, hb, hm, hs⟩ := CancelOrder.cancelOrder_ok ext order env w w' h
  obtain ⟨rok, hS1, hB1, hw1⟩ := remove_canonical ext hget hR pid (fun _ _ => rfl)
    (fun _ _ _ => rfl) (fun _ _ => rfl) (fun _ _ _ => rfl) id env w w1 hr
  have f := writes_frame ext hget pid hw1
  exact ⟨g1, g2, rok, w1, w3, w4, hS1, hB1, f.1, f.2.2.2.2.2.2, hb, hm, hs⟩

/-- **`cancelOrder` unlinks the order from its FIFO queue before any external call.** In FIFO
mode, if the order's level holds the queue `xs ∋ id`, the world the rest of `cancelOrder` runs in
(`w1`, before the burn and any re-entry) has that level holding `xs.erase id`. -/
theorem cancelOrder_queue_of_spec (hget : ∀ w s, ext.get (ext.set w s) = s) (hR : RemoveSpec ext)
    (order : AsyncOrder) (env : Env) (w w' : σ)
    (h : AsyncSwap.cancelOrder ext order env w = .ok ((), w'))
    (xs : List Nat)
    (hm : ((ext.get w).priceBooks (CancelOrder.poolId ext order.key)).orderingMode = 0)
    (hq : Queue ((ext.get w).asyncOrders (CancelOrder.poolId ext order.key)).orders
      (levelOfOrder ((ext.get w).asyncOrders (CancelOrder.poolId ext order.key))
        ((ext.get w).priceBooks (CancelOrder.poolId ext order.key))
        (CancelOrder.orderId ext env order)) xs)
    (hid : CancelOrder.orderId ext env order ∈ xs) :
    let pid := CancelOrder.poolId ext order.key
    let id := CancelOrder.orderId ext env order
    let o := ((ext.get w).asyncOrders pid).orders id
    ∃ w1, ext.fn_AsyncFiller_remove_6902 (CancelOrder.selfGet ext pid) (CancelOrder.selfSet ext pid)
        (CancelOrder.bookGet ext pid) (CancelOrder.bookSet ext pid) id env w = .ok ((), w1) ∧
      Queue ((ext.get w1).asyncOrders pid).orders
        (levels ((ext.get w1).priceBooks pid) o.isBuy o.price) (xs.erase id) := by
  intro pid id o
  obtain ⟨-, -, w1, -, -, hr, -⟩ := CancelOrder.cancelOrder_ok ext order env w w' h
  have L := lawful_canonical ext hget pid (sg := CancelOrder.selfGet ext pid)
    (ss := CancelOrder.selfSet ext pid) (bg := CancelOrder.bookGet ext pid)
    (bs := CancelOrder.bookSet ext pid) (fun _ _ => rfl) (fun _ _ _ => rfl) (fun _ _ => rfl)
    (fun _ _ _ => rfl)
  exact ⟨w1, hr, remove_queue hR L id env w w1 hm hq hid hr⟩

/-! ## `AsyncSwap.recordPriorityFee` (`AsyncSwapRecordPriorityFee.lean`) -/

/-- **No double escrow, from the final state.** `recordPriorityFee_twice_reverts` holds for the
world right after the flag write; with the specs it holds for the world the call *ends* in: the
priority re-queue (`_remove` then `_append`) keeps the escrow flag, so the order stays escrowed, and
while it is still the pending order, recording its bid again reverts. -/
theorem recordPriorityFee_escrowed_of_spec (hget : ∀ w s, ext.get (ext.set w s) = s)
    (hR : RemoveSpec ext) (hA : AppendSpec ext) (key : PoolKey) (maker amount : Nat) (env : Env)
    (w w' : σ) (h : AsyncSwap.recordPriorityFee ext key maker amount env w = .ok ((), w')) :
    let pid := RecordPriorityFee.poolId ext key
    let id := RecordPriorityFee.pendingId ext w
    (((ext.get w').asyncOrders pid).orders id).priorityFeeEscrowed = true ∧
    ∀ maker' amount' env', RecordPriorityFee.pendingId ext w' = id →
      ∃ e, AsyncSwap.recordPriorityFee ext key maker' amount' env' w' = .error e := by
  intro pid id
  obtain ⟨-, -, -, -, -, -, -, w1, -, ha⟩ := RecordPriorityFee.recordPriorityFee_ok ext key maker
    amount env w w' h
  have hflag : (((ext.get w').asyncOrders pid).orders id).priorityFeeEscrowed = true := by
    have hf2 := (RecordPriorityFee.flagWorld_frame ext hget pid id w1).1
    unfold RecordPriorityFee.afterMint at ha
    simp only at ha
    split at ha
    · rename_i hm
      simp only [run_bind] at ha
      split at ha
      · rename_i w3 hr
        obtain ⟨-, hS3, hB3, -⟩ := remove_canonical ext hget hR pid (fun _ _ => rfl)
          (fun _ _ _ => rfl) (fun _ _ => rfl) (fun _ _ _ => rfl) id env
          (RecordPriorityFee.flagWorld ext pid id w1) w3 hr
        obtain ⟨-, -, -, -, -, -, -, -, hS, -⟩ := append_canonical ext hget hA pid (fun _ _ => rfl)
          (fun _ _ _ => rfl) (fun _ _ => rfl) (fun _ _ _ => rfl) id env w3 w' ha
        rw [hS]
        rw [(appendState_keeps _ _ id id).2.2.2.2.2.2.2.2, hS3, removeState_prio _ _ _ hm, hf2]
      · cases ha
    · simp only [Except.ok.injEq, Prod.mk.injEq] at ha
      rw [← ha.2, hf2]
  refine ⟨hflag, fun maker' amount' env' hp => ?_⟩
  apply RecordPriorityFee.recordPriorityFee_escrowed_reverts
  rw [hp]; exact hflag

end AsyncSwap.Swarm.SpecBook
