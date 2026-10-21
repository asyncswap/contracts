import Generated.NativeClaims
import Refinement.Monad

/-!
# `NativeClaims.unlockCallback`

`function unlockCallback(bytes calldata data) external returns (bytes memory)` (src/NativeClaims.sol:35).

* reverts `OnlyPoolManager` unless `msg.sender == poolManager`;
* else reverts `abi.decode` unless `data` holds three words with the first two fitting an `address`;
* else calls `poolManager.burn(owner, 0, amount)` then `poolManager.take(native, recipient, amount)`
  (the second from the world the first left), propagates either revert, writes nothing of its own
  and returns `""`.

For the maintainer's "consume more than you own" concern: the amount burned from `owner`'s
native claim (id 0) and the amount of native currency taken out are the *same* decoded word, the
burn comes first (so a take never happens without a successful burn of equal size), and only the
pool manager can drive it.
-/

open FormalAst Refinement

namespace NativeClaims.Swarm

variable {σ : Type} (ext : Ext σ)

/-- The ABI word of `data` at byte `pos` (what `abiWordAt` yields when in bounds). -/
def word (data : List Nat) (pos : Nat) : Nat := bytesWord ((data.drop pos).take 32)

/-- The well-formedness `abi.decode(data, (address, address, uint256))` checks. -/
def decodes (data : List Nat) : Prop :=
  96 ≤ data.length ∧ word data 0 < 2 ^ 160 ∧ word data 32 < 2 ^ 160

instance (data : List Nat) : Decidable (decodes data) := by unfold decodes; infer_instance

/-- The two external calls, run in sequence (burn, then take from the world burn left). -/
def calls (env : Env) (w : σ) (owner recipient amount : Nat) : Except Revert (List Nat × σ) :=
  match ext.call_IPoolManager_burn ext.poolManager owner 0 amount env w with
  | .ok (_, w1) =>
    match ext.call_IPoolManager_take ext.poolManager 0 recipient amount env w1 with
    | .ok (_, w2) => .ok ([], w2)
    | .error e => .error e
  | .error e => .error e

/-- Full characterization of a run (no lawfulness assumed on `ext`). -/
theorem unlockCallback_run (env : Env) (w : σ) (data : List Nat) :
    NativeClaims.unlockCallback ext data env w =
      if env.sender ≠ ext.poolManager then .error ⟨"OnlyPoolManager"⟩
      else if ¬ decodes data then .error ⟨"abi.decode"⟩
      else calls ext env w (word data 0) (word data 32) (word data 64) := by
  unfold NativeClaims.unlockCallback decodes word calls
  by_cases hs : env.sender = ext.poolManager
  · by_cases o : bytesWord (List.take 32 data) < 2 ^ 160 <;>
    by_cases r : bytesWord (List.take 32 (List.drop 32 data)) < 2 ^ 160 <;>
    by_cases h0 : 32 ≤ data.length <;> by_cases h1 : 64 ≤ data.length <;>
    by_cases h2 : 96 ≤ data.length <;> (try omega) <;>
    simp [abiWordAt, abiUint, hs, o, r, h0, h1, h2]
    all_goals
      rcases ext.call_IPoolManager_burn ext.poolManager (bytesWord (List.take 32 data)) 0
        (bytesWord (List.take 32 (List.drop 64 data))) env w with e | ⟨u, w1⟩
      · rfl
      · simp only
        rcases ext.call_IPoolManager_take ext.poolManager 0
          (bytesWord (List.take 32 (List.drop 32 data)))
          (bytesWord (List.take 32 (List.drop 64 data))) env w1 with e | ⟨u2, w2⟩ <;> rfl
  · have hb : (env.sender != ext.poolManager) = true := by simpa using hs
    simp [hs]

/-- Guard: any caller other than the pool manager reverts with `OnlyPoolManager`. -/
theorem unlockCallback_onlyPoolManager (env : Env) (w : σ) (data : List Nat)
    (h : env.sender ≠ ext.poolManager) :
    NativeClaims.unlockCallback ext data env w = .error ⟨"OnlyPoolManager"⟩ := by
  rw [unlockCallback_run]; simp [h]

/-- Malformed `data` (short, or an out-of-range address word) reverts with `abi.decode`. -/
theorem unlockCallback_badData (env : Env) (w : σ) (data : List Nat)
    (hs : env.sender = ext.poolManager) (h : ¬ decodes data) :
    NativeClaims.unlockCallback ext data env w = .error ⟨"abi.decode"⟩ := by
  rw [unlockCallback_run]; simp [hs, h]

