import Mathlib
/-- Capping before division is equivalent to computing the full quotient and then capping.
The branch avoids a potentially overflowing intermediate quotient in bounded-word execution. -/
theorem fill_cap (a b d : Nat) (hd : 0 < d) :
    min (a * b / d) b = if d ≤ a then b else a * b / d := by
  split_ifs with h
  · apply min_eq_right
    exact (Nat.le_div_iff_mul_le hd).2 (by nlinarith)
  · apply min_eq_left
    apply Nat.div_le_of_le_mul
    nlinarith
