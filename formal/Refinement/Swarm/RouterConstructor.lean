import Generated.Router
import Refinement.Monad
import Refinement.Swarm.Assumptions
import Refinement.Swarm.RouterDOMAIN_SEPARATOR

/-!
# `Router.constructor`

```solidity
constructor(IPoolManager _poolManager, AsyncSwap _hook, ISignatureTransfer _permit2)
    EIP712("AsyncSwap Router", "1")
{
    POOLMANAGER = _poolManager;
    HOOK = _hook;
    PERMIT2 = _permit2;
}
```
(src/Router.sol:85).

formal-ast leaves the constructor opaque (`ext.fn_Router__150`, "can't write POOLMANAGER") and
models what it fixes as the `Ext` immutables `POOLMANAGER`, `HOOK`, `PERMIT2` and OpenZeppelin
`EIP712`'s `_name`, `_version`, `_hashedName`, `_hashedVersion`, `_cachedDomainSeparator`,
`_cachedChainId`, `_cachedThis`. The named assumption `CtorSpec env0 pm hk p2` states the
deployment in environment `env0` with those arguments:

* `storage` (`CtorStorageSpec`): no guards and no storage writes (the names are short strings, so
  the fallback slots are not written; everything else is an immutable);
* `POOLMANAGER = pm`, `HOOK = hk`, `PERMIT2 = p2`;
* `eip712`: `Assumptions.EIP712Ctor "AsyncSwap Router" "1"` (short-string `_name`/`_version`,
  their keccaks, `_cachedChainId = block.chainid`, `_cachedThis = address(this)` and the separator
  built at deployment).

It is checked on the bytecode by `test/formal/RouterConstructor.t.sol`. From it: the constructor
never reverts and writes nothing; `_domainSeparatorV4` / `DOMAIN_SEPARATOR` always equal the
separator rebuilt from the current chain id and address, over the constant name/version hashes.
-/

open FormalAst Refinement
open Refinement.Swarm.Assumptions

namespace Router.Swarm.Constructor

variable {σ : Type} (ext : Ext σ)

/-- The constructor's effect on storage: none, and it never reverts. -/
def CtorStorageSpec : Prop :=
  ∀ pm hk p2 env w, ext.fn_Router__150 pm hk p2 env w = .ok ((), w)

/-- **Named assumption.** What the deployment of the Router in `env0` with
`_poolManager = pm`, `_hook = hk`, `_permit2 = p2` does and fixes. -/
structure CtorSpec (env0 : Env) (pm hk p2 : Nat) : Prop where
  storage : CtorStorageSpec ext
  poolManager : ext.POOLMANAGER = pm
  hook : ext.HOOK = hk
  permit2 : ext.PERMIT2 = p2
  eip712 : EIP712Ctor "AsyncSwap Router" "1" HASH_ASYNCSWAP_ROUTER HASH_ONE ext.keccak env0.chainid
    env0.self ext._name ext._version ext._hashedName ext._hashedVersion ext._cachedDomainSeparator
    ext._cachedChainId ext._cachedThis

/-- The domain separator rebuilt from the current environment. -/
def builtSep (env : Env) : Nat :=
  ext.keccak [EIP712.TYPE_HASH, ext._hashedName, ext._hashedVersion, env.chainid, env.self]

variable {ext}

theorem typeHash_eq : Refinement.Swarm.Assumptions.TYPE_HASH = EIP712.TYPE_HASH := rfl

/-- The deployed `_name` immutable. -/
theorem CtorSpec.name_word {env0 : Env} {pm hk p2 : Nat} (h : CtorSpec ext env0 pm hk p2) :
    ext._name = 0x4173796e635377617020526f7574657200000000000000000000000000000010 := by
  rw [h.eip712.name_eq]; exact asyncSwapRouter_short

/-- The deployed `_version` immutable. -/
theorem CtorSpec.version_word {env0 : Env} {pm hk p2 : Nat} (h : CtorSpec ext env0 pm hk p2) :
    ext._version = 0x3100000000000000000000000000000000000000000000000000000000000001 := by
  rw [h.eip712.version_eq]; exact one_short

