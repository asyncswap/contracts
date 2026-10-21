import Generated.FeeVault
import Refinement.Monad

/-!
# `FeeVault.unlockCallback`

`function unlockCallback(bytes calldata data) external returns (bytes memory)` (src/FeeVault.sol:34).

* reverts `Unauthorized` unless `msg.sender == poolManager`;
* else reverts `abi.decode` unless `data` holds two words, both fitting an `address`;
* else reads `amount = poolManager.balanceOf(address(this), currency)` (a staticcall; its revert
  propagates);
* if `amount == 0` it returns `""` with the world unchanged;
* else calls `poolManager.burn(address(this), currency, amount)` then
  `poolManager.take(currency, recipient, amount)` (from the world `burn` left), propagates either
  revert, writes nothing of its own and returns `""`.

For the maintainer's "consume more than you own" concern: the amount taken out is exactly the
vault's *own* ERC-6909 claim balance for that currency, read just before; the burn is from
`address(this)` (the vault), never from another user's claim, it uses the same `amount` as the take,
and it comes first. Only the pool manager can drive it (and the pool manager only calls back the
contract that called `unlock`, i.e. `collect`, which is owner-gated — see `FeeVaultCollect`).

(Inside `namespace FeeVault.Swarm`, `FeeVault.unlockCallback` resolves to the generated
`FeeVault.FeeVault.unlockCallback`.)
-/

open FormalAst Refinement

namespace FeeVault.Swarm

variable {σ : Type} (ext : Ext σ)

/-- The ABI word of `data` at byte `pos` (what `abiWordAt` yields when in bounds). -/
def word (data : List Nat) (pos : Nat) : Nat := bytesWord ((data.drop pos).take 32)

/-- The well-formedness `abi.decode(data, (Currency, address))` checks. -/
def decodes (data : List Nat) : Prop :=
  64 ≤ data.length ∧ word data 0 < 2 ^ 160 ∧ word data 32 < 2 ^ 160

instance (data : List Nat) : Decidable (decodes data) := by unfold decodes; infer_instance

/-- Burn the vault's whole claim then take it (the nonzero-balance branch). -/
def burnTake (env : Env) (w : σ) (currency recipient amount : Nat) : Except Revert (List Nat × σ) :=
  match ext.call_IPoolManager_burn ext.poolManager env.self currency amount env w with
  | .ok (_, w1) =>
    match ext.call_IPoolManager_take ext.poolManager currency recipient amount env w1 with
    | .ok (_, w2) => .ok ([], w2)
    | .error e => .error e
  | .error e => .error e

/-- The body after the guards: the balance read, then burn/take when nonzero. -/
def body (env : Env) (w : σ) (currency recipient : Nat) : Except Revert (List Nat × σ) :=
  match ext.view_IERC6909Claims_balanceOf env w ext.poolManager env.self currency with
  | .error e => .error e
  | .ok amount => if amount = 0 then .ok ([], w) else burnTake ext env w currency recipient amount

/-- Full characterization of a run (no lawfulness assumed on `ext`). -/
theorem unlockCallback_run (env : Env) (w : σ) (data : List Nat) :
    FeeVault.unlockCallback ext data env w =
      if env.sender ≠ ext.poolManager then .error ⟨"Unauthorized"⟩
      else if ¬ decodes data then .error ⟨"abi.decode"⟩
      else body ext env w (word data 0) (word data 32) := by
  unfold FeeVault.unlockCallback CurrencyLibrary.toId view decodes word body burnTake
  by_cases hs : env.sender = ext.poolManager
  · by_cases o : bytesWord (List.take 32 data) < 2 ^ 160 <;>
    by_cases r : bytesWord (List.take 32 (List.drop 32 data)) < 2 ^ 160 <;>
    by_cases h0 : 32 ≤ data.length <;> by_cases h1 : 64 ≤ data.length <;> (try omega) <;>
    simp [abiWordAt, abiUint, hs, o, r, h0, h1]
    all_goals
      rcases ext.view_IERC6909Claims_balanceOf env w ext.poolManager env.self
        (bytesWord (List.take 32 data)) with e | amt
      · rfl
      · by_cases ha : amt = 0
        · simp [ha]
        · simp only [ha, ite_false, run_pure]
          rcases ext.call_IPoolManager_burn ext.poolManager env.self (bytesWord (List.take 32 data))
            amt env w with e | ⟨u, w1⟩
          · rfl
          · simp only
            rcases ext.call_IPoolManager_take ext.poolManager (bytesWord (List.take 32 data))
              (bytesWord (List.take 32 (List.drop 32 data))) amt env w1 with e | ⟨u2, w2⟩ <;> rfl
  · simp [hs]

