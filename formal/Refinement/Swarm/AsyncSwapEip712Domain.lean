import Generated.AsyncSwap
import Refinement.Monad
import Refinement.Swarm.AsyncSwapDOMAIN_SEPARATOR

/-!
# `EIP712.eip712Domain` (AsyncSwap)

```solidity
function eip712Domain() public view virtual returns (
    bytes1 fields, string memory name, string memory version, uint256 chainId,
    address verifyingContract, bytes32 salt, uint256[] memory extensions)
{
    return (hex"0f", _EIP712Name(), _EIP712Version(), block.chainid, address(this),
            bytes32(0), new uint256[](0));
}
```
(OpenZeppelin `EIP712.sol:114`, inherited by AsyncSwap).

formal-ast leaves this function opaque (`ext.fn_EIP712_eip712Domain_2155`, "hexString literal")
and also `ShortStrings.toStringWithFallback` / `ShortStrings.toString`. The generated defs
`EIP712._EIP712Name` / `EIP712._EIP712Version` are used as they are. The file states two
assumptions, both transcriptions of the Solidity:

* `DomainSpec`: the opaque function runs `_EIP712Name()`, then `_EIP712Version()`, and returns
  `(0x0f, name, version, block.chainid, address(this), 0, [])`.
* `ShortStringSpec dec`: `toStringWithFallback(value, store)` is `toString(value)` when
  `value ≠ FALLBACK_SENTINEL` and reads `store` otherwise; `toString(value)` returns the decoded
  string `dec value` and touches no storage.

The results: `eip712Domain` never reverts, writes nothing, returns the fields above with the name
and version picked from the short-string immutables or their fallback slots; with short
name/version (the deployed `"AsyncSwap"`, `"1"`) the result does not depend on storage; and the
separator rebuilt off-chain from the returned fields (ERC-5267) is the one `DOMAIN_SEPARATOR()`
returns, in every environment.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.Eip712Domain

variable {σ : Type} (ext : Ext σ)

/-- The body of `eip712Domain()` as the Solidity states it, over the generated
`_EIP712Name` / `_EIP712Version`. -/
def domainBody : M σ (Nat × String × String × Nat × Nat × Nat × (List Nat)) := do
  let n ← EIP712.«_EIP712Name» ext
  let v ← EIP712.«_EIP712Version» ext
  return (0x0f, n, v, (← read).chainid, (← read).self, 0, [])

/-- Assumption: the opaque `eip712Domain` is `domainBody`. -/
def DomainSpec : Prop :=
  ∀ env w, ext.fn_EIP712_eip712Domain_2155 env w = domainBody ext env w

/-- Assumption: OpenZeppelin `ShortStrings.toStringWithFallback` / `toString`, with `dec` the
decoding of a short string. -/
structure ShortStringSpec (dec : Nat → String) : Prop where
  toString : ∀ v env w, ext.fn_ShortStrings_toString_9528 v env w = .ok (dec v, w)
  withFallback : ∀ v (g : M σ String) (s : String → M σ Unit) env w,
    ext.fn_ShortStrings_toStringWithFallback_9627 v g s env w =
      if v ≠ ShortStrings.FALLBACK_SENTINEL then ext.fn_ShortStrings_toString_9528 v env w
      else g env w

/-- The name `eip712Domain` reports in state `w`. -/
def nameStr (dec : Nat → String) (w : σ) : String :=
  if ext._name ≠ ShortStrings.FALLBACK_SENTINEL then dec ext._name else (ext.get w)._nameFallback

/-- The version `eip712Domain` reports in state `w`. -/
def versionStr (dec : Nat → String) (w : σ) : String :=
  if ext._version ≠ ShortStrings.FALLBACK_SENTINEL then dec ext._version
  else (ext.get w)._versionFallback

theorem EIP712Name_spec (dec : Nat → String) (hs : ShortStringSpec ext dec) (env : Env) (w : σ) :
    EIP712.«_EIP712Name» ext env w = .ok (nameStr ext dec w, w) := by
  unfold EIP712.«_EIP712Name» nameStr
  simp only [run_bind, hs.withFallback]
  by_cases h : ext._name = ShortStrings.FALLBACK_SENTINEL
  · simp [h]
  · simp [h, hs.toString]

theorem EIP712Version_spec (dec : Nat → String) (hs : ShortStringSpec ext dec) (env : Env) (w : σ) :
    EIP712.«_EIP712Version» ext env w = .ok (versionStr ext dec w, w) := by
  unfold EIP712.«_EIP712Version» versionStr
  simp only [run_bind, hs.withFallback]
  by_cases h : ext._version = ShortStrings.FALLBACK_SENTINEL
  · simp [h]
  · simp [h, hs.toString]

