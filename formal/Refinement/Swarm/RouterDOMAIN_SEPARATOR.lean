import Generated.Router
import Refinement.Monad

/-!
# `Router.DOMAIN_SEPARATOR`

`function DOMAIN_SEPARATOR() external view returns (bytes32)` (src/Router.sol:213).

* No guards: it never reverts.
* Footprint: writes nothing (the state is returned unchanged).
* Returns OpenZeppelin's `_domainSeparatorV4()`: the cached separator when `address(this)` and
  `block.chainid` match the cached values, else
  `keccak256(abi.encode(TYPE_HASH, _hashedName, _hashedVersion, block.chainid, address(this)))`.
-/

open FormalAst Refinement

namespace Router.Swarm.DOMAIN_SEPARATOR

variable {σ : Type} (ext : Ext σ)

/-- The EIP-712 domain separator for environment `env`. -/
def domainSep (env : Env) : Nat :=
  if env.self = ext._cachedThis ∧ env.chainid = ext._cachedChainId then ext._cachedDomainSeparator
  else ext.keccak [EIP712.TYPE_HASH, ext._hashedName, ext._hashedVersion, env.chainid, env.self]

/-- **Exact behaviour.** `DOMAIN_SEPARATOR` always succeeds, leaves storage unchanged and returns
the EIP-712 domain separator (cached or rebuilt). -/
theorem DOMAIN_SEPARATOR_spec (env : Env) (s : σ) :
    Router.DOMAIN_SEPARATOR ext env s = .ok (domainSep ext env, s) := by
  by_cases hc : env.self = ext._cachedThis ∧ env.chainid = ext._cachedChainId
  · simp [Router.DOMAIN_SEPARATOR, EIP712.«_domainSeparatorV4», domainSep, hc]
  · simp only [domainSep, hc, ite_false]
    simp [Router.DOMAIN_SEPARATOR, EIP712.«_domainSeparatorV4»,
      EIP712.«_buildDomainSeparator»]
    intro h1 h2
    exact absurd ⟨h1, h2⟩ hc

/-- No guards: it never reverts. -/
theorem DOMAIN_SEPARATOR_never_reverts (env : Env) (s : σ) (e : Revert) :
    Router.DOMAIN_SEPARATOR ext env s ≠ .error e := by
  rw [DOMAIN_SEPARATOR_spec]; simp

/-- Footprint: on success storage is unchanged and the result is the domain separator. -/
theorem DOMAIN_SEPARATOR_preserves (env : Env) (s s' : σ) (r : Nat)
    (h : Router.DOMAIN_SEPARATOR ext env s = .ok (r, s')) : s' = s ∧ r = domainSep ext env := by
  rw [DOMAIN_SEPARATOR_spec] at h
  cases h; exact ⟨rfl, rfl⟩

end Router.Swarm.DOMAIN_SEPARATOR
