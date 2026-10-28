import Generated.AsyncSwap
import Refinement.Monad
open FormalAst Refinement

/-!
# `AsyncSwap.orderCreatedSequence` (src/AsyncSwap.sol:306; plan item 179)

```solidity
function orderCreatedSequence(PoolId poolId, bytes32 id) external view returns (uint64) {
    return asyncOrders[poolId].orders[id].createdSequence;
}
```

Closed form: it never reverts, leaves the world unchanged and returns
`asyncOrders[poolId].orders[id].createdSequence`.
-/

namespace AsyncSwap
variable {σ : Type} (ext : Ext σ)

/-- Exact semantics: always succeeds with the stored `createdSequence`, world unchanged. -/
theorem orderCreatedSequence_run (poolId id : Nat) (r : Env) (s : σ) :
    AsyncSwap.orderCreatedSequence ext poolId id r s
      = .ok ((((ext.get s).asyncOrders poolId).orders id).createdSequence, s) := rfl

/-- Totality: no caller, environment, argument or state makes it revert. -/
theorem orderCreatedSequence_never_reverts (poolId id : Nat) (r : Env) (s : σ) (e : FormalAst.Revert) :
    AsyncSwap.orderCreatedSequence ext poolId id r s ≠ .error e := by
  rw [orderCreatedSequence_run]; simp

/-- Frame and return value: a successful run writes nothing and returns the stored field. -/
theorem orderCreatedSequence_ok (poolId id : Nat) (r : Env) (s s' : σ) (v : Nat)
    (hok : AsyncSwap.orderCreatedSequence ext poolId id r s = .ok (v, s')) :
    s' = s ∧ v = (((ext.get s).asyncOrders poolId).orders id).createdSequence := by
  rw [orderCreatedSequence_run] at hok
  cases hok
  exact ⟨rfl, rfl⟩

end AsyncSwap
