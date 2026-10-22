import Generated.AsyncSwap
import Refinement.Monad

/-!
# AsyncSwap: `RadixPriceTree.remove`

`remove(self, price)` has one guard and no external calls. Over any storage lens for the tree it
reverts with `PriceLevelMissing` exactly when `leaves[price] == 0`; otherwise it succeeds, returns
`()`, and writes back only the tree, which becomes `removeTree t price` below: `leaves[price]`
cleared, and either (leaf is the root) `root := 0` and the leaf freed, or the leaf's parent branch
spliced out (grandparent's child pointer / `root` set to the sibling, sibling's `parent` set to
the grandparent) and the branch and the leaf freed, in that order.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.Remove

variable {σ : Type} (ext : Ext σ)

/-- What `_freeNode(id)` does to the tree. -/
def freeTree (t : RadixPriceTree.Tree) (id : Nat) : RadixPriceTree.Tree :=
  { t with nodes := upd t.nodes id default, freeIds := t.freeIds ++ [id] }

/-- The tree written back by a successful `remove(price)`, step by step as in the code. -/
def removeTree (t : RadixPriceTree.Tree) (price : Nat) : RadixPriceTree.Tree :=
  let leafId := t.leaves price
  let t1 := { t with leaves := upd t.leaves price default }
  if leafId = t1.root then
    freeTree { t1 with root := 0 } leafId
  else
    let branchId := (t1.nodes leafId).parent
    let siblingId :=
      if (t1.nodes branchId).left = leafId then (t1.nodes branchId).right
      else (t1.nodes branchId).left
    let gp := (t1.nodes branchId).parent
    let t2 :=
      if gp = 0 then { t1 with root := siblingId }
      else if (t1.nodes gp).left = branchId then
        { t1 with nodes := upd t1.nodes gp { t1.nodes gp with left := siblingId } }
      else
        { t1 with nodes := upd t1.nodes gp { t1.nodes gp with right := siblingId } }
    let t3 := { t2 with nodes := upd t2.nodes siblingId { t2.nodes siblingId with parent := gp } }
    freeTree (freeTree t3 branchId) leafId

