import Specs.AsyncSwap
import Proofs.Monad
import Proofs.Functions.AsyncSwapGetTickAtSqrtPrice
open FormalAst Refinement

/-!
# `TickMath.getTickAtSqrtPrice` on its range (src/AsyncSwap.sol)

* `logR_bounds`: the Q64.64 `log_2` built by the 14-rung squaring ladder satisfies
  `(msb-128)·2^64 ≤ L ≤ (msb-128)·2^64 + 2^64 - 2^50` (bits 63..50 are set exactly by OR = add).
* `ticks_bounds`: on `-64·2^64 ≤ L ≤ 64·2^64 - 2^50`, `tickHi ∈ [-887272, 887272]` and
  `tickHi - 1 ≤ tickLow ≤ tickHi`.
* `getTickAtSqrtPrice_bounded`: on `[MIN_SQRT_PRICE, MAX_SQRT_PRICE)` it succeeds, leaves the state
  unchanged and returns a tick in `[MIN_TICK, MAX_TICK]`.

Split out of `AsyncSwapKey` so that `AsyncSwapFloorTick` (which `AsyncSwapKey` imports) can use it.
-/

namespace AsyncSwap.Swarm.TickBounds

open AsyncSwap.Swarm.GetTickAtSqrtPrice AsyncSwap.Swarm.MostSignificantBit
open AsyncSwap.Swarm.GetSqrtPriceAtTick (absTickOf absTickOf_eq toUnsigned_cast)

theorem wrapI256_id (x : Int) (h1 : -2 ^ 255 ≤ x) (h2 : x < 2 ^ 255) : wrapI 256 x = x := by
  simp only [wrapI, Nat.reduceSub]
  split <;> omega

theorem wrapI24_id (x : Int) (h1 : -2 ^ 23 ≤ x) (h2 : x < 2 ^ 23) : wrapI 24 x = x := by
  simp only [wrapI, Nat.reduceSub]
  split <;> omega

theorem ts_tu (x : Int) (h1 : -2 ^ 255 ≤ x) (h2 : x < 2 ^ 255) :
    toSigned 256 (toUnsigned 256 x) = x := by
  have hc := toUnsigned_cast x
  generalize toUnsigned 256 x = u at hc ⊢
  simp only [toSigned, wrapI, Nat.reduceSub]
  split <;> omega

theorem tu_ts (V : Nat) (h : V < 2 ^ 256) : toUnsigned 256 (toSigned 256 V) = V := by
  have hc := toUnsigned_cast (toSigned 256 V)
  generalize toUnsigned 256 (toSigned 256 V) = u at hc ⊢
  simp only [toSigned, wrapI, Nat.reduceSub] at hc
  split at hc <;> omega

/-- The rung on its squared value `x < 2^129`: the overflow bit is 0 or 1, the halved value stays
below `2^128`, and the log gets `0` or `2^k` ORed in. -/
theorem rung_x (k : Nat) (hk : k < 64) (x : Nat) (L : Int) (hx : x < 2 ^ 129) :
    yshr (yshr 128 x) x < 2 ^ 128 ∧ ∃ g, (g = 0 ∨ g = 2 ^ k) ∧
      toSigned 256 (yor (toUnsigned 256 L) (yshl k (yshr 128 x)))
        = toSigned 256 (toUnsigned 256 L ||| g) := by
  have h128 : yshr 128 x = x / 2 ^ 128 := by
    simp [yshr, Nat.shiftRight_eq_div_pow]
  have hf : x / 2 ^ 128 = 0 ∨ x / 2 ^ 128 = 1 := by omega
  rw [h128]
  rcases hf with hf | hf
  · rw [hf]
    refine ⟨?_, 0, Or.inl rfl, ?_⟩
    · simp only [yshr, show (0 : Nat) < 256 from by decide, ite_true, Nat.shiftRight_zero]
      omega
    · simp [yshl, yor]
  · rw [hf]
    refine ⟨?_, 2 ^ k, Or.inr rfl, ?_⟩
    · simp only [yshr, show (1 : Nat) < 256 from by decide, ite_true, Nat.shiftRight_eq_div_pow]
      omega
    · have hk2 : (2 : Nat) ^ k < W := by
        unfold W; exact Nat.pow_lt_pow_right (by decide) (by omega)
      simp only [yshl, yor, show k < 256 by omega, ite_true, Nat.one_shiftLeft,
        Nat.mod_eq_of_lt hk2]

