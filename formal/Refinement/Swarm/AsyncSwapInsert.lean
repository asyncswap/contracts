import Generated.AsyncSwap
import Refinement.Monad
import Refinement.Swarm.AsyncSwapNewNode
import Refinement.Swarm.AsyncSwapMostSignificantBit

/-!
# AsyncSwap: `RadixPriceTree.insert`

`insert(self, price)` has no `require`/custom-error guard of its own and no external calls. Over
any storage lens for the tree (`get'`/`set'` with the usual get-set and set-set laws):

* `insert_present`: if `leaves[price] ≠ 0` it returns `false` and leaves the state untouched;
* `insert_reverts`: every revert happens with `leaves[price] = 0` and is either `NodeIdOverflow`
  (from one of the two `_newNode` calls) or `"loop bound"` (one of the two tree walks not
  terminating within `2^64` steps, the model's stand-in for running out of gas);
  `insert_overflow` shows the first `_newNode` revert is reached;
* `insert_empty`: into an empty tree (`root = 0`) the new leaf becomes the root, carries `price`
  and `leaf = true`, and `leaves[price]` points at it;
* `insert_footprint`: on success, either the price was present (`false`, nothing written) or it
  was absent, the result is `true`, only the tree is written (`w' = set' w _`), and
  `leaves` changes exactly at `price` (set to the new leaf id).
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.Insert

variable {σ : Type} (ext : Ext σ)

/-! ## Loops whose body never writes or reverts -/

theorem forIn_list_pure {β : Type} (f : Nat → β → M σ (ForInStep β)) (env : Env) (w : σ)
    (hf : ∀ i b, ∃ s, f i b env w = .ok (s, w)) :
    ∀ (l : List Nat) (b : β), ∃ b', forIn l b f env w = .ok (b', w) := by
  intro l
  induction l with
  | nil => intro b; exact ⟨b, rfl⟩
  | cons i l ih =>
    intro b
    rw [List.forIn_cons, run_bind]
    obtain ⟨s, hs⟩ := hf i b
    rw [hs]
    cases s with
    | done b' => exact ⟨b', rfl⟩
    | yield b' => exact ih b'

