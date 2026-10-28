import Specs.AsyncSwap
import Proofs.Monad
open FormalAst Refinement

/-!
# `AsyncSwap.setDefaultMinOrder` (src/AsyncSwap.sol:262)

```solidity
function setDefaultMinOrder(uint256 minimum) external onlyOwner { defaultMinOrder = minimum; }
```

Closed form: run in environment `r` on world `s`, the call reverts with `NotOwner` unless
`r.sender = owner`, and otherwise returns `()` having written exactly `defaultMinOrder := minimum`.
-/

namespace AsyncSwap
variable {σ : Type} (ext : Ext σ)

/-- Exact semantics: guard `msg.sender == owner`, single write `defaultMinOrder := minimum`. -/
theorem setDefaultMinOrder_run (minimum : Nat) (r : Env) (s : σ) :
    AsyncSwap.setDefaultMinOrder ext minimum r s =
      if r.sender = (ext.get s).owner then
        .ok ((), ext.set s { ext.get s with defaultMinOrder := minimum })
      else .error ⟨"NotOwner"⟩ := by
  unfold AsyncSwap.setDefaultMinOrder AsyncSwap.onlyOwner
  by_cases h : r.sender = (ext.get s).owner <;> simp [h]

/-- Guard: a caller other than `owner` makes the call revert with `NotOwner`. -/
theorem setDefaultMinOrder_reverts_of_not_owner (minimum : Nat) (r : Env) (s : σ)
    (h : r.sender ≠ (ext.get s).owner) :
    AsyncSwap.setDefaultMinOrder ext minimum r s = .error ⟨"NotOwner"⟩ := by
  rw [setDefaultMinOrder_run]; simp [h]

/-- Effect: called by `owner`, it returns `()` and writes only `defaultMinOrder := minimum`. -/
theorem setDefaultMinOrder_ok_of_owner (minimum : Nat) (r : Env) (s : σ)
    (h : r.sender = (ext.get s).owner) :
    AsyncSwap.setDefaultMinOrder ext minimum r s =
      .ok ((), ext.set s { ext.get s with defaultMinOrder := minimum }) := by
  rw [setDefaultMinOrder_run]; simp [h]

/-- The call succeeds iff the caller is `owner`; on success the post-world is the single write. -/
theorem setDefaultMinOrder_ok_iff (minimum : Nat) (r : Env) (s s' : σ) (u : Unit) :
    AsyncSwap.setDefaultMinOrder ext minimum r s = .ok (u, s') ↔
      r.sender = (ext.get s).owner ∧
        s' = ext.set s { ext.get s with defaultMinOrder := minimum } := by
  rw [setDefaultMinOrder_run]
  by_cases h : r.sender = (ext.get s).owner
  · simp [h]; constructor <;> intro hh <;> simp_all
  · simp [h]

/-- Frame: on success the contract state read back (under a lawful `Ext`) differs from the old
one only in `defaultMinOrder`, which now equals `minimum`; in particular `owner` is unchanged. -/
theorem setDefaultMinOrder_frame (minimum : Nat) (r : Env) (s s' : σ) (u : Unit)
    (hget : ∀ w st, ext.get (ext.set w st) = st)
    (hok : AsyncSwap.setDefaultMinOrder ext minimum r s = .ok (u, s')) :
    ext.get s' = { ext.get s with defaultMinOrder := minimum } ∧
      (ext.get s').defaultMinOrder = minimum ∧
      (ext.get s').owner = (ext.get s).owner := by
  obtain ⟨_, rfl⟩ := (setDefaultMinOrder_ok_iff ext minimum r s s' u).1 hok
  simp [hget]

end AsyncSwap
