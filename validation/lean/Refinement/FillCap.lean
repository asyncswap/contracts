/-- Capping before division is equivalent to computing the full quotient and then capping.
The branch avoids a potentially overflowing intermediate quotient in bounded-word execution. -/
theorem fill_cap (a b d : Nat) (hd : 0 < d) :
    min (a * b / d) b = if d ≤ a then b else a * b / d := by
  by_cases h : d ≤ a
  · rw [if_pos h]
    apply Nat.min_eq_right
    apply (Nat.le_div_iff_mul_le hd).2
    have := Nat.mul_le_mul_left b h
    rw [Nat.mul_comm a b]; exact this
  · rw [if_neg h]
    apply Nat.min_eq_left
    apply Nat.div_le_of_le_mul
    exact Nat.mul_le_mul_right b (Nat.le_of_lt (Nat.lt_of_not_le h))
