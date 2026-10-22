import Mathlib
import Generated.AsyncSwap
import Refinement.Monad

/-!
# AsyncMatching._crosses

`_crosses(buyKey, sellKey, buy, sell)`: with distinct price keys the buy crosses iff its key is
higher; with equal keys it compares `mulDiv(buy.amountIn, sell.amountIn, sell.amountOutMin)` with
`buy.amountOutMin`. It has no guards of its own; the only reverts come from `Math.mulDiv`
(`sell.amountOutMin = 0` → panic 0x12, quotient ≥ 2^256 → `MathOverflowedMulDiv`). It writes nothing.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.Crosses

variable {σ : Type} (ext : Ext σ)

/-- Full run with pure readers of the two orders (as the storage-pointer getters are). -/
theorem crosses_run (bk sk : Nat) (b s : AsyncFiller.OrderInfo)
    (bs : AsyncFiller.OrderInfo → M σ Unit) (ss : AsyncFiller.OrderInfo → M σ Unit)
    (env : Env) (w : σ) :
    AsyncMatching.«_crosses» ext bk sk (pure b) bs (pure s) ss env w
      = if bk ≠ sk then .ok (decide (bk > sk), w)
        else if s.amountOutMin = 0 then .error (panic "0x12")
        else if b.amountIn * s.amountIn / s.amountOutMin < 2 ^ 256 then
          .ok (decide (b.amountIn * s.amountIn / s.amountOutMin ≥ b.amountOutMin), w)
        else .error ⟨"MathOverflowedMulDiv"⟩ := by
  by_cases h : bk = sk
  · subst h
    by_cases hd : s.amountOutMin = 0
    · simp [AsyncMatching.«_crosses», mulDivFloor, hd]
    · by_cases ho : b.amountIn * s.amountIn / s.amountOutMin < 2 ^ 256
      · have ho' := ho; norm_num at ho'
        simp [AsyncMatching.«_crosses», mulDivFloor, hd, ho']
      · have ho' := ho; norm_num at ho'
        simp [AsyncMatching.«_crosses», mulDivFloor, hd, Nat.not_lt.mpr ho']
  · simp [AsyncMatching.«_crosses», h]

/-- Distinct keys: never reverts, returns `buyKey > sellKey`, reads nothing, writes nothing. -/
theorem crosses_ne_any (bk sk : Nat) (bg : M σ AsyncFiller.OrderInfo)
    (bs : AsyncFiller.OrderInfo → M σ Unit) (sg : M σ AsyncFiller.OrderInfo)
    (ss : AsyncFiller.OrderInfo → M σ Unit) (env : Env) (w : σ) (h : bk ≠ sk) :
    AsyncMatching.«_crosses» ext bk sk bg bs sg ss env w = .ok (decide (bk > sk), w) := by
  simp [AsyncMatching.«_crosses», h]

/-- Equal keys and `sell.amountOutMin = 0`: reverts with panic 0x12 (division by zero). -/
theorem crosses_reverts_div0 (k : Nat) (b s : AsyncFiller.OrderInfo)
    (bs : AsyncFiller.OrderInfo → M σ Unit) (ss : AsyncFiller.OrderInfo → M σ Unit)
    (env : Env) (w : σ) (hd : s.amountOutMin = 0) :
    AsyncMatching.«_crosses» ext k k (pure b) bs (pure s) ss env w = .error (panic "0x12") := by
  rw [crosses_run]; simp [hd]

/-- Equal keys and an overflowing quotient: reverts `MathOverflowedMulDiv`. -/
theorem crosses_reverts_overflow (k : Nat) (b s : AsyncFiller.OrderInfo)
    (bs : AsyncFiller.OrderInfo → M σ Unit) (ss : AsyncFiller.OrderInfo → M σ Unit)
    (env : Env) (w : σ) (hd : s.amountOutMin ≠ 0)
    (ho : 2 ^ 256 ≤ b.amountIn * s.amountIn / s.amountOutMin) :
    AsyncMatching.«_crosses» ext k k (pure b) bs (pure s) ss env w
      = .error ⟨"MathOverflowedMulDiv"⟩ := by
  rw [crosses_run]
  have ho' := ho; norm_num at ho'
  simp [hd, Nat.not_lt.mpr ho']

/-- Frame: for any readers that do not change storage, a successful `_crosses` leaves the
state unchanged (the setters are never called). -/
theorem crosses_frame (bk sk : Nat) (bg : M σ AsyncFiller.OrderInfo)
    (bs : AsyncFiller.OrderInfo → M σ Unit) (sg : M σ AsyncFiller.OrderInfo)
    (ss : AsyncFiller.OrderInfo → M σ Unit) (env : Env) (w w' : σ) (r : Bool)
    (hbg : ∀ w₀ o w₁, bg env w₀ = .ok (o, w₁) → w₁ = w₀)
    (hsg : ∀ w₀ o w₁, sg env w₀ = .ok (o, w₁) → w₁ = w₀)
    (h : AsyncMatching.«_crosses» ext bk sk bg bs sg ss env w = .ok (r, w')) : w' = w := by
  by_cases hk : bk = sk
  · subst hk
    unfold AsyncMatching.«_crosses» at h
    simp only [bne_self_eq_false, Bool.false_eq_true, ite_false] at h
    simp only [run_bind] at h
    rcases h1 : bg env w with e | ⟨o1, w1⟩
    · rw [h1] at h; cases h
    rw [h1] at h; simp only at h
    have e1 := hbg _ _ _ h1
    rcases h2 : sg env w1 with e | ⟨o2, w2⟩
    · rw [h2] at h; cases h
    rw [h2] at h; simp only at h
    have e2 := hsg _ _ _ h2
    rcases h3 : sg env w2 with e | ⟨o3, w3⟩
    · rw [h3] at h; cases h
    rw [h3] at h; simp only at h
    have e3 := hsg _ _ _ h3
    rcases h4 : mulDivFloor (σ := σ) o1.amountIn o2.amountIn o3.amountOutMin env w3 with
      e | ⟨p, w4⟩
    · rw [h4] at h; cases h
    rw [h4] at h; simp only at h
    have e4 : w4 = w3 := by
      unfold mulDivFloor at h4; split_ifs at h4 <;> cases h4; rfl
    rcases h5 : bg env w4 with e | ⟨o5, w5⟩
    · rw [h5] at h; cases h
    rw [h5] at h; simp only [run_pure] at h
    have e5 := hbg _ _ _ h5
    cases h
    subst e1 e2 e3 e4 e5; rfl
  · rw [crosses_ne_any ext bk sk bg bs sg ss env w hk] at h
    cases h; rfl

end AsyncSwap.Swarm.Crosses
