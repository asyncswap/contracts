import Generated.AsyncSwap
import Refinement.Monad
import Refinement.Swarm.Assumptions
import Refinement.Swarm.AsyncSwapConstructor
import Refinement.Swarm.AsyncSwapEip712Domain

/-!
# Named specs: AsyncSwap's constructor, `eip712Domain` and `ShortStrings` (AsyncSwap model)

formal-ast leaves four of AsyncSwap's functions opaque:

* `AsyncSwap.constructor` (`ext.fn_AsyncSwap__309`, "can't write numeraire"), whose results the
  model reads as the `Ext` immutables;
* `EIP712.eip712Domain` (`ext.fn_EIP712_eip712Domain_2155`, "hexString literal");
* `ShortStrings.toString` (`ext.fn_ShortStrings_toString_9528`, "builtin") and
  `ShortStrings.toStringWithFallback` (`ext.fn_ShortStrings_toStringWithFallback_9627`, "reference
  to store").

This module states each one's behaviour as one named structure:

* `Constructor.CtorSpec env0 pm num`: the storage effect (`CtorStorageSpec`: the two guards, then
  `owner := _owner` only), the immutables (`poolManager`, `numeraire`, cached address / chain id /
  separator), the OpenZeppelin `EIP712("AsyncSwap", "1")` immutables (`Assumptions.EIP712Ctor`:
  `_name`/`_version` are the short-string encodings, `_hashedName`/`_hashedVersion` the keccaks of
  the names), and that `feeVault` is a deployed contract.
* `ShortStringsSpec`: `toString(v)` reverts with `InvalidShortString` when `v & 0xFF > 31`, else
  returns the string whose bytes are the first `v & 0xFF` bytes of `v` and writes nothing;
  `toStringWithFallback(v, store)` is `toString(v)` unless `v = FALLBACK_SENTINEL`, when it reads
  `store`.
* `Eip712DomainSpec`: `eip712Domain()` is `(0x0f, _EIP712Name(), _EIP712Version(),
  block.chainid, address(this), 0, [])`.

All three are checked on the bytecode by `test/formal/SpecEip712.t.sol` (and the constructor's
storage half by `test/formal/AsyncSwapConstructor.t.sol`). The `_of_spec` theorems re-derive the
results of `AsyncSwapConstructor.lean` and `AsyncSwapEip712Domain.lean` from these specs alone.
Those files' `ShortStringSpec dec` claims `toString` succeeds on *every* word, which the bytecode
refutes (`byteLength` reverts above 31); it cannot be derived from `ShortStringsSpec`, so the
`eip712Domain` results are re-proved here from the deployed immutables, where the guard passes.
-/

open FormalAst Refinement
open Refinement.Swarm.Assumptions

namespace AsyncSwap.Swarm.Constructor

variable {σ : Type} (ext : Ext σ)

/-- **Named assumption.** What the deployment of AsyncSwap in `env0` with `_poolManager = pm`,
`_numeraire = num` does and fixes. -/
structure CtorSpec (env0 : Env) (pm num : Nat) : Prop where
  storage : CtorStorageSpec ext
  immutables : Immutables ext env0 pm num
  eip712 : EIP712Ctor "AsyncSwap" "1" HASH_ASYNCSWAP HASH_ONE ext.keccak env0.chainid env0.self
    ext._name ext._version ext._hashedName ext._hashedVersion ext._cachedDomainSeparator
    ext._cachedChainId ext._cachedThis
  feeVault_code : ext.codeLength ext.feeVault ≠ 0

variable {ext}

/-- The deployed `_name` immutable. -/
theorem CtorSpec.name_word {env0 : Env} {pm num : Nat} (h : CtorSpec ext env0 pm num) :
    ext._name = 0x4173796e63537761700000000000000000000000000000000000000000000009 := by
  rw [h.eip712.name_eq]; exact Refinement.Swarm.Assumptions.asyncSwap_short

/-- The deployed `_version` immutable. -/
theorem CtorSpec.version_word {env0 : Env} {pm num : Nat} (h : CtorSpec ext env0 pm num) :
    ext._version = 0x3100000000000000000000000000000000000000000000000000000000000001 := by
  rw [h.eip712.version_eq]; exact Refinement.Swarm.Assumptions.one_short

/-- With the deployment's immutables, the separator rebuilt anywhere is the one over the constant
name/version hashes. -/
theorem DOMAIN_SEPARATOR_deployed {env0 : Env} {pm num : Nat} (h : CtorSpec ext env0 pm num)
    (env : Env) (s : σ) :
    AsyncSwap.DOMAIN_SEPARATOR ext env s =
      .ok (ext.keccak [EIP712.TYPE_HASH, HASH_ASYNCSWAP, HASH_ONE, env.chainid, env.self], s) := by
  rw [DOMAIN_SEPARATOR_eq_built ext env0 pm num h.immutables, builtSep, h.eip712.hashedName_eq,
    h.eip712.hashedVersion_eq]

/-! ## `AsyncSwapConstructor.lean`, from `CtorSpec` -/

theorem ctor_invalidNumeraire_of_spec {env0 : Env} {pm0 num0 : Nat} (h : CtorSpec ext env0 pm0 num0)
    (pm num own : Nat) (env : Env) (w : σ) (hc : ext.codeLength num = 0) :
    ext.fn_AsyncSwap__309 pm num own env w = .error ⟨"InvalidNumeraire"⟩ :=
  ctor_invalidNumeraire ext h.storage pm num own env w hc

theorem ctor_zeroOwner_of_spec {env0 : Env} {pm0 num0 : Nat} (h : CtorSpec ext env0 pm0 num0)
    (pm num : Nat) (env : Env) (w : σ) (hc : ext.codeLength num ≠ 0) :
    ext.fn_AsyncSwap__309 pm num 0 env w = .error ⟨"ZeroAddress"⟩ :=
  ctor_zeroOwner ext h.storage pm num env w hc

theorem ctor_reverts_iff_of_spec {env0 : Env} {pm0 num0 : Nat} (h : CtorSpec ext env0 pm0 num0)
    (pm num own : Nat) (env : Env) (w : σ) :
    (∃ e, ext.fn_AsyncSwap__309 pm num own env w = .error e) ↔
      (ext.codeLength num = 0 ∨ own = 0) :=
  ctor_reverts_iff ext h.storage pm num own env w

theorem ctor_ok_iff_of_spec {env0 : Env} {pm0 num0 : Nat} (h : CtorSpec ext env0 pm0 num0)
    (pm num own : Nat) (env : Env) (w w' : σ) :
    ext.fn_AsyncSwap__309 pm num own env w = .ok ((), w') ↔
      ext.codeLength num ≠ 0 ∧ own ≠ 0 ∧ w' = ext.set w { ext.get w with owner := own } :=
  ctor_ok_iff ext h.storage pm num own env w w'

theorem ctor_fresh_state_of_spec {env0 : Env} {pm0 num0 : Nat} (h : CtorSpec ext env0 pm0 num0)
    (hget : ∀ w s, ext.get (ext.set w s) = s)
    (pm num own : Nat) (env : Env) (w w' : σ) (hfresh : ext.get w = default)
    (hok : ext.fn_AsyncSwap__309 pm num own env w = .ok ((), w')) :
    ext.get w' = { (default : State) with owner := own } ∧
      (ext.get w').owner = own ∧ own ≠ 0 ∧ (ext.get w').pendingOwner = 0 ∧
      ext.codeLength num ≠ 0 :=
  ctor_fresh_state ext h.storage hget pm num own env w w' hfresh hok

theorem ctor_deployed_of_spec {env0 : Env} {pm num : Nat} (h : CtorSpec ext env0 pm num)
    (hget : ∀ w s, ext.get (ext.set w s) = s) (own : Nat) (w w' : σ)
    (hok : ext.fn_AsyncSwap__309 pm num own env0 w = .ok ((), w')) :
    ext.poolManager = pm ∧ ext.numeraire = num ∧ ext.codeLength ext.numeraire ≠ 0 ∧
      (ext.get w').owner = own ∧ own ≠ 0 :=
  ctor_deployed ext h.storage hget env0 pm num own w w' h.immutables hok

theorem domainSeparatorV4_eq_built_of_spec {env0 : Env} {pm num : Nat} (h : CtorSpec ext env0 pm num)
    (env : Env) (s : σ) :
    EIP712.«_domainSeparatorV4» ext env s = .ok (builtSep ext env, s) :=
  domainSeparatorV4_eq_built ext env0 pm num h.immutables env s

theorem DOMAIN_SEPARATOR_eq_built_of_spec {env0 : Env} {pm num : Nat} (h : CtorSpec ext env0 pm num)
    (env : Env) (s : σ) :
    AsyncSwap.DOMAIN_SEPARATOR ext env s = .ok (builtSep ext env, s) :=
  DOMAIN_SEPARATOR_eq_built ext env0 pm num h.immutables env s

end AsyncSwap.Swarm.Constructor

namespace AsyncSwap.Swarm.SpecEip712

open AsyncSwap.Swarm.Constructor

variable {σ : Type} (ext : Ext σ)

/-- **Named assumption.** OpenZeppelin `ShortStrings.toString` / `toStringWithFallback`. -/
structure ShortStringsSpec : Prop where
  /-- `byteLength`'s guard: a length byte above 31 reverts. -/
  toString_reverts : ∀ v env w, 31 < ShortStr.len v →
    ext.fn_ShortStrings_toString_9528 v env w = .error ⟨"InvalidShortString"⟩
  /-- Otherwise it succeeds, writes nothing, and returns the string made of the first `len v`
  bytes of `v` (whenever those bytes are UTF-8, the only strings Lean's `String` represents). -/
  toString_ok : ∀ v env w, ShortStr.len v ≤ 31 → ∃ s,
    ext.fn_ShortStrings_toString_9528 v env w = .ok (s, w) ∧
      ∀ t : String, ShortStr.bytes t = ShortStr.decodeBytes v → s = t
  /-- `toString(v)` unless `v` is the sentinel, else the stored string (the setter is never run). -/
  withFallback : ∀ v (g : M σ String) (st : String → M σ Unit) env w,
    ext.fn_ShortStrings_toStringWithFallback_9627 v g st env w =
      if v ≠ ShortStrings.FALLBACK_SENTINEL then ext.fn_ShortStrings_toString_9528 v env w
      else g env w

/-- **Named assumption.** `eip712Domain()` is its body over the generated `_EIP712Name` /
`_EIP712Version`. -/
structure Eip712DomainSpec : Prop where
  body : ∀ env w, ext.fn_EIP712_eip712Domain_2155 env w = Eip712Domain.domainBody ext env w

variable {ext}

/-- Bridge: the old `DomainSpec` is the spec's only field. -/
theorem Eip712DomainSpec.domainSpec (h : Eip712DomainSpec ext) : Eip712Domain.DomainSpec ext :=
  h.body

/-- The generated `byteLength` reverts exactly where `toString` does: its guard is `len v > 31`. -/
theorem byteLength_eq (v : Nat) (env : Env) (w : σ) :
    ShortStrings.byteLength ext v env w =
      if 31 < ShortStr.len v then .error ⟨"InvalidShortString"⟩ else .ok (ShortStr.len v, w) := by
  have hm : v &&& 0xFF = v % 256 := by
    show v &&& (2 ^ 8 - 1) = v % 2 ^ 8
    exact Nat.and_two_pow_sub_one_eq_mod v 8
  unfold ShortStrings.byteLength
  simp only [hm, ShortStr.len]
  by_cases h : 31 < v % 256 <;> simp [h]

/-- `toString` reverts iff the generated `byteLength` does. -/
theorem toString_reverts_iff_byteLength (hs : ShortStringsSpec ext) (v : Nat) (env : Env) (w : σ) :
    (∃ e, ext.fn_ShortStrings_toString_9528 v env w = .error e) ↔
      (∃ e, ShortStrings.byteLength ext v env w = .error e) := by
  rw [byteLength_eq]
  by_cases h : 31 < ShortStr.len v
  · simp [h, hs.toString_reverts v env w h]
  · obtain ⟨s, hs1, -⟩ := hs.toString_ok v env w (by omega)
    simp [h, hs1]

/-- `toString` of a word `encode`d from a string `t` returns `t` and writes nothing. -/
theorem toString_eq (hs : ShortStringsSpec ext) (v : Nat) (t : String) (env : Env) (w : σ)
    (hl : ShortStr.len v ≤ 31) (hb : ShortStr.bytes t = ShortStr.decodeBytes v) :
    ext.fn_ShortStrings_toString_9528 v env w = .ok (t, w) := by
  obtain ⟨s, h1, h2⟩ := hs.toString_ok v env w hl
  rw [h1, h2 t hb]

section deployed

variable {env0 : Env} {pm num : Nat}

/-- The deployed `_name` decodes to `"AsyncSwap"`. -/
theorem toString_name (hc : CtorSpec ext env0 pm num) (hs : ShortStringsSpec ext) (env : Env) (w : σ) :
    ext.fn_ShortStrings_toString_9528 ext._name env w = .ok ("AsyncSwap", w) := by
  apply toString_eq hs
  · rw [hc.eip712.name_eq]; exact deployed_short.1
  · rw [hc.eip712.name_eq]; exact decode_asyncSwap.symm

/-- The deployed `_version` decodes to `"1"`. -/
theorem toString_version (hc : CtorSpec ext env0 pm num) (hs : ShortStringsSpec ext) (env : Env)
    (w : σ) : ext.fn_ShortStrings_toString_9528 ext._version env w = .ok ("1", w) := by
  apply toString_eq hs
  · rw [hc.eip712.version_eq]; exact deployed_short.2.1
  · rw [hc.eip712.version_eq]; exact decode_one.symm

theorem name_ne_sentinel (hc : CtorSpec ext env0 pm num) :
    ext._name ≠ ShortStrings.FALLBACK_SENTINEL := by
  rw [hc.name_word]; decide

theorem version_ne_sentinel (hc : CtorSpec ext env0 pm num) :
    ext._version ≠ ShortStrings.FALLBACK_SENTINEL := by
  rw [hc.version_word]; decide

/-! ## `AsyncSwapEip712Domain.lean`, from the named specs -/

theorem EIP712Name_of_spec (hc : CtorSpec ext env0 pm num) (hs : ShortStringsSpec ext) (env : Env)
    (w : σ) : EIP712.«_EIP712Name» ext env w = .ok ("AsyncSwap", w) := by
  unfold EIP712.«_EIP712Name»
  simp [hs.withFallback, name_ne_sentinel hc, toString_name hc hs]

theorem EIP712Version_of_spec (hc : CtorSpec ext env0 pm num) (hs : ShortStringsSpec ext) (env : Env)
    (w : σ) : EIP712.«_EIP712Version» ext env w = .ok ("1", w) := by
  unfold EIP712.«_EIP712Version»
  simp [hs.withFallback, version_ne_sentinel hc, toString_version hc hs]

theorem eip712Domain_spec_of_spec (hc : CtorSpec ext env0 pm num) (hd : Eip712DomainSpec ext)
    (hs : ShortStringsSpec ext) (env : Env) (w : σ) :
    ext.fn_EIP712_eip712Domain_2155 env w =
      .ok ((0x0f, "AsyncSwap", "1", env.chainid, env.self, 0, []), w) := by
  rw [hd.body]
  simp [Eip712Domain.domainBody, EIP712Name_of_spec hc hs, EIP712Version_of_spec hc hs]

theorem eip712Domain_never_reverts_of_spec (hc : CtorSpec ext env0 pm num) (hd : Eip712DomainSpec ext)
    (hs : ShortStringsSpec ext) (env : Env) (w : σ) (e : Revert) :
    ext.fn_EIP712_eip712Domain_2155 env w ≠ .error e := by
  rw [eip712Domain_spec_of_spec hc hd hs]; simp

theorem eip712Domain_ok_of_spec (hc : CtorSpec ext env0 pm num) (hd : Eip712DomainSpec ext)
    (hs : ShortStringsSpec ext) (env : Env) (w w' : σ) f n v c a salt ex
    (h : ext.fn_EIP712_eip712Domain_2155 env w = .ok ((f, n, v, c, a, salt, ex), w')) :
    w' = w ∧ f = 0x0f ∧ n = "AsyncSwap" ∧ v = "1" ∧ c = env.chainid ∧
      a = env.self ∧ salt = 0 ∧ ex = [] := by
  rw [eip712Domain_spec_of_spec hc hd hs] at h
  simp only [Except.ok.injEq, Prod.mk.injEq] at h
  obtain ⟨⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩, rfl⟩ := h
  exact ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

/-- ERC-5267: with `H` the keccak256 of a string's bytes (at the two deployed names), the separator
rebuilt from `eip712Domain()`'s fields is `DOMAIN_SEPARATOR()`, in every environment. -/
theorem eip712Domain_matches_DOMAIN_SEPARATOR_of_spec (hc : CtorSpec ext env0 pm num)
    (hd : Eip712DomainSpec ext) (hs : ShortStringsSpec ext) (H : String → Nat)
    (hHn : H "AsyncSwap" = HASH_ASYNCSWAP) (hHv : H "1" = HASH_ONE)
    (env : Env) (w w' : σ) f n v c a salt ex
    (h : ext.fn_EIP712_eip712Domain_2155 env w = .ok ((f, n, v, c, a, salt, ex), w')) :
    AsyncSwap.DOMAIN_SEPARATOR ext env w =
      .ok (ext.keccak [EIP712.TYPE_HASH, H n, H v, c, a], w) := by
  obtain ⟨-, -, rfl, rfl, rfl, rfl, -, -⟩ := eip712Domain_ok_of_spec hc hd hs env w w' f n v c a salt ex h
  rw [hHn, hHv, DOMAIN_SEPARATOR_deployed hc]

end deployed

end AsyncSwap.Swarm.SpecEip712
