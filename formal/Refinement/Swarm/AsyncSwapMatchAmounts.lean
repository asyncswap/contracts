import Generated.AsyncSwap
import Refinement.Monad
import AsyncSwapSpec.Match

/-!
# AsyncSwap: `AsyncMatching._matchAmounts`

The generated `AsyncMatching.«_matchAmounts»` is a pure function of the two stored orders: its
`sell_get` / `buy_get` accessors are reads of `orders[sellId]` / `orders[buyId]` at the call site
(`_matchPair`), and it never calls `sell_set` / `buy_set`. For accessors that read without writing:

* `matchAmounts_ok`: every successful run leaves the world unchanged and returns exactly
  `AsyncSwap.matchAmounts (toSpec sell) (toSpec buy) restingBuy` (`AsyncSwapSpec/Match.lean`);
* `matchAmounts_ok_sound`: a non-zero result honours both escrows and both limit prices;
* `matchAmounts_reverts_restingBuy` / `_restingSell`: a zero `amountOutMin` on the resting side
  reverts in the first `mulDiv` (which divides by it): panic `0x12` when the product of the two
  `amountIn`s fits 256 bits, `MathOverflowedMulDiv` otherwise (OpenZeppelin 5.0.2 checks
  `denominator <= prod1` before it divides);
* `matchAmounts_succeeds`: with `uint128` amounts and a positive resting `amountOutMin` no
  `mulDiv` reverts, so the run returns the spec's amounts.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.MatchAmounts

variable {σ : Type} (ext : Ext σ)

/-- The two thresholds of OpenZeppelin 5.0.2's `mulDiv` agree for a nonzero `d`:
`d ≤ ⌊x·y / 2^256⌋` exactly when the quotient `⌊x·y / d⌋` doesn't fit 256 bits. -/
theorem floor_cases (x y d : Nat) :
    d = 0 ∨ (d ≤ x * y / 2 ^ 256 ∧ 2 ^ 256 ≤ x * y / d)
      ∨ (x * y / 2 ^ 256 < d ∧ x * y / d < 2 ^ 256) := by
  have hW : 0 < 2 ^ 256 := Nat.two_pow_pos 256
  rcases Nat.eq_zero_or_pos d with hd | hd
  · exact Or.inl hd
  · right
    by_cases h : d ≤ x * y / 2 ^ 256
    · left; refine ⟨h, ?_⟩
      rw [Nat.le_div_iff_mul_le hW] at h
      rw [Nat.le_div_iff_mul_le hd, Nat.mul_comm (2 ^ 256) d]; exact h
    · right; refine ⟨Nat.lt_of_not_le h, ?_⟩
      rw [Nat.le_div_iff_mul_le hW] at h
      rw [Nat.div_lt_iff_lt_mul hd, Nat.mul_comm (2 ^ 256) d]; exact Nat.lt_of_not_le h

/-- `mulDivFloor` run: a zero `d` panics `0x12` when the product fits one word and reverts
`MathOverflowedMulDiv` otherwise (OpenZeppelin 5.0.2 checks `d ≤ prod1` before dividing); a
nonzero `d` returns the floor when it fits 256 bits and reverts `MathOverflowedMulDiv` when not. -/
theorem floor_run (x y d : Nat) (env : Env) (s : σ) :
    (mulDivFloor x y d : M σ Nat) env s =
      (if d = 0 then .error (if x * y < 2 ^ 256 then panic "0x12" else ⟨"MathOverflowedMulDiv"⟩)
       else if x * y / d < 2 ^ 256 then .ok (x * y / d, s) else .error ⟨"MathOverflowedMulDiv"⟩) := by
  have k := floor_cases x y d
  have hle := Nat.div_le_self (x * y) d
  unfold mulDivFloor
  generalize x * y / 2 ^ 256 = H at *
  generalize x * y / d = Q at *
  generalize x * y = P at *
  generalize (2 : Nat) ^ 256 = W at *
  split_ifs <;> first | rfl | (exfalso; omega)