/-- Success: the caller is the pool manager, `data` decodes, `burn(owner, 0, amount)` succeeded
from the entry world, `take(native, recipient, amount)` succeeded from the world `burn` left with
the *same* `amount`, the final world is the one `take` left (no write of our own), and the return
value is empty bytes. -/
theorem unlockCallback_ok (env : Env) (w w' : σ) (data ret : List Nat)
    (hok : NativeClaims.unlockCallback ext data env w = .ok (ret, w')) :
    env.sender = ext.poolManager ∧ decodes data ∧ ret = [] ∧
      ∃ w1, (∃ u, ext.call_IPoolManager_burn ext.poolManager (word data 0) 0 (word data 64) env w
              = .ok (u, w1)) ∧
        ∃ u, ext.call_IPoolManager_take ext.poolManager 0 (word data 32) (word data 64) env w1
              = .ok (u, w') := by
  rw [unlockCallback_run] at hok
  by_cases hs : env.sender = ext.poolManager
  · by_cases hd : decodes data
    · simp only [hs, hd, ne_eq, not_true_eq_false, ite_false, calls] at hok
      refine ⟨hs, hd, ?_⟩
      revert hok
      cases hb : ext.call_IPoolManager_burn ext.poolManager (word data 0) 0 (word data 64) env w with
      | error e => intro hok; cases hok
      | ok p =>
        cases ht : ext.call_IPoolManager_take ext.poolManager 0 (word data 32) (word data 64) env p.2 with
        | error e => simp [ht]
        | ok q =>
          simp only [ht]
          intro hok; cases hok
          exact ⟨rfl, p.2, ⟨p.1, rfl⟩, q.1, ht⟩
    · simp [hs, hd] at hok
  · simp [hs] at hok

/-- Burn-before-take: if `burn` reverts, `unlockCallback` reverts with the same error, so no native
currency is ever taken without the matching claim burn. -/
theorem unlockCallback_burn_fails (env : Env) (w : σ) (data : List Nat) (e : Revert)
    (hs : env.sender = ext.poolManager) (hd : decodes data)
    (hb : ext.call_IPoolManager_burn ext.poolManager (word data 0) 0 (word data 64) env w = .error e) :
    NativeClaims.unlockCallback ext data env w = .error e := by
  rw [unlockCallback_run]; simp [hs, hd, hb, calls]

/-- Revert characterization. -/
theorem unlockCallback_reverts_iff (env : Env) (w : σ) (data : List Nat) :
    (∃ e, NativeClaims.unlockCallback ext data env w = .error e) ↔
      (env.sender ≠ ext.poolManager ∨ ¬ decodes data ∨
        (∃ e, ext.call_IPoolManager_burn ext.poolManager (word data 0) 0 (word data 64) env w
          = .error e) ∨
        ∃ u w1, ext.call_IPoolManager_burn ext.poolManager (word data 0) 0 (word data 64) env w
            = .ok (u, w1) ∧
          ∃ e, ext.call_IPoolManager_take ext.poolManager 0 (word data 32) (word data 64) env w1
            = .error e) := by
  rw [unlockCallback_run]
  by_cases hs : env.sender = ext.poolManager
  · by_cases hd : decodes data
    · simp only [hs, hd, ne_eq, not_true_eq_false, ite_false, false_or, calls]
      cases hb : ext.call_IPoolManager_burn ext.poolManager (word data 0) 0 (word data 64) env w with
      | error e => simp
      | ok p =>
        cases ht : ext.call_IPoolManager_take ext.poolManager 0 (word data 32) (word data 64) env p.2 with
        | error e =>
          simp only [ht]
          exact ⟨fun _ => Or.inr ⟨p.1, p.2, rfl, e, ht⟩, fun _ => ⟨e, rfl⟩⟩
        | ok q =>
          simp only [ht]
          constructor
          · rintro ⟨e, he⟩; cases he
          · rintro (⟨e, he⟩ | ⟨u, w1, h, e, he⟩)
            · cases he
            · cases h; rw [ht] at he; cases he
    · constructor
      · intro _; exact Or.inr (Or.inl hd)
      · intro _; exact ⟨⟨"abi.decode"⟩, by simp [hs, hd]⟩
  · constructor
    · intro _; exact Or.inl hs
    · intro _; exact ⟨⟨"OnlyPoolManager"⟩, by simp [hs]⟩

/-- The owner and recipient words handed to the pool manager are addresses (< 2^160). -/
theorem unlockCallback_ok_args (env : Env) (w w' : σ) (data ret : List Nat)
    (hok : NativeClaims.unlockCallback ext data env w = .ok (ret, w')) :
    word data 0 < 2 ^ 160 ∧ word data 32 < 2 ^ 160 := by
  obtain ⟨-, ⟨-, h0, h1⟩, -⟩ := unlockCallback_ok ext env w w' data ret hok
  exact ⟨h0, h1⟩

end NativeClaims.Swarm
