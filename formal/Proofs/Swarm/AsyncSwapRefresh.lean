import Specs.AsyncSwap
import Proofs.Monad
import Proofs.Swarm.AsyncSwapRepair
open FormalAst Refinement

/-!
# `EligiblePrice.refresh` (src/AsyncSwap.sol)

`refresh(rank, price, isBuy)` reads `leaf = tree.leaves[rank]`, overwrites the cached bound of
that leaf (`bounds[leaf] = price`), then repairs the cached bounds from the leaf's parent upwards
with `_repair(nodes[leaf].parent, isBuy, true)` (the first write is forced).

The function has no `require` of its own. Storage is reached only through the accessors:
`tree_get`/`bounds_get` (reads) and `bounds_set` (the only write); `tree_set` is never used,
neither by `refresh` nor by `_repair`. It returns `()`.
-/

namespace AsyncSwap.Swarm.Refresh

open AsyncSwap.Swarm.Repair

variable {σ : Type}

/-- **Invariant / revert characterisation.** If `tree_get`, `bounds_get`, every `bounds_set f`
and every comparison `le a b` keep `Q` and fail only with `P`-errors, and `P` accepts the
loop-bound revert, then `EligiblePrice.refresh` keeps `Q` and fails only with `P`-errors. -/
theorem refresh_good (ext : Ext σ) (tree_get : M σ RadixPriceTree.Tree)
    (tree_set : RadixPriceTree.Tree → M σ Unit) (bounds_get : M σ (Nat → EligiblePrice.Ratio))
    (bounds_set : (Nat → EligiblePrice.Ratio) → M σ Unit) (rank : Nat)
    (price : EligiblePrice.Ratio) (isBuy : Bool)
    (Q : σ → Prop) (P : Revert → Prop)
    (htg : Good Q P tree_get) (hbg : Good Q P bounds_get)
    (hbs : ∀ f, Good Q P (bounds_set f))
    (hle : ∀ a b, Good Q P (ext.fn_EligiblePrice_le_12578 a b))
    (hlb : P ⟨"loop bound"⟩) :
    Good Q P (EligiblePrice.refresh ext tree_get tree_set bounds_get bounds_set
      rank price isBuy) := by
  have hrep : ∀ c, Good Q P (EligiblePrice.«_repair» ext (do return (← tree_get))
      (fun x => do tree_set (x)) (do return (← bounds_get)) (fun x => do bounds_set (x))
      c isBuy true) := fun c =>
    repair_good ext _ _ _ _ c isBuy true Q P htg hbg (fun f => hbs f) hle hlb
  unfold EligiblePrice.refresh
  repeat' (first | (with_reducible apply hbs) | (with_reducible apply hrep) | good_step)

