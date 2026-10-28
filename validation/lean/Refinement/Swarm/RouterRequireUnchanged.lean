import Generated.Router
import Refinement.Monad

/-!
# `Router._requireUnchanged`

The function reads `AsyncSwap.asyncOrderInfo(HOOK, toId(order.key), id)` through one view call and
reverts with "Order changed during fill" unless it returns exactly `(amountIn, amountOutMin)`.
It writes no storage.
-/

open FormalAst Refinement

namespace Router.Swarm.RequireUnchanged

variable {σ : Type}

/-- The pool id `PoolIdLibrary.toId` computes for `key`. -/
def poolId (ext : Ext σ) (key : PoolKey) : Nat :=
  ext.keccak [key.currency0, key.currency1, key.fee, toUnsigned 256 key.tickSpacing, key.hooks]

/-- Exact semantics: the outcome is decided by the single `asyncOrderInfo` view call. -/
theorem requireUnchanged_run (ext : Ext σ) (order : AsyncOrder) (id amountIn amountOutMin : Nat)
    (env : Env) (s : σ) :
    Router.«_requireUnchanged» ext order id amountIn amountOutMin env s =
      match ext.view_AsyncSwap_asyncOrderInfo env s ext.HOOK (poolId ext order.key) id with
      | .ok v =>
          if v.1 = amountIn ∧ v.2 = amountOutMin then .ok ((), s)
          else .error ⟨"Order changed during fill"⟩
      | .error r => .error r := by
  unfold Router.«_requireUnchanged» PoolIdLibrary.toId view
  simp only [poolId]
  cases h : ext.view_AsyncSwap_asyncOrderInfo env s ext.HOOK
      (ext.keccak [order.key.currency0, order.key.currency1, order.key.fee,
        toUnsigned 256 order.key.tickSpacing, order.key.hooks]) id with
  | error r => simp [h]
  | ok v =>
    by_cases h1 : v.1 = amountIn
    · by_cases h2 : v.2 = amountOutMin
      · simp [h, h1, h2]
      · simp [h, h1, h2]
    · simp [h, h1]

/-- Success iff the order is unchanged; storage is left as it was. -/
theorem requireUnchanged_ok_iff (ext : Ext σ) (order : AsyncOrder) (id amountIn amountOutMin : Nat)
    (env : Env) (s s' : σ) (u : Unit) :
    Router.«_requireUnchanged» ext order id amountIn amountOutMin env s = .ok (u, s') ↔
      ext.view_AsyncSwap_asyncOrderInfo env s ext.HOOK (poolId ext order.key) id
        = .ok (amountIn, amountOutMin) ∧ s' = s := by
  rw [requireUnchanged_run]
  cases h : ext.view_AsyncSwap_asyncOrderInfo env s ext.HOOK (poolId ext order.key) id with
  | error r => simp
  | ok v =>
    obtain ⟨a, b⟩ := v
    by_cases hc : a = amountIn ∧ b = amountOutMin
    · obtain ⟨rfl, rfl⟩ := hc
      simp [eq_comm]
    · simp only
      rw [if_neg hc]
      constructor
      · intro h'; cases h'
      · rintro ⟨h', -⟩
        simp only [Except.ok.injEq, Prod.mk.injEq] at h'
        exact absurd h' hc

/-- Reverts with "Order changed during fill" when the view succeeds with different amounts. -/
theorem requireUnchanged_reverts_changed (ext : Ext σ) (order : AsyncOrder)
    (id amountIn amountOutMin : Nat) (env : Env) (s : σ) (i o : Nat)
    (hv : ext.view_AsyncSwap_asyncOrderInfo env s ext.HOOK (poolId ext order.key) id = .ok (i, o))
    (hne : ¬ (i = amountIn ∧ o = amountOutMin)) :
    Router.«_requireUnchanged» ext order id amountIn amountOutMin env s =
      .error ⟨"Order changed during fill"⟩ := by
  rw [requireUnchanged_run, hv]
  exact if_neg hne

/-- A revert of the view call propagates unchanged. -/
theorem requireUnchanged_reverts_view (ext : Ext σ) (order : AsyncOrder)
    (id amountIn amountOutMin : Nat) (env : Env) (s : σ) (r : Revert)
    (hv : ext.view_AsyncSwap_asyncOrderInfo env s ext.HOOK (poolId ext order.key) id = .error r) :
    Router.«_requireUnchanged» ext order id amountIn amountOutMin env s = .error r := by
  rw [requireUnchanged_run, hv]

/-- Footprint: no storage writes. Every successful run leaves the state unchanged. -/
theorem requireUnchanged_frame (ext : Ext σ) (order : AsyncOrder) (id amountIn amountOutMin : Nat)
    (env : Env) (s s' : σ) (u : Unit)
    (h : Router.«_requireUnchanged» ext order id amountIn amountOutMin env s = .ok (u, s')) :
    s' = s :=
  ((requireUnchanged_ok_iff ext order id amountIn amountOutMin env s s' u).mp h).2

end Router.Swarm.RequireUnchanged
