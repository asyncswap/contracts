import Generated.Router
import Refinement.Monad

/-!
# `Router.matchBook` (src/Router.sol:228)

No guards, no own storage writes: the call is exactly
`POOLMANAGER.unlock(abi.encode(SwapCallback(MatchBook = 4, placeholder, maxMatches)))`, where the
placeholder order is all zeros except its pool key. It reverts iff `unlock` reverts, and on success the
state is whatever `unlock` left (the Router itself writes nothing).
-/

open FormalAst Refinement

namespace Router

variable {σ : Type} (ext : Ext σ)

/-- The calldata `matchBook` hands to `PoolManager.unlock`: action `MatchBook` (4), the key, a zero
placeholder order and `maxMatches`. -/
def matchBookData (key : PoolKey) (maxMatches : Nat) : List Nat :=
  abiEncode [4, key.currency0, key.currency1, key.fee, toUnsigned 256 key.tickSpacing, key.hooks,
    0, 0, 0, 0, 0, 0, 0, maxMatches]

/-- **`Router.matchBook` is exactly one `unlock` call** to `POOLMANAGER` with `matchBookData`, its
result discarded. -/
theorem matchBook_eq (key : PoolKey) (maxMatches : Nat) (env : Env) (w : σ) :
    Router.matchBook ext key maxMatches env w
      = ((fun _ => ()) <$> ext.call_IPoolManager_unlock ext.POOLMANAGER (matchBookData key maxMatches)) env w := by
  simp only [Router.matchBook, matchBookData]
  rfl

/-- **Guards**: `Router.matchBook` reverts exactly when the `unlock` call reverts, with the same error. -/
theorem matchBook_revert_iff (key : PoolKey) (maxMatches : Nat) (env : Env) (w : σ) (e : Revert) :
    Router.matchBook ext key maxMatches env w = .error e
      ↔ ext.call_IPoolManager_unlock ext.POOLMANAGER (matchBookData key maxMatches) env w = .error e := by
  rw [matchBook_eq, run_map]
  rcases ext.call_IPoolManager_unlock ext.POOLMANAGER (matchBookData key maxMatches) env w with _ | ⟨_, _⟩ <;>
    simp

/-- **Footprint / success**: `Router.matchBook` succeeds with final state `w'` exactly when `unlock`
succeeds ending in `w'`; the Router writes no storage of its own. -/
theorem matchBook_ok_iff (key : PoolKey) (maxMatches : Nat) (env : Env) (w w' : σ) :
    Router.matchBook ext key maxMatches env w = .ok ((), w')
      ↔ ∃ r, ext.call_IPoolManager_unlock ext.POOLMANAGER (matchBookData key maxMatches) env w = .ok (r, w') := by
  rw [matchBook_eq, run_map]
  rcases ext.call_IPoolManager_unlock ext.POOLMANAGER (matchBookData key maxMatches) env w with _ | ⟨_, _⟩ <;>
    simp

end Router