/-- **Reverts.** If the accessors and the comparison never revert, `EligiblePrice.refresh` can
revert only with the model's `"loop bound"` (it has no guard of its own). -/
theorem refresh_reverts_only_loop_bound (ext : Ext σ) (tree_get : M σ RadixPriceTree.Tree)
    (tree_set : RadixPriceTree.Tree → M σ Unit) (bounds_get : M σ (Nat → EligiblePrice.Ratio))
    (bounds_set : (Nat → EligiblePrice.Ratio) → M σ Unit) (rank : Nat)
    (price : EligiblePrice.Ratio) (isBuy : Bool)
    (htg : ∀ r s, ∃ v s', tree_get r s = .ok (v, s'))
    (hbg : ∀ r s, ∃ v s', bounds_get r s = .ok (v, s'))
    (hbs : ∀ f r s, ∃ s', bounds_set f r s = .ok ((), s'))
    (hle : ∀ a b r s, ∃ v s', ext.fn_EligiblePrice_le_12578 a b r s = .ok (v, s'))
    (r : Env) (s : σ) (e : Revert)
    (h : EligiblePrice.refresh ext tree_get tree_set bounds_get bounds_set rank price isBuy r s =
      .error e) :
    e = ⟨"loop bound"⟩ := by
  have hg := refresh_good ext tree_get tree_set bounds_get bounds_set rank price isBuy
    (fun _ => True) (fun e => e = ⟨"loop bound"⟩)
    (by intro r s _; obtain ⟨v, s', hh⟩ := htg r s; simp [hh])
    (by intro r s _; obtain ⟨v, s', hh⟩ := hbg r s; simp [hh])
    (by intro f r s _; obtain ⟨s', hh⟩ := hbs f r s; simp [hh])
    (by intro a b r s _; obtain ⟨v, s', hh⟩ := hle a b r s; simp [hh])
    rfl r s trivial
  rw [h] at hg
  exact hg

/-- **Frame: storage is written only through `bounds_set`.** If the reads (`tree_get`,
`bounds_get`, `le`) leave the world unchanged and every `bounds_set f` leaves `view` unchanged,
a successful `EligiblePrice.refresh` leaves `view` unchanged. With `view` = the tree (or any
storage other than the bounds map), this says `refresh` writes nothing but the bounds. -/
theorem refresh_frame {τ : Type} (view : σ → τ) (ext : Ext σ)
    (tree_get : M σ RadixPriceTree.Tree)
    (tree_set : RadixPriceTree.Tree → M σ Unit) (bounds_get : M σ (Nat → EligiblePrice.Ratio))
    (bounds_set : (Nat → EligiblePrice.Ratio) → M σ Unit) (rank : Nat)
    (price : EligiblePrice.Ratio) (isBuy : Bool)
    (htg : ∀ r s v s', tree_get r s = .ok (v, s') → s' = s)
    (hbg : ∀ r s v s', bounds_get r s = .ok (v, s') → s' = s)
    (hle : ∀ a b r s v s', ext.fn_EligiblePrice_le_12578 a b r s = .ok (v, s') → s' = s)
    (hbs : ∀ f r s s', bounds_set f r s = .ok ((), s') → view s' = view s)
    (r : Env) (s s' : σ) (u : Unit)
    (h : EligiblePrice.refresh ext tree_get tree_set bounds_get bounds_set rank price isBuy r s =
      .ok (u, s')) :
    view s' = view s := by
  have hg := refresh_good ext tree_get tree_set bounds_get bounds_set rank price isBuy
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

/-- **`tree_set` is never used**: `EligiblePrice.refresh` does not depend on the tree setter, so
it never writes the tree. -/
theorem refresh_tree_set_irrelevant (ext : Ext σ) (tree_get : M σ RadixPriceTree.Tree)
    (ts₁ ts₂ : RadixPriceTree.Tree → M σ Unit) (bounds_get : M σ (Nat → EligiblePrice.Ratio))
    (bounds_set : (Nat → EligiblePrice.Ratio) → M σ Unit) (rank : Nat)
    (price : EligiblePrice.Ratio) (isBuy : Bool) :
    EligiblePrice.refresh ext tree_get ts₁ bounds_get bounds_set rank price isBuy =
      EligiblePrice.refresh ext tree_get ts₂ bounds_get bounds_set rank price isBuy := rfl

/-- **The write and the hand-off.** If `tree_get` is a pure read of a tree `T` and, at the start,
`bounds_get` is a pure read of `B`, then running `EligiblePrice.refresh` is exactly: write
`bounds_set (upd B leaf price)` with `leaf = T.leaves rank`, then run
`_repair((T.nodes leaf).parent, isBuy, forceFirst = true)` in the resulting state. -/
theorem refresh_eq (ext : Ext σ) (tree_get : M σ RadixPriceTree.Tree)
    (tree_set : RadixPriceTree.Tree → M σ Unit) (bounds_get : M σ (Nat → EligiblePrice.Ratio))
    (bounds_set : (Nat → EligiblePrice.Ratio) → M σ Unit) (rank : Nat)
    (price : EligiblePrice.Ratio) (isBuy : Bool)
    (T : RadixPriceTree.Tree) (B : Nat → EligiblePrice.Ratio) (r : Env) (s : σ)
    (htg : ∀ r' s', tree_get r' s' = .ok (T, s'))
    (hbg : bounds_get r s = .ok (B, s)) :
    EligiblePrice.refresh ext tree_get tree_set bounds_get bounds_set rank price isBuy r s =
      (match bounds_set (upd B (T.leaves rank) price) r s with
       | .ok (_, s₁) =>
          EligiblePrice.«_repair» ext tree_get tree_set bounds_get bounds_set
            ((T.nodes (T.leaves rank)).parent) isBuy true r s₁
       | .error e => .error e) := by
  unfold EligiblePrice.refresh
  simp only [run_bind, run_pure, htg, hbg]
  cases bounds_set (upd B (T.leaves rank) price) r s with
  | error e => rfl
  | ok p =>
    obtain ⟨_, s₁⟩ := p
    simp only
    cases EligiblePrice.«_repair» ext tree_get tree_set bounds_get bounds_set
        ((T.nodes (T.leaves rank)).parent) isBuy true r s₁ with
    | error e => rfl
    | ok q => obtain ⟨_, _⟩ := q; rfl

end AsyncSwap.Swarm.Refresh