theorem ceil_run (x y d : Nat) (env : Env) (s : σ) :
    (mulDivRnd x y d 1 : M σ Nat) env s =
      (if d = 0 then .error (if x * y < 2 ^ 256 then panic "0x12" else ⟨"MathOverflowedMulDiv"⟩)
       else if x * y / d < 2 ^ 256 then
         (if x * y % d = 0 then .ok (x * y / d, s)
          else if x * y / d + 1 < 2 ^ 256 then .ok (x * y / d + 1, s) else .error (panic "0x11"))
       else .error ⟨"MathOverflowedMulDiv"⟩) := by
  unfold mulDivRnd FormalAst.mulDivCeil addc
  simp only [show (1 : Nat) % 2 = 1 from rfl, ite_true, run_bind, floor_run]
  split_ifs <;> simp [*] <;> omega

theorem default_asset : (default : AsyncFiller.MatchAmounts).assetAmount = 0 := rfl
theorem default_quote : (default : AsyncFiller.MatchAmounts).quoteAmount = 0 := rfl

/-- `q ≤ c ⇒ q·b/c ≤ b`, as a disjunction `omega` can use. -/
theorem aux_le (q b c : Nat) : c < q ∨ q * b / c ≤ b := by
  by_cases h : q ≤ c
  · right
    rcases Nat.eq_zero_or_pos c with hc | hc
    · subst hc; simp
    · exact Nat.div_le_of_le_mul (Nat.mul_le_mul_right b h)
  · left; omega

/-- A positive multiple of `c` has a positive quotient. -/
theorem aux_pos (a c : Nat) : a = 0 ∨ a % c ≠ 0 ∨ 0 < a / c := by
  by_cases ha : a = 0
  · exact Or.inl ha
  by_cases hm : a % c = 0
  · right; right
    rcases Nat.eq_zero_or_pos c with hc | hc
    · subst hc; simp at hm; omega
    · have := Nat.div_add_mod a c
      rw [hm, Nat.add_zero] at this
      rcases Nat.eq_zero_or_pos (a / c) with h0 | h0
      · rw [h0, Nat.mul_zero] at this; omega
      · exact h0
  · exact Or.inr (Or.inl hm)

