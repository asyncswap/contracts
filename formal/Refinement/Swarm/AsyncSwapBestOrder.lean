import Generated.AsyncSwap
import Refinement.Monad

/-!
# `AsyncSwap.bestOrder`

`function bestOrder(PoolId poolId, bool isBuy) external view returns (bool found, uint128 priceKey,
bytes32 orderId, address maker)` (src/AsyncSwap.sol:271), through `AsyncMatching.bestOrder` →
`AsyncFiller.bestOrder` → `RadixPriceTree.best` (+ the opaque `AsyncFiller.bestAtPrice`).

With `T = isBuy ? priceBooks[poolId].bids : priceBooks[poolId].asks` and
`step c = isBuy ? T.nodes[c].right : T.nodes[c].left` (`best(true)` on bids, `best(false)` on asks):

* `bestOrder_run` (**full characterization**):
  - `T.root = 0` (empty side): returns `(false, 0, 0, 0)`, state unchanged (`bestOrder_empty`);
  - otherwise the walk `root, step root, step² root, …` is followed to its first leaf `c`; if no
    leaf shows up within `loopBound = 2^64` steps it reverts `"loop bound"` (the model's stand-in for
    running out of gas, `bestOrder_loopBound`) — the only revert of this layer;
  - at the leaf, `p = T.nodes[c].price`, `orderId = bestAtPrice(book, isBuy, p)` (opaque in the
    model, its reverts are its own), `maker = asyncOrders[poolId].orders[orderId].owner`; it
    returns `(true, p, orderId, maker)`.
* **Footprint**: the tree walk reads `priceBooks[poolId]` and writes nothing (`best_run`); the only
  thing that could touch state is the opaque `bestAtPrice`, so if that one is read-only (it is a
  `view` in Solidity) the whole call is (`bestOrder_readOnly`). `bestOrder_ok` gives the success
  shape: the leaf is reachable from the root, every node before it is a branch.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.BestOrder

variable {σ : Type}

def bookGet (ext : Ext σ) (pid : Nat) : M σ AsyncFiller.Book := do
  return ((ext.get (← get)).priceBooks pid)
def bookSet (ext : Ext σ) (pid : Nat) : AsyncFiller.Book → M σ Unit := fun x =>
  modify fun w => ext.set w (let s := ext.get w; { s with priceBooks := upd (s.priceBooks) pid x })

/-- The side of the book `bestOrder` walks. -/
def tree (ext : Ext σ) (pid : Nat) (isBuy : Bool) (w : σ) : RadixPriceTree.Tree :=
  if isBuy then ((ext.get w).priceBooks pid).bids else ((ext.get w).priceBooks pid).asks

/-- One step down from a branch: right for `highest`, left otherwise. -/
def stepDown (T : RadixPriceTree.Tree) (highest : Bool) (c : Nat) : Nat :=
  if highest then (T.nodes c).right else (T.nodes c).left

/-- `n` steps down from `c`. -/
def walkN (T : RadixPriceTree.Tree) (highest : Bool) : Nat → Nat → Nat
  | 0, c => c
  | n + 1, c => walkN T highest n (stepDown T highest c)

/-- The first leaf on the walk from `c`, within `fuel` loop iterations. -/
def firstLeaf (T : RadixPriceTree.Tree) (highest : Bool) : Nat → Nat → Option Nat
  | 0, _ => none
  | k + 1, c => if (T.nodes c).leaf then some c else firstLeaf T highest k (stepDown T highest c)

