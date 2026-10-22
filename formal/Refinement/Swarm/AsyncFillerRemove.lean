import Mathlib.Tactic
import Generated.AsyncSwap
import Refinement.Monad
import Refinement.Swarm.AsyncSwapRemove

open FormalAst Refinement

namespace AsyncSwap.Swarm.FillerRemove

/-! ## The FIFO queue of a price level -/

/-- `Seg os p xs q`: the orders `xs`, in this order, are doubly linked, the first one's `previous`
is `p` and the last one's `next` is `q`. -/
def Seg (os : Nat → AsyncFiller.OrderInfo) : Nat → List Nat → Nat → Prop
  | _, [], _ => True
  | p, x :: r, q => (os x).previous = p ∧ (os x).next = r.headD q ∧ Seg os x r q

theorem seg_append (os : Nat → AsyncFiller.OrderInfo) :
    ∀ (p : Nat) (as bs : List Nat) (q : Nat),
      Seg os p (as ++ bs) q ↔ Seg os p as (bs.headD q) ∧ Seg os (as.getLastD p) bs q
  | p, [], bs, q => by simp [Seg]
  | p, [x], bs, q => by simp [Seg, and_assoc]
  | p, x :: y :: r, bs, q => by
      have ih := seg_append os x (y :: r) bs q
      simp only [List.cons_append, Seg, List.headD_cons] at ih ⊢
      rw [ih]
      simp only [List.getLastD, List.getLast_cons_cons, and_assoc]

/-- Only the `previous`/`next` fields of the listed orders matter, and the first's `previous` /
the last's `next` may be retargeted. -/
theorem seg_congr (os os' : Nat → AsyncFiller.OrderInfo) :
    ∀ (p : Nat) (xs : List Nat) (q p' q' : Nat), Seg os p xs q →
      (∀ x ∈ xs.dropLast, (os' x).next = (os x).next) →
      (∀ x ∈ xs.tail, (os' x).previous = (os x).previous) →
      (∀ x, xs.head? = some x → (os' x).previous = p') →
      (∀ x, xs.getLast? = some x → (os' x).next = q') →
      Seg os' p' xs q'
  | p, [], q, p', q', _, _, _, _, _ => by simp [Seg]
  | p, [x], q, p', q', h, _, _, hh, hl => by
      simp [Seg] at h ⊢
      exact ⟨hh x rfl, hl x rfl⟩
  | p, x :: y :: r, q, p', q', h, hn, hp, hh, hl => by
      simp only [Seg, List.headD_cons] at h ⊢
      obtain ⟨_, hx2, hy1, hy2, hrest⟩ := h
      refine ⟨hh x rfl, ?_, ?_⟩
      · rw [hn x (by simp), hx2]
      · have := seg_congr os os' x (y :: r) q x q' (by simp only [Seg]; exact ⟨hy1, hy2, hrest⟩)
          (fun z hz => hn z (by rw [List.dropLast_cons_cons]; exact List.mem_cons_of_mem _ hz))
          (fun z hz => hp z (by simp at hz ⊢; exact Or.inr hz))
          (fun z hz => by simp at hz; subst hz; rw [hp y (by simp), hy1])
          (fun z hz => hl z (by simpa [List.getLast?_cons_cons] using hz))
        simpa only [Seg] using this

end AsyncSwap.Swarm.FillerRemove
