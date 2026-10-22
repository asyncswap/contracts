import Generated.AsyncSwap
import Refinement.Monad
import Refinement.Swarm.AsyncSwapReduceAfterMatch

/-!
# `AsyncMatching._reduceMatchedOrders`

`function _reduceMatchedOrders(State storage self, Book storage book, PoolKey memory key,
uint256 firstId, uint256 secondId, MatchAmounts memory amounts, address hook) private`
(src/AsyncSwap.sol, library `AsyncMatching`).

It reads `orders[firstId].isBuy` to name the sell side and the buy side, reads each side's
`zeroForOne` to pick its input currency, then reduces the sell order (input `assetAmount`, output
`quoteAmount`) and then the buy order (input `quoteAmount`, output `assetAmount`) through
`_reduceAfterMatch`. It writes nothing itself: every storage write and external call happens inside
those two reductions, in that order.
-/

open FormalAst Refinement AsyncSwap.Swarm.ReduceAfterMatch

set_option linter.unusedSimpArgs false

namespace AsyncSwap.Swarm.ReduceMatchedOrders

variable {σ : Type} (ext : Ext σ)

/-- The sell side's id: `secondId` when the first order is a buy, else `firstId`. -/
def sellId (S : AsyncFiller.State_) (firstId secondId : Nat) : Nat :=
  if (S.orders firstId).isBuy then secondId else firstId

/-- The buy side's id: `firstId` when the first order is a buy, else `secondId`. -/
def buyId (S : AsyncFiller.State_) (firstId secondId : Nat) : Nat :=
  if (S.orders firstId).isBuy then firstId else secondId

/-- The input currency of an order: `currency0` when it sells token 0, else `currency1`. -/
def inputOf (S : AsyncFiller.State_) (key : PoolKey) (id : Nat) : Nat :=
  if (S.orders id).zeroForOne then key.currency0 else key.currency1

/-- The reduction of the sell order: it gave `assetAmount` and received `quoteAmount`. -/
def sellParams (S : AsyncFiller.State_) (key : PoolKey) (firstId secondId : Nat)
    (amounts : AsyncFiller.MatchAmounts) : AsyncMatching.ReductionParams :=
  { id := sellId S firstId secondId, inputUsed := amounts.assetAmount,
    outputReceived := amounts.quoteAmount,
    inputCurrency := inputOf S key (sellId S firstId secondId) }

/-- The reduction of the buy order: it gave `quoteAmount` and received `assetAmount`. -/
def buyParams (S : AsyncFiller.State_) (key : PoolKey) (firstId secondId : Nat)
    (amounts : AsyncFiller.MatchAmounts) : AsyncMatching.ReductionParams :=
  { id := buyId S firstId secondId, inputUsed := amounts.quoteAmount,
    outputReceived := amounts.assetAmount,
    inputCurrency := inputOf S key (buyId S firstId secondId) }

/-- The two sides are exactly the two matched orders: `{sellId, buyId} = {firstId, secondId}`. -/
theorem sides_cover (S : AsyncFiller.State_) (firstId secondId : Nat) :
    (sellId S firstId secondId = secondId ∧ buyId S firstId secondId = firstId) ∨
    (sellId S firstId secondId = firstId ∧ buyId S firstId secondId = secondId) := by
  unfold sellId buyId; split <;> simp

variable {self_get : M σ AsyncFiller.State_} {self_set : AsyncFiller.State_ → M σ Unit}
    {book_get : M σ AsyncFiller.Book} {book_set : AsyncFiller.Book → M σ Unit}
    {g : σ → AsyncFiller.State_} {ss : σ → AsyncFiller.State_ → σ}
    {bg : σ → AsyncFiller.Book} {bs : σ → AsyncFiller.Book → σ}

/-- **Decomposition.** A run of `_reduceMatchedOrders` is exactly the reduction of the sell order
followed (on success) by the reduction of the buy order, with sides and input currencies read from
the state at entry; it performs no other write and no other external call, and a revert of either
reduction is its revert. -/
theorem reduceMatchedOrders_eq
    (L : Lawful self_get self_set book_get book_set g ss bg bs)
    (key : PoolKey) (firstId secondId : Nat) (amounts : AsyncFiller.MatchAmounts) (hook : Nat)
    (env : Env) (w : σ) :
    AsyncMatching.«_reduceMatchedOrders» ext self_get self_set book_get book_set key firstId
        secondId amounts hook env w =
      (match AsyncMatching.«_reduceAfterMatch» ext self_get self_set book_get book_set key
          (sellParams (g w) key firstId secondId amounts) hook env w with
       | .ok (_, w1) => AsyncMatching.«_reduceAfterMatch» ext self_get self_set book_get book_set
          key (buyParams (g w) key firstId secondId amounts) hook env w1
       | .error e => .error e) := by
  unfold AsyncMatching.«_reduceMatchedOrders»
  simp only [run_bind, L.hsg, run_pure]
  split
  next a w1 heq =>
    have h1 : AsyncMatching.«_reduceAfterMatch» ext self_get self_set book_get book_set key
        (sellParams (g w) key firstId secondId amounts) hook env w = .ok (a, w1) := heq
    rw [h1]
    split
    next b w2 heq2 =>
      have h2 : AsyncMatching.«_reduceAfterMatch» ext self_get self_set book_get book_set key
          (buyParams (g w) key firstId secondId amounts) hook env w1 = .ok (b, w2) := heq2
      cases b; exact h2.symm
    next e heq2 =>
      have h2 : AsyncMatching.«_reduceAfterMatch» ext self_get self_set book_get book_set key
          (buyParams (g w) key firstId secondId amounts) hook env w1 = .error e := heq2
      exact h2.symm
  next e heq =>
    have h1 : AsyncMatching.«_reduceAfterMatch» ext self_get self_set book_get book_set key
        (sellParams (g w) key firstId secondId amounts) hook env w = .error e := heq
    rw [h1]

