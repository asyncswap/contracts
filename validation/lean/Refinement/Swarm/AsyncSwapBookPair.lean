import Generated.AsyncSwap
import Refinement.Monad
import Refinement.Swarm.AsyncSwapBest
open FormalAst Refinement AsyncSwap.Swarm.Best

/-!
# `AsyncMatching._bookPair` (src/AsyncSwap.sol)

`_bookPair()` reads the best bid price (`bids.best(true)`) and best ask price (`asks.best(false)`).
If either side is empty or the book is not crossed (`bidPrice < askPrice`) it returns `(0, 0)`.
Otherwise it picks the order with best priority at each price (`bestAtPrice`) and returns
`(bidId, askId)` when `_crosses(bidPrice, askPrice, bid, ask)` holds, `(0, 0)` otherwise.

It has no `require`; its reverts come from its callees only: the radix-tree loop bound, the
`mulDiv` inside `_crosses` (equal prices only), and the two helpers of `bestAtPrice`
(`mostPermissiveAtPrice`, `eligibleAtPrice`), taken here as black boxes with a contract.
It never calls `self_set`; storage is written only by whatever those helpers do with
`book_set`.
-/

namespace AsyncSwap.Swarm.BookPair

variable {σ : Type}

/-! ## Part A: reverts and footprint -/

