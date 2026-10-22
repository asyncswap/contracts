import Generated.AsyncSwap
import Refinement.Monad
import Refinement.Swarm.AsyncSwapMatchAmounts
import Refinement.Swarm.AsyncSwapSettleTransfers
import Refinement.Swarm.AsyncSwapReduceMatchedOrders

/-!
# `AsyncMatching._matchPair`

`_matchPair(State storage self, Book storage book, PoolKey memory key, uint256 firstId,
uint256 secondId, address hook) private returns (bool)` (src/AsyncSwap.sol, library
`AsyncMatching`).

* **Skip** (`matchPair_skip`): when either order has `amountIn = 0` or both are on the same side it
  returns `false` and leaves the world unchanged.
* **Decomposition** (`matchPair_eq`): otherwise it is `_matchAmounts` on (sell, buy) with the older
  order's side as the resting side, then (unless an amount is zero, which returns `false` with no
  effect) `_settleTransfers` followed by `_reduceMatchedOrders`, then `true`.
* **Outcome** (`matchPair_ok`, `matchPair_true`): the amounts are exactly the spec's
  `AsyncSwap.matchAmounts`; a `true` result means both escrows and both limit prices are honoured,
  each leg burns from the hook exactly what it pays out in the same currency, and each order's
  reduction consumes exactly the amount paid out of its input currency (conservation per currency).
* **Reverts** (`matchPair_error`, `matchPair_reverts_restingZero`).

`self` and `book` are getter/setter pairs satisfying `Lawful` (plain reads and writes of two
disjoint slots of the world), which is how every caller instantiates them.
-/

open FormalAst Refinement

set_option linter.unusedSimpArgs false

namespace AsyncSwap.Swarm.MatchPair

open AsyncSwap.Swarm.ReduceAfterMatch (Lawful)
open AsyncSwap.Swarm.ReduceMatchedOrders (sellId buyId sellParams buyParams)
open AsyncSwap.Swarm.MatchAmounts (toSpec)
open AsyncSwap.Swarm.SettleTransfers (sellInput buyInput sellOwner buyOwner)
open AsyncSwap.Swarm.TransferEscrow (payout)

variable {σ : Type} (ext : Ext σ)

set_option maxHeartbeats 4000000 in
theorem matchAmounts_congr_true (sg : M σ AsyncFiller.OrderInfo) (ssx : AsyncFiller.OrderInfo → M σ Unit)
    (bgx : M σ AsyncFiller.OrderInfo) (bsx : AsyncFiller.OrderInfo → M σ Unit)
    (ss' bs' : AsyncFiller.OrderInfo → M σ Unit)
    (S B : AsyncFiller.OrderInfo) (env : Env) (w : σ)
    (hs : ∀ e, sg e w = .ok (S, w)) (hb : ∀ e, bgx e w = .ok (B, w)) :
    AsyncMatching.«_matchAmounts» ext sg ssx bgx bsx true env w =
      AsyncMatching.«_matchAmounts» ext (fun _ t => .ok (S, t)) ss' (fun _ t => .ok (B, t)) bs' true env w := by
  have hs' : ∀ e, (fun (_ : Env) (t : σ) => (Except.ok (S, t) : Except Revert (AsyncFiller.OrderInfo × σ))) e w = .ok (S, w) := fun _ => rfl
  have hb' : ∀ e, (fun (_ : Env) (t : σ) => (Except.ok (B, t) : Except Revert (AsyncFiller.OrderInfo × σ))) e w = .ok (B, w) := fun _ => rfl
  simp only [AsyncMatching.«_matchAmounts», run_bind, hs, hb, hs', hb',
    AsyncSwap.Swarm.MatchAmounts.floor_run, ite_true]
  split_ifs <;> simp only [run_bind, hs, hb, hs', hb', run_pure, run_ite,
    AsyncSwap.Swarm.MatchAmounts.ceil_run]
  all_goals (repeat' (first
    | (split_ifs)
    | (simp only [run_bind, hs, hb, hs', hb', run_pure, run_ite])))