/-- Guard: any caller other than the pool manager reverts with `Unauthorized`. -/
theorem unlockCallback_unauthorized (env : Env) (w : σ) (data : List Nat)
    (h : env.sender ≠ ext.poolManager) :
    FeeVault.unlockCallback ext data env w = .error ⟨"Unauthorized"⟩ := by
  rw [unlockCallback_run]; simp [h]

/-- Malformed `data` (short, or an out-of-range address word) reverts with `abi.decode`. -/
theorem unlockCallback_badData (env : Env) (w : σ) (data : List Nat)
    (hs : env.sender = ext.poolManager) (h : ¬ decodes data) :
    FeeVault.unlockCallback ext data env w = .error ⟨"abi.decode"⟩ := by
  rw [unlockCallback_run]; simp [hs, h]

/-- The balance view reverting makes the callback revert with the same reason. -/
theorem unlockCallback_view_reverts (env : Env) (w : σ) (data : List Nat) (e : Revert)
    (hs : env.sender = ext.poolManager) (hd : decodes data)
    (hv : ext.view_IERC6909Claims_balanceOf env w ext.poolManager env.self (word data 0) = .error e) :
    FeeVault.unlockCallback ext data env w = .error e := by
  rw [unlockCallback_run]; simp [hs, hd, body, hv]

/-- Zero vault balance: no external call is made, the world is unchanged, `""` is returned. -/
theorem unlockCallback_zero (env : Env) (w : σ) (data : List Nat)
    (hs : env.sender = ext.poolManager) (hd : decodes data)
    (hv : ext.view_IERC6909Claims_balanceOf env w ext.poolManager env.self (word data 0) = .ok 0) :
    FeeVault.unlockCallback ext data env w = .ok ([], w) := by
  rw [unlockCallback_run]; simp [hs, hd, body, hv]

/-- Nonzero vault balance: exactly `burn(self, currency, amount)` then
`take(currency, recipient, amount)` with that same `amount`. -/
theorem unlockCallback_nonzero (env : Env) (w : σ) (data : List Nat) (amount : Nat)
    (hs : env.sender = ext.poolManager) (hd : decodes data)
    (hv : ext.view_IERC6909Claims_balanceOf env w ext.poolManager env.self (word data 0) = .ok amount)
    (ha : amount ≠ 0) :
    FeeVault.unlockCallback ext data env w = burnTake ext env w (word data 0) (word data 32) amount := by
  rw [unlockCallback_run]; simp [hs, hd, body, hv, ha]

