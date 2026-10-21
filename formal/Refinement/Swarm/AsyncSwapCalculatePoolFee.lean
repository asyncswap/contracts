import Generated.AsyncSwap
import Refinement.Monad

/-!
# `AsyncSwap.calculatePoolFee`

`function calculatePoolFee(uint24, uint256 amount) public pure returns (uint256)`
(src/AsyncSwap.sol:315): `(amount / 997) * 3 + ((amount % 997) * 3) / 997`.

* Guards: none reachable. The only reverts are checked-arithmetic panics `0x11`, and for any
  `amount < 2^256` (every ABI `uint256`) none of the intermediate terms overflows.
* Footprint: reads and writes nothing (the world is returned unchanged).
* Return: `amount * 3 / 997` (30 bps of gross, rounded down), which is `≤ amount`.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.CalculatePoolFee

variable {σ : Type} (ext : Ext σ)

/-- The expression as written in the source. -/
def pf (a : Nat) : Nat := a / 997 * 3 + a % 997 * 3 / 997

/-- The split form equals the naive `amount * 3 / 997`. -/
theorem pf_eq (a : Nat) : pf a = a * 3 / 997 := by unfold pf; omega

theorem pf_le (a : Nat) : pf a ≤ a := by unfold pf; omega

/-- Exact behaviour for any `Nat` argument: panic iff the result overflows, otherwise
returns `pf amount` and leaves the world unchanged. -/
theorem calculatePoolFee_run (f a : Nat) (env : Env) (w : σ) :
    AsyncSwap.calculatePoolFee ext f a env w =
      if pf a < 2 ^ 256 then .ok (pf a, w) else .error (panic "0x11") := by
  unfold pf
  simp only [AsyncSwap.calculatePoolFee, divc, modc, mulc, addc, run_bind, run_ite, run_pure,
    run_throw]
  have h2 : a % 997 * 3 < 2 ^ 256 := by omega
  by_cases h : a / 997 * 3 + a % 997 * 3 / 997 < 2 ^ 256
  · have h1 : a / 997 * 3 < 2 ^ 256 := by omega
    simp [h, h1, h2]
  · by_cases h1 : a / 997 * 3 < 2 ^ 256 <;> simp [h, h1, h2]

/-- For every `uint256` amount it never reverts, writes nothing and returns
`amount * 3 / 997`. -/
theorem calculatePoolFee_ok (f a : Nat) (ha : a < 2 ^ 256) (env : Env) (w : σ) :
    AsyncSwap.calculatePoolFee ext f a env w = .ok (a * 3 / 997, w) := by
  rw [calculatePoolFee_run, ← pf_eq]
  have : pf a < 2 ^ 256 := Nat.lt_of_le_of_lt (pf_le a) ha
  simp [this]

/-- The returned fee never exceeds the amount, and the world is unchanged. -/
theorem calculatePoolFee_le (f a : Nat) (ha : a < 2 ^ 256) (env : Env) (w : σ) (r : Nat) (w' : σ)
    (h : AsyncSwap.calculatePoolFee ext f a env w = .ok (r, w')) : r ≤ a ∧ w' = w := by
  rw [calculatePoolFee_ok ext f a ha] at h
  cases h
  exact ⟨by omega, rfl⟩

end AsyncSwap.Swarm.CalculatePoolFee