set_option maxHeartbeats 4000000 in
theorem matchAmounts_congr_false (sg : M σ AsyncFiller.OrderInfo) (ssx : AsyncFiller.OrderInfo → M σ Unit)
    (bgx : M σ AsyncFiller.OrderInfo) (bsx : AsyncFiller.OrderInfo → M σ Unit)
    (ss' bs' : AsyncFiller.OrderInfo → M σ Unit)
    (S B : AsyncFiller.OrderInfo) (env : Env) (w : σ)
    (hs : ∀ e, sg e w = .ok (S, w)) (hb : ∀ e, bgx e w = .ok (B, w)) :
    AsyncMatching.«_matchAmounts» ext sg ssx bgx bsx false env w =
      AsyncMatching.«_matchAmounts» ext (fun _ t => .ok (S, t)) ss' (fun _ t => .ok (B, t)) bs' false env w := by
  have hs' : ∀ e, (fun (_ : Env) (t : σ) => (Except.ok (S, t) : Except Revert (AsyncFiller.OrderInfo × σ))) e w = .ok (S, w) := fun _ => rfl
  have hb' : ∀ e, (fun (_ : Env) (t : σ) => (Except.ok (B, t) : Except Revert (AsyncFiller.OrderInfo × σ))) e w = .ok (B, w) := fun _ => rfl
  simp only [AsyncMatching.«_matchAmounts», run_bind, hs, hb, hs', hb',
    AsyncSwap.Swarm.MatchAmounts.floor_run, Bool.false_eq_true, ite_false]
  split_ifs <;> simp only [run_bind, hs, hb, hs', hb', run_pure, run_ite,
    AsyncSwap.Swarm.MatchAmounts.ceil_run]
  all_goals (repeat' (first
    | (split_ifs)
    | (simp only [run_bind, hs, hb, hs', hb', run_pure, run_ite])))

/-- `_matchAmounts` only reads its accessors: at a world `w` where both getters are pure reads of
`S` / `B`, its run equals the run with constant getters and any setters. -/
theorem matchAmounts_congr (sg : M σ AsyncFiller.OrderInfo) (ssx : AsyncFiller.OrderInfo → M σ Unit)
    (bgx : M σ AsyncFiller.OrderInfo) (bsx : AsyncFiller.OrderInfo → M σ Unit)
    (ss' bs' : AsyncFiller.OrderInfo → M σ Unit)
    (S B : AsyncFiller.OrderInfo) (rb : Bool) (env : Env) (w : σ)
    (hs : ∀ e, sg e w = .ok (S, w)) (hb : ∀ e, bgx e w = .ok (B, w)) :
    AsyncMatching.«_matchAmounts» ext sg ssx bgx bsx rb env w =
      AsyncMatching.«_matchAmounts» ext (fun _ t => .ok (S, t)) ss' (fun _ t => .ok (B, t)) bs' rb env w := by
  cases rb
  · exact matchAmounts_congr_false ext sg ssx bgx bsx ss' bs' S B env w hs hb
  · exact matchAmounts_congr_true ext sg ssx bgx bsx ss' bs' S B env w hs hb

/-- The pair is skipped when either order is empty or both are on the same side. -/
def skip (S : AsyncFiller.State_) (f s : Nat) : Prop :=
  (S.orders f).amountIn = 0 ∨ (S.orders s).amountIn = 0 ∨ (S.orders f).isBuy = (S.orders s).isBuy

/-- `makerBuy`: the side of the older order (strictly lower sequence, else the second order). -/
def makerBuy (S : AsyncFiller.State_) (f s : Nat) : Bool :=
  if (S.orders f).sequence < (S.orders s).sequence then (S.orders f).isBuy else (S.orders s).isBuy

/-- The amounts the spec `AsyncSwap.matchAmounts` assigns to the pair. -/
def amountsOf (S : AsyncFiller.State_) (f s : Nat) : AsyncFiller.MatchAmounts :=
  { assetAmount := (AsyncSwap.matchAmounts (toSpec (S.orders (sellId S f s)))
      (toSpec (S.orders (buyId S f s))) (makerBuy S f s)).assetAmount,
    quoteAmount := (AsyncSwap.matchAmounts (toSpec (S.orders (sellId S f s)))
      (toSpec (S.orders (buyId S f s))) (makerBuy S f s)).quoteAmount }

