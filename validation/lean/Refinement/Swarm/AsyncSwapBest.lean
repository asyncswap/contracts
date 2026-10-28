import Generated.AsyncSwap
import Refinement.Monad
open FormalAst Refinement

/-!
# `EligiblePrice.best` (src/AsyncSwap.sol)

`best(limit, isBuy)` looks for an eligible price in the radix price tree. If the root is the
empty sentinel (`root == 0`) or the root's subtree bound is not eligible against `limit`
(`_eligible`), it returns `(false, 0)`. Otherwise it descends from the root: at every inner node it
goes right when the right child's bound is eligible and left otherwise, and it stops at the first
leaf, returning `(true, leaf.price)`.

The function has no `require`; storage is reached only through the accessors `tree_get` and
`bounds_get` (reads). The setters `tree_set` and `bounds_set` are never called. Its only revert of
its own is the model's gas bound `"loop bound"`.

* Part A (`Good Q P`, a Hoare-style predicate closed under `pure`, `bind`, `ite`, `throw` and
  `forIn`): revert characterisation and frame.
* Part B (fixed read-only views `t`, `b`, `leF`): the exact `(false, 0)` cases and, for
  `(true, p)`, that `p` is the price of a leaf reached from an eligible root. This uses the loop
  invariant `done = true → (t.nodes cursor).leaf`.
-/

namespace AsyncSwap.Swarm.Best

variable {σ : Type}

/-! ## Part A: reverts and footprint -/