/-- **Revert characterisation / frame.** If the reads `book_get`, `self_get` and the two helpers
used by `bestAtPrice` keep the state predicate `Q` and fail only with `P`-errors, and `P`
accepts the three reverts the callees can raise of their own (`"loop bound"`, `panic 0x12`,
`MathOverflowedMulDiv`), then `_bookPair` keeps `Q` and fails only with `P`-errors.
No hypothesis on `self_set` or `book_set` is needed beyond what the helpers do with them. -/
theorem bookPair_good (ext : Ext σ) (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (Q : σ → Prop) (P : Revert → Prop)
    (hbg : Good Q P book_get) (hsg : Good Q P self_get)
    (hmp : ∀ g st b p, Good Q P (AsyncFiller.mostPermissiveAtPrice ext g st b p))
    (hel : ∀ g st b p k, Good Q P (AsyncFiller.eligibleAtPrice ext g st b p k))
    (hlb : P ⟨"loop bound"⟩) (hdz : P (FormalAst.panic "0x12"))
    (hov : P ⟨"MathOverflowedMulDiv"⟩) :
    Good Q P (AsyncMatching.«_bookPair» ext self_get self_set book_get book_set) := by
  unfold AsyncMatching.«_bookPair» RadixPriceTree.best AsyncFiller.bestAtPrice
    AsyncMatching.«_crosses» mulDivFloor
  repeat' (first | (with_reducible apply hmp) | (with_reducible apply hel) | good_step)

/-- **Reverts only through its callees.** If the reads and the two helpers never revert,
every revert of `_bookPair` is the loop bound, `panic 0x12` or `MathOverflowedMulDiv`. -/
theorem bookPair_reverts (ext : Ext σ) (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit)
    (hbg : Good (fun _ => True) (fun _ => False) book_get)
    (hsg : Good (fun _ => True) (fun _ => False) self_get)
    (hmp : ∀ g st b p, Good (fun _ => True) (fun _ => False)
      (AsyncFiller.mostPermissiveAtPrice ext g st b p))
    (hel : ∀ g st b p k, Good (fun _ => True) (fun _ => False)
      (AsyncFiller.eligibleAtPrice ext g st b p k))
    (r : Env) (s : σ) (e : Revert)
    (h : AsyncMatching.«_bookPair» ext self_get self_set book_get book_set r s = .error e) :
    e = ⟨"loop bound"⟩ ∨ e = FormalAst.panic "0x12" ∨ e = ⟨"MathOverflowedMulDiv"⟩ := by
  have hg := bookPair_good ext self_get self_set book_get book_set (fun _ => True)
    (fun e => e = ⟨"loop bound"⟩ ∨ e = FormalAst.panic "0x12" ∨ e = ⟨"MathOverflowedMulDiv"⟩)
    (fun r s _ => by have := hbg r s trivial; split at this <;> simp_all)
    (fun r s _ => by have := hsg r s trivial; split at this <;> simp_all)
    (fun g st b p r s _ => by
      have := hmp g st b p r s trivial; split at this <;> simp_all)
    (fun g st b p k r s _ => by
      have := hel g st b p k r s trivial; split at this <;> simp_all)
    (Or.inl rfl) (Or.inr (Or.inl rfl)) (Or.inr (Or.inr rfl)) r s trivial
  rw [h] at hg
  exact hg

/-- **`self_set` is never called.** `_bookPair` does not depend on the order-map setter: it only
reads orders (in `_crosses`), so it cannot write `orders` itself. -/
theorem bookPair_self_set_irrelevant (ext : Ext σ) (self_get : M σ AsyncFiller.State_)
    (self_set self_set' : AsyncFiller.State_ → M σ Unit) (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) :
    AsyncMatching.«_bookPair» ext self_get self_set book_get book_set
      = AsyncMatching.«_bookPair» ext self_get self_set' book_get book_set := by
  unfold AsyncMatching.«_bookPair» AsyncMatching.«_crosses»
  rfl

/-! ## Part B: exact outcomes, composed from the callees' runs -/

/-- **No pair.** When the best-bid and best-ask reads succeed and either side is empty or the
book is not crossed (`bidPrice < askPrice`), `_bookPair` returns `(0, 0)` and the state is the
one the two reads left. -/
theorem bookPair_no_pair (ext : Ext σ) (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (r : Env) (s s1 s2 : σ)
    (hb ha : Bool) (pb pa : Nat)
    (h1 : RadixPriceTree.best ext (do return ((← book_get)).bids)
      (fun x => do book_set ({ ((← book_get)) with bids := x })) true r s = .ok ((hb, pb), s1))
    (h2 : RadixPriceTree.best ext (do return ((← book_get)).asks)
      (fun x => do book_set ({ ((← book_get)) with asks := x })) false r s1 = .ok ((ha, pa), s2))
    (hc : hb = false ∨ ha = false ∨ pb < pa) :
    AsyncMatching.«_bookPair» ext self_get self_set book_get book_set r s = .ok ((0, 0), s2) := by
  unfold AsyncMatching.«_bookPair»
  simp only [run_bind, h1, h2]
  rcases hc with hc | hc | hc <;> simp [hc]

/-- **Strictly crossed book.** When both sides are non-empty and `askPrice < bidPrice`,
`_bookPair` returns the ids `bestAtPrice` picks at the two prices: `_crosses` compares the
prices only and reads no order. -/
theorem bookPair_strict (ext : Ext σ) (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (r : Env) (s s1 s2 s3 s4 : σ)
    (pb pa bid ask : Nat)
    (h1 : RadixPriceTree.best ext (do return ((← book_get)).bids)
      (fun x => do book_set ({ ((← book_get)) with bids := x })) true r s = .ok ((true, pb), s1))
    (h2 : RadixPriceTree.best ext (do return ((← book_get)).asks)
      (fun x => do book_set ({ ((← book_get)) with asks := x })) false r s1 = .ok ((true, pa), s2))
    (hlt : pa < pb)
    (h3 : AsyncFiller.bestAtPrice ext (do return (← book_get)) (fun x => do book_set (x)) true pb
      r s2 = .ok (bid, s3))
    (h4 : AsyncFiller.bestAtPrice ext (do return (← book_get)) (fun x => do book_set (x)) false pa
      r s3 = .ok (ask, s4)) :
    AsyncMatching.«_bookPair» ext self_get self_set book_get book_set r s
      = .ok ((bid, ask), s4) := by
  unfold AsyncMatching.«_bookPair» AsyncMatching.«_crosses»
  have hne : pb ≠ pa := Nat.ne_of_gt hlt
  have hnlt : ¬ pb < pa := Nat.not_lt.mpr (Nat.le_of_lt hlt)
  simp only [run_bind, h1, h2]
  simp [hnlt, hne, hlt, h3, h4]

/-- **Equal prices.** When both sides are non-empty at the same price `p`, the order map is read
through a read-only view `st`, the ask's `amountOutMin` is non-zero and the product fits 256 bits,
`_bookPair` returns `(bid, ask)` exactly when
`⌊bid.amountIn · ask.amountIn / ask.amountOutMin⌋ ≥ bid.amountOutMin`, and `(0, 0)` otherwise. -/
theorem bookPair_equal (ext : Ext σ) (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (r : Env) (s s1 s2 s3 s4 : σ)
    (p bid ask : Nat) (st : AsyncFiller.State_)
    (h1 : RadixPriceTree.best ext (do return ((← book_get)).bids)
      (fun x => do book_set ({ ((← book_get)) with bids := x })) true r s = .ok ((true, p), s1))
    (h2 : RadixPriceTree.best ext (do return ((← book_get)).asks)
      (fun x => do book_set ({ ((← book_get)) with asks := x })) false r s1 = .ok ((true, p), s2))
    (h3 : AsyncFiller.bestAtPrice ext (do return (← book_get)) (fun x => do book_set (x)) true p
      r s2 = .ok (bid, s3))
    (h4 : AsyncFiller.bestAtPrice ext (do return (← book_get)) (fun x => do book_set (x)) false p
      r s3 = .ok (ask, s4))
    (hsg : ∀ r s, self_get r s = .ok (st, s))
    (hd : (st.orders ask).amountOutMin ≠ 0)
    (hfit : (st.orders bid).amountIn * (st.orders ask).amountIn < 2 ^ 256) :
    AsyncMatching.«_bookPair» ext self_get self_set book_get book_set r s
      = .ok ((if (st.orders bid).amountOutMin
                ≤ (st.orders bid).amountIn * (st.orders ask).amountIn / (st.orders ask).amountOutMin
              then (bid, ask) else (0, 0)), s4) := by
  unfold AsyncMatching.«_bookPair» AsyncMatching.«_crosses» mulDivFloor
  simp only [run_bind, h1, h2]
  by_cases hc : (st.orders bid).amountOutMin
      ≤ (st.orders bid).amountIn * (st.orders ask).amountIn / (st.orders ask).amountOutMin
  · simp [hsg, hd, hfit, h3, h4, hc]
  · simp [hsg, hd, hfit, h3, h4, hc]

/-- **Equal prices, zero `amountOutMin` on the ask: revert.** The `mulDiv` in `_crosses` divides
by the ask's `amountOutMin`; when it is `0` and the product fits one word, `_bookPair` reverts
with `panic 0x12`. -/
theorem bookPair_equal_div_zero (ext : Ext σ) (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (book_get : M σ AsyncFiller.Book)
    (book_set : AsyncFiller.Book → M σ Unit) (r : Env) (s s1 s2 s3 s4 : σ)
    (p bid ask : Nat) (st : AsyncFiller.State_)
    (h1 : RadixPriceTree.best ext (do return ((← book_get)).bids)
      (fun x => do book_set ({ ((← book_get)) with bids := x })) true r s = .ok ((true, p), s1))
    (h2 : RadixPriceTree.best ext (do return ((← book_get)).asks)
      (fun x => do book_set ({ ((← book_get)) with asks := x })) false r s1 = .ok ((true, p), s2))
    (h3 : AsyncFiller.bestAtPrice ext (do return (← book_get)) (fun x => do book_set (x)) true p
      r s2 = .ok (bid, s3))
    (h4 : AsyncFiller.bestAtPrice ext (do return (← book_get)) (fun x => do book_set (x)) false p
      r s3 = .ok (ask, s4))
    (hsg : ∀ r s, self_get r s = .ok (st, s))
    (hd : (st.orders ask).amountOutMin = 0)
    (hfit : (st.orders bid).amountIn * (st.orders ask).amountIn < 2 ^ 256) :
    AsyncMatching.«_bookPair» ext self_get self_set book_get book_set r s
      = .error (FormalAst.panic "0x12") := by
  unfold AsyncMatching.«_bookPair» AsyncMatching.«_crosses» mulDivFloor
  simp only [run_bind, h1, h2]
  simp [hsg, hd, hfit, h3, h4]

end AsyncSwap.Swarm.BookPair