/-- The run of `_matchAmounts` that `_matchPair` performs, with the orders read at entry. -/
def matchRun (S : AsyncFiller.State_) (f s : Nat) (env : Env) (w : σ) :
    Except Revert (AsyncFiller.MatchAmounts × σ) :=
  AsyncMatching.«_matchAmounts» ext
    (fun _ t => .ok (S.orders (sellId S f s), t)) (fun _ => pure ())
    (fun _ t => .ok (S.orders (buyId S f s), t)) (fun _ => pure ())
    (makerBuy S f s) env w

/-- **Conservation of the reductions.** The sell order's reduction consumes `assetAmount` of the
sell input currency (the currency the asset leg burns and pays out) and is credited `quoteAmount`;
the buy order's consumes `quoteAmount` of the buy input currency and is credited `assetAmount`. -/
theorem params_conserve (S : AsyncFiller.State_) (key : PoolKey) (f s : Nat)
    (m : AsyncFiller.MatchAmounts) :
    (sellParams S key f s m).inputCurrency = sellInput S key f s ∧
    (sellParams S key f s m).inputUsed = m.assetAmount ∧
    (sellParams S key f s m).outputReceived = m.quoteAmount ∧
    (buyParams S key f s m).inputCurrency = buyInput S key f s ∧
    (buyParams S key f s m).inputUsed = m.quoteAmount ∧
    (buyParams S key f s m).outputReceived = m.assetAmount := by
  unfold sellParams buyParams sellInput buyInput sellId buyId
    AsyncSwap.Swarm.ReduceMatchedOrders.inputOf AsyncSwap.Swarm.SettleTransfers.inputOf
  split <;> simp

/-- The reduction parameters depend only on the stored orders. -/
theorem params_of_orders (S S' : AsyncFiller.State_) (h : S'.orders = S.orders) (key : PoolKey)
    (f s : Nat) (m : AsyncFiller.MatchAmounts) :
    sellParams S' key f s m = sellParams S key f s m ∧ buyParams S' key f s m = buyParams S key f s m := by
  unfold sellParams buyParams sellId buyId AsyncSwap.Swarm.ReduceMatchedOrders.inputOf
  rw [h]; exact ⟨rfl, rfl⟩

variable {self_get : M σ AsyncFiller.State_} {self_set : AsyncFiller.State_ → M σ Unit}
    {book_get : M σ AsyncFiller.Book} {book_set : AsyncFiller.Book → M σ Unit}
    {g : σ → AsyncFiller.State_} {ss : σ → AsyncFiller.State_ → σ}
    {bg : σ → AsyncFiller.Book} {bs : σ → AsyncFiller.Book → σ}

/-- **Skip.** An empty order or two orders on the same side: `false`, world unchanged. -/
theorem matchPair_skip
    (L : Lawful self_get self_set book_get book_set g ss bg bs)
    (key : PoolKey) (f s hook : Nat) (env : Env) (w : σ) (hsk : skip (g w) f s) :
    AsyncMatching.«_matchPair» ext self_get self_set book_get book_set key f s hook env w
      = .ok (false, w) := by
  unfold AsyncMatching.«_matchPair»
  rcases hsk with h | h | h
  · simp [run_bind, L.hsg, run_pure, run_ite, h]
  · by_cases h1 : ((g w).orders f).amountIn = 0
    · simp [run_bind, L.hsg, run_pure, run_ite, h1]
    · simp [run_bind, L.hsg, run_pure, run_ite, h, h1]
  · by_cases h1 : ((g w).orders f).amountIn = 0
    · simp [run_bind, L.hsg, run_pure, run_ite, h1]
    · by_cases h2 : ((g w).orders s).amountIn = 0
      · simp [run_bind, L.hsg, run_pure, run_ite, h1, h2]
      · simp [run_bind, L.hsg, run_pure, run_ite, h, h1, h2]

