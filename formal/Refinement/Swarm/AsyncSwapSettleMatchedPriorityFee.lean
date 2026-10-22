import Generated.AsyncSwap
import Refinement.Monad
import Refinement.Swarm.AsyncSwapMulDiv

/-!
# `AsyncMatching._settleMatchedPriorityFee`

`function _settleMatchedPriorityFee(State storage self, PoolKey memory key, bytes32 id,
uint256 inputUsed, uint256 oldInput, address hook) internal returns (uint256 unfilledPriorityFee)`
(src/AsyncSwap.sol, library `AsyncMatching`).

It reads `fee = paidPriorityFee(self.orders[id])` (the escrowed bid, or 0). With `fee = 0` it
returns 0 and touches nothing. Otherwise it computes `filled = mulDiv(fee, inputUsed, oldInput)`,
reverts on `oldInput = 0` (panic 0x12 when `fee * inputUsed` fits 256 bits, `MathOverflowedMulDiv`
otherwise), on a result above 2^256 (`MathOverflowedMulDiv`) or when
`filled > fee` (panic 0x11 from `fee - filled`), then hands `settlePriorityFee(self, key, id,
self.orders[id].owner, filled, hook)` everything and returns `fee - filled`. It writes no storage
of its own: every write and external call comes from `settlePriorityFee`.

`self` is a storage pointer, passed as a getter/setter pair. The theorems assume the getter is a
pure read of the world (`self_get env w = .ok (g w, w)`), which is how every caller instantiates it.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.SettleMatchedPriorityFee

variable {σ : Type} (ext : Ext σ)

/-- The fee `paidPriorityFee` reports for an order: the escrowed bid, or 0. -/
def paidFee (info : AsyncFiller.OrderInfo) : Nat :=
  if info.priorityFeeEscrowed then info.priorityFee else 0

