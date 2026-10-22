import Generated.Router
import Refinement.Monad
import Refinement.Swarm.RouterDOMAIN_SEPARATOR

/-!
# `EIP712.eip712Domain` (Router)

Same statement as `AsyncSwapEip712Domain` for the Router's copy of OpenZeppelin `EIP712`
(`EIP712.sol:114`): formal-ast leaves it opaque (`ext.fn_EIP712_eip712Domain_1758`, "hexString
literal"), as well as `ShortStrings.toStringWithFallback` / `toString`. Under the two
transcription assumptions `DomainSpec` and `ShortStringSpec dec`, `eip712Domain` never reverts,
writes nothing, returns `(0x0f, name, version, block.chainid, address(this), 0, [])`, and the
separator rebuilt from its fields is `DOMAIN_SEPARATOR()`.
-/

open FormalAst Refinement

namespace Router.Swarm.Eip712Domain

variable {σ : Type} (ext : Ext σ)

/-- The body of `eip712Domain()` as the Solidity states it. -/
def domainBody : M σ (Nat × String × String × Nat × Nat × Nat × (List Nat)) := do
  let n ← EIP712.«_EIP712Name» ext
  let v ← EIP712.«_EIP712Version» ext
  return (0x0f, n, v, (← read).chainid, (← read).self, 0, [])

/-- Assumption: the opaque `eip712Domain` is `domainBody`. -/
def DomainSpec : Prop :=
  ∀ env w, ext.fn_EIP712_eip712Domain_1758 env w = domainBody ext env w

/-- Assumption: OpenZeppelin `ShortStrings.toStringWithFallback` / `toString`. -/
structure ShortStringSpec (dec : Nat → String) : Prop where
  toString : ∀ v env w, ext.fn_ShortStrings_toString_5595 v env w = .ok (dec v, w)
  withFallback : ∀ v (g : M σ String) (s : String → M σ Unit) env w,
    ext.fn_ShortStrings_toStringWithFallback_5694 v g s env w =
      if v ≠ ShortStrings.FALLBACK_SENTINEL then ext.fn_ShortStrings_toString_5595 v env w
      else g env w

def nameStr (dec : Nat → String) (w : σ) : String :=
  if ext._name ≠ ShortStrings.FALLBACK_SENTINEL then dec ext._name else (ext.get w)._nameFallback

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

theorem eip712Domain_spec (dec : Nat → String) (hd : DomainSpec ext) (hs : ShortStringSpec ext dec)
    (env : Env) (w : σ) :
    ext.fn_EIP712_eip712Domain_1758 env w =
      .ok ((0x0f, nameStr ext dec w, versionStr ext dec w, env.chainid, env.self, 0, []), w) := by
  rw [hd]
  simp [domainBody, EIP712Name_spec ext dec hs, EIP712Version_spec ext dec hs]

theorem eip712Domain_never_reverts (dec : Nat → String) (hd : DomainSpec ext)
    (hs : ShortStringSpec ext dec) (env : Env) (w : σ) (e : Revert) :
    ext.fn_EIP712_eip712Domain_1758 env w ≠ .error e := by
  rw [eip712Domain_spec ext dec hd hs]; simp

theorem eip712Domain_ok (dec : Nat → String) (hd : DomainSpec ext) (hs : ShortStringSpec ext dec)
    (env : Env) (w w' : σ) f n v c a salt ex
    (h : ext.fn_EIP712_eip712Domain_1758 env w = .ok ((f, n, v, c, a, salt, ex), w')) :
    w' = w ∧ f = 0x0f ∧ n = nameStr ext dec w ∧ v = versionStr ext dec w ∧ c = env.chainid ∧
      a = env.self ∧ salt = 0 ∧ ex = [] := by
  rw [eip712Domain_spec ext dec hd hs] at h
  simp only [Except.ok.injEq, Prod.mk.injEq] at h
  obtain ⟨⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩, rfl⟩ := h
  exact ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

theorem eip712Domain_short (dec : Nat → String) (hd : DomainSpec ext) (hs : ShortStringSpec ext dec)
    (hn : ext._name ≠ ShortStrings.FALLBACK_SENTINEL)
    (hv : ext._version ≠ ShortStrings.FALLBACK_SENTINEL) (env : Env) (w : σ) :
    ext.fn_EIP712_eip712Domain_1758 env w =
      .ok ((0x0f, dec ext._name, dec ext._version, env.chainid, env.self, 0, []), w) := by
  rw [eip712Domain_spec ext dec hd hs]
  simp [nameStr, versionStr, hn, hv]

theorem eip712Domain_matches_DOMAIN_SEPARATOR (dec : Nat → String) (H : String → Nat)
    (hd : DomainSpec ext) (hs : ShortStringSpec ext dec) (env : Env) (w w' : σ) f n v c a salt ex
    (hname : ext._hashedName = H (nameStr ext dec w))
    (hver : ext._hashedVersion = H (versionStr ext dec w))
    (hcache : ext._cachedDomainSeparator =
      ext.keccak [EIP712.TYPE_HASH, ext._hashedName, ext._hashedVersion, ext._cachedChainId,
        ext._cachedThis])
    (h : ext.fn_EIP712_eip712Domain_1758 env w = .ok ((f, n, v, c, a, salt, ex), w')) :
    Router.DOMAIN_SEPARATOR ext env w =
      .ok (ext.keccak [EIP712.TYPE_HASH, H n, H v, c, a], w) := by
  obtain ⟨-, -, rfl, rfl, rfl, rfl, -, -⟩ := eip712Domain_ok ext dec hd hs env w w' f n v c a salt ex h
  rw [Router.Swarm.DOMAIN_SEPARATOR.DOMAIN_SEPARATOR_spec, ← hname, ← hver]
  by_cases hc : env.self = ext._cachedThis ∧ env.chainid = ext._cachedChainId
  · obtain ⟨h1, h2⟩ := hc
    simp [Router.Swarm.DOMAIN_SEPARATOR.domainSep, h1, h2, hcache]
  · simp [Router.Swarm.DOMAIN_SEPARATOR.domainSep, hc]

end Router.Swarm.Eip712Domain