/-- One rung keeps `r < 2^128` and ORs either `0` or `2^k` into the log. -/
theorem rung_spec (k : Nat) (hk : k < 64) (r : Nat) (L : Int) (hr : r < 2 ^ 128) :
    (rung k (r, L)).1 < 2 ^ 128 ∧ ∃ g, (g = 0 ∨ g = 2 ^ k) ∧
      (rung k (r, L)).2 = toSigned 256 (toUnsigned 256 L ||| g) := by
  have hrr : r * r < 2 ^ 256 := by
    have h := Nat.mul_self_lt_mul_self hr
    have e : (2 : Nat) ^ 128 * 2 ^ 128 = 2 ^ 256 := by rw [← Nat.pow_add]
    omega
  have hm : ymul r r = r * r := by unfold ymul W; exact Nat.mod_eq_of_lt hrr
  have hx : yshr 127 (ymul r r) < 2 ^ 129 := by
    rw [hm]
    simp only [yshr, show (127 : Nat) < 256 from by decide, ite_true, Nat.shiftRight_eq_div_pow]
    have e : (2 : Nat) ^ 129 * 2 ^ 127 = 2 ^ 256 := by rw [← Nat.pow_add]
    exact (Nat.div_lt_iff_lt_mul (Nat.two_pow_pos _)).2 (by omega)
  have e : rung k (r, L) = (yshr (yshr 128 (yshr 127 (ymul r r))) (yshr 127 (ymul r r)),
      toSigned 256 (yor (toUnsigned 256 L) (yshl k (yshr 128 (yshr 127 (ymul r r)))))) := rfl
  rw [e]
  exact rung_x k hk _ L hx

/-- Ladder invariant after the bits `≥ j` are set. -/
def Inv (U0 j : Nat) (st : Nat × Int) : Prop :=
  st.1 < 2 ^ 128 ∧ st.2 = toSigned 256 (toUnsigned 256 st.2) ∧ 2 ^ j ∣ toUnsigned 256 st.2 ∧
    U0 ≤ toUnsigned 256 st.2 ∧ toUnsigned 256 st.2 + 2 ^ j ≤ U0 + 2 ^ 64

theorem inv_step (U0 k : Nat) (hk : k < 64) (hU0 : U0 + 2 ^ 64 ≤ 2 ^ 256) (st : Nat × Int)
    (h : Inv U0 (k + 1) st) : Inv U0 k (rung k st) := by
  obtain ⟨r, L⟩ := st
  obtain ⟨hr, _, hd, hlo, hhi⟩ := h
  obtain ⟨h1, g, hg, h2⟩ := rung_spec k hk r L hr
  simp only at hd hlo hhi
  generalize toUnsigned 256 L = U at hd hlo hhi h2
  have hp : (2 : Nat) ^ (k + 1) = 2 * 2 ^ k := by rw [Nat.pow_succ]; omega
  have hpos : 0 < (2 : Nat) ^ k := Nat.two_pow_pos k
  have hor : U ||| g = U + g := by
    rcases hg with rfl | rfl
    · simp
    · exact or_eq_add (k + 1) U (2 ^ k) hd (Nat.pow_lt_pow_right (by decide) (by omega))
  have hlt : U + g < 2 ^ 256 := by rcases hg with rfl | rfl <;> omega
  rw [hor] at h2
  have hdk : 2 ^ k ∣ U + g := by
    refine Nat.dvd_add (Nat.dvd_trans (Nat.pow_dvd_pow 2 (Nat.le_succ k)) hd) ?_
    rcases hg with rfl | rfl
    · exact Nat.dvd_zero _
    · exact Nat.dvd_refl _
  refine ⟨h1, ?_, ?_, ?_, ?_⟩ <;> rw [h2, tu_ts _ hlt]
  · exact hdk
  · omega
  · rcases hg with rfl | rfl <;> omega

theorem log0_eq (msb : Nat) (hm : msb < 256) : log0 msb = ((msb : Int) - 128) * 2 ^ 64 := by
  have h1 : toSigned 256 msb = (msb : Int) := by
    simp only [toSigned]; exact wrapI256_id _ (by omega) (by omega)
  unfold log0
  rw [h1, wrapI256_id ((msb : Int) - 128) (by omega) (by omega)]
  rw [wrapI256_id _ (by omega) (by omega)]
  simp