/-- No guards: the constructor never reverts. -/
theorem ctor_never_reverts {env0 : Env} {pm hk p2 : Nat} (h : CtorSpec ext env0 pm hk p2)
    (a b c : Nat) (env : Env) (w : σ) (e : Revert) :
    ext.fn_Router__150 a b c env w ≠ .error e := by
  rw [h.storage]; simp

/-- Footprint: the constructor writes no storage. -/
theorem ctor_ok {env0 : Env} {pm hk p2 : Nat} (h : CtorSpec ext env0 pm hk p2)
    (a b c : Nat) (env : Env) (w w' : σ) (hok : ext.fn_Router__150 a b c env w = .ok ((), w')) :
    w' = w := by
  rw [h.storage] at hok; cases hok; rfl

/-- The deployment fixes the three addresses and the cache key. -/
theorem ctor_deployed {env0 : Env} {pm hk p2 : Nat} (h : CtorSpec ext env0 pm hk p2) :
    ext.POOLMANAGER = pm ∧ ext.HOOK = hk ∧ ext.PERMIT2 = p2 ∧ ext._cachedThis = env0.self ∧
      ext._cachedChainId = env0.chainid :=
  ⟨h.poolManager, h.hook, h.permit2, h.eip712.cachedThis_eq, h.eip712.cachedChainId_eq⟩

/-- `_domainSeparatorV4` never reverts, writes nothing and returns the separator built from the
current `block.chainid` and `address(this)`. -/
theorem domainSeparatorV4_eq_built {env0 : Env} {pm hk p2 : Nat} (h : CtorSpec ext env0 pm hk p2)
    (env : Env) (s : σ) :
    EIP712.«_domainSeparatorV4» ext env s = .ok (builtSep ext env, s) := by
  have hsep := h.eip712.cachedSep_eq
  rw [typeHash_eq] at hsep
  by_cases hc : env.self = ext._cachedThis ∧ env.chainid = ext._cachedChainId
  · obtain ⟨h1, h2⟩ := hc
    simp [EIP712.«_domainSeparatorV4», builtSep, h1, h2, hsep, h.eip712.cachedThis_eq,
      h.eip712.cachedChainId_eq]
  · simp [EIP712.«_domainSeparatorV4», EIP712.«_buildDomainSeparator», builtSep]
    intro h1 h2
    exact absurd ⟨h1, h2⟩ hc

/-- `DOMAIN_SEPARATOR()` returns the separator rebuilt from the current chain id and address. -/
theorem DOMAIN_SEPARATOR_eq_built {env0 : Env} {pm hk p2 : Nat} (h : CtorSpec ext env0 pm hk p2)
    (env : Env) (s : σ) :
    Router.DOMAIN_SEPARATOR ext env s = .ok (builtSep ext env, s) := by
  have hsep := h.eip712.cachedSep_eq
  rw [typeHash_eq] at hsep
  rw [Router.Swarm.DOMAIN_SEPARATOR.DOMAIN_SEPARATOR_spec]
  by_cases hc : env.self = ext._cachedThis ∧ env.chainid = ext._cachedChainId
  · obtain ⟨h1, h2⟩ := hc
    simp [Router.Swarm.DOMAIN_SEPARATOR.domainSep, builtSep, h1, h2, hsep,
      h.eip712.cachedThis_eq, h.eip712.cachedChainId_eq]
  · simp only [Router.Swarm.DOMAIN_SEPARATOR.domainSep, hc, ite_false, builtSep]

/-- With the deployed hashes: `DOMAIN_SEPARATOR()` is the separator over
`keccak256("AsyncSwap Router")`, `keccak256("1")`, the current chain id and address. -/
theorem DOMAIN_SEPARATOR_deployed {env0 : Env} {pm hk p2 : Nat} (h : CtorSpec ext env0 pm hk p2)
    (env : Env) (s : σ) :
    Router.DOMAIN_SEPARATOR ext env s =
      .ok (ext.keccak [EIP712.TYPE_HASH, HASH_ASYNCSWAP_ROUTER, HASH_ONE, env.chainid, env.self], s) := by
  rw [DOMAIN_SEPARATOR_eq_built h, builtSep, h.eip712.hashedName_eq, h.eip712.hashedVersion_eq]

end Router.Swarm.Constructor