/-- **Guard (sell side).** When the sell order holds less input than `assetAmount`, the call
reverts with panic 0x11 before any write or external call. -/
theorem reduceMatchedOrders_sell_overuse
    (L : Lawful self_get self_set book_get book_set g ss bg bs)
    (key : PoolKey) (firstId secondId : Nat) (amounts : AsyncFiller.MatchAmounts) (hook : Nat)
    (env : Env) (w : σ)
    (hu : ((g w).orders (sellId (g w) firstId secondId)).amountIn < amounts.assetAmount) :
    AsyncMatching.«_reduceMatchedOrders» ext self_get self_set book_get book_set key firstId
        secondId amounts hook env w = .error (FormalAst.panic "0x11") := by
  rw [reduceMatchedOrders_eq ext L, reduceAfterMatch_overuse ext L _ _ _ _ _ hu]

/-- **Guard (buy side).** When the sell reduction succeeds into world `w1` and the buy order then
holds less input than `quoteAmount`, the call reverts with panic 0x11. -/
theorem reduceMatchedOrders_buy_overuse
    (L : Lawful self_get self_set book_get book_set g ss bg bs)
    (key : PoolKey) (firstId secondId : Nat) (amounts : AsyncFiller.MatchAmounts) (hook : Nat)
    (env : Env) (w w1 : σ)
    (h1 : AsyncMatching.«_reduceAfterMatch» ext self_get self_set book_get book_set key
      (sellParams (g w) key firstId secondId amounts) hook env w = .ok ((), w1))
    (hu : ((g w1).orders (buyId (g w) firstId secondId)).amountIn < amounts.quoteAmount) :
    AsyncMatching.«_reduceMatchedOrders» ext self_get self_set book_get book_set key firstId
        secondId amounts hook env w = .error (FormalAst.panic "0x11") := by
  rw [reduceMatchedOrders_eq ext L, h1]
  exact reduceAfterMatch_overuse ext L _ _ _ _ _ hu

/-- **Success.** The call succeeds into `w'` exactly when the sell reduction succeeds into some
`w1` and the buy reduction succeeds from `w1` into `w'`. -/
theorem reduceMatchedOrders_ok_iff
    (L : Lawful self_get self_set book_get book_set g ss bg bs)
    (key : PoolKey) (firstId secondId : Nat) (amounts : AsyncFiller.MatchAmounts) (hook : Nat)
    (env : Env) (w w' : σ) :
    AsyncMatching.«_reduceMatchedOrders» ext self_get self_set book_get book_set key firstId
        secondId amounts hook env w = .ok ((), w') ↔
      ∃ w1, AsyncMatching.«_reduceAfterMatch» ext self_get self_set book_get book_set key
          (sellParams (g w) key firstId secondId amounts) hook env w = .ok ((), w1) ∧
        AsyncMatching.«_reduceAfterMatch» ext self_get self_set book_get book_set key
          (buyParams (g w) key firstId secondId amounts) hook env w1 = .ok ((), w') := by
  rw [reduceMatchedOrders_eq ext L]
  constructor
  · intro h
    split at h
    next u w1 h1 => cases u; exact ⟨w1, h1, h⟩
    next => cases h
  · rintro ⟨w1, h1, h2⟩
    rw [h1]; exact h2

/-- **Success bounds.** On success the sell order held at least `assetAmount` of input at entry and
the buy order held at least `quoteAmount` of input once the sell side was reduced. -/
theorem reduceMatchedOrders_ok_bounds
    (L : Lawful self_get self_set book_get book_set g ss bg bs)
    (key : PoolKey) (firstId secondId : Nat) (amounts : AsyncFiller.MatchAmounts) (hook : Nat)
    (env : Env) (w w' : σ)
    (h : AsyncMatching.«_reduceMatchedOrders» ext self_get self_set book_get book_set key firstId
        secondId amounts hook env w = .ok ((), w')) :
    amounts.assetAmount ≤ ((g w).orders (sellId (g w) firstId secondId)).amountIn ∧
    ∃ w1, AsyncMatching.«_reduceAfterMatch» ext self_get self_set book_get book_set key
          (sellParams (g w) key firstId secondId amounts) hook env w = .ok ((), w1) ∧
      amounts.quoteAmount ≤ ((g w1).orders (buyId (g w) firstId secondId)).amountIn := by
  obtain ⟨w1, h1, h2⟩ := (reduceMatchedOrders_ok_iff ext L _ _ _ _ _ _ _ _).1 h
  refine ⟨?_, w1, h1, ?_⟩
  · refine Nat.le_of_not_lt fun hc => ?_
    have := reduceAfterMatch_overuse ext L key (sellParams (g w) key firstId secondId amounts)
      hook env w hc
    rw [this] at h1; cases h1
  · refine Nat.le_of_not_lt fun hc => ?_
    have := reduceAfterMatch_overuse ext L key (buyParams (g w) key firstId secondId amounts)
      hook env w1 hc
    rw [this] at h2; cases h2

end AsyncSwap.Swarm.ReduceMatchedOrders