/-- Full characterization of `_settleMatchedPriorityFee`: its guards, the single call to
`settlePriorityFee` with `amount = fee * inputUsed / oldInput`, and its return value
`fee - filled`. -/
theorem settleMatchedPriorityFee_run (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (g : σ → AsyncFiller.State_)
    (hget : ∀ env w, self_get env w = .ok (g w, w))
    (key : PoolKey) (id inputUsed oldInput hook : Nat) (env : Env) (w : σ) :
    AsyncMatching.«_settleMatchedPriorityFee» ext self_get self_set key id inputUsed oldInput hook
        env w =
      (if paidFee ((g w).orders id) = 0 then .ok (0, w)
       else if oldInput = 0 then
         .error (if paidFee ((g w).orders id) * inputUsed < 2 ^ 256 then FormalAst.panic "0x12"
                 else ⟨"MathOverflowedMulDiv"⟩)
       else if paidFee ((g w).orders id) * inputUsed / oldInput < 2 ^ 256 then
         if paidFee ((g w).orders id) * inputUsed / oldInput ≤ paidFee ((g w).orders id) then
           match AsyncFiller.settlePriorityFee ext self_get self_set key id
               ((g w).orders id).owner (paidFee ((g w).orders id) * inputUsed / oldInput)
               hook env w with
           | .ok (_, w') => .ok (paidFee ((g w).orders id) -
               paidFee ((g w).orders id) * inputUsed / oldInput, w')
           | .error e => .error e
         else .error (FormalAst.panic "0x11")
       else .error ⟨"MathOverflowedMulDiv"⟩) := by
  unfold AsyncMatching.«_settleMatchedPriorityFee» AsyncFiller.paidPriorityFee
  simp only [run_bind, hget, run_pure, MulDiv.mulDivFloor_run, MulDiv.W_eq, subc, run_ite,
    run_throw, beq_iff_eq]
  cases hE : ((g w).orders id).priorityFeeEscrowed
  · simp [hE, paidFee]
  have hp : paidFee ((g w).orders id) = ((g w).orders id).priorityFee := by simp [paidFee, hE]
  rw [hp]
  simp only [ite_true]
  by_cases h0 : ((g w).orders id).priorityFee = 0
  · simp [h0]
  by_cases hd : oldInput = 0
  · by_cases hp : ((g w).orders id).priorityFee * inputUsed < 2 ^ 256
    · simp only [h0, hd, hp, ↓reduceIte]
    · simp only [h0, hd, hp, ↓reduceIte]
  by_cases hb : ((g w).orders id).priorityFee * inputUsed / oldInput < 2 ^ 256
  · by_cases hle : ((g w).orders id).priorityFee * inputUsed / oldInput ≤
        ((g w).orders id).priorityFee
    · simp only [h0, hd, hb, hle, ↓reduceIte]
      cases AsyncFiller.settlePriorityFee ext self_get self_set key id ((g w).orders id).owner
        (((g w).orders id).priorityFee * inputUsed / oldInput) hook env w <;> rfl
    · simp only [h0, hd, hb, hle, ↓reduceIte]
  · simp only [h0, hd, hb, ↓reduceIte]

/-- No escrowed fee (or a zero one): it succeeds, returns 0 and leaves the world unchanged. -/
theorem settleMatchedPriorityFee_no_fee (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (g : σ → AsyncFiller.State_)
    (hget : ∀ env w, self_get env w = .ok (g w, w))
    (key : PoolKey) (id inputUsed oldInput hook : Nat) (env : Env) (w : σ)
    (h : paidFee ((g w).orders id) = 0) :
    AsyncMatching.«_settleMatchedPriorityFee» ext self_get self_set key id inputUsed oldInput hook
        env w = .ok (0, w) := by
  rw [settleMatchedPriorityFee_run ext self_get self_set g hget]
  simp [h]

/-- The pro-rata share never exceeds the recorded fee when no more input is consumed than
recorded. -/
theorem filled_le_fee (fee inputUsed oldInput : Nat) (h : inputUsed ≤ oldInput) :
    fee * inputUsed / oldInput ≤ fee := by
  rcases Nat.eq_zero_or_pos oldInput with h0 | h0
  · simp [h0]
  · exact Nat.div_le_of_le_mul (by simpa [Nat.mul_comm] using Nat.mul_le_mul_left fee h)

/-- In the matching path (`inputUsed ≤ oldInput`, `oldInput ≠ 0`, a fee that fits a word) with
an escrowed fee, the only guards left are those of `settlePriorityFee`: it settles
`filled = fee * inputUsed / oldInput` for the order's owner and returns `fee - filled`, with the
world `settlePriorityFee` leaves. -/
theorem settleMatchedPriorityFee_matched (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (g : σ → AsyncFiller.State_)
    (hget : ∀ env w, self_get env w = .ok (g w, w))
    (key : PoolKey) (id inputUsed oldInput hook : Nat) (env : Env) (w : σ)
    (hf : paidFee ((g w).orders id) ≠ 0) (hd : oldInput ≠ 0) (hu : inputUsed ≤ oldInput)
    (hw : paidFee ((g w).orders id) < 2 ^ 256) :
    AsyncMatching.«_settleMatchedPriorityFee» ext self_get self_set key id inputUsed oldInput hook
        env w =
      match AsyncFiller.settlePriorityFee ext self_get self_set key id
          ((g w).orders id).owner (paidFee ((g w).orders id) * inputUsed / oldInput)
          hook env w with
      | .ok (_, w') => .ok (paidFee ((g w).orders id) -
          paidFee ((g w).orders id) * inputUsed / oldInput, w')
      | .error e => .error e := by
  rw [settleMatchedPriorityFee_run ext self_get self_set g hget]
  have hle := filled_le_fee (paidFee ((g w).orders id)) inputUsed oldInput hu
  simp only [hf, hd, hle, Nat.lt_of_le_of_lt hle hw, ↓reduceIte]

/-- On success, the fee is split exactly once and never over-paid: either there was no fee
(returns 0, world unchanged), or `settlePriorityFee` was run once with an amount
`filled ≤ fee`, producing the final world, and the returned unfilled part satisfies
`unfilled + filled = fee`. In every case `unfilled ≤ fee`. -/
theorem settleMatchedPriorityFee_ok (self_get : M σ AsyncFiller.State_)
    (self_set : AsyncFiller.State_ → M σ Unit) (g : σ → AsyncFiller.State_)
    (hget : ∀ env w, self_get env w = .ok (g w, w))
    (key : PoolKey) (id inputUsed oldInput hook : Nat) (env : Env) (w w' : σ) (r : Nat)
    (h : AsyncMatching.«_settleMatchedPriorityFee» ext self_get self_set key id inputUsed oldInput
        hook env w = .ok (r, w')) :
    r ≤ paidFee ((g w).orders id) ∧
    ((paidFee ((g w).orders id) = 0 ∧ r = 0 ∧ w' = w) ∨
     (oldInput ≠ 0 ∧
      paidFee ((g w).orders id) * inputUsed / oldInput ≤ paidFee ((g w).orders id) ∧
      r + paidFee ((g w).orders id) * inputUsed / oldInput = paidFee ((g w).orders id) ∧
      AsyncFiller.settlePriorityFee ext self_get self_set key id ((g w).orders id).owner
        (paidFee ((g w).orders id) * inputUsed / oldInput) hook env w = .ok ((), w'))) := by
  rw [settleMatchedPriorityFee_run ext self_get self_set g hget] at h
  by_cases h0 : paidFee ((g w).orders id) = 0
  · simp only [h0, ↓reduceIte, Except.ok.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl⟩ := h
    simp [h0]
  simp only [h0, ↓reduceIte] at h
  by_cases hd : oldInput = 0
  · simp [hd] at h
  simp only [hd, ↓reduceIte] at h
  by_cases hb : paidFee ((g w).orders id) * inputUsed / oldInput < 2 ^ 256
  · by_cases hle : paidFee ((g w).orders id) * inputUsed / oldInput ≤ paidFee ((g w).orders id)
    · simp only [hb, hle, ↓reduceIte] at h
      split at h
      · rename_i u w'' hs
        simp only [Except.ok.injEq, Prod.mk.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        refine ⟨Nat.sub_le _ _, Or.inr ⟨hd, hle, Nat.sub_add_cancel hle, ?_⟩⟩
        rw [hs]
      · simp at h
    · simp only [hb, hle, ↓reduceIte] at h; cases h
  · simp only [hb, ↓reduceIte] at h; cases h

end AsyncSwap.Swarm.SettleMatchedPriorityFee
