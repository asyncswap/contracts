import Generated.AsyncSwap
import Refinement.Monad
open FormalAst Refinement

/-!
# `EligiblePrice._repair` (src/AsyncSwap.sol)

`_repair(cursor, isBuy, forceFirst)` walks from `cursor` up the radix price tree towards the
root: at each node it recomputes the node's bound as the better (per `isBuy`, via `le`) of its two
children's bounds, stops as soon as the node is the root sentinel (`cursor == 0`) or its stored
bound already equals the recomputed one (unless `forceFirst` forces the first write), and
otherwise writes the new bound and moves to `parent`.

The function has no `require` of its own. Storage is reached only through the accessors it is
handed: `tree_get` (read), `bounds_get` (read) and `bounds_set` (write); `tree_set` is never used.
The only revert it raises itself is the model's gas bound `"loop bound"`.

The proofs use a Hoare-style predicate `Good Q P x`: started in a `Q`-state, `x` either succeeds
in a `Q`-state or fails with an error satisfying `P`. `Good` is closed under `pure`, `bind`,
`ite`, `throw` and `forIn` (by induction on the iterated list), so it propagates from the
callbacks through the whole loop body.
-/

namespace AsyncSwap.Swarm.Repair

variable {σ : Type}

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

/-- One syntax-directed step of propagating `Good` through a program: unification runs at
reducible transparency, so each lemma fires only on its own head symbol. -/
macro "good_step" : tactic => `(tactic| first
  | with_reducible assumption
  | with_reducible apply good_pure
  | (with_reducible apply good_throw); with_reducible assumption
  | with_reducible apply good_ite
  | with_reducible apply good_bind
  | with_reducible intro _)

/-- **Invariant / revert characterisation.** For any state predicate `Q` and error predicate `P`:
if `tree_get`, `bounds_get`, every `bounds_set f` and every comparison `le a b` keep `Q` and fail
only with `P`-errors, and `P` accepts the loop-bound revert, then `EligiblePrice._repair` keeps `Q`
and fails only with `P`-errors. `tree_set` needs no hypothesis: it is never called. -/
theorem repair_good (ext : Ext σ) (tree_get : M σ RadixPriceTree.Tree)
    (tree_set : RadixPriceTree.Tree → M σ Unit) (bounds_get : M σ (Nat → EligiblePrice.Ratio))
    (bounds_set : (Nat → EligiblePrice.Ratio) → M σ Unit) (cursor : Nat) (isBuy forceFirst : Bool)
    (Q : σ → Prop) (P : Revert → Prop)
    (htg : Good Q P tree_get) (hbg : Good Q P bounds_get)
    (hbs : ∀ f, Good Q P (bounds_set f))
    (hle : ∀ a b, Good Q P (ext.fn_EligiblePrice_le_12578 a b))
    (hlb : P ⟨"loop bound"⟩) :
    Good Q P (EligiblePrice.«_repair» ext tree_get tree_set bounds_get bounds_set
      cursor isBuy forceFirst) := by
  unfold EligiblePrice.«_repair»
  refine good_bind (good_forIn_range _ _ _ ?_) ?_
  · intro _ b
    repeat' (first | (with_reducible apply hbs) | (with_reducible apply hle) | good_step)
  · intro _
    repeat' good_step

/-- **Only revert of its own: the loop bound.** If the accessors and the comparison never revert,
`EligiblePrice._repair` can revert only with `"loop bound"`. -/
theorem repair_reverts_only_loop_bound (ext : Ext σ) (tree_get : M σ RadixPriceTree.Tree)
    (tree_set : RadixPriceTree.Tree → M σ Unit) (bounds_get : M σ (Nat → EligiblePrice.Ratio))
    (bounds_set : (Nat → EligiblePrice.Ratio) → M σ Unit) (cursor : Nat) (isBuy forceFirst : Bool)
    (htg : ∀ r s, ∃ v s', tree_get r s = .ok (v, s'))
    (hbg : ∀ r s, ∃ v s', bounds_get r s = .ok (v, s'))
    (hbs : ∀ f r s, ∃ s', bounds_set f r s = .ok ((), s'))
    (hle : ∀ a b r s, ∃ v s', ext.fn_EligiblePrice_le_12578 a b r s = .ok (v, s'))
    (r : Env) (s : σ) (e : Revert)
    (h : EligiblePrice.«_repair» ext tree_get tree_set bounds_get bounds_set
      cursor isBuy forceFirst r s = .error e) :
    e = ⟨"loop bound"⟩ := by
  have hg := repair_good ext tree_get tree_set bounds_get bounds_set cursor isBuy forceFirst
    (fun _ => True) (fun e => e = ⟨"loop bound"⟩)
    (by intro r s _; obtain ⟨v, s', hh⟩ := htg r s; simp [hh])
    (by intro r s _; obtain ⟨v, s', hh⟩ := hbg r s; simp [hh])
    (by intro f r s _; obtain ⟨s', hh⟩ := hbs f r s; simp [hh])
    (by intro a b r s _; obtain ⟨v, s', hh⟩ := hle a b r s; simp [hh])
    rfl r s trivial
  rw [h] at hg
  exact hg

/-- **Frame: storage is written only through `bounds_set`.** For any view of the world: if the
reads (`tree_get`, `bounds_get`, `le`) leave the world unchanged, and every `bounds_set f` leaves
the view unchanged, then a successful `EligiblePrice._repair` leaves the view unchanged. (Taking
the view to be the tree, or any storage other than the bounds map, shows `_repair` writes nothing
but the bounds.) -/
theorem repair_frame {τ : Type} (view : σ → τ) (ext : Ext σ) (tree_get : M σ RadixPriceTree.Tree)
    (tree_set : RadixPriceTree.Tree → M σ Unit) (bounds_get : M σ (Nat → EligiblePrice.Ratio))
    (bounds_set : (Nat → EligiblePrice.Ratio) → M σ Unit) (cursor : Nat) (isBuy forceFirst : Bool)
    (htg : ∀ r s v s', tree_get r s = .ok (v, s') → s' = s)
    (hbg : ∀ r s v s', bounds_get r s = .ok (v, s') → s' = s)
    (hle : ∀ a b r s v s', ext.fn_EligiblePrice_le_12578 a b r s = .ok (v, s') → s' = s)
    (hbs : ∀ f r s s', bounds_set f r s = .ok ((), s') → view s' = view s)
    (r : Env) (s s' : σ) (u : Unit)
    (h : EligiblePrice.«_repair» ext tree_get tree_set bounds_get bounds_set
      cursor isBuy forceFirst r s = .ok (u, s')) :
    view s' = view s := by
  have hg := repair_good ext tree_get tree_set bounds_get bounds_set cursor isBuy forceFirst
    (fun w => view w = view s) (fun _ => True)
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
      intro f r w hw; revert hw
      cases hh : bounds_set f r w with
      | error e => intro _; trivial
      | ok p => obtain ⟨v, w'⟩ := p; intro hw; simp only; rw [hbs f r w w' hh]; exact hw)
    (by
      intro a b r w hw; revert hw
      cases hh : ext.fn_EligiblePrice_le_12578 a b r w with
      | error e => intro _; trivial
      | ok p => obtain ⟨v, w'⟩ := p; intro hw; simp only; rw [hle a b r w v w' hh]; exact hw)
    trivial r s rfl
  rw [h] at hg
  exact hg

/-- **`tree_set` is never used**: the function does not depend on the tree setter, so it never
writes the tree. -/
theorem repair_tree_set_irrelevant (ext : Ext σ) (tree_get : M σ RadixPriceTree.Tree)
    (ts₁ ts₂ : RadixPriceTree.Tree → M σ Unit) (bounds_get : M σ (Nat → EligiblePrice.Ratio))
    (bounds_set : (Nat → EligiblePrice.Ratio) → M σ Unit) (cursor : Nat) (isBuy forceFirst : Bool) :
    EligiblePrice.«_repair» ext tree_get ts₁ bounds_get bounds_set cursor isBuy forceFirst =
      EligiblePrice.«_repair» ext tree_get ts₂ bounds_get bounds_set cursor isBuy forceFirst := rfl

/-- **Base case: the root sentinel.** With `cursor = 0` the walk stops at once: it returns `()`,
leaves the world unchanged, and calls no accessor. -/
theorem repair_cursor_zero (ext : Ext σ) (tree_get : M σ RadixPriceTree.Tree)
    (tree_set : RadixPriceTree.Tree → M σ Unit) (bounds_get : M σ (Nat → EligiblePrice.Ratio))
    (bounds_set : (Nat → EligiblePrice.Ratio) → M σ Unit) (isBuy forceFirst : Bool)
    (r : Env) (s : σ) :
    EligiblePrice.«_repair» ext tree_get tree_set bounds_get bounds_set 0 isBuy forceFirst r s =
      .ok ((), s) := by
  have hsz : ([:loopBound] : Std.Legacy.Range).size = (2 ^ 64 - 1) + 1 := by
    simp [Std.Legacy.Range.size, loopBound]
  unfold EligiblePrice.«_repair»
  rw [Std.Legacy.Range.forIn_eq_forIn_range', hsz, List.range'_succ, List.forIn_cons]
  simp

end AsyncSwap.Swarm.Repair
