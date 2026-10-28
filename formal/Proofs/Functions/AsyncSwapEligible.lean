import Specs.AsyncSwap
import Proofs.Monad
open FormalAst

/-!
# `EligiblePrice._eligible` (src/AsyncSwap.sol)

`_eligible(bound, limit, isBuy)` returns `le(limit, bound)` on the buy side and `le(bound, limit)`
on the sell side. It has no `require` of its own and touches no storage: everything it does is the
single comparison call `ext.fn_EligiblePrice_le_12578`.
-/

namespace AsyncSwap.Swarm.Eligible

variable {σ : Type}

/-- **Exact behaviour.** `_eligible` is, as a program, exactly the oriented comparison. -/
theorem eligible_eq (ext : Ext σ) (bound limit : EligiblePrice.Ratio) (isBuy : Bool) :
    EligiblePrice.«_eligible» ext bound limit isBuy =
      (if isBuy then ext.fn_EligiblePrice_le_12578 limit bound
       else ext.fn_EligiblePrice_le_12578 bound limit) := by
  cases isBuy <;> simp [EligiblePrice.«_eligible»]

/-- **Reverts.** `_eligible` reverts with `e` iff the oriented comparison reverts with `e`. -/
theorem eligible_reverts_iff (ext : Ext σ) (bound limit : EligiblePrice.Ratio) (isBuy : Bool)
    (r : Env) (s : σ) (e : Revert) :
    EligiblePrice.«_eligible» ext bound limit isBuy r s = .error e ↔
      (if isBuy then ext.fn_EligiblePrice_le_12578 limit bound r s
       else ext.fn_EligiblePrice_le_12578 bound limit r s) = .error e := by
  rw [eligible_eq]; cases isBuy <;> rfl

/-- **Footprint and result.** If the comparison never reverts and leaves the state unchanged
(it is a pure view of its arguments), `_eligible` never reverts, writes nothing, and returns the
comparison's value: `limit ≤ bound` for buys, `bound ≤ limit` for sells. -/
theorem eligible_ok (ext : Ext σ) (bound limit : EligiblePrice.Ratio) (isBuy : Bool)
    (leF : EligiblePrice.Ratio → EligiblePrice.Ratio → Bool)
    (hle : ∀ a b r s, ext.fn_EligiblePrice_le_12578 a b r s = .ok (leF a b, s))
    (r : Env) (s : σ) :
    EligiblePrice.«_eligible» ext bound limit isBuy r s =
      .ok ((if isBuy then leF limit bound else leF bound limit), s) := by
  rw [eligible_eq]; cases isBuy <;> simp [hle]

/-- **No revert of its own.** If the comparison never reverts, neither does `_eligible`. -/
theorem eligible_never_reverts (ext : Ext σ) (bound limit : EligiblePrice.Ratio) (isBuy : Bool)
    (hle : ∀ a b r s, ∃ v s', ext.fn_EligiblePrice_le_12578 a b r s = .ok (v, s'))
    (r : Env) (s : σ) :
    ∃ v s', EligiblePrice.«_eligible» ext bound limit isBuy r s = .ok (v, s') := by
  rw [eligible_eq]; cases isBuy <;> simpa using hle _ _ r s

end AsyncSwap.Swarm.Eligible