/-- **Decomposition.** For a non-skipped pair the run is `_matchAmounts` (with constant reads of
the sell and buy orders at entry and the older order's side resting), then, unless an amount is
zero (`false`, world as `_matchAmounts` left it), `_settleTransfers` and `_reduceMatchedOrders`
with those amounts, returning `true`. Any revert of a step is the revert of the call. -/
theorem matchPair_eq
    (L : Lawful self_get self_set book_get book_set g ss bg bs)
    (key : PoolKey) (f s hook : Nat) (env : Env) (w : σ) (hns : ¬ skip (g w) f s) :
    AsyncMatching.«_matchPair» ext self_get self_set book_get book_set key f s hook env w
      = (match matchRun ext (g w) f s env w with
         | .error e => .error e
         | .ok (m, w1) =>
           if m.assetAmount = 0 ∨ m.quoteAmount = 0 then .ok (false, w1) else
           match AsyncMatching.«_settleTransfers» ext self_get self_set key f s m hook env w1 with
           | .error e => .error e
           | .ok (_, w2) =>
             match AsyncMatching.«_reduceMatchedOrders» ext self_get self_set book_get book_set
                 key f s m hook env w2 with
             | .error e => .error e
             | .ok (_, w3) => .ok (true, w3)) := by
  unfold AsyncMatching.«_matchPair» matchRun
  simp only [skip, not_or] at hns
  obtain ⟨h1, h2, h3⟩ := hns
  have hrd : ∀ i e, (do let x ← self_get; pure (x.orders i) : M σ AsyncFiller.OrderInfo) e w
      = .ok ((g w).orders i, w) := by
    intro i e; simp only [run_bind, L.hsg, run_pure]
  simp only [run_bind, L.hsg, run_pure, run_ite, bind_pure, h1, h2, h3, beq_iff_eq,
    Bool.not_eq_true', beq_eq_false_iff_ne, ne_eq, not_false_eq_true, Bool.not_false,
    ite_true, ite_false, Bool.false_eq_true, decide_eq_true_eq]
  unfold makerBuy sellId buyId
  split_ifs with hq
  all_goals (try rw [matchAmounts_congr ext _ _ _ _ (fun _ => pure ()) (fun _ => pure ()) _ _ _ env w
    (hrd _) (hrd _)])
  all_goals
    split
    next _ m w1 heq =>
      rw [heq]
      simp only [Bool.or_eq_true, beq_iff_eq]
      split_ifs
      · rfl
      · rcases AsyncMatching.«_settleTransfers» ext self_get self_set key f s m hook env w1
          with e | ⟨u, w2⟩
        · rfl
        · dsimp only
          rcases AsyncMatching.«_reduceMatchedOrders» ext self_get self_set book_get book_set
              key f s m hook env w2 with e | ⟨u', w3⟩ <;> rfl
    next _ e heq => rw [heq]

/-- A successful `_matchAmounts` run leaves the world unchanged and returns the spec's amounts. -/
theorem matchRun_ok (S : AsyncFiller.State_) (f s : Nat) (env : Env) (w w1 : σ)
    (m : AsyncFiller.MatchAmounts) (hm : matchRun ext S f s env w = .ok (m, w1)) :
    w1 = w ∧ m = amountsOf S f s := by
  obtain ⟨hw, ha, hq⟩ := AsyncSwap.Swarm.MatchAmounts.matchAmounts_ok ext _ _ _ _ _ _
    (fun _ _ => rfl) (fun _ _ => rfl) _ env w w1 m hm
  refine ⟨hw, ?_⟩
  cases m; simp only [amountsOf, AsyncFiller.MatchAmounts.mk.injEq]
  exact ⟨ha, hq⟩

/-- **Outcome.** Every successful run is one of: a skip (`false`, no effect); a non-skipped pair
whose spec amounts have a zero (`false`, no effect); or a non-skipped pair with non-zero spec amounts
`m = amountsOf`, returning `true` after `_settleTransfers` and then `_reduceMatchedOrders` with
exactly `m`. -/
theorem matchPair_ok
    (L : Lawful self_get self_set book_get book_set g ss bg bs)
    (key : PoolKey) (f s hook : Nat) (env : Env) (w w' : σ) (r : Bool)
    (h : AsyncMatching.«_matchPair» ext self_get self_set book_get book_set key f s hook env w
      = .ok (r, w')) :
    (skip (g w) f s ∧ r = false ∧ w' = w) ∨
    (¬ skip (g w) f s ∧ ((amountsOf (g w) f s).assetAmount = 0 ∨ (amountsOf (g w) f s).quoteAmount = 0)
      ∧ r = false ∧ w' = w) ∨
    (¬ skip (g w) f s ∧ (amountsOf (g w) f s).assetAmount ≠ 0 ∧ (amountsOf (g w) f s).quoteAmount ≠ 0
      ∧ r = true ∧
      ∃ w2, AsyncMatching.«_settleTransfers» ext self_get self_set key f s (amountsOf (g w) f s) hook
          env w = .ok ((), w2) ∧
        AsyncMatching.«_reduceMatchedOrders» ext self_get self_set book_get book_set key f s
          (amountsOf (g w) f s) hook env w2 = .ok ((), w')) := by
  by_cases hsk : skip (g w) f s
  · rw [matchPair_skip ext L key f s hook env w hsk] at h
    simp only [Except.ok.injEq, Prod.mk.injEq] at h
    exact Or.inl ⟨hsk, h.1.symm, h.2.symm⟩
  · rw [matchPair_eq ext L key f s hook env w hsk] at h
    rcases hm : matchRun ext (g w) f s env w with e | ⟨m, w1⟩
    · rw [hm] at h; cases h
    · rw [hm] at h
      obtain ⟨hw, hmeq⟩ := matchRun_ok ext (g w) f s env w w1 m hm
      rw [hw, hmeq] at h
      dsimp only at h
      split_ifs at h with hz
      · simp only [Except.ok.injEq, Prod.mk.injEq] at h
        exact Or.inr (Or.inl ⟨hsk, hz, h.1.symm, h.2.symm⟩)
      · rw [not_or] at hz
        refine Or.inr (Or.inr ⟨hsk, hz.1, hz.2, ?_⟩)
        rcases h2 : AsyncMatching.«_settleTransfers» ext self_get self_set key f s
            (amountsOf (g w) f s) hook env w with e | ⟨u, w2⟩
        · rw [h2] at h; cases h
        · rw [h2] at h; dsimp only at h
          rcases h3 : AsyncMatching.«_reduceMatchedOrders» ext self_get self_set book_get book_set
              key f s (amountsOf (g w) f s) hook env w2 with e | ⟨u', w3⟩
          · rw [h3] at h; cases h
          · rw [h3] at h
            simp only [Except.ok.injEq, Prod.mk.injEq] at h
            obtain ⟨rfl, rfl⟩ := h
            cases u; cases u'
            exact ⟨rfl, w2, by first | rfl | exact h2, by first | rfl | exact h3⟩

/-- **A `true` result: soundness and conservation per currency.** With `m = amountsOf` (the spec's
amounts), `S`/`B` the sell/buy orders at entry:
* `m` is non-zero, `m.assetAmount ≤ S.amountIn`, `m.quoteAmount ≤ B.amountIn`, and both limit
  prices hold;
* the run is exactly: burn `m.assetAmount` of the sell input currency from the hook, pay the same
  amount of that currency to the buyer, burn `m.quoteAmount` of the buy input currency from the hook,
  pay the same amount of it to the seller, then reduce the sell order (by `sellParams`, which
  consumes `m.assetAmount`) and the buy order (by `buyParams`, which consumes `m.quoteAmount`), the
  parameters read from the world the transfers left. -/
theorem matchPair_true
    (L : Lawful self_get self_set book_get book_set g ss bg bs)
    (key : PoolKey) (f s hook : Nat) (env : Env) (w w' : σ)
    (h : AsyncMatching.«_matchPair» ext self_get self_set book_get book_set key f s hook env w
      = .ok (true, w')) :
    ¬ skip (g w) f s ∧ (amountsOf (g w) f s).assetAmount ≠ 0 ∧ (amountsOf (g w) f s).quoteAmount ≠ 0 ∧
    (amountsOf (g w) f s).assetAmount ≤ ((g w).orders (sellId (g w) f s)).amountIn ∧
    (amountsOf (g w) f s).quoteAmount ≤ ((g w).orders (buyId (g w) f s)).amountIn ∧
    (amountsOf (g w) f s).assetAmount * ((g w).orders (sellId (g w) f s)).amountOutMin
      ≤ (amountsOf (g w) f s).quoteAmount * ((g w).orders (sellId (g w) f s)).amountIn ∧
    (amountsOf (g w) f s).quoteAmount * ((g w).orders (buyId (g w) f s)).amountOutMin
      ≤ (amountsOf (g w) f s).assetAmount * ((g w).orders (buyId (g w) f s)).amountIn ∧
    ∃ w1 w2 w3 w4 w5,
      (∃ u, ext.call_IPoolManager_burn (g w).poolManager hook (sellInput (g w) key f s)
        (amountsOf (g w) f s).assetAmount env w = .ok (u, w1)) ∧
      (∃ u, payout ext (g w).poolManager (sellInput (g w) key f s) (buyOwner (g w) f s)
        (amountsOf (g w) f s).assetAmount env w1 = .ok (u, w2)) ∧
      (∃ u, ext.call_IPoolManager_burn (g w2).poolManager hook (buyInput (g w) key f s)
        (amountsOf (g w) f s).quoteAmount env w2 = .ok (u, w3)) ∧
      payout ext (g w2).poolManager (buyInput (g w) key f s) (sellOwner (g w) f s)
        (amountsOf (g w) f s).quoteAmount env w3 = .ok ((), w4) ∧
      AsyncMatching.«_reduceAfterMatch» ext self_get self_set book_get book_set key
        (sellParams (g w4) key f s (amountsOf (g w) f s)) hook env w4 = .ok ((), w5) ∧
      AsyncMatching.«_reduceAfterMatch» ext self_get self_set book_get book_set key
        (buyParams (g w4) key f s (amountsOf (g w) f s)) hook env w5 = .ok ((), w') ∧
      (sellParams (g w4) key f s (amountsOf (g w) f s)).inputUsed = (amountsOf (g w) f s).assetAmount ∧
      (buyParams (g w4) key f s (amountsOf (g w) f s)).inputUsed = (amountsOf (g w) f s).quoteAmount := by
  rcases matchPair_ok ext L key f s hook env w w' true h with
    ⟨_, hr, _⟩ | ⟨_, _, hr, _⟩ | ⟨hsk, ha, hq, _, w4, h2, h3⟩
  · cases hr
  · cases hr
  obtain ⟨hs0, hb0⟩ := AsyncSwap.Swarm.MatchAmounts.spec_pos _ _ _ ha hq
  have hsd := AsyncSwap.matchAmounts_sound _ _ _ hs0 hb0 _ rfl ha hq
  obtain ⟨w1, w2, w3, hb1, hp1, hb2, hp2⟩ :=
    AsyncSwap.Swarm.SettleTransfers.settleTransfers_ok ext self_get self_set g L.hsg key f s
      (amountsOf (g w) f s) hook env w w4 () h2
  obtain ⟨w5, h5, h6⟩ :=
    (AsyncSwap.Swarm.ReduceMatchedOrders.reduceMatchedOrders_ok_iff ext L key f s
      (amountsOf (g w) f s) hook env w4 w').1 h3
  obtain ⟨-, hu1, -, -, hu2, -⟩ := params_conserve (g w4) key f s (amountsOf (g w) f s)
  exact ⟨hsk, ha, hq, hsd.asset_le_sell_escrow, hsd.quote_le_buy_escrow, hsd.seller_limit,
    hsd.buyer_limit, w1, w2, w3, w4, w5, hb1, hp1, hb2, hp2, h5, h6, hu1, hu2⟩

/-- **Reverts.** A revert never happens on a skipped pair; otherwise it is the revert of
`_matchAmounts`, or (with non-zero spec amounts) of `_settleTransfers`, or of
`_reduceMatchedOrders` after a successful settlement. -/
theorem matchPair_error
    (L : Lawful self_get self_set book_get book_set g ss bg bs)
    (key : PoolKey) (f s hook : Nat) (env : Env) (w : σ) (e : Revert)
    (h : AsyncMatching.«_matchPair» ext self_get self_set book_get book_set key f s hook env w
      = .error e) :
    ¬ skip (g w) f s ∧
    (matchRun ext (g w) f s env w = .error e ∨
     ((amountsOf (g w) f s).assetAmount ≠ 0 ∧ (amountsOf (g w) f s).quoteAmount ≠ 0 ∧
      (AsyncMatching.«_settleTransfers» ext self_get self_set key f s (amountsOf (g w) f s) hook
          env w = .error e ∨
       ∃ w2, AsyncMatching.«_settleTransfers» ext self_get self_set key f s (amountsOf (g w) f s)
          hook env w = .ok ((), w2) ∧
        AsyncMatching.«_reduceMatchedOrders» ext self_get self_set book_get book_set key f s
          (amountsOf (g w) f s) hook env w2 = .error e))) := by
  by_cases hsk : skip (g w) f s
  · rw [matchPair_skip ext L key f s hook env w hsk] at h; cases h
  refine ⟨hsk, ?_⟩
  rw [matchPair_eq ext L key f s hook env w hsk] at h
  rcases hm : matchRun ext (g w) f s env w with e' | ⟨m, w1⟩
  · rw [hm] at h; cases h; exact Or.inl rfl
  · rw [hm] at h
    obtain ⟨hw, hmeq⟩ := matchRun_ok ext (g w) f s env w w1 m hm
    rw [hw, hmeq] at h
    dsimp only at h
    split_ifs at h with hz
    rw [not_or] at hz
    right
    refine ⟨hz.1, hz.2, ?_⟩
    rcases h2 : AsyncMatching.«_settleTransfers» ext self_get self_set key f s
        (amountsOf (g w) f s) hook env w with e' | ⟨u, w2⟩
    · rw [h2] at h; cases h; exact Or.inl rfl
    · rw [h2] at h; dsimp only at h
      right
      cases u
      refine ⟨w2, rfl, ?_⟩
      rcases h3 : AsyncMatching.«_reduceMatchedOrders» ext self_get self_set book_get book_set
          key f s (amountsOf (g w) f s) hook env w2 with e' | ⟨u', w3⟩
      · rw [h3] at h; cases h; rfl
      · rw [h3] at h; cases h

/-- **Guard (division by zero).** For a non-skipped pair whose resting order (the older one) has
`amountOutMin = 0`, the call reverts with panic `0x12` before any write or external call. -/
theorem matchPair_reverts_restingZero
    (L : Lawful self_get self_set book_get book_set g ss bg bs)
    (key : PoolKey) (f s hook : Nat) (env : Env) (w : σ) (hns : ¬ skip (g w) f s)
    (hz : if makerBuy (g w) f s then ((g w).orders (buyId (g w) f s)).amountOutMin = 0
          else ((g w).orders (sellId (g w) f s)).amountOutMin = 0) :
    AsyncMatching.«_matchPair» ext self_get self_set book_get book_set key f s hook env w
      = .error (FormalAst.panic "0x12") := by
  rw [matchPair_eq ext L key f s hook env w hns]
  have : matchRun ext (g w) f s env w = .error (FormalAst.panic "0x12") := by
    unfold matchRun
    cases hmb : makerBuy (g w) f s
    · rw [hmb] at hz
      exact AsyncSwap.Swarm.MatchAmounts.matchAmounts_reverts_restingSell ext _ _ _ _ _ _
        (fun _ _ => rfl) (fun _ _ => rfl) (by simpa using hz) env w
    · rw [hmb] at hz
      exact AsyncSwap.Swarm.MatchAmounts.matchAmounts_reverts_restingBuy ext _ _ _ _ _ _
        (fun _ _ => rfl) (fun _ _ => rfl) (by simpa using hz) env w
  rw [this]

end AsyncSwap.Swarm.MatchPair