theorem firstLeaf_spec (T : RadixPriceTree.Tree) (highest : Bool) :
    ∀ (fuel c c' : Nat), firstLeaf T highest fuel c = some c' →
      ∃ n < fuel, c' = walkN T highest n c ∧ (T.nodes c').leaf = true ∧
        ∀ j < n, (T.nodes (walkN T highest j c)).leaf = false := by
  intro fuel
  induction fuel with
  | zero => intro c c' h; simp [firstLeaf] at h
  | succ k ih =>
    intro c c' h
    simp only [firstLeaf] at h
    by_cases hl : (T.nodes c).leaf = true
    · simp only [hl, ite_true, Option.some.injEq] at h
      subst h
      exact ⟨0, by omega, rfl, hl, fun j hj => absurd hj (by omega)⟩
    · simp only [hl, Bool.false_eq_true, ite_false] at h
      obtain ⟨n, hn, rfl, hleaf, hbefore⟩ := ih _ _ h
      refine ⟨n + 1, by omega, rfl, hleaf, ?_⟩
      intro j hj
      cases j with
      | zero => simpa [walkN] using hl
      | succ j => exact hbefore j (by omega)

/-! ## The tree walk, for any read-only accessor -/

/-- The loop body, run against a getter that only reads `T w`: no state change, a pure step. -/
theorem body_run (T : σ → RadixPriceTree.Tree) (g : M σ RadixPriceTree.Tree)
    (hg : ∀ env w, g env w = .ok (T w, w)) (highest : Bool) (env : Env) (w : σ)
    (b : Nat × Bool) :
    (do
        let __t3 ← g
        if (!!(__t3.nodes b.fst).leaf) = true then pure (ForInStep.done (b.fst, true))
          else
            if highest = true then do
              let __t4 ← g
              pure (ForInStep.yield ((__t4.nodes b.fst).right, b.snd))
            else do
              let __t5 ← g
              pure (ForInStep.yield ((__t5.nodes b.fst).left, b.snd)) : M σ (ForInStep (Nat × Bool))) env w =
      .ok ((if ((T w).nodes b.1).leaf then ForInStep.done (b.1, true)
            else ForInStep.yield (stepDown (T w) highest b.1, b.2)), w) := by
  simp only [run_bind, hg, run_pure, run_ite, stepDown]
  cases hl : ((T w).nodes b.1).leaf <;> cases highest <;> simp

/-- The walk loop over any index list, in the pure form. -/
theorem loop_run (T : σ → RadixPriceTree.Tree) (g : M σ RadixPriceTree.Tree)
    (hg : ∀ env w, g env w = .ok (T w, w)) (highest : Bool) (env : Env) (w : σ) :
    ∀ (l : List Nat) (c : Nat),
      forIn l (c, false) (fun (_ : Nat) (b : Nat × Bool) => (do
        let __t3 ← g
        if (!!(__t3.nodes b.fst).leaf) = true then pure (ForInStep.done (b.fst, true))
          else
            if highest = true then do
              let __t4 ← g
              pure (ForInStep.yield ((__t4.nodes b.fst).right, b.snd))
            else do
              let __t5 ← g
              pure (ForInStep.yield ((__t5.nodes b.fst).left, b.snd)) : M σ (ForInStep (Nat × Bool))))
        env w =
      .ok ((match firstLeaf (T w) highest l.length c with
            | some c' => (c', true)
            | none => (walkN (T w) highest l.length c, false)), w) := by
  intro l
  induction l with
  | nil => intro c; simp [firstLeaf, walkN]
  | cons i l ih =>
    intro c
    rw [List.forIn_cons, run_bind, body_run T g hg highest env w (c, false)]
    simp only [List.length_cons, firstLeaf]
    cases hl : ((T w).nodes c).leaf
    · simp only [Bool.false_eq_true, ite_false]
      rw [ih]
      rfl
    · simp

