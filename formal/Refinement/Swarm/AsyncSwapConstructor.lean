import Generated.AsyncSwap
import Refinement.Monad
import Refinement.Swarm.AsyncSwapDOMAIN_SEPARATOR
import Refinement.Swarm.AsyncSwapTransferOwnership
import Refinement.Swarm.AsyncSwapAcceptOwnership

/-!
# `AsyncSwap.constructor`

```solidity
constructor(IPoolManager _poolManager, Currency _numeraire, address _owner)
    BaseHook(_poolManager) EIP712("AsyncSwap", "1")
{
    if (Currency.unwrap(_numeraire).code.length == 0) revert InvalidNumeraire();
    if (_owner == address(0)) revert ZeroAddress();
    numeraire = _numeraire; owner = _owner; feeVault = new FeeVault(_poolManager);
}
```
(src/AsyncSwap.sol:141).

formal-ast leaves the constructor opaque (`ext.fn_AsyncSwap__309`, "can't write numeraire") and
models its results as the `Ext` immutables `poolManager`, `numeraire`, `feeVault`, `_cachedThis`,
`_cachedChainId`, `_cachedDomainSeparator`, `_hashedName`, `_hashedVersion`. This file states the
constructor's behaviour as two explicit assumptions, both checked by the Foundry test
`test/formal/AsyncSwapConstructor.t.sol`:

* `CtorStorageSpec`: on storage, the constructor reverts with `InvalidNumeraire` iff the numeraire
  has no code, else with `ZeroAddress` iff `_owner = 0`, else writes exactly `owner := _owner`
  (the name/version are short strings, so `_nameFallback`/`_versionFallback` are not written; the
  `FeeVault` deployment touches no AsyncSwap storage).
* `Immutables env pm num`: the deployment in environment `env` with arguments `pm`, `num` fixes
  `poolManager = pm`, `numeraire = num`, `_cachedThis = address(this)`,
  `_cachedChainId = block.chainid` and the cached separator as the freshly built one.

and proves their consequences against the generated defs: the guard/success characterization,
the deployed storage, the owner-nonzero invariant through the two-step ownership transfer, and
that `DOMAIN_SEPARATOR` / `_domainSeparatorV4` always equal the separator rebuilt from the current
`block.chainid` and `address(this)`.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.Constructor

variable {σ : Type} (ext : Ext σ)

/-- The constructor's effect on storage, as the Solidity states it. -/
def ctorRun (num own : Nat) (w : σ) : Except Revert (Unit × σ) :=
  if ext.codeLength num = 0 then .error ⟨"InvalidNumeraire"⟩
  else if own = 0 then .error ⟨"ZeroAddress"⟩
  else .ok ((), ext.set w { ext.get w with owner := own })

/-- Assumption (storage): the opaque constructor `ext.fn_AsyncSwap__309 pm num own` behaves as
`ctorRun`. -/
def CtorStorageSpec : Prop :=
  ∀ pm num own env w, ext.fn_AsyncSwap__309 pm num own env w = ctorRun ext num own w

/-- Assumption (immutables): what the deployment in `env` with `_poolManager = pm`,
`_numeraire = num` fixes. -/
structure Immutables (env : Env) (pm num : Nat) : Prop where
  poolManager : ext.poolManager = pm
  numeraire : ext.numeraire = num
  cachedThis : ext._cachedThis = env.self
  cachedChainId : ext._cachedChainId = env.chainid
  cachedDomainSeparator :
    ext._cachedDomainSeparator =
      ext.keccak [EIP712.TYPE_HASH, ext._hashedName, ext._hashedVersion, env.chainid, env.self]

/-- The domain separator rebuilt from the current environment. -/
def builtSep (env : Env) : Nat :=
  ext.keccak [EIP712.TYPE_HASH, ext._hashedName, ext._hashedVersion, env.chainid, env.self]

/-! ## Guards and writes -/

/-- A numeraire without code reverts with `InvalidNumeraire` (checked first). -/
theorem ctor_invalidNumeraire (hs : CtorStorageSpec ext) (pm num own : Nat) (env : Env) (w : σ)
    (h : ext.codeLength num = 0) :
    ext.fn_AsyncSwap__309 pm num own env w = .error ⟨"InvalidNumeraire"⟩ := by
  rw [hs]; simp [ctorRun, h]

/-- With a numeraire that has code, a zero owner reverts with `ZeroAddress`. -/
theorem ctor_zeroOwner (hs : CtorStorageSpec ext) (pm num : Nat) (env : Env) (w : σ)
    (h : ext.codeLength num ≠ 0) :
    ext.fn_AsyncSwap__309 pm num 0 env w = .error ⟨"ZeroAddress"⟩ := by
  rw [hs]; simp [ctorRun, h]

/-- The constructor reverts exactly when the numeraire has no code or the owner is zero. -/
theorem ctor_reverts_iff (hs : CtorStorageSpec ext) (pm num own : Nat) (env : Env) (w : σ) :
    (∃ e, ext.fn_AsyncSwap__309 pm num own env w = .error e) ↔
      (ext.codeLength num = 0 ∨ own = 0) := by
  rw [hs]
  by_cases h1 : ext.codeLength num = 0 <;> by_cases h2 : own = 0 <;> simp [ctorRun, h1, h2]