/-- **Exact behaviour.** `eip712Domain` never reverts, leaves the state unchanged and returns
`(0x0f, name, version, block.chainid, address(this), 0, [])`. -/
theorem eip712Domain_spec (dec : Nat → String) (hd : DomainSpec ext) (hs : ShortStringSpec ext dec)
    (env : Env) (w : σ) :
    ext.fn_EIP712_eip712Domain_2155 env w =
      .ok ((0x0f, nameStr ext dec w, versionStr ext dec w, env.chainid, env.self, 0, []), w) := by
  rw [hd]
  simp [domainBody, EIP712Name_spec ext dec hs, EIP712Version_spec ext dec hs]

/-- No guards: it never reverts. -/
theorem eip712Domain_never_reverts (dec : Nat → String) (hd : DomainSpec ext)
    (hs : ShortStringSpec ext dec) (env : Env) (w : σ) (e : Revert) :
    ext.fn_EIP712_eip712Domain_2155 env w ≠ .error e := by
  rw [eip712Domain_spec ext dec hd hs]; simp

/-- Footprint and fields: on success the state is unchanged, `fields = 0x0f` (name, version,
chainId, verifyingContract), `chainId = block.chainid`, `verifyingContract = address(this)`,
`salt = 0` and `extensions = []`. -/
theorem eip712Domain_ok (dec : Nat → String) (hd : DomainSpec ext) (hs : ShortStringSpec ext dec)
    (env : Env) (w w' : σ) f n v c a salt ex
    (h : ext.fn_EIP712_eip712Domain_2155 env w = .ok ((f, n, v, c, a, salt, ex), w')) :
    w' = w ∧ f = 0x0f ∧ n = nameStr ext dec w ∧ v = versionStr ext dec w ∧ c = env.chainid ∧
      a = env.self ∧ salt = 0 ∧ ex = [] := by
  rw [eip712Domain_spec ext dec hd hs] at h
  simp only [Except.ok.injEq, Prod.mk.injEq] at h
  obtain ⟨⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩, rfl⟩ := h
  exact ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

/-- With short-string name and version (no fallback slot in use, as for the deployed
`"AsyncSwap"` / `"1"`), the reported name and version are the decoded immutables, independent of
storage. -/
theorem eip712Domain_short (dec : Nat → String) (hd : DomainSpec ext) (hs : ShortStringSpec ext dec)
    (hn : ext._name ≠ ShortStrings.FALLBACK_SENTINEL)
    (hv : ext._version ≠ ShortStrings.FALLBACK_SENTINEL) (env : Env) (w : σ) :
    ext.fn_EIP712_eip712Domain_2155 env w =
      .ok ((0x0f, dec ext._name, dec ext._version, env.chainid, env.self, 0, []), w) := by
  rw [eip712Domain_spec ext dec hd hs]
  simp [nameStr, versionStr, hn, hv]

/-- **ERC-5267 consistency.** Suppose the constructor hashed the reported strings
(`_hashedName = H(name)`, `_hashedVersion = H(version)`, `H` = keccak256 of the bytes) and cached
the separator it built for `(_cachedChainId, _cachedThis)`. Then the separator a client rebuilds
from `eip712Domain()`'s fields, `keccak256(abi.encode(TYPE_HASH, H(name), H(version), chainId,
verifyingContract))`, is exactly what `DOMAIN_SEPARATOR()` returns, in every environment. -/
theorem eip712Domain_matches_DOMAIN_SEPARATOR (dec : Nat → String) (H : String → Nat)
    (hd : DomainSpec ext) (hs : ShortStringSpec ext dec) (env : Env) (w w' : σ) f n v c a salt ex
    (hname : ext._hashedName = H (nameStr ext dec w))
    (hver : ext._hashedVersion = H (versionStr ext dec w))
    (hcache : ext._cachedDomainSeparator =
      ext.keccak [EIP712.TYPE_HASH, ext._hashedName, ext._hashedVersion, ext._cachedChainId,
        ext._cachedThis])
    (h : ext.fn_EIP712_eip712Domain_2155 env w = .ok ((f, n, v, c, a, salt, ex), w')) :
    AsyncSwap.DOMAIN_SEPARATOR ext env w =
      .ok (ext.keccak [EIP712.TYPE_HASH, H n, H v, c, a], w) := by
  obtain ⟨-, -, rfl, rfl, rfl, rfl, -, -⟩ := eip712Domain_ok ext dec hd hs env w w' f n v c a salt ex h
  rw [AsyncSwap.Swarm.DOMAIN_SEPARATOR.DOMAIN_SEPARATOR_spec, ← hname, ← hver]
  by_cases hc : env.self = ext._cachedThis ∧ env.chainid = ext._cachedChainId
  · obtain ⟨h1, h2⟩ := hc
    simp [AsyncSwap.Swarm.DOMAIN_SEPARATOR.domainSep, h1, h2, hcache]
  · simp [AsyncSwap.Swarm.DOMAIN_SEPARATOR.domainSep, hc]

end AsyncSwap.Swarm.Eip712Domain
