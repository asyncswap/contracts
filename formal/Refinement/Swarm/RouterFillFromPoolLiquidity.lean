import Generated.Router
import Refinement.Monad
import Refinement.Router

/-!
# `Router.fillFromPoolLiquidity` (src/Router.sol:238)

No guards and no persistent storage writes. The call does two transient stores,
`USER_LOCATION := msg.sender` and `ASYNC_FILLER_LOCATION := address(this)`, then a single
`POOLMANAGER.unlock(abi.encode(SwapCallback(PoolLiquidityFill = 5, order, 0))))`. It reverts exactly
when `unlock` reverts. On success the final state is whatever `unlock` leaves, starting from the
state after the two transient stores.
-/

open FormalAst Refinement

namespace Router

variable {σ : Type} (ext : Ext σ)

/-- The state `unlock` starts from: the caller and `address(this)` recorded in transient storage. -/
def fillFromPoolLiquidityPre (env : Env) (w : σ) : σ :=
  tstore ext (tstore ext w Router.USER_LOCATION env.sender) Router.ASYNC_FILLER_LOCATION env.self

/-- **`Router.fillFromPoolLiquidity` is exactly two transient stores and one `unlock` call**:
it calls `POOLMANAGER` with `SwapCallback(PoolLiquidityFill = 5, order, maxMatches = 0)`, encoded
word by word, and ignores the result. -/
theorem fillFromPoolLiquidity_eq (order : AsyncOrder) (env : Env) (w : σ) :
    Router.fillFromPoolLiquidity ext order env w
      = ((fun _ => ()) <$> ext.call_IPoolManager_unlock ext.POOLMANAGER (callbackData 5 order 0)) env
          (fillFromPoolLiquidityPre ext env w) := by
  simp only [Router.fillFromPoolLiquidity, fillFromPoolLiquidityPre, callbackData, tstore]
  rfl

/-- **Guards**: `Router.fillFromPoolLiquidity` reverts exactly when `unlock` reverts, with the same
error. The Router checks nothing itself. -/
theorem fillFromPoolLiquidity_revert_iff (order : AsyncOrder) (env : Env) (w : σ) (e : Revert) :
    Router.fillFromPoolLiquidity ext order env w = .error e
      ↔ ext.call_IPoolManager_unlock ext.POOLMANAGER (callbackData 5 order 0) env
          (fillFromPoolLiquidityPre ext env w) = .error e := by
  rw [fillFromPoolLiquidity_eq, run_map]
  rcases ext.call_IPoolManager_unlock ext.POOLMANAGER (callbackData 5 order 0) env
    (fillFromPoolLiquidityPre ext env w) with _ | ⟨_, _⟩ <;> simp

/-- **Footprint / success**: `Router.fillFromPoolLiquidity` ends in `w'` exactly when `unlock`, run
from the state with the two transient stores, ends in `w'`. The Router writes no persistent storage of
its own. -/
theorem fillFromPoolLiquidity_ok_iff (order : AsyncOrder) (env : Env) (w w' : σ) :
    Router.fillFromPoolLiquidity ext order env w = .ok ((), w')
      ↔ ∃ r, ext.call_IPoolManager_unlock ext.POOLMANAGER (callbackData 5 order 0) env
          (fillFromPoolLiquidityPre ext env w) = .ok (r, w') := by
  rw [fillFromPoolLiquidity_eq, run_map]
  rcases ext.call_IPoolManager_unlock ext.POOLMANAGER (callbackData 5 order 0) env
    (fillFromPoolLiquidityPre ext env w) with _ | ⟨_, _⟩ <;> simp

/-- The two transient writes only change the `transient` field of the Router's state. Every
persistent field `unlock` sees is the same as at entry. -/
theorem fillFromPoolLiquidityPre_get (env : Env) (w : σ) (hget : ∀ w s, ext.get (ext.set w s) = s) :
    ext.get (fillFromPoolLiquidityPre ext env w)
      = (let s := ext.get w
         let t := upd (upd s.«transient» Router.USER_LOCATION env.sender) Router.ASYNC_FILLER_LOCATION env.self
         { s with «transient» := t }) := by
  simp [fillFromPoolLiquidityPre, tstore, hget]

end Router