/-- **`RadixPriceTree.best`, characterized** for a read-only accessor: empty tree → `(false, 0)`;
else the first leaf of the walk within `loopBound` iterations, or a `"loop bound"` revert. Never
writes. -/
theorem best_run (ext : Ext σ) (T : σ → RadixPriceTree.Tree) (g : M σ RadixPriceTree.Tree)
    (hg : ∀ env w, g env w = .ok (T w, w)) (s : RadixPriceTree.Tree → M σ Unit) (highest : Bool)
    (env : Env) (w : σ) :
    RadixPriceTree.best ext g s highest env w =
      if (T w).root = 0 then .ok ((false, 0), w)
      else match firstLeaf (T w) highest loopBound (T w).root with
        | some c => .ok ((true, ((T w).nodes c).price), w)
        | none => .error ⟨"loop bound"⟩ := by
  simp only [RadixPriceTree.best, run_bind, hg, run_pure, run_ite, beq_iff_eq]
  by_cases h0 : (T w).root = 0
  · simp [h0]
  · simp only [h0, ite_false]
    rw [Std.Legacy.Range.forIn_eq_forIn_range', loop_run T g hg highest env w]
    have hsz : ([:loopBound] : Std.Legacy.Range).size = loopBound := by
      simp [Std.Legacy.Range.size]
    simp only [List.length_range', hsz]
    cases firstLeaf (T w) highest loopBound (T w).root <;> simp

/-! ## `AsyncSwap.bestOrder` -/

/-- **Full characterization** of `AsyncSwap.bestOrder`. -/
theorem bestOrder_run (ext : Ext σ) (pid : Nat) (isBuy : Bool) (env : Env) (w : σ) :
    AsyncSwap.bestOrder ext pid isBuy env w =
      let T := tree ext pid isBuy w
      if T.root = 0 then .ok ((false, 0, 0, 0), w)
      else match firstLeaf T isBuy loopBound T.root with
        | none => .error ⟨"loop bound"⟩
        | some c =>
          match ext.fn_AsyncFiller_bestAtPrice_6051 (bookGet ext pid) (bookSet ext pid) isBuy
              (T.nodes c).price env w with
          | .ok (id, w') =>
            .ok ((true, (T.nodes c).price, id, (((ext.get w').asyncOrders pid).orders id).owner), w')
          | .error e => .error e := by
  simp only [AsyncSwap.bestOrder, AsyncMatching.bestOrder, AsyncFiller.bestOrder, run_bind,
    run_pure, run_ite, tree]
  cases isBuy
  · simp only [Bool.false_eq_true, ite_false]
    rw [best_run ext (fun w => ((ext.get w).priceBooks pid).asks) _ ?hg]
    case hg => intro env w; rfl
    by_cases h0 : ((ext.get w).priceBooks pid).asks.root = 0
    · simp only [h0, ite_true]; rfl
    · simp only [h0, ite_false]
      cases firstLeaf ((ext.get w).priceBooks pid).asks false loopBound
        ((ext.get w).priceBooks pid).asks.root
      · rfl
      · rename_i c
        simp only [ite_true, run_get]
        cases h : ext.fn_AsyncFiller_bestAtPrice_6051 (bookGet ext pid) (bookSet ext pid) false
            (((ext.get w).priceBooks pid).asks.nodes c).price env w with
        | error e => erw [h]
        | ok p => obtain ⟨id, w'⟩ := p; erw [h]
  · simp only [ite_true]
    rw [best_run ext (fun w => ((ext.get w).priceBooks pid).bids) _ ?hg]
    case hg => intro env w; rfl
    by_cases h0 : ((ext.get w).priceBooks pid).bids.root = 0
    · simp only [h0, ite_true]; rfl
    · simp only [h0, ite_false]
      cases firstLeaf ((ext.get w).priceBooks pid).bids true loopBound
        ((ext.get w).priceBooks pid).bids.root
      · rfl
      · rename_i c
        simp only [ite_true, run_get]
        cases h : ext.fn_AsyncFiller_bestAtPrice_6051 (bookGet ext pid) (bookSet ext pid) true
            (((ext.get w).priceBooks pid).bids.nodes c).price env w with
        | error e => erw [h]
        | ok p => obtain ⟨id, w'⟩ := p; erw [h]

/-- **Empty side.** No order on that side: `(false, 0, 0, 0)`, nothing written, no revert. -/
theorem bestOrder_empty (ext : Ext σ) (pid : Nat) (isBuy : Bool) (env : Env) (w : σ)
    (h : (tree ext pid isBuy w).root = 0) :
    AsyncSwap.bestOrder ext pid isBuy env w = .ok ((false, 0, 0, 0), w) := by
  rw [bestOrder_run]; simp only [h, ite_true]

/-- **Loop bound.** A non-empty side whose walk meets no leaf within `2^64` steps reverts. -/
theorem bestOrder_loopBound (ext : Ext σ) (pid : Nat) (isBuy : Bool) (env : Env) (w : σ)
    (h0 : (tree ext pid isBuy w).root ≠ 0)
    (h : firstLeaf (tree ext pid isBuy w) isBuy loopBound (tree ext pid isBuy w).root = none) :
    AsyncSwap.bestOrder ext pid isBuy env w = .error ⟨"loop bound"⟩ := by
  rw [bestOrder_run]; simp only [h0, h, ite_false]

/-- **Success shape.** Either the side is empty (`(false, 0, 0, 0)`, state unchanged), or `found`
holds, the price is the one stored at a leaf `c` reached from the root by `n < 2^64` steps toward
the best price (every node before it a branch), `orderId` is what `bestAtPrice` returns for that
price, and `maker` is that order's stored owner. -/
theorem bestOrder_ok (ext : Ext σ) (pid : Nat) (isBuy : Bool) (env : Env) (w w' : σ)
    (r : Bool × Nat × Nat × Nat) (h : AsyncSwap.bestOrder ext pid isBuy env w = .ok (r, w')) :
    (tree ext pid isBuy w).root = 0 ∧ r = (false, 0, 0, 0) ∧ w' = w ∨
    (tree ext pid isBuy w).root ≠ 0 ∧ ∃ n < loopBound, ∃ c id,
      c = walkN (tree ext pid isBuy w) isBuy n (tree ext pid isBuy w).root ∧
      ((tree ext pid isBuy w).nodes c).leaf = true ∧
      (∀ j < n, ((tree ext pid isBuy w).nodes
          (walkN (tree ext pid isBuy w) isBuy j (tree ext pid isBuy w).root)).leaf = false) ∧
      ext.fn_AsyncFiller_bestAtPrice_6051 (bookGet ext pid) (bookSet ext pid) isBuy
        ((tree ext pid isBuy w).nodes c).price env w = .ok (id, w') ∧
      r = (true, ((tree ext pid isBuy w).nodes c).price, id,
        (((ext.get w').asyncOrders pid).orders id).owner) := by
  rw [bestOrder_run] at h
  simp only at h
  by_cases h0 : (tree ext pid isBuy w).root = 0
  · simp only [h0, ite_true, Except.ok.injEq, Prod.mk.injEq] at h
    exact Or.inl ⟨h0, h.1.symm, h.2.symm⟩
  · right
    refine ⟨h0, ?_⟩
    simp only [h0, ite_false] at h
    split at h
    · cases h
    · rename_i c hc
      obtain ⟨n, hn, hcn, hleaf, hbefore⟩ := firstLeaf_spec _ _ _ _ _ hc
      split at h
      · rename_i id w2 hba
        simp only [Except.ok.injEq, Prod.mk.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        exact ⟨n, hn, c, id, hcn, hleaf, hbefore, hba, rfl⟩
      · cases h

/-- **Footprint.** If the opaque `bestAtPrice` is read-only (as the Solidity `view` makes it), a
successful `bestOrder` leaves the state exactly as it found it. -/
theorem bestOrder_readOnly (ext : Ext σ) (pid : Nat) (isBuy : Bool)
    (hba : ∀ p env w id w', ext.fn_AsyncFiller_bestAtPrice_6051 (bookGet ext pid) (bookSet ext pid)
      isBuy p env w = .ok (id, w') → w' = w)
    (env : Env) (w w' : σ) (r : Bool × Nat × Nat × Nat)
    (h : AsyncSwap.bestOrder ext pid isBuy env w = .ok (r, w')) : w' = w := by
  rcases bestOrder_ok ext pid isBuy env w w' r h with ⟨_, _, hw⟩ | ⟨_, _, _, _, _, _, _, _, hb, _⟩
  · exact hw
  · exact hba _ _ _ _ _ hb

end AsyncSwap.Swarm.BestOrder
