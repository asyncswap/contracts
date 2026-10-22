import Generated.AsyncSwap
import Refinement.Monad

/-!
# AsyncSwap: `RadixPriceTree._newNode`

`_newNode()` has no external calls. Over a storage lens:
* if `freeIds` is non-empty it pops the last released id, returns it, and writes only
  `freeIds := freeIds.dropLast` (it can't revert: the `idx` and `pop` checks are discharged by
  non-emptiness);
* otherwise it bumps `nextNodeId` to `uint32(nextNodeId + 1)` and returns it, reverting with
  `NodeIdOverflow` exactly when that wrapped value is `0`.
No other field of the tree (`root`, `nodes`, `leaves`) and nothing outside the tree changes.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.NewNode

variable {σ : Type} (ext : Ext σ)

/-- Free-list branch: `freeIds ≠ []` ⇒ returns the last free id and drops it. -/
theorem newNode_run_free (get' : σ → RadixPriceTree.Tree) (set' : σ → RadixPriceTree.Tree → σ)
    (_hgs : ∀ w t, get' (set' w t) = t) (env : Env) (w : σ)
    (hne : (get' w).freeIds ≠ []) :
    RadixPriceTree.«_newNode» ext (do return get' (← get)) (fun x => modify fun w => set' w x) env w
      = .ok ((get' w).freeIds.getLast hne,
             set' w { get' w with freeIds := (get' w).freeIds.dropLast }) := by
  have hlen : (get' w).freeIds.length ≠ 0 := by simpa [List.length_eq_zero_iff] using hne
  have hlt : (get' w).freeIds.length - 1 < (get' w).freeIds.length := by omega
  have hle : 1 ≤ (get' w).freeIds.length := by omega
  simp [RadixPriceTree.«_newNode», subc, idx, hle, hlt, hne, List.getLast_eq_getElem]

/-- Fresh-id branch: `freeIds = []` ⇒ `nextNodeId := uint32(nextNodeId + 1)`, returned;
reverts with `NodeIdOverflow` iff the wrapped id is `0`. -/
theorem newNode_run_fresh (get' : σ → RadixPriceTree.Tree) (set' : σ → RadixPriceTree.Tree → σ)
    (_hgs : ∀ w t, get' (set' w t) = t) (env : Env) (w : σ)
    (he : (get' w).freeIds = []) :
    RadixPriceTree.«_newNode» ext (do return get' (← get)) (fun x => modify fun w => set' w x) env w
      = if addw 32 (get' w).nextNodeId 1 = 0 then .error ⟨"NodeIdOverflow"⟩
        else .ok (addw 32 (get' w).nextNodeId 1,
                  set' w { get' w with nextNodeId := addw 32 (get' w).nextNodeId 1 }) := by
  simp [RadixPriceTree.«_newNode», he]

/-- Guards: `_newNode` reverts exactly when there is no free id and `uint32(nextNodeId + 1) = 0`. -/
theorem newNode_reverts_iff (get' : σ → RadixPriceTree.Tree) (set' : σ → RadixPriceTree.Tree → σ)
    (hgs : ∀ w t, get' (set' w t) = t) (env : Env) (w : σ) :
    (∃ e, RadixPriceTree.«_newNode» ext (do return get' (← get))
        (fun x => modify fun w => set' w x) env w = .error e)
      ↔ (get' w).freeIds = [] ∧ addw 32 (get' w).nextNodeId 1 = 0 := by
  by_cases he : (get' w).freeIds = []
  · rw [newNode_run_fresh ext get' set' hgs env w he]
    split <;> simp_all
  · rw [newNode_run_free ext get' set' hgs env w he]
    simp [he]

/-- Footprint and result on success: `root`, `nodes`, `leaves` are unchanged; either the id is
the popped last free id (and `nextNodeId` unchanged), or the free list was empty, the id is
`uint32(nextNodeId + 1)`, nonzero, and becomes the new `nextNodeId`. -/
theorem newNode_footprint (get' : σ → RadixPriceTree.Tree) (set' : σ → RadixPriceTree.Tree → σ)
    (hgs : ∀ w t, get' (set' w t) = t) (env : Env) (w w' : σ) (id : Nat)
    (h : RadixPriceTree.«_newNode» ext (do return get' (← get))
        (fun x => modify fun w => set' w x) env w = .ok (id, w')) :
    w' = set' w (get' w') ∧
    (get' w').root = (get' w).root ∧
    (get' w').nodes = (get' w).nodes ∧
    (get' w').leaves = (get' w).leaves ∧
    ((∃ hne : (get' w).freeIds ≠ [], id = (get' w).freeIds.getLast hne ∧
        (get' w').freeIds = (get' w).freeIds.dropLast ∧
        (get' w').nextNodeId = (get' w).nextNodeId) ∨
     ((get' w).freeIds = [] ∧ id = addw 32 (get' w).nextNodeId 1 ∧ id ≠ 0 ∧
        (get' w').nextNodeId = id ∧ (get' w').freeIds = [])) := by
  by_cases he : (get' w).freeIds = []
  · rw [newNode_run_fresh ext get' set' hgs env w he] at h
    split at h
    · cases h
    · rename_i hz
      simp only [Except.ok.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      refine ⟨by simp [hgs], by simp [hgs], by simp [hgs], by simp [hgs], Or.inr ?_⟩
      simp [hgs, he, hz]
  · rw [newNode_run_free ext get' set' hgs env w he] at h
    simp only [Except.ok.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl⟩ := h
    refine ⟨by simp [hgs], by simp [hgs], by simp [hgs], by simp [hgs], Or.inl ⟨he, ?_⟩⟩
    simp [hgs]

/-- The same run, with the accessor wrappers the caller (`insert`) passes in. -/
theorem newNode_run_wrapped_eq (get' : σ → RadixPriceTree.Tree) (set' : σ → RadixPriceTree.Tree → σ)
    (env : Env) (w : σ) :
    RadixPriceTree.«_newNode» ext
        (do return (← (do return get' (← get) : M σ RadixPriceTree.Tree)))
        (fun x => do (modify fun w => set' w x : M σ Unit)) env w
      = RadixPriceTree.«_newNode» ext (do return get' (← get))
          (fun x => modify fun w => set' w x) env w := by
  simp

end AsyncSwap.Swarm.NewNode