/-- **The log ladder's range.** -/
theorem logR_bounds (r msb : Nat) (hr : r < 2 ^ 128) (hm1 : 64 ≤ msb) (hm2 : msb ≤ 191) :
    ((msb : Int) - 128) * 2 ^ 64 ≤ logR r msb ∧
      logR r msb ≤ ((msb : Int) - 128) * 2 ^ 64 + 2 ^ 64 - 2 ^ 50 := by
  have hB := log0_eq msb (by omega)
  have hc := toUnsigned_cast (log0 msb)
  have hU0 : toUnsigned 256 (log0 msb) + 2 ^ 64 ≤ 2 ^ 256 := by omega
  have hd0 : 2 ^ 64 ∣ toUnsigned 256 (log0 msb) := by
    have : ((2 ^ 64 : Nat) : Int) ∣ ((toUnsigned 256 (log0 msb) : Nat) : Int) := by
      rw [hc]; omega
    exact Int.natCast_dvd_natCast.mp this
  have i64 : Inv (toUnsigned 256 (log0 msb)) 64 (r, log0 msb) := by
    refine ⟨hr, ?_, hd0, Nat.le_refl _, Nat.le_refl _⟩
    simp only
    rw [hB, ts_tu _ (by omega) (by omega)]
  have i63 := inv_step _ 63 (by decide) hU0 _ i64
  have i62 := inv_step _ 62 (by decide) hU0 _ i63
  have i61 := inv_step _ 61 (by decide) hU0 _ i62
  have i60 := inv_step _ 60 (by decide) hU0 _ i61
  have i59 := inv_step _ 59 (by decide) hU0 _ i60
  have i58 := inv_step _ 58 (by decide) hU0 _ i59
  have i57 := inv_step _ 57 (by decide) hU0 _ i58
  have i56 := inv_step _ 56 (by decide) hU0 _ i57
  have i55 := inv_step _ 55 (by decide) hU0 _ i56
  have i54 := inv_step _ 54 (by decide) hU0 _ i55
  have i53 := inv_step _ 53 (by decide) hU0 _ i54
  have i52 := inv_step _ 52 (by decide) hU0 _ i53
  have i51 := inv_step _ 51 (by decide) hU0 _ i52
  have i50 := inv_step _ 50 (by decide) hU0 _ i51
  have e : logR r msb = (rung 50 (rung 51 (rung 52 (rung 53 (rung 54 (rung 55 (rung 56 (rung 57
      (rung 58 (rung 59 (rung 60 (rung 61 (rung 62 (rung 63 (r, log0 msb))))))))))))))).2 := rfl
  rw [e]
  generalize (rung 50 (rung 51 (rung 52 (rung 53 (rung 54 (rung 55 (rung 56 (rung 57
      (rung 58 (rung 59 (rung 60 (rung 61 (rung 62 (rung 63 (r, log0 msb))))))))))))))) = st at i50
  obtain ⟨_, hL, _, hlo, hhi⟩ := i50
  rw [hL]
  generalize toUnsigned 256 st.2 = U at hlo hhi
  generalize toUnsigned 256 (log0 msb) = U0 at hc hlo hhi
  simp only [toSigned, wrapI, Nat.reduceSub]
  split <;> omega

/-- **The candidate ticks' range.** -/
theorem ticks_bounds (L : Int) (h1 : -64 * 2 ^ 64 ≤ L) (h2 : L ≤ 64 * 2 ^ 64 - 2 ^ 50) :
    -887272 ≤ tickHiOf L ∧ tickHiOf L ≤ 887272 ∧ tickHiOf L - 1 ≤ tickLowOf L ∧
      tickLowOf L ≤ tickHiOf L := by
  unfold tickHiOf tickLowOf
  rw [wrapI256_id (L * 255738958999603826347141) (by omega) (by omega)]
  rw [wrapI256_id (L * 255738958999603826347141 + 291339464771989622907027621153398088495)
    (by omega) (by omega)]
  rw [wrapI256_id (L * 255738958999603826347141 - 3402992956809132418596140100660247210)
    (by omega) (by omega)]
  rw [wrapI24_id _ (by omega) (by omega), wrapI24_id _ (by omega) (by omega)]
  omega

theorem sqrt_min :
    AsyncSwap.Swarm.GetSqrtPriceAtTick.sqrtPure (-887272) = TickMath.MIN_SQRT_PRICE := by
  decide +kernel