/-- Success iff both guards pass; the only write is `owner := _owner`. -/
theorem ctor_ok_iff (hs : CtorStorageSpec ext) (pm num own : Nat) (env : Env) (w w' : σ) :
    ext.fn_AsyncSwap__309 pm num own env w = .ok ((), w') ↔
      ext.codeLength num ≠ 0 ∧ own ≠ 0 ∧ w' = ext.set w { ext.get w with owner := own } := by
  rw [hs]
  by_cases h1 : ext.codeLength num = 0 <;> by_cases h2 : own = 0 <;>
    simp [ctorRun, h1, h2, eq_comm]

/-- Deployed storage: from fresh (all-zero) storage, a successful constructor leaves
`owner = _owner ≠ 0`, `pendingOwner = 0`, and every other field at its zero value. -/
theorem ctor_fresh_state (hs : CtorStorageSpec ext) (hget : ∀ w s, ext.get (ext.set w s) = s)
    (pm num own : Nat) (env : Env) (w w' : σ) (hfresh : ext.get w = default)
    (hok : ext.fn_AsyncSwap__309 pm num own env w = .ok ((), w')) :
    ext.get w' = { (default : State) with owner := own } ∧
      (ext.get w').owner = own ∧ own ≠ 0 ∧ (ext.get w').pendingOwner = 0 ∧
      ext.codeLength num ≠ 0 := by
  obtain ⟨hn, ho, rfl⟩ := (ctor_ok_iff ext hs pm num own env w w').1 hok
  refine ⟨?_, ?_, ho, ?_, hn⟩ <;> simp [hget, hfresh] <;> rfl

/-- A successful deployment fixes `poolManager = _poolManager`, `numeraire = _numeraire` (a
contract) and `owner = _owner ≠ 0`. -/
theorem ctor_deployed (hs : CtorStorageSpec ext) (hget : ∀ w s, ext.get (ext.set w s) = s)
    (env0 : Env) (pm num own : Nat) (w w' : σ) (hi : Immutables ext env0 pm num)
    (hok : ext.fn_AsyncSwap__309 pm num own env0 w = .ok ((), w')) :
    ext.poolManager = pm ∧ ext.numeraire = num ∧ ext.codeLength ext.numeraire ≠ 0 ∧
      (ext.get w').owner = own ∧ own ≠ 0 := by
  obtain ⟨hn, ho, rfl⟩ := (ctor_ok_iff ext hs pm num own env0 w w').1 hok
  exact ⟨hi.poolManager, hi.numeraire, hi.numeraire ▸ hn, by simp [hget], ho⟩

/-! ## Owner invariant: `owner ≠ 0` from deployment on -/

/-- `transferOwnership` never changes `owner`, so it keeps `owner ≠ 0`. -/
theorem owner_nonzero_transferOwnership (hget : ∀ w s, ext.get (ext.set w s) = s)
    (newOwner : Nat) (env : Env) (w w' : σ) (hinv : (ext.get w).owner ≠ 0)
    (hok : AsyncSwap.transferOwnership ext newOwner env w = .ok ((), w')) :
    (ext.get w').owner ≠ 0 := by
  rw [(AsyncSwap.Swarm.transferOwnership_ok_state ext newOwner env w w' hget hok).2.2]
  exact hinv

/-- `acceptOwnership` by a nonzero `msg.sender` (every real caller) keeps `owner ≠ 0`. -/
theorem owner_nonzero_acceptOwnership (hget : ∀ w s, ext.get (ext.set w s) = s)
    (env : Env) (w w' : σ) (hsender : env.sender ≠ 0)
    (hok : AsyncSwap.acceptOwnership ext env w = .ok ((), w')) :
    (ext.get w').owner ≠ 0 := by
  rw [(AsyncSwap.Swarm.acceptOwnership_ok_state ext env w w' hget hok).2.2.1]
  exact hsender

/-! ## EIP-712 immutables -/

/-- With the deployment's immutables, `_domainSeparatorV4` never reverts, writes nothing and
returns the separator built from the current `block.chainid` and `address(this)` (the cache is
only ever used when it equals that value). -/
theorem domainSeparatorV4_eq_built (env0 : Env) (pm num : Nat)
    (hi : Immutables ext env0 pm num) (env : Env) (s : σ) :
    EIP712.«_domainSeparatorV4» ext env s = .ok (builtSep ext env, s) := by
  by_cases hc : env.self = ext._cachedThis ∧ env.chainid = ext._cachedChainId
  · obtain ⟨h1, h2⟩ := hc
    simp [EIP712.«_domainSeparatorV4», builtSep, h1, h2, hi.cachedDomainSeparator,
      hi.cachedThis, hi.cachedChainId]
  · simp [EIP712.«_domainSeparatorV4», EIP712.«_buildDomainSeparator», builtSep]
    intro h1 h2
    exact absurd ⟨h1, h2⟩ hc

/-- `DOMAIN_SEPARATOR()` returns the separator rebuilt from the current chain id and address,
in every environment (in particular after a chain fork). -/
theorem DOMAIN_SEPARATOR_eq_built (env0 : Env) (pm num : Nat)
    (hi : Immutables ext env0 pm num) (env : Env) (s : σ) :
    AsyncSwap.DOMAIN_SEPARATOR ext env s = .ok (builtSep ext env, s) := by
  rw [AsyncSwap.Swarm.DOMAIN_SEPARATOR.DOMAIN_SEPARATOR_spec]
  by_cases hc : env.self = ext._cachedThis ∧ env.chainid = ext._cachedChainId
  · obtain ⟨h1, h2⟩ := hc
    simp [AsyncSwap.Swarm.DOMAIN_SEPARATOR.domainSep, builtSep, h1, h2,
      hi.cachedDomainSeparator, hi.cachedThis, hi.cachedChainId]
  · simp only [AsyncSwap.Swarm.DOMAIN_SEPARATOR.domainSep, hc, ite_false, builtSep]

end AsyncSwap.Swarm.Constructor