/-- Success: the caller is the pool manager, `data` decodes, the return value is `""`, and either the
vault's claim balance for `currency` was zero and the world is untouched, or it was `amount ≠ 0`,
`burn(address(this), currency, amount)` succeeded from the entry world and
`take(currency, recipient, amount)` — the *same* amount — succeeded from the world burn left, which
is the final world (no write of our own). -/
theorem unlockCallback_ok (env : Env) (w w' : σ) (data ret : List Nat)
    (hok : FeeVault.unlockCallback ext data env w = .ok (ret, w')) :
    env.sender = ext.poolManager ∧ decodes data ∧ ret = [] ∧
      ((ext.view_IERC6909Claims_balanceOf env w ext.poolManager env.self (word data 0) = .ok 0 ∧
          w' = w) ∨
       ∃ amount, amount ≠ 0 ∧
        ext.view_IERC6909Claims_balanceOf env w ext.poolManager env.self (word data 0) = .ok amount ∧
        ∃ w1, (∃ u, ext.call_IPoolManager_burn ext.poolManager env.self (word data 0) amount env w
                = .ok (u, w1)) ∧
          ∃ u, ext.call_IPoolManager_take ext.poolManager (word data 0) (word data 32) amount env w1
                = .ok (u, w')) := by
  rw [unlockCallback_run] at hok
  by_cases hs : env.sender = ext.poolManager
  · by_cases hd : decodes data
    · simp only [hs, hd, ne_eq, not_true_eq_false, ite_false, body] at hok
      refine ⟨hs, hd, ?_⟩
      revert hok
      cases hv : ext.view_IERC6909Claims_balanceOf env w ext.poolManager env.self (word data 0) with
      | error e => intro hok; cases hok
      | ok amount =>
        by_cases ha : amount = 0
        · subst ha; simp only [ite_true]; intro hok; cases hok
          exact ⟨rfl, Or.inl ⟨by simp, rfl⟩⟩
        · simp only [ha, ite_false, burnTake]
          cases hb : ext.call_IPoolManager_burn ext.poolManager env.self (word data 0) amount env w with
          | error e => intro hok; cases hok
          | ok p =>
            cases ht : ext.call_IPoolManager_take ext.poolManager (word data 0) (word data 32) amount
                env p.2 with
            | error e => simp [ht]
            | ok q =>
              simp only [ht]
              intro hok; cases hok
              exact ⟨rfl, Or.inr ⟨amount, ha, rfl, p.2, ⟨p.1, by first | exact hb | rfl⟩, q.1, ht⟩⟩
    · simp [hs, hd] at hok
  · simp [hs] at hok

/-- No overdraw: whenever the callback asks the pool manager to `take` some amount of a currency,
that amount is exactly the vault's own claim balance of that currency (read in the entry world),
and it was first burned from the vault's own account (`address(this)`), not from anyone else's. -/
theorem unlockCallback_take_eq_own_balance (env : Env) (w w' : σ) (data ret : List Nat)
    (amount : Nat) (w1 : σ) (u : Unit)
    (hok : FeeVault.unlockCallback ext data env w = .ok (ret, w'))
    (hb : ext.call_IPoolManager_burn ext.poolManager env.self (word data 0) amount env w = .ok (u, w1))
    (hv : ext.view_IERC6909Claims_balanceOf env w ext.poolManager env.self (word data 0) = .ok amount)
    (ha : amount ≠ 0) :
    ∃ u', ext.call_IPoolManager_take ext.poolManager (word data 0) (word data 32) amount env w1
      = .ok (u', w') := by
  obtain ⟨-, -, -, h⟩ := unlockCallback_ok ext env w w' data ret hok
  rcases h with ⟨h0, -⟩ | ⟨a, -, ha', w1', ⟨u1, hb'⟩, u2, ht⟩
  · rw [hv] at h0; cases h0; exact absurd rfl ha
  · rw [hv] at ha'; cases ha'
    rw [hb] at hb'; cases hb'
    exact ⟨u2, ht⟩

/-- Burn-before-take: if burning the vault's claim reverts, the callback reverts with the same
error, so nothing is taken without the matching burn. -/
theorem unlockCallback_burn_fails (env : Env) (w : σ) (data : List Nat) (amount : Nat) (e : Revert)
    (hs : env.sender = ext.poolManager) (hd : decodes data)
    (hv : ext.view_IERC6909Claims_balanceOf env w ext.poolManager env.self (word data 0) = .ok amount)
    (ha : amount ≠ 0)
    (hb : ext.call_IPoolManager_burn ext.poolManager env.self (word data 0) amount env w = .error e) :
    FeeVault.unlockCallback ext data env w = .error e := by
  rw [unlockCallback_nonzero ext env w data amount hs hd hv ha]; simp [burnTake, hb]

/-- Revert characterization. -/
theorem unlockCallback_reverts_iff (env : Env) (w : σ) (data : List Nat) :
    (∃ e, FeeVault.unlockCallback ext data env w = .error e) ↔
      (env.sender ≠ ext.poolManager ∨ ¬ decodes data ∨
        ∃ e, body ext env w (word data 0) (word data 32) = .error e) := by
  rw [unlockCallback_run]
  by_cases hs : env.sender = ext.poolManager
  · by_cases hd : decodes data
    · simp [hs, hd]
    · constructor
      · intro _; exact Or.inr (Or.inl hd)
      · intro _; exact ⟨⟨"abi.decode"⟩, by simp [hs, hd]⟩
  · constructor
    · intro _; exact Or.inl hs
    · intro _; exact ⟨⟨"Unauthorized"⟩, by simp [hs]⟩

end FeeVault.Swarm