theorem norm_lt (x msb : Nat) (h2 : x < 2 ^ (msb + 1)) (hm : msb < 256) : norm x msb < 2 ^ 128 := by
  unfold norm
  split
  · rename_i h
    have hs : subw 256 msb 127 = msb - 127 := by unfold subw; omega
    rw [hs, Nat.shiftRight_eq_div_pow]
    apply (Nat.div_lt_iff_lt_mul (Nat.two_pow_pos _)).2
    rw [← Nat.pow_add, show 128 + (msb - 127) = msb + 1 by omega]
    exact h2
  · rename_i h
    have hs : subw 256 127 msb = 127 - msb := by unfold subw; omega
    rw [hs]
    unfold shlw
    apply Nat.lt_of_le_of_lt (Nat.mod_le _ _)
    rw [Nat.shiftLeft_eq]
    have := Nat.mul_lt_mul_of_pos_right h2 (Nat.two_pow_pos (127 - msb))
    rw [← Nat.pow_add, show msb + 1 + (127 - msb) = 128 by omega] at this
    exact this

/-- **The log of an in-range sqrt price.** -/
theorem logOf_bounds (p : Nat) (hp : p < 2 ^ 160) (hmin : TickMath.MIN_SQRT_PRICE ≤ p) :
    -64 * 2 ^ 64 ≤ logOf p ∧ logOf p ≤ 64 * 2 ^ 64 - 2 ^ 50 := by
  have hx : priceOf p = p * 2 ^ 32 := by
    unfold priceOf shlw
    rw [Nat.shiftLeft_eq, Nat.mod_eq_of_lt (by omega)]
  unfold TickMath.MIN_SQRT_PRICE at hmin
  have hx1 : 2 ^ 64 ≤ priceOf p := by rw [hx]; omega
  have hx2 : priceOf p < 2 ^ 192 := by rw [hx]; omega
  obtain ⟨s1, s2⟩ := msbPure_spec (priceOf p) (by omega) (by omega)
  unfold logOf
  generalize msbPure (priceOf p) = m at s1 s2 ⊢
  have hm1 : 64 ≤ m := by
    rcases Nat.lt_or_ge m 64 with hc | hc
    · have : 2 ^ (m + 1) ≤ 2 ^ 64 := Nat.pow_le_pow_right (by decide) (by omega)
      omega
    · exact hc
  have hm2 : m ≤ 191 := by
    rcases Nat.lt_or_ge m 192 with hc | hc
    · omega
    · have : 2 ^ 192 ≤ 2 ^ m := Nat.pow_le_pow_right (by decide) hc
      omega
  have hb := logR_bounds (norm (priceOf p) m) m (norm_lt _ _ s2 (by omega)) hm1 hm2
  omega

/-- **`getTickAtSqrtPrice` on its range.** For `MIN_SQRT_PRICE ≤ p < MAX_SQRT_PRICE` it never
reverts, never writes, and returns a tick in `[MIN_TICK, MAX_TICK]`. -/
theorem getTickAtSqrtPrice_bounded {σ : Type} (ext : Ext σ) (p : Nat) (env : Env) (s : σ)
    (hmin : TickMath.MIN_SQRT_PRICE ≤ p) (hmax : p < TickMath.MAX_SQRT_PRICE) :
    ∃ t, TickMath.getTickAtSqrtPrice ext p env s = .ok (t, s) ∧
      TickMath.MIN_TICK ≤ t ∧ t ≤ TickMath.MAX_TICK := by
  have hp : p < 2 ^ 160 := by unfold TickMath.MAX_SQRT_PRICE at hmax; omega
  obtain ⟨hL1, hL2⟩ := logOf_bounds p hp hmin
  obtain ⟨a, b, c, d⟩ := ticks_bounds _ hL1 hL2
  rw [getTickAtSqrtPrice_run ext p env s hp hmin hmax]
  generalize tickLowOf (logOf p) = tl at a b c d ⊢
  generalize tickHiOf (logOf p) = th at a b c d ⊢
  simp only [TickMath.MIN_TICK, TickMath.MAX_TICK]
  by_cases he : tl = th
  · rw [ite_eq_left he]; exact ⟨_, rfl, by omega, by omega⟩
  rw [ite_eq_right he]
  have habs : absTickOf th = th.natAbs := absTickOf_eq th (by omega) (by omega)
  rw [habs, ite_eq_right (show ¬ th.natAbs > 887272 by omega)]
  by_cases hle : AsyncSwap.Swarm.GetSqrtPriceAtTick.sqrtPure th ≤ p
  · rw [ite_eq_left hle]; exact ⟨_, rfl, by omega, by omega⟩
  · rw [ite_eq_right hle]
    have hne : tl ≠ -887273 := by
      intro h
      have hth : th = -887272 := by omega
      rw [hth, sqrt_min] at hle
      exact hle hmin
    exact ⟨_, rfl, by omega, by omega⟩

end AsyncSwap.Swarm.TickBounds
