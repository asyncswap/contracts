import Generated.AsyncSwap
import Refinement.Monad

/-!
# `AsyncMatching._transferEscrow`

`_transferEscrow(IPoolManager manager, Currency currency, address recipient, uint256 amount,
address hook)` (internal, src/AsyncSwap.sol, library `AsyncMatching`):

```
CurrencySettler.settle(currency, manager, hook, amount, true);          // burn hook's claims
CurrencySettler.take(currency, manager, recipient, amount, currency.isAddressZero());
```

In the model this is exactly two external calls and nothing else:

1. `poolManager.burn(hook, currency.toId(), amount)` from the entry world;
2. from the world the burn left: if `currency` is native (`address(0)`), it is
   `poolManager.mint(recipient, 0, amount)` (the escrow stays as ERC-6909 claims, now owned by
   `recipient`); otherwise `poolManager.take(currency, recipient, amount)` (the underlying ERC-20
   is paid out).

Both calls use the *same* `amount` and the same `currency`; the burn is always from `hook` and comes
first. The function has no guard of its own and makes no storage write of its own: it reverts
exactly when one of the two calls reverts (with that call's reason), and on success the final
world is the one the second call left, the return value being `()`.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.TransferEscrow

variable {σ : Type} (ext : Ext σ)

/-- The second leg: mint claims for native currency, take the ERC-20 otherwise. -/
def payout (manager currency recipient amount : Nat) (env : Env) (w : σ) :
    Except Revert (Unit × σ) :=
  if currency = 0 then ext.call_IPoolManager_mint manager recipient currency amount env w
  else ext.call_IPoolManager_take manager currency recipient amount env w

/-- What a run of `_transferEscrow` is: the burn from `hook`, then the payout to `recipient`. -/
def spec (manager currency recipient amount hook : Nat) (env : Env) (w : σ) :
    Except Revert (Unit × σ) :=
  match ext.call_IPoolManager_burn manager hook currency amount env w with
  | .error e => .error e
  | .ok (_, w1) => payout ext manager currency recipient amount env w1

/-- Full characterization of a run (no assumption on `ext`). -/
theorem transferEscrow_run (manager currency recipient amount hook : Nat) (env : Env) (w : σ) :
    AsyncMatching.«_transferEscrow» ext manager currency recipient amount hook env w =
      spec ext manager currency recipient amount hook env w := by
  unfold spec payout
  rcases hb : ext.call_IPoolManager_burn manager hook currency amount env w with e | ⟨u, w1⟩
  · simp [AsyncMatching.«_transferEscrow», CurrencySettler.settle, CurrencyLibrary.toId, hb]
  · by_cases hc : currency = 0
    · subst hc
      rcases hm : ext.call_IPoolManager_mint manager recipient 0 amount env w1 with e | ⟨u2, w2⟩ <;>
      simp [AsyncMatching.«_transferEscrow», CurrencySettler.settle, CurrencySettler.take,
        CurrencyLibrary.toId, CurrencyLibrary.isAddressZero, CurrencyLibrary.ADDRESS_ZERO, hb, hm]
    · rcases ht : ext.call_IPoolManager_take manager currency recipient amount env w1 with
        e | ⟨u2, w2⟩ <;>
      simp [AsyncMatching.«_transferEscrow», CurrencySettler.settle, CurrencySettler.take,
        CurrencyLibrary.toId, CurrencyLibrary.isAddressZero, CurrencyLibrary.ADDRESS_ZERO, hb, ht, hc]

/-- Burn first: if burning the hook's escrowed claims reverts, `_transferEscrow` reverts with the
same reason and nothing is paid out. -/
theorem transferEscrow_burn_reverts (manager currency recipient amount hook : Nat) (env : Env)
    (w : σ) (e : Revert)
    (hb : ext.call_IPoolManager_burn manager hook currency amount env w = .error e) :
    AsyncMatching.«_transferEscrow» ext manager currency recipient amount hook env w = .error e := by
  rw [transferEscrow_run]; simp [spec, hb]

/-- Native currency: after the burn, exactly `mint(recipient, 0, amount)` follows; its result
(revert or final world) is the function's result. -/
theorem transferEscrow_native (manager recipient amount hook : Nat) (env : Env) (w w1 : σ) (u : Unit)
    (hb : ext.call_IPoolManager_burn manager hook 0 amount env w = .ok (u, w1)) :
    AsyncMatching.«_transferEscrow» ext manager 0 recipient amount hook env w =
      ext.call_IPoolManager_mint manager recipient 0 amount env w1 := by
  rw [transferEscrow_run]; simp [spec, hb, payout]

/-- ERC-20 currency: after the burn, exactly `take(currency, recipient, amount)` follows; its result
(revert or final world) is the function's result. -/
theorem transferEscrow_erc20 (manager currency recipient amount hook : Nat) (env : Env) (w w1 : σ)
    (u : Unit) (hc : currency ≠ 0)
    (hb : ext.call_IPoolManager_burn manager hook currency amount env w = .ok (u, w1)) :
    AsyncMatching.«_transferEscrow» ext manager currency recipient amount hook env w =
      ext.call_IPoolManager_take manager currency recipient amount env w1 := by
  rw [transferEscrow_run]; simp [spec, hb, payout, hc]

/-- Success: the burn of `amount` claims of `currency` from `hook` succeeded from the entry world,
and from the world it left the payout of that *same* `amount` of that same `currency` to
`recipient` (mint of claims if native, ERC-20 take otherwise) succeeded and produced the final
world. No other state change happens. -/
theorem transferEscrow_ok (manager currency recipient amount hook : Nat) (env : Env) (w w' : σ)
    (r : Unit)
    (hok : AsyncMatching.«_transferEscrow» ext manager currency recipient amount hook env w
      = .ok (r, w')) :
    ∃ w1, (∃ u, ext.call_IPoolManager_burn manager hook currency amount env w = .ok (u, w1)) ∧
      payout ext manager currency recipient amount env w1 = .ok (r, w') := by
  rw [transferEscrow_run] at hok
  rcases hb : ext.call_IPoolManager_burn manager hook currency amount env w with e | ⟨u, w1⟩
  · simp [spec, hb] at hok
  · simp only [spec, hb] at hok
    exact ⟨w1, ⟨u, rfl⟩, hok⟩

/-- Revert characterization: `_transferEscrow` reverts exactly when the burn reverts, or the burn
succeeds and the payout reverts. -/
theorem transferEscrow_reverts_iff (manager currency recipient amount hook : Nat) (env : Env)
    (w : σ) :
    (∃ e, AsyncMatching.«_transferEscrow» ext manager currency recipient amount hook env w
      = .error e) ↔
      ((∃ e, ext.call_IPoolManager_burn manager hook currency amount env w = .error e) ∨
        ∃ u w1, ext.call_IPoolManager_burn manager hook currency amount env w = .ok (u, w1) ∧
          ∃ e, payout ext manager currency recipient amount env w1 = .error e) := by
  rw [transferEscrow_run]
  rcases hb : ext.call_IPoolManager_burn manager hook currency amount env w with e | ⟨u, w1⟩
  · simp [spec, hb]
  · simp [spec, hb]

end AsyncSwap.Swarm.TransferEscrow