/-- Started in a `Q`-state, `x` ends in a `Q`-state or fails with a `P`-error. -/
def Good (Q : σ → Prop) (P : Revert → Prop) {α : Type} (x : M σ α) : Prop :=
  ∀ r s, Q s → match x r s with
    | .ok (_, s') => Q s'
    | .error e => P e

section closure
variable {Q : σ → Prop} {P : Revert → Prop}

theorem good_pure {α : Type} (a : α) : Good Q P (pure a : M σ α) := by
  intro r s h; simpa [run_pure] using h

theorem good_throw {α : Type} (e : Revert) (he : P e) : Good Q P (throw e : M σ α) := by
  intro r s _; simpa [run_throw] using he

theorem good_bind {α β : Type} {x : M σ α} {f : α → M σ β}
    (hx : Good Q P x) (hf : ∀ a, Good Q P (f a)) : Good Q P (x >>= f) := by
  intro r s h
  rw [run_bind]
  have hxs := hx r s h
  revert hxs
  cases x r s with
  | error e => intro he; exact he
  | ok p => obtain ⟨a, s'⟩ := p; intro hs; exact hf a r s' hs

theorem good_ite {α : Type} (c : Prop) [Decidable c] {x y : M σ α}
    (hx : Good Q P x) (hy : Good Q P y) : Good Q P (if c then x else y) := by
  split <;> assumption

theorem good_forIn_list {α β : Type} (l : List α) (init : β) (f : α → β → M σ (ForInStep β))
    (hf : ∀ a b, Good Q P (f a b)) : Good Q P (forIn l init f) := by
  induction l generalizing init with
  | nil => rw [List.forIn_nil]; exact good_pure init
  | cons a l ih =>
    rw [List.forIn_cons]
    apply good_bind (hf a init)
    intro step
    cases step with
    | done b => exact good_pure b
    | yield b => exact ih b

theorem good_forIn_range {β : Type} (rg : Std.Legacy.Range) (init : β)
    (f : Nat → β → M σ (ForInStep β))
    (hf : ∀ a b, Good Q P (f a b)) : Good Q P (forIn rg init f) := by
  rw [Std.Legacy.Range.forIn_eq_forIn_range']
  exact good_forIn_list _ init f hf

end closure

macro "good_step" : tactic => `(tactic| first
  | with_reducible assumption
  | with_reducible apply good_pure
  | (with_reducible apply good_throw); with_reducible assumption
  | with_reducible apply good_ite
  | with_reducible apply good_bind
  | with_reducible apply good_forIn_range
  | with_reducible intro _)

/-- **Invariant / revert characterisation.** If `tree_get`, `bounds_get` and every comparison
`le a b` keep the state predicate `Q` and fail only with `P`-errors, and `P` accepts the loop-bound
revert, then `EligiblePrice.best` keeps `Q` and fails only with `P`-errors. No hypothesis on
`tree_set` or `bounds_set` is needed: they are never called. -/
theorem best_good (ext : Ext σ) (tree_get : M σ RadixPriceTree.Tree)
    (tree_set : RadixPriceTree.Tree → M σ Unit) (bounds_get : M σ (Nat → EligiblePrice.Ratio))
    (bounds_set : (Nat → EligiblePrice.Ratio) → M σ Unit) (limit : EligiblePrice.Ratio)
    (isBuy : Bool) (Q : σ → Prop) (P : Revert → Prop)
    (htg : Good Q P tree_get) (hbg : Good Q P bounds_get)
    (hle : ∀ a b, Good Q P (ext.fn_EligiblePrice_le_12578 a b))
    (hlb : P ⟨"loop bound"⟩) :
    Good Q P (EligiblePrice.best ext tree_get tree_set bounds_get bounds_set limit isBuy) := by
  unfold EligiblePrice.best EligiblePrice.«_eligible»
  repeat' (first | (with_reducible apply hle) | good_step)

/-- **Only revert of its own: the loop bound.** If the reads and the comparison never revert,
`EligiblePrice.best` can revert only with `"loop bound"`. -/
theorem best_reverts_only_loop_bound (ext : Ext σ) (tree_get : M σ RadixPriceTree.Tree)
    (tree_set : RadixPriceTree.Tree → M σ Unit) (bounds_get : M σ (Nat → EligiblePrice.Ratio))
    (bounds_set : (Nat → EligiblePrice.Ratio) → M σ Unit) (limit : EligiblePrice.Ratio)
    (isBuy : Bool)
    (htg : ∀ r s, ∃ v s', tree_get r s = .ok (v, s'))
    (hbg : ∀ r s, ∃ v s', bounds_get r s = .ok (v, s'))
    (hle : ∀ a b r s, ∃ v s', ext.fn_EligiblePrice_le_12578 a b r s = .ok (v, s'))
    (r : Env) (s : σ) (e : Revert)
    (h : EligiblePrice.best ext tree_get tree_set bounds_get bounds_set limit isBuy r s
      = .error e) :
    e = ⟨"loop bound"⟩ := by
  have hg := best_good ext tree_get tree_set bounds_get bounds_set limit isBuy
    (fun _ => True) (fun e => e = ⟨"loop bound"⟩)
    (by intro r s _; obtain ⟨v, s', hh⟩ := htg r s; simp [hh])
    (by intro r s _; obtain ⟨v, s', hh⟩ := hbg r s; simp [hh])
    (by intro a b r s _; obtain ⟨v, s', hh⟩ := hle a b r s; simp [hh])
    rfl r s trivial
  rw [h] at hg
  exact hg

/-- **Frame: writes nothing.** If `tree_get`, `bounds_get` and the comparison leave the world
unchanged, a successful `EligiblePrice.best` leaves the world unchanged. -/
theorem best_frame (ext : Ext σ) (tree_get : M σ RadixPriceTree.Tree)
    (tree_set : RadixPriceTree.Tree → M σ Unit) (bounds_get : M σ (Nat → EligiblePrice.Ratio))
    (bounds_set : (Nat → EligiblePrice.Ratio) → M σ Unit) (limit : EligiblePrice.Ratio)
    (isBuy : Bool)
    (htg : ∀ r s v s', tree_get r s = .ok (v, s') → s' = s)
    (hbg : ∀ r s v s', bounds_get r s = .ok (v, s') → s' = s)
    (hle : ∀ a b r s v s', ext.fn_EligiblePrice_le_12578 a b r s = .ok (v, s') → s' = s)
    (r : Env) (s s' : σ) (res : Bool × Nat)
    (h : EligiblePrice.best ext tree_get tree_set bounds_get bounds_set limit isBuy r s
      = .ok (res, s')) :
    s' = s := by
  have hg := best_good ext tree_get tree_set bounds_get bounds_set limit isBuy
    (fun w => w = s) (fun _ => True)
    (by
      intro r w hw; revert hw
      cases hh : tree_get r w with
      | error e => intro _; trivial
      | ok p => obtain ⟨v, w'⟩ := p; intro hw; simp only; rw [htg r w v w' hh]; exact hw)
    (by
      intro r w hw; revert hw
      cases hh : bounds_get r w with
      | error e => intro _; trivial
      | ok p => obtain ⟨v, w'⟩ := p; intro hw; simp only; rw [hbg r w v w' hh]; exact hw)
    (by
      intro a b r w hw; revert hw
      cases hh : ext.fn_EligiblePrice_le_12578 a b r w with
      | error e => intro _; trivial
      | ok p => obtain ⟨v, w'⟩ := p; intro hw; simp only; rw [hle a b r w v w' hh]; exact hw)
    trivial r s rfl
  rw [h] at hg
  exact hg

/-- **The setters are never used**: `EligiblePrice.best` does not depend on `tree_set` or
`bounds_set`, so it never writes the tree or the bounds. -/
theorem best_setters_irrelevant (ext : Ext σ) (tree_get : M σ RadixPriceTree.Tree)
    (ts₁ ts₂ : RadixPriceTree.Tree → M σ Unit) (bounds_get : M σ (Nat → EligiblePrice.Ratio))
    (bs₁ bs₂ : (Nat → EligiblePrice.Ratio) → M σ Unit) (limit : EligiblePrice.Ratio)
    (isBuy : Bool) :
    EligiblePrice.best ext tree_get ts₁ bounds_get bs₁ limit isBuy =
      EligiblePrice.best ext tree_get ts₂ bounds_get bs₂ limit isBuy := rfl

/-! ## Part B: the result -/

/-- Loop invariant, consequence form: if every body step from an `I`-accumulator succeeds without
changing the state and yields an `I`-accumulator, a successful loop ends in an `I`-accumulator with
the state unchanged. -/
theorem loop_ok {β : Type} (l : List Nat) (init : β) (f : Nat → β → M σ (ForInStep β))
    (I : β → Prop) (hI : I init)
    (hf : ∀ a b r s, I b → ∃ st, f a b r s = .ok (st, s) ∧ I st.value)
    (r : Env) (s s' : σ) (q : β) (h : forIn l init f r s = .ok (q, s')) :
    s' = s ∧ I q := by
  induction l generalizing init with
  | nil => simp at h; obtain ⟨rfl, rfl⟩ := h; exact ⟨rfl, hI⟩
  | cons a l ih =>
    rw [List.forIn_cons, run_bind] at h
    obtain ⟨st, hst, hIst⟩ := hf a init r s hI
    rw [hst] at h
    cases st with
    | done b => simp at h; obtain ⟨rfl, rfl⟩ := h; exact ⟨rfl, hIst⟩
    | yield b => exact ih b hIst h

/-- The loop cannot fail when its body cannot. -/
theorem loop_no_err {β : Type} (l : List Nat) (init : β) (f : Nat → β → M σ (ForInStep β))
    (I : β → Prop) (hI : I init)
    (hf : ∀ a b r s, I b → ∃ st, f a b r s = .ok (st, s) ∧ I st.value)
    (r : Env) (s : σ) (e : Revert) (h : forIn l init f r s = .error e) : False := by
  induction l generalizing init with
  | nil => simp at h
  | cons a l ih =>
    rw [List.forIn_cons, run_bind] at h
    obtain ⟨st, hst, hIst⟩ := hf a init r s hI
    rw [hst] at h
    cases st with
    | done b => simp at h
    | yield b => exact ih b hIst h

/-- Whether a subtree bound is eligible against `limit`: `limit ≤ bound` for buys,
`bound ≤ limit` for sells, under the comparison `leF`. -/
def elig (leF : EligiblePrice.Ratio → EligiblePrice.Ratio → Bool) (limit : EligiblePrice.Ratio)
    (isBuy : Bool) (x : EligiblePrice.Ratio) : Bool :=
  if isBuy then leF limit x else leF x limit

/-- **Empty tree.** With a read-only tree view whose root is the sentinel `0`,
`EligiblePrice.best` returns `(false, 0)` and leaves the state unchanged. -/
theorem best_empty (ext : Ext σ) (tree_get : M σ RadixPriceTree.Tree)
    (tree_set : RadixPriceTree.Tree → M σ Unit) (bounds_get : M σ (Nat → EligiblePrice.Ratio))
    (bounds_set : (Nat → EligiblePrice.Ratio) → M σ Unit) (limit : EligiblePrice.Ratio)
    (isBuy : Bool) (t : RadixPriceTree.Tree)
    (htg : ∀ r s, tree_get r s = .ok (t, s)) (hr : t.root = 0) (r : Env) (s : σ) :
    EligiblePrice.best ext tree_get tree_set bounds_get bounds_set limit isBuy r s
      = .ok ((false, 0), s) := by
  unfold EligiblePrice.best
  simp [htg, hr]

/-- **Ineligible root.** With read-only views, a non-empty root whose bound is not eligible makes
`EligiblePrice.best` return `(false, 0)` and leave the state unchanged. -/
theorem best_root_ineligible (ext : Ext σ) (tree_get : M σ RadixPriceTree.Tree)
    (tree_set : RadixPriceTree.Tree → M σ Unit) (bounds_get : M σ (Nat → EligiblePrice.Ratio))
    (bounds_set : (Nat → EligiblePrice.Ratio) → M σ Unit) (limit : EligiblePrice.Ratio)
    (isBuy : Bool) (t : RadixPriceTree.Tree) (b : Nat → EligiblePrice.Ratio)
    (leF : EligiblePrice.Ratio → EligiblePrice.Ratio → Bool)
    (htg : ∀ r s, tree_get r s = .ok (t, s))
    (hbg : ∀ r s, bounds_get r s = .ok (b, s))
    (hle : ∀ a c r s, ext.fn_EligiblePrice_le_12578 a c r s = .ok (leF a c, s))
    (hr : t.root ≠ 0) (he : elig leF limit isBuy (b t.root) = false) (r : Env) (s : σ) :
    EligiblePrice.best ext tree_get tree_set bounds_get bounds_set limit isBuy r s
      = .ok ((false, 0), s) := by
  unfold EligiblePrice.best EligiblePrice.«_eligible»
  cases isBuy <;> simp [elig] at he <;> simp [htg, hbg, hle, hr, he]

/-- **Result.** With read-only views (`tree_get` reads `t`, `bounds_get` reads `b`, and the
comparison is the pure `leF`), every successful run of `EligiblePrice.best` leaves the state
unchanged, and
* returns `(false, 0)` only when the root is the empty sentinel or its bound is not eligible;
* returns `(true, p)` only when the root is non-empty with an eligible bound and `p` is the price
  of a leaf node of the tree. -/
theorem best_result (ext : Ext σ) (tree_get : M σ RadixPriceTree.Tree)
    (tree_set : RadixPriceTree.Tree → M σ Unit) (bounds_get : M σ (Nat → EligiblePrice.Ratio))
    (bounds_set : (Nat → EligiblePrice.Ratio) → M σ Unit) (limit : EligiblePrice.Ratio)
    (isBuy : Bool) (t : RadixPriceTree.Tree) (b : Nat → EligiblePrice.Ratio)
    (leF : EligiblePrice.Ratio → EligiblePrice.Ratio → Bool)
    (htg : ∀ r s, tree_get r s = .ok (t, s))
    (hbg : ∀ r s, bounds_get r s = .ok (b, s))
    (hle : ∀ a c r s, ext.fn_EligiblePrice_le_12578 a c r s = .ok (leF a c, s))
    (r : Env) (s s' : σ) (found : Bool) (p : Nat)
    (h : EligiblePrice.best ext tree_get tree_set bounds_get bounds_set limit isBuy r s
      = .ok ((found, p), s')) :
    s' = s ∧
      (found = false → p = 0 ∧ (t.root = 0 ∨ elig leF limit isBuy (b t.root) = false)) ∧
      (found = true → t.root ≠ 0 ∧ elig leF limit isBuy (b t.root) = true ∧
        ∃ c, (t.nodes c).leaf = true ∧ p = (t.nodes c).price) := by
  unfold EligiblePrice.best EligiblePrice.«_eligible» at h
  simp [htg, hbg, hle] at h
  by_cases hr : t.root = 0
  · simp [hr] at h
    obtain ⟨⟨rfl, rfl⟩, rfl⟩ := h
    simp [hr]
  · simp [hr] at h
    cases isBuy <;> simp only [elig] <;> simp at h ⊢ <;>
    · split at h
      · next he =>
        simp at h
        obtain ⟨⟨rfl, rfl⟩, rfl⟩ := h
        simp [he]
      · next he =>
        split at h
        · next q s'' heq =>
          obtain ⟨rfl, hI⟩ := loop_ok _ _ _
            (fun q : Nat × Bool => q.2 = true → (t.nodes q.1).leaf = true) (by simp) (by
              intro a q r s hq
              by_cases hl : (t.nodes q.1).leaf = true
              · simp [htg, hl]
              · simp [htg, hbg, hle, hl]
                split <;> exact ⟨_, rfl, fun hd => absurd (hq hd) hl⟩) r s s'' q heq
          split at h
          · simp at h
          · next hd =>
            simp at h
            obtain ⟨⟨rfl, rfl⟩, rfl⟩ := h
            simp at hd
            exact ⟨rfl, by simp, fun _ => ⟨hr, by simpa using he, q.1, hI hd, rfl⟩⟩
        · next e heq =>
          exact (loop_no_err _ _ _
            (fun q : Nat × Bool => q.2 = true → (t.nodes q.1).leaf = true) (by simp) (by
              intro a q r s hq
              by_cases hl : (t.nodes q.1).leaf = true
              · simp [htg, hl]
              · simp [htg, hbg, hle, hl]
                split <;> exact ⟨_, rfl, fun hd => absurd (hq hd) hl⟩) r s e heq).elim

end AsyncSwap.Swarm.Best
