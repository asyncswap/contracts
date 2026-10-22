import Generated.AsyncSwap
import Refinement.Monad

/-!
# AsyncSwap: `RadixPriceTree._freeNode`

`_freeNode(id)` has no guards and no external calls. Over any storage lens it never reverts,
returns `()`, and writes exactly two fields of the tree: `nodes[id]` is reset to the default
(empty) node and `id` is pushed onto `freeIds`. `root`, `nextNodeId`, `leaves` and every other
node are left as they were, and nothing outside the tree changes.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.FreeNode

variable {σ : Type} (ext : Ext σ)

/-- Over any `self_get`/`self_set` the def is exactly: read, clear `nodes[id]`, write; read, push
`id` onto `freeIds`, write. It has no guard of its own, so it reverts only if the accessors do. -/
theorem freeNode_unfold (self_get : M σ RadixPriceTree.Tree)
    (self_set : RadixPriceTree.Tree → M σ Unit) (id : Nat) :
    RadixPriceTree.«_freeNode» ext self_get self_set id
      = (do
          let t1 ← self_get
          self_set { t1 with nodes := upd t1.nodes id default }
          let t2 ← self_get
          self_set { t2 with freeIds := t2.freeIds ++ [id] }) := by
  simp [RadixPriceTree.«_freeNode»]

/-- Over a storage lens (`get'`, `set'` with the lens laws), `_freeNode(id)` succeeds, returns
`()`, and writes back the tree with `nodes[id]` cleared and `id` appended to `freeIds`. -/
theorem freeNode_run (get' : σ → RadixPriceTree.Tree) (set' : σ → RadixPriceTree.Tree → σ)
    (hgs : ∀ w t, get' (set' w t) = t) (hss : ∀ w t t', set' (set' w t) t' = set' w t')
    (id : Nat) (env : Env) (w : σ) :
    RadixPriceTree.«_freeNode» ext (do return get' (← get)) (fun x => modify fun w => set' w x)
        id env w
      = .ok ((), set' w { get' w with nodes := upd (get' w).nodes id default,
                                      freeIds := (get' w).freeIds ++ [id] }) := by
  simp [RadixPriceTree.«_freeNode», hgs, hss]

/-- The same, with the accessor wrappers the callers (`remove`) pass in:
`(do return (← self_get))` and `(fun x => do self_set x)`. -/
theorem freeNode_run_wrapped (get' : σ → RadixPriceTree.Tree) (set' : σ → RadixPriceTree.Tree → σ)
    (hgs : ∀ w t, get' (set' w t) = t) (hss : ∀ w t t', set' (set' w t) t' = set' w t')
    (id : Nat) (env : Env) (w : σ) :
    RadixPriceTree.«_freeNode» ext
        (do return (← (do return get' (← get) : M σ RadixPriceTree.Tree)))
        (fun x => do (modify fun w => set' w x : M σ Unit)) id env w
      = .ok ((), set' w { get' w with nodes := upd (get' w).nodes id default,
                                      freeIds := (get' w).freeIds ++ [id] }) := by
  simp [RadixPriceTree.«_freeNode», hgs, hss]

/-- Never reverts (no guards, no external calls). -/
theorem freeNode_no_revert (get' : σ → RadixPriceTree.Tree) (set' : σ → RadixPriceTree.Tree → σ)
    (hgs : ∀ w t, get' (set' w t) = t) (hss : ∀ w t t', set' (set' w t) t' = set' w t')
    (id : Nat) (env : Env) (w : σ) :
    ∃ w', RadixPriceTree.«_freeNode» ext (do return get' (← get))
        (fun x => modify fun w => set' w x) id env w = .ok ((), w') :=
  ⟨_, freeNode_run ext get' set' hgs hss id env w⟩

/-- Footprint: after `_freeNode(id)` the tree has `nodes[id] = default`, every other node,
`root`, `nextNodeId` and `leaves` unchanged, and `freeIds` extended by `id` at the end. -/
theorem freeNode_footprint (get' : σ → RadixPriceTree.Tree) (set' : σ → RadixPriceTree.Tree → σ)
    (hgs : ∀ w t, get' (set' w t) = t) (hss : ∀ w t t', set' (set' w t) t' = set' w t')
    (id : Nat) (env : Env) (w w' : σ) (r : Unit)
    (h : RadixPriceTree.«_freeNode» ext (do return get' (← get))
        (fun x => modify fun w => set' w x) id env w = .ok (r, w')) :
    (get' w').nodes id = default ∧
    (∀ x, x ≠ id → (get' w').nodes x = (get' w).nodes x) ∧
    (get' w').freeIds = (get' w).freeIds ++ [id] ∧
    (get' w').root = (get' w).root ∧
    (get' w').nextNodeId = (get' w).nextNodeId ∧
    (get' w').leaves = (get' w).leaves ∧
    w' = set' w (get' w') := by
  rw [freeNode_run ext get' set' hgs hss] at h
  simp only [Except.ok.injEq, Prod.mk.injEq] at h
  obtain ⟨-, rfl⟩ := h
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;> simp [hgs, upd]
  intro x hx; simp [hx]

end AsyncSwap.Swarm.FreeNode