/-- Full behaviour over a storage lens: revert iff `leaves[price] = 0`, otherwise return `()`
and write back `removeTree`. -/
theorem remove_run (get' : σ → RadixPriceTree.Tree) (set' : σ → RadixPriceTree.Tree → σ)
    (hgs : ∀ w t, get' (set' w t) = t) (hss : ∀ w t t', set' (set' w t) t' = set' w t')
    (price : Nat) (env : Env) (w : σ) :
    RadixPriceTree.remove ext (do return get' (← get)) (fun x => modify fun w => set' w x)
        price env w
      = if (get' w).leaves price = 0 then .error ⟨"PriceLevelMissing"⟩
        else .ok ((), set' w (removeTree (get' w) price)) := by
  by_cases h0 : (get' w).leaves price = 0
  · simp [RadixPriceTree.remove, h0]
  · simp only [RadixPriceTree.remove, RadixPriceTree.«_freeNode», removeTree, freeTree, h0]
    by_cases hr : (get' w).leaves price = (get' w).root
    · have hr0 : ¬ (get' w).root = 0 := hr ▸ h0
      simp [hgs, hss, hr, hr0]
    · by_cases hl : ((get' w).nodes ((get' w).nodes ((get' w).leaves price)).parent).left
          = (get' w).leaves price <;>
      by_cases hg : ((get' w).nodes ((get' w).nodes ((get' w).leaves price)).parent).parent = 0 <;>
      by_cases hgl : ((get' w).nodes ((get' w).nodes ((get' w).nodes ((get' w).leaves price)).parent).parent).left
          = ((get' w).nodes ((get' w).leaves price)).parent <;>
      simp [hgs, hss, hr, h0, hl, hg, hgl]

/-! ## Fields of the written tree -/

theorem removeTree_leaves (t : RadixPriceTree.Tree) (price : Nat) :
    (removeTree t price).leaves = upd t.leaves price 0 := by
  by_cases hr : t.leaves price = t.root <;>
  by_cases hg : (t.nodes (t.nodes (t.leaves price)).parent).parent = 0 <;>
  by_cases hgl : (t.nodes (t.nodes (t.nodes (t.leaves price)).parent).parent).left
      = (t.nodes (t.leaves price)).parent <;>
  simp [removeTree, freeTree, hr, hg, hgl] <;> rfl

theorem removeTree_nextNodeId (t : RadixPriceTree.Tree) (price : Nat) :
    (removeTree t price).nextNodeId = t.nextNodeId := by
  by_cases hr : t.leaves price = t.root <;>
  by_cases hg : (t.nodes (t.nodes (t.leaves price)).parent).parent = 0 <;>
  by_cases hgl : (t.nodes (t.nodes (t.nodes (t.leaves price)).parent).parent).left
      = (t.nodes (t.leaves price)).parent <;>
  simp [removeTree, freeTree, hr, hg, hgl]

theorem removeTree_freeIds (t : RadixPriceTree.Tree) (price : Nat) :
    (removeTree t price).freeIds = t.freeIds ++
      (if t.leaves price = t.root then [t.leaves price]
       else [(t.nodes (t.leaves price)).parent, t.leaves price]) := by
  by_cases hr : t.leaves price = t.root <;>
  by_cases hg : (t.nodes (t.nodes (t.leaves price)).parent).parent = 0 <;>
  by_cases hgl : (t.nodes (t.nodes (t.nodes (t.leaves price)).parent).parent).left
      = (t.nodes (t.leaves price)).parent <;>
  simp [removeTree, freeTree, hr, hg, hgl]

/-- When the leaf is the root, the tree becomes empty. -/
theorem removeTree_root_of_root (t : RadixPriceTree.Tree) (price : Nat)
    (hr : t.leaves price = t.root) : (removeTree t price).root = 0 := by
  simp [removeTree, freeTree, hr]

/-! ## Guards and footprint of `RadixPriceTree.remove` -/

/-- The only revert: `PriceLevelMissing` exactly when `leaves[price] = 0`. -/
theorem remove_reverts_iff (get' : σ → RadixPriceTree.Tree) (set' : σ → RadixPriceTree.Tree → σ)
    (hgs : ∀ w t, get' (set' w t) = t) (hss : ∀ w t t', set' (set' w t) t' = set' w t')
    (price : Nat) (env : Env) (w : σ) (e : Revert) :
    RadixPriceTree.remove ext (do return get' (← get)) (fun x => modify fun w => set' w x)
        price env w = .error e ↔ (get' w).leaves price = 0 ∧ e = ⟨"PriceLevelMissing"⟩ := by
  rw [remove_run ext get' set' hgs hss]
  by_cases h0 : (get' w).leaves price = 0
  · simp [h0, eq_comm]
  · simp [h0]

/-- Succeeds (returning `()`) whenever the price is present. -/
theorem remove_ok (get' : σ → RadixPriceTree.Tree) (set' : σ → RadixPriceTree.Tree → σ)
    (hgs : ∀ w t, get' (set' w t) = t) (hss : ∀ w t t', set' (set' w t) t' = set' w t')
    (price : Nat) (env : Env) (w : σ) (h : (get' w).leaves price ≠ 0) :
    RadixPriceTree.remove ext (do return get' (← get)) (fun x => modify fun w => set' w x)
        price env w = .ok ((), set' w (removeTree (get' w) price)) := by
  rw [remove_run ext get' set' hgs hss]; simp [h]

/-- Footprint on success: the price was present, only the tree is written (`w' = set' w _`);
`leaves[price]` is cleared, every other `leaves` entry and `nextNodeId` are unchanged, and
`freeIds` gets the freed ids appended (`[leaf]` when the leaf was the root, `[branch, leaf]`
otherwise). -/
theorem remove_footprint (get' : σ → RadixPriceTree.Tree) (set' : σ → RadixPriceTree.Tree → σ)
    (hgs : ∀ w t, get' (set' w t) = t) (hss : ∀ w t t', set' (set' w t) t' = set' w t')
    (price : Nat) (env : Env) (w w' : σ) (r : Unit)
    (h : RadixPriceTree.remove ext (do return get' (← get)) (fun x => modify fun w => set' w x)
        price env w = .ok (r, w')) :
    (get' w).leaves price ≠ 0 ∧
    w' = set' w (get' w') ∧
    (get' w').leaves price = 0 ∧
    (∀ p, p ≠ price → (get' w').leaves p = (get' w).leaves p) ∧
    (get' w').nextNodeId = (get' w).nextNodeId ∧
    (get' w').freeIds = (get' w).freeIds ++
      (if (get' w).leaves price = (get' w).root then [(get' w).leaves price]
       else [((get' w).nodes ((get' w).leaves price)).parent, (get' w).leaves price]) := by
  rw [remove_run ext get' set' hgs hss] at h
  by_cases h0 : (get' w).leaves price = 0
  · simp [h0] at h
  · simp only [h0, ite_false, Except.ok.injEq, Prod.mk.injEq] at h
    obtain ⟨-, rfl⟩ := h
    refine ⟨h0, by simp [hgs], ?_, ?_, ?_, ?_⟩
    · simp [hgs, removeTree_leaves, upd]
    · intro p hp; simp [hgs, removeTree_leaves, upd, hp]
    · simp [hgs, removeTree_nextNodeId]
    · simp [hgs, removeTree_freeIds]

end AsyncSwap.Swarm.Remove