theorem forIn_range_pure {β : Type} (f : Nat → β → M σ (ForInStep β)) (env : Env) (w : σ)
    (hf : ∀ i b, ∃ s, f i b env w = .ok (s, w)) (r : Std.Legacy.Range) (b : β) :
    ∃ b', forIn r b f env w = .ok (b', w) := by
  rw [Std.Legacy.Range.forIn_eq_forIn_range']
  exact forIn_list_pure f env w hf _ b

theorem forIn_ok_state {β : Type} (f : Nat → β → M σ (ForInStep β)) (env : Env) (w : σ)
    (hf : ∀ i b, ∃ s, f i b env w = .ok (s, w)) (r : Std.Legacy.Range) (b x : β) (w' : σ)
    (h : forIn r b f env w = .ok (x, w')) : w' = w := by
  obtain ⟨b', hb⟩ := forIn_range_pure f env w hf r b
  rw [hb] at h; cases h; rfl

theorem forIn_no_error {β : Type} (f : Nat → β → M σ (ForInStep β)) (env : Env) (w : σ)
    (hf : ∀ i b, ∃ s, f i b env w = .ok (s, w)) (r : Std.Legacy.Range) (b : β) (e : Revert)
    (h : forIn r b f env w = .error e) : False := by
  obtain ⟨b', hb⟩ := forIn_range_pure f env w hf r b
  rw [hb] at h; cases h

/-! ## `_newNode`, as `insert` uses it -/

theorem newNode_ok (get' : σ → RadixPriceTree.Tree) (set' : σ → RadixPriceTree.Tree → σ)
    (hgs : ∀ w t, get' (set' w t) = t) (env : Env) (w s : σ) (a : Nat)
    (h : RadixPriceTree.«_newNode» ext (do return get' (← get))
        (fun x => modify fun w => set' w x) env w = .ok (a, s)) :
    s = set' w (get' s) ∧ (get' s).leaves = (get' w).leaves ∧ (get' s).root = (get' w).root := by
  obtain ⟨h1, h3, -, h2, -⟩ :=
    AsyncSwap.Swarm.NewNode.newNode_footprint ext get' set' hgs env w s a h
  exact ⟨h1, h2, h3⟩

theorem newNode_err (get' : σ → RadixPriceTree.Tree) (set' : σ → RadixPriceTree.Tree → σ)
    (hgs : ∀ w t, get' (set' w t) = t) (env : Env) (w : σ) (e : Revert)
    (h : RadixPriceTree.«_newNode» ext (do return get' (← get))
        (fun x => modify fun w => set' w x) env w = .error e) :
    e = ⟨"NodeIdOverflow"⟩ := by
  by_cases he : (get' w).freeIds = []
  · rw [AsyncSwap.Swarm.NewNode.newNode_run_fresh ext get' set' hgs env w he] at h
    split at h
    · cases h; rfl
    · cases h
  · rw [AsyncSwap.Swarm.NewNode.newNode_run_free ext get' set' hgs env w he] at h
    cases h

/-! ## `RadixPriceTree.insert` -/

/-- Price already present: returns `false`, nothing written, no revert. -/
theorem insert_present (get' : σ → RadixPriceTree.Tree) (set' : σ → RadixPriceTree.Tree → σ)
    (price : Nat) (env : Env) (w : σ) (h0 : (get' w).leaves price ≠ 0) :
    RadixPriceTree.insert ext (do return get' (← get)) (fun x => modify fun w => set' w x)
        price env w = .ok (false, w) := by
  simp [RadixPriceTree.insert, h0]

/-- The first `_newNode` guard is reached: an absent price with an empty free list and
`uint32(nextNodeId + 1) = 0` reverts with `NodeIdOverflow`. -/
theorem insert_overflow (get' : σ → RadixPriceTree.Tree) (set' : σ → RadixPriceTree.Tree → σ)
    (hgs : ∀ w t, get' (set' w t) = t)
    (price : Nat) (env : Env) (w : σ) (h0 : (get' w).leaves price = 0)
    (he : (get' w).freeIds = []) (hz : addw 32 (get' w).nextNodeId 1 = 0) :
    RadixPriceTree.insert ext (do return get' (← get)) (fun x => modify fun w => set' w x)
        price env w = .error ⟨"NodeIdOverflow"⟩ := by
  have hn := AsyncSwap.Swarm.NewNode.newNode_run_fresh ext get' set' hgs env w he
  simp only [hz, ite_true] at hn
  simp only [RadixPriceTree.insert, run_bind, run_get, run_pure, run_ite, run_modify, run_throw,
    h0, bne_self_eq_false, Bool.false_eq_true, ite_false]
  rw [hn]

/-- Insert into an empty tree: with `_newNode` returning `a` and tree `t1`, the tree written is
`t1` with `root := a`, node `a` given `price` and `leaf = true`, and `leaves[price] := a`. -/
theorem insert_empty (get' : σ → RadixPriceTree.Tree) (set' : σ → RadixPriceTree.Tree → σ)
    (hgs : ∀ w t, get' (set' w t) = t) (hss : ∀ w t t', set' (set' w t) t' = set' w t')
    (price : Nat) (env : Env) (w s : σ) (a : Nat) (h0 : (get' w).leaves price = 0)
    (hr : (get' w).root = 0)
    (hn : RadixPriceTree.«_newNode» ext (do return get' (← get))
        (fun x => modify fun w => set' w x) env w = .ok (a, s)) :
    RadixPriceTree.insert ext (do return get' (← get)) (fun x => modify fun w => set' w x)
        price env w = .ok (true, set' w { get' s with
          root := a,
          nodes := upd (get' s).nodes a { (get' s).nodes a with price := price, leaf := true },
          leaves := upd (get' s).leaves price a }) := by
  obtain ⟨hs, -, hrs⟩ := newNode_ok ext get' set' hgs env w s a hn
  simp only [RadixPriceTree.insert, run_bind, run_get, run_pure, run_ite, run_modify, run_throw,
    hgs, hss, h0, bne_self_eq_false, Bool.false_eq_true, ite_false]
  rw [hn]
  simp only [hrs, hr, beq_self_eq_true, ite_true]
  rw [hs]
  simp only [hgs, hss, Except.ok.injEq, Prod.mk.injEq, true_and]
  congr 2
  funext x
  simp only [upd]
  split_ifs <;> rfl

/-- Reverts: only for an absent price, and only `NodeIdOverflow` (a `_newNode` call) or
`"loop bound"` (a tree walk exceeding `2^64` steps). -/
theorem insert_reverts (get' : σ → RadixPriceTree.Tree) (set' : σ → RadixPriceTree.Tree → σ)
    (hgs : ∀ w t, get' (set' w t) = t) (hss : ∀ w t t', set' (set' w t) t' = set' w t')
    (price : Nat) (env : Env) (w : σ) (e : Revert)
    (h : RadixPriceTree.insert ext (do return get' (← get)) (fun x => modify fun w => set' w x)
        price env w = .error e) :
    (get' w).leaves price = 0 ∧ (e = ⟨"NodeIdOverflow"⟩ ∨ e = ⟨"loop bound"⟩) := by
  simp only [RadixPriceTree.insert, run_bind, run_get, run_pure, run_ite, run_modify, run_throw,
    hgs, hss] at h
  by_cases h0 : (get' w).leaves price = 0
  · simp only [h0, bne_self_eq_false, Bool.false_eq_true, ite_false] at h
    split at h
    · rename_i a s' hn
      split at h
      · cases h
      · split at h
        · rename_i x s2 hfor
          have := forIn_ok_state _ _ _ ?hf _ _ _ _ hfor
          case hf =>
            intro i b
            simp only [run_bind, run_get, run_pure, run_ite, RadixPriceTree.«_bitSet»]
            split_ifs <;> exact ⟨_, rfl⟩
          subst this
          split at h
          · cases h; exact ⟨h0, Or.inr rfl⟩
          · simp only [hgs, AsyncSwap.Swarm.MostSignificantBit.mostSignificantBit_spec] at h
            split at h
            · rename_i y s3 hfor2
              have := forIn_ok_state _ _ _ ?hf2 _ _ _ _ hfor2
              case hf2 =>
                intro i b
                simp only [run_bind, run_get, run_pure, run_ite, RadixPriceTree.«_bitSet»]
                split_ifs <;> exact ⟨_, rfl⟩
              subst this
              split at h
              · cases h; exact ⟨h0, Or.inr rfl⟩
              · split at h
                · rename_i bId s4 hn2
                  obtain ⟨hs4, -, -⟩ := newNode_ok ext get' set' hgs env _ s4 bId hn2
                  rw [hs4] at h
                  simp only [hgs, hss, RadixPriceTree.«_bitSet», run_bind, run_pure] at h
                  repeat' (split at h)
                  all_goals cases h
                · rename_i e' hn2
                  have := newNode_err ext get' set' hgs env _ e' hn2
                  cases h
                  exact ⟨h0, Or.inl this⟩
            · rename_i e' hfor2
              exact (forIn_no_error _ _ _ (by
                intro i b
                simp only [run_bind, run_get, run_pure, run_ite, RadixPriceTree.«_bitSet»]
                split_ifs <;> exact ⟨_, rfl⟩) _ _ _ hfor2).elim
        · rename_i e' hfor
          exact (forIn_no_error _ _ _ (by
            intro i b
            simp only [run_bind, run_get, run_pure, run_ite, RadixPriceTree.«_bitSet»]
            split_ifs <;> exact ⟨_, rfl⟩) _ _ _ hfor).elim
    · rename_i e' hn
      have := newNode_err ext get' set' hgs env w e' hn
      cases h
      exact ⟨h0, Or.inl this⟩
  · simp [h0] at h

/-- Footprint on success: either the price was present (`false`, state unchanged), or it was
absent, the result is `true`, only the tree is written, and `leaves` is updated exactly at
`price` (to the new leaf's id). -/
theorem insert_footprint (get' : σ → RadixPriceTree.Tree) (set' : σ → RadixPriceTree.Tree → σ)
    (hgs : ∀ w t, get' (set' w t) = t) (hss : ∀ w t t', set' (set' w t) t' = set' w t')
    (price : Nat) (env : Env) (w w' : σ) (r : Bool)
    (h : RadixPriceTree.insert ext (do return get' (← get)) (fun x => modify fun w => set' w x)
        price env w = .ok (r, w')) :
    ((get' w).leaves price ≠ 0 ∧ r = false ∧ w' = w) ∨
    ((get' w).leaves price = 0 ∧ r = true ∧ w' = set' w (get' w') ∧
      ∃ leafId, (get' w').leaves = upd (get' w).leaves price leafId) := by
  simp only [RadixPriceTree.insert, run_bind, run_get, run_pure, run_ite, run_modify, run_throw,
    hgs, hss] at h
  by_cases h0 : (get' w).leaves price = 0
  · right
    simp only [h0, bne_self_eq_false, Bool.false_eq_true, ite_false] at h
    split at h
    · rename_i a s' hn
      obtain ⟨hs', hl, -⟩ := newNode_ok ext get' set' hgs env w s' a hn
      split at h
      · simp only [Except.ok.injEq, Prod.mk.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        refine ⟨h0, rfl, ?_, a, ?_⟩
        · rw [hs']; simp [hgs, hss]
        · simp [hgs, hl]
      · split at h
        · rename_i x s2 hfor
          have := forIn_ok_state _ _ _ ?hf _ _ _ _ hfor
          case hf =>
            intro i b
            simp only [run_bind, run_get, run_pure, run_ite, RadixPriceTree.«_bitSet»]
            split_ifs <;> exact ⟨_, rfl⟩
          subst this
          split at h
          · cases h
          · simp only [hgs, AsyncSwap.Swarm.MostSignificantBit.mostSignificantBit_spec] at h
            split at h
            · rename_i y s3 hfor2
              have := forIn_ok_state _ _ _ ?hf2 _ _ _ _ hfor2
              case hf2 =>
                intro i b
                simp only [run_bind, run_get, run_pure, run_ite, RadixPriceTree.«_bitSet»]
                split_ifs <;> exact ⟨_, rfl⟩
              subst this
              split at h
              · cases h
              · split at h
                · rename_i bId s4 hn2
                  obtain ⟨hs4, hl4, -⟩ := newNode_ok ext get' set' hgs env _ s4 bId hn2
                  simp only [hgs] at hl4
                  rw [hs4] at h
                  simp only [hgs, hss, RadixPriceTree.«_bitSet», run_bind, run_pure] at h
                  repeat' (split at h)
                  all_goals first
                    | (cases h; done)
                    | (injection h with h1
                       injection h1 with hr hw
                       subst hr hw
                       refine ⟨h0, rfl, ?_, a, ?_⟩
                       · rw [hs']; simp [hgs, hss]
                       · simp [hgs, hl4, hl])
                · cases h
            · cases h
        · cases h
    · cases h
  · left
    simp [h0] at h
    obtain ⟨rfl, rfl⟩ := h
    exact ⟨h0, rfl, rfl⟩

end AsyncSwap.Swarm.Insert