theorem aux_mul (x y : Nat) : x = 0 ∨ y = 0 ∨ 0 < x * y := by
  rcases Nat.eq_zero_or_pos x with h | h
  · exact Or.inl h
  rcases Nat.eq_zero_or_pos y with h' | h'
  · exact Or.inr (Or.inl h')
  · exact Or.inr (Or.inr (Nat.mul_pos h h'))

theorem aux_cancel (x y : Nat) : x = 0 ∨ x * y / x = y :=
  (Nat.eq_zero_or_pos x).imp id (fun h => Nat.mul_div_cancel_left y h)

theorem aux_prod (x y : Nat) (hx : x < 2 ^ 128) (hy : y < 2 ^ 128) : x * y < 2 ^ 256 :=
  calc x * y < 2 ^ 128 * 2 ^ 128 := Nat.mul_lt_mul'' hx hy
    _ = 2 ^ 256 := by norm_num

/-- The `AsyncSwapSpec` view of a stored `AsyncFiller.OrderInfo`. -/
def toSpec (o : AsyncFiller.OrderInfo) : AsyncSwap.Order :=
  { owner := o.owner, amountIn := o.amountIn, amountOutMin := o.amountOutMin, isBuy := o.isBuy,
    zeroForOne := o.zeroForOne, priorityFee := o.priorityFee,
    priorityFeeEscrowed := o.priorityFeeEscrowed }

variable (sell buy : AsyncFiller.OrderInfo) (sell_get : M σ AsyncFiller.OrderInfo)
    (sell_set : AsyncFiller.OrderInfo → M σ Unit) (buy_get : M σ AsyncFiller.OrderInfo)
    (buy_set : AsyncFiller.OrderInfo → M σ Unit)

/-! ## Successful runs refine `AsyncSwap.matchAmounts` -/

set_option maxHeartbeats 4000000 in
theorem ok_restingBuy
    (hs : ∀ e t, sell_get e t = .ok (sell, t)) (hb : ∀ e t, buy_get e t = .ok (buy, t))
    (env : Env) (st st' : σ) (m : AsyncFiller.MatchAmounts)
    (h : AsyncMatching.«_matchAmounts» ext sell_get sell_set buy_get buy_set true env st = .ok (m, st')) :
    st' = st ∧ m.assetAmount = (AsyncSwap.matchAmounts (toSpec sell) (toSpec buy) true).assetAmount
      ∧ m.quoteAmount = (AsyncSwap.matchAmounts (toSpec sell) (toSpec buy) true).quoteAmount := by
  simp only [AsyncMatching.«_matchAmounts», run_bind, hs, hb, floor_run, ite_true] at h
  repeat' (first
    | (split_ifs at h)
    | (simp only [run_bind, run_pure, run_ite, hs, hb, ceil_run] at h))
  all_goals (simp only [Except.ok.injEq, Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h)
  all_goals (refine ⟨rfl, ?_⟩)
  all_goals (simp only [decide_eq_true_eq, beq_iff_eq, gt_iff_lt, default_asset] at *)
  all_goals (simp only [AsyncSwap.matchAmounts, toSpec, AsyncSwap.mulDiv, AsyncSwap.mulDivCeil, min_def])
  all_goals (generalize (2:Nat) ^ 256 = W at *)
  all_goals (split_ifs <;> dsimp only <;> omega)

set_option maxHeartbeats 4000000 in
theorem ok_restingSell
    (hs : ∀ e t, sell_get e t = .ok (sell, t)) (hb : ∀ e t, buy_get e t = .ok (buy, t))
    (env : Env) (st st' : σ) (m : AsyncFiller.MatchAmounts)
    (h : AsyncMatching.«_matchAmounts» ext sell_get sell_set buy_get buy_set false env st = .ok (m, st')) :
    st' = st ∧ m.assetAmount = (AsyncSwap.matchAmounts (toSpec sell) (toSpec buy) false).assetAmount
      ∧ m.quoteAmount = (AsyncSwap.matchAmounts (toSpec sell) (toSpec buy) false).quoteAmount := by
  simp only [AsyncMatching.«_matchAmounts», run_bind, hs, hb, floor_run, Bool.false_eq_true,
    ite_false] at h
  repeat' (first
    | (split_ifs at h)
    | (simp only [run_bind, run_pure, run_ite, hs, hb, ceil_run] at h))
  all_goals (simp only [Except.ok.injEq, Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h)
  all_goals (refine ⟨rfl, ?_⟩)
  all_goals (simp only [decide_eq_true_eq, beq_iff_eq, gt_iff_lt, default_quote] at *)
  all_goals (simp only [AsyncSwap.matchAmounts, toSpec, AsyncSwap.mulDiv, AsyncSwap.mulDivCeil, min_def,
    Bool.false_eq_true, ite_false])
  all_goals (generalize (2:Nat) ^ 256 = W at *)
  all_goals (split_ifs <;> dsimp only <;> omega)

/-- **Refinement.** With accessors that read `sell` / `buy` without writing, every successful run of
`_matchAmounts` leaves the world unchanged (the setters are never called) and returns exactly the
amounts of the spec `AsyncSwap.matchAmounts`. -/
theorem matchAmounts_ok
    (hs : ∀ e t, sell_get e t = .ok (sell, t)) (hb : ∀ e t, buy_get e t = .ok (buy, t))
    (rb : Bool) (env : Env) (st st' : σ) (m : AsyncFiller.MatchAmounts)
    (h : AsyncMatching.«_matchAmounts» ext sell_get sell_set buy_get buy_set rb env st = .ok (m, st')) :
    st' = st ∧ m.assetAmount = (AsyncSwap.matchAmounts (toSpec sell) (toSpec buy) rb).assetAmount
      ∧ m.quoteAmount = (AsyncSwap.matchAmounts (toSpec sell) (toSpec buy) rb).quoteAmount := by
  cases rb
  · exact ok_restingSell ext sell buy sell_get sell_set buy_get buy_set hs hb env st st' m h
  · exact ok_restingBuy ext sell buy sell_get sell_set buy_get buy_set hs hb env st st' m h

theorem spec_pos (s b : AsyncSwap.Order) (rb : Bool)
    (ha : (AsyncSwap.matchAmounts s b rb).assetAmount ≠ 0)
    (hq : (AsyncSwap.matchAmounts s b rb).quoteAmount ≠ 0) :
    0 < s.amountIn ∧ 0 < b.amountIn := by
  cases rb <;> simp only [AsyncSwap.matchAmounts, min_def, Bool.false_eq_true, ite_true, ite_false]
    at ha hq <;> split_ifs at ha hq <;> dsimp only at ha hq <;> omega

/-- **Soundness.** A successful run with non-zero amounts spends at most each order's escrow and
honours both limit prices. -/
theorem matchAmounts_ok_sound
    (hs : ∀ e t, sell_get e t = .ok (sell, t)) (hb : ∀ e t, buy_get e t = .ok (buy, t))
    (rb : Bool) (env : Env) (st st' : σ) (m : AsyncFiller.MatchAmounts)
    (h : AsyncMatching.«_matchAmounts» ext sell_get sell_set buy_get buy_set rb env st = .ok (m, st'))
    (ha : m.assetAmount ≠ 0) (hq : m.quoteAmount ≠ 0) :
    st' = st
    ∧ m.assetAmount ≤ sell.amountIn ∧ m.quoteAmount ≤ buy.amountIn
    ∧ m.assetAmount * sell.amountOutMin ≤ m.quoteAmount * sell.amountIn
    ∧ m.quoteAmount * buy.amountOutMin ≤ m.assetAmount * buy.amountIn := by
  obtain ⟨hst, h1, h2⟩ := matchAmounts_ok ext sell buy sell_get sell_set buy_get buy_set hs hb rb env st st' m h
  rw [h1] at ha ⊢; rw [h2] at hq ⊢
  obtain ⟨hs0, hb0⟩ := spec_pos _ _ rb ha hq
  have hsd := AsyncSwap.matchAmounts_sound (toSpec sell) (toSpec buy) rb hs0 hb0 _ rfl ha hq
  exact ⟨hst, hsd.asset_le_sell_escrow, hsd.quote_le_buy_escrow, hsd.seller_limit, hsd.buyer_limit⟩

/-! ## Reverts -/

/-- When the buyer rests and its `amountOutMin` is zero, the first `mulDiv`
(`sell.amountIn * buy.amountIn / 0`) reverts: panic `0x12` when the product fits 256 bits,
`MathOverflowedMulDiv` otherwise. -/
theorem matchAmounts_reverts_restingBuy
    (hs : ∀ e t, sell_get e t = .ok (sell, t)) (hb : ∀ e t, buy_get e t = .ok (buy, t))
    (h0 : buy.amountOutMin = 0) (env : Env) (st : σ) :
    AsyncMatching.«_matchAmounts» ext sell_get sell_set buy_get buy_set true env st
      = .error (if sell.amountIn * buy.amountIn < 2 ^ 256 then panic "0x12"
                else ⟨"MathOverflowedMulDiv"⟩) := by
  simp [AsyncMatching.«_matchAmounts», run_bind, hs, hb, floor_run, h0]

/-- When the seller rests and its `amountOutMin` is zero, the first `mulDiv`
(`buy.amountIn * sell.amountIn / 0`) reverts: panic `0x12` when the product fits 256 bits,
`MathOverflowedMulDiv` otherwise. -/
theorem matchAmounts_reverts_restingSell
    (hs : ∀ e t, sell_get e t = .ok (sell, t)) (hb : ∀ e t, buy_get e t = .ok (buy, t))
    (h0 : sell.amountOutMin = 0) (env : Env) (st : σ) :
    AsyncMatching.«_matchAmounts» ext sell_get sell_set buy_get buy_set false env st
      = .error (if buy.amountIn * sell.amountIn < 2 ^ 256 then panic "0x12"
                else ⟨"MathOverflowedMulDiv"⟩) := by
  simp [AsyncMatching.«_matchAmounts», run_bind, hs, hb, floor_run, h0]

set_option maxHeartbeats 4000000 in
theorem noerr_restingBuy
    (hs : ∀ e t, sell_get e t = .ok (sell, t)) (hb : ∀ e t, buy_get e t = .ok (buy, t))
    (hsi : sell.amountIn < 2 ^ 128) (hbi : buy.amountIn < 2 ^ 128)
    (hsm : sell.amountOutMin < 2 ^ 128) (hbm : buy.amountOutMin < 2 ^ 128)
    (hbm0 : 0 < buy.amountOutMin)
    (env : Env) (st : σ) (e : Revert)
    (h : AsyncMatching.«_matchAmounts» ext sell_get sell_set buy_get buy_set true env st = .error e) :
    False := by
  have f1 := aux_prod _ _ hsi hbi
  have f2 := Nat.div_le_self (sell.amountIn * buy.amountIn) buy.amountOutMin
  have e1 := Nat.mul_mod_right buy.amountIn buy.amountOutMin
  have e2 := aux_cancel buy.amountIn buy.amountOutMin
  have g2 := aux_le (sell.amountIn * buy.amountIn / buy.amountOutMin) buy.amountOutMin buy.amountIn
  have p2 := aux_pos (sell.amountIn * buy.amountIn / buy.amountOutMin * buy.amountOutMin) buy.amountIn
  have m2 := aux_mul (sell.amountIn * buy.amountIn / buy.amountOutMin) buy.amountOutMin
  have k1 := aux_le (buy.amountIn * buy.amountOutMin / buy.amountIn) sell.amountOutMin sell.amountIn
  have k2 := aux_le (buy.amountIn * buy.amountOutMin / buy.amountIn + 1) sell.amountOutMin sell.amountIn
  have k3 := aux_le (sell.amountIn * buy.amountIn / buy.amountOutMin * buy.amountOutMin / buy.amountIn)
    sell.amountOutMin sell.amountIn
  have k4 := aux_le (sell.amountIn * buy.amountIn / buy.amountOutMin * buy.amountOutMin / buy.amountIn + 1)
    sell.amountOutMin sell.amountIn
  simp only [AsyncMatching.«_matchAmounts», run_bind, hs, hb, floor_run, ite_true] at h
  repeat' (first
    | (split_ifs at h)
    | (simp only [run_bind, run_pure, run_ite, hs, hb, ceil_run] at h))
  all_goals (try simp only [decide_eq_true_eq, beq_iff_eq, gt_iff_lt] at *)
  all_goals (
    generalize sell.amountIn * buy.amountIn = P at *
    generalize P / buy.amountOutMin = X at *
    generalize buy.amountIn * buy.amountOutMin = Q1 at *
    generalize Q1 / buy.amountIn = A1 at *
    generalize X * buy.amountOutMin = Q2 at *
    generalize Q2 / buy.amountIn = A2 at *
    generalize Q2 % buy.amountIn = R2 at *
    omega)

set_option maxHeartbeats 4000000 in
theorem noerr_restingSell
    (hs : ∀ e t, sell_get e t = .ok (sell, t)) (hb : ∀ e t, buy_get e t = .ok (buy, t))
    (hsi : sell.amountIn < 2 ^ 128) (hbi : buy.amountIn < 2 ^ 128)
    (hsm : sell.amountOutMin < 2 ^ 128) (hbm : buy.amountOutMin < 2 ^ 128)
    (hsm0 : 0 < sell.amountOutMin)
    (env : Env) (st : σ) (e : Revert)
    (h : AsyncMatching.«_matchAmounts» ext sell_get sell_set buy_get buy_set false env st = .error e) :
    False := by
  have f1 := aux_prod _ _ hbi hsi
  have f2 := Nat.div_le_self (buy.amountIn * sell.amountIn) sell.amountOutMin
  have e1 := Nat.mul_mod_right sell.amountIn sell.amountOutMin
  have e2 := aux_cancel sell.amountIn sell.amountOutMin
  have g2 := aux_le (buy.amountIn * sell.amountIn / sell.amountOutMin) sell.amountOutMin sell.amountIn
  have p2 := aux_pos (buy.amountIn * sell.amountIn / sell.amountOutMin * sell.amountOutMin) sell.amountIn
  have m2 := aux_mul (buy.amountIn * sell.amountIn / sell.amountOutMin) sell.amountOutMin
  have k1 := aux_le (sell.amountIn * sell.amountOutMin / sell.amountIn) buy.amountOutMin buy.amountIn
  have k2 := aux_le (sell.amountIn * sell.amountOutMin / sell.amountIn + 1) buy.amountOutMin buy.amountIn
  have k3 := aux_le (buy.amountIn * sell.amountIn / sell.amountOutMin * sell.amountOutMin / sell.amountIn)
    buy.amountOutMin buy.amountIn
  have k4 := aux_le (buy.amountIn * sell.amountIn / sell.amountOutMin * sell.amountOutMin / sell.amountIn + 1)
    buy.amountOutMin buy.amountIn
  simp only [AsyncMatching.«_matchAmounts», run_bind, hs, hb, floor_run, Bool.false_eq_true,
    ite_false] at h
  repeat' (first
    | (split_ifs at h)
    | (simp only [run_bind, run_pure, run_ite, hs, hb, ceil_run] at h))
  all_goals (try simp only [decide_eq_true_eq, beq_iff_eq, gt_iff_lt] at *)
  all_goals (
    generalize buy.amountIn * sell.amountIn = P at *
    generalize P / sell.amountOutMin = X at *
    generalize sell.amountIn * sell.amountOutMin = Q1 at *
    generalize Q1 / sell.amountIn = A1 at *
    generalize X * sell.amountOutMin = Q2 at *
    generalize Q2 / sell.amountIn = A2 at *
    generalize Q2 % sell.amountIn = R2 at *
    omega)

/-- **No spurious revert.** With `uint128` amounts and a positive `amountOutMin` on the resting
side (the order whose price sizes the trade), `_matchAmounts` never reverts: it returns the spec's
amounts and leaves the world unchanged. -/
theorem matchAmounts_succeeds
    (hs : ∀ e t, sell_get e t = .ok (sell, t)) (hb : ∀ e t, buy_get e t = .ok (buy, t))
    (hsi : sell.amountIn < 2 ^ 128) (hbi : buy.amountIn < 2 ^ 128)
    (hsm : sell.amountOutMin < 2 ^ 128) (hbm : buy.amountOutMin < 2 ^ 128)
    (rb : Bool) (hrest : if rb then 0 < buy.amountOutMin else 0 < sell.amountOutMin)
    (env : Env) (st : σ) :
    AsyncMatching.«_matchAmounts» ext sell_get sell_set buy_get buy_set rb env st
      = .ok ({ assetAmount := (AsyncSwap.matchAmounts (toSpec sell) (toSpec buy) rb).assetAmount,
               quoteAmount := (AsyncSwap.matchAmounts (toSpec sell) (toSpec buy) rb).quoteAmount }, st) := by
  match hr : AsyncMatching.«_matchAmounts» ext sell_get sell_set buy_get buy_set rb env st with
  | .error e =>
    exfalso
    cases rb
    · exact noerr_restingSell ext sell buy sell_get sell_set buy_get buy_set hs hb hsi hbi hsm hbm
        (by simpa using hrest) env st e hr
    · exact noerr_restingBuy ext sell buy sell_get sell_set buy_get buy_set hs hb hsi hbi hsm hbm
        (by simpa using hrest) env st e hr
  | .ok (m, st') =>
    obtain ⟨rfl, h1, h2⟩ := matchAmounts_ok ext sell buy sell_get sell_set buy_get buy_set hs hb rb env st st' m hr
    rw [← h1, ← h2]

end AsyncSwap.Swarm.MatchAmounts
