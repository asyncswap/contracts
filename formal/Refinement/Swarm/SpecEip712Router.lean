import Generated.Router
import Refinement.Monad
import Refinement.Swarm.Assumptions
import Refinement.Swarm.RouterConstructor
import Refinement.Swarm.RouterEip712Domain

/-!
# Named specs: `eip712Domain` and `ShortStrings` (Router model)

The Router's copy of OpenZeppelin `EIP712` / `ShortStrings`, as in `SpecEip712AsyncSwap.lean`:
formal-ast leaves `EIP712.eip712Domain` (`ext.fn_EIP712_eip712Domain_1758`),
`ShortStrings.toString` (`ext.fn_ShortStrings_toString_5595`) and
`ShortStrings.toStringWithFallback` (`ext.fn_ShortStrings_toStringWithFallback_5694`) opaque.

* `ShortStringsSpec`: `toString(v)` reverts with `InvalidShortString` when `v & 0xFF > 31`, else
  returns the first `v & 0xFF` bytes of `v` and writes nothing; `toStringWithFallback(v, store)` is
  `toString(v)` unless `v = FALLBACK_SENTINEL`, when it reads `store`.
* `Eip712DomainSpec`: `eip712Domain()` is `(0x0f, _EIP712Name(), _EIP712Version(),
  block.chainid, address(this), 0, [])`.

With the constructor's `Router.Swarm.Constructor.CtorSpec` (`RouterConstructor.lean`), the
`_of_spec` theorems re-derive `RouterEip712Domain.lean`'s results. Checked on the bytecode by
`test/formal/SpecEip712.t.sol`.
-/

open FormalAst Refinement
open Refinement.Swarm.Assumptions

namespace Router.Swarm.SpecEip712

open Router.Swarm.Constructor

variable {σ : Type} (ext : Ext σ)

/-- **Named assumption.** OpenZeppelin `ShortStrings.toString` / `toStringWithFallback`. -/
structure ShortStringsSpec : Prop where
  /-- `byteLength`'s guard: a length byte above 31 reverts. -/
  toString_reverts : ∀ v env w, 31 < ShortStr.len v →
    ext.fn_ShortStrings_toString_5595 v env w = .error ⟨"InvalidShortString"⟩
  /-- Otherwise it succeeds, writes nothing, and returns the string made of the first `len v`
  bytes of `v` (whenever those bytes are UTF-8, the only strings Lean's `String` represents). -/
  toString_ok : ∀ v env w, ShortStr.len v ≤ 31 → ∃ s,
    ext.fn_ShortStrings_toString_5595 v env w = .ok (s, w) ∧
      ∀ t : String, ShortStr.bytes t = ShortStr.decodeBytes v → s = t
  /-- `toString(v)` unless `v` is the sentinel, else the stored string (the setter is never run). -/
  withFallback : ∀ v (g : M σ String) (st : String → M σ Unit) env w,
    ext.fn_ShortStrings_toStringWithFallback_5694 v g st env w =
      if v ≠ ShortStrings.FALLBACK_SENTINEL then ext.fn_ShortStrings_toString_5595 v env w
      else g env w

/-- **Named assumption.** `eip712Domain()` is its body over the generated `_EIP712Name` /
`_EIP712Version`. -/
structure Eip712DomainSpec : Prop where
  body : ∀ env w, ext.fn_EIP712_eip712Domain_1758 env w = Router.Swarm.Eip712Domain.domainBody ext env w

variable {ext}

/-- Bridge: the old `DomainSpec` is the spec's only field. -/
theorem Eip712DomainSpec.domainSpec (h : Eip712DomainSpec ext) : Router.Swarm.Eip712Domain.DomainSpec ext :=
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
    (∃ e, ext.fn_ShortStrings_toString_5595 v env w = .error e) ↔
      (∃ e, ShortStrings.byteLength ext v env w = .error e) := by
  rw [byteLength_eq]
  by_cases h : 31 < ShortStr.len v
  · simp [h, hs.toString_reverts v env w h]
  · obtain ⟨s, hs1, -⟩ := hs.toString_ok v env w (by omega)
    simp [h, hs1]

/-- `toString` of a word `encode`d from a string `t` returns `t` and writes nothing. -/
theorem toString_eq (hs : ShortStringsSpec ext) (v : Nat) (t : String) (env : Env) (w : σ)
    (hl : ShortStr.len v ≤ 31) (hb : ShortStr.bytes t = ShortStr.decodeBytes v) :
    ext.fn_ShortStrings_toString_5595 v env w = .ok (t, w) := by
  obtain ⟨s, h1, h2⟩ := hs.toString_ok v env w hl
  rw [h1, h2 t hb]

section deployed

variable {env0 : Env} {pm hk p2 : Nat}

/-- The deployed `_name` decodes to `"AsyncSwap Router"`. -/
theorem toString_name (hc : CtorSpec ext env0 pm hk p2) (hs : ShortStringsSpec ext) (env : Env) (w : σ) :
    ext.fn_ShortStrings_toString_5595 ext._name env w = .ok ("AsyncSwap Router", w) := by
  apply toString_eq hs
  · rw [hc.eip712.name_eq]; exact deployed_short.2.2.1
  · rw [hc.eip712.name_eq]; exact decode_asyncSwapRouter.symm

/-- The deployed `_version` decodes to `"1"`. -/
theorem toString_version (hc : CtorSpec ext env0 pm hk p2) (hs : ShortStringsSpec ext) (env : Env)
    (w : σ) : ext.fn_ShortStrings_toString_5595 ext._version env w = .ok ("1", w) := by
  apply toString_eq hs
  · rw [hc.eip712.version_eq]; exact deployed_short.2.1
  · rw [hc.eip712.version_eq]; exact decode_one.symm

theorem name_ne_sentinel (hc : CtorSpec ext env0 pm hk p2) :
    ext._name ≠ ShortStrings.FALLBACK_SENTINEL := by
  rw [hc.name_word]; decide

theorem version_ne_sentinel (hc : CtorSpec ext env0 pm hk p2) :
    ext._version ≠ ShortStrings.FALLBACK_SENTINEL := by
  rw [hc.version_word]; decide

/-! ## `RouterEip712Domain.lean`, from the named specs -/

theorem EIP712Name_of_spec (hc : CtorSpec ext env0 pm hk p2) (hs : ShortStringsSpec ext) (env : Env)
    (w : σ) : EIP712.«_EIP712Name» ext env w = .ok ("AsyncSwap Router", w) := by
  unfold EIP712.«_EIP712Name»
  simp [hs.withFallback, name_ne_sentinel hc, toString_name hc hs]

theorem EIP712Version_of_spec (hc : CtorSpec ext env0 pm hk p2) (hs : ShortStringsSpec ext) (env : Env)
    (w : σ) : EIP712.«_EIP712Version» ext env w = .ok ("1", w) := by
  unfold EIP712.«_EIP712Version»
  simp [hs.withFallback, version_ne_sentinel hc, toString_version hc hs]

theorem eip712Domain_spec_of_spec (hc : CtorSpec ext env0 pm hk p2) (hd : Eip712DomainSpec ext)
    (hs : ShortStringsSpec ext) (env : Env) (w : σ) :
    ext.fn_EIP712_eip712Domain_1758 env w =
      .ok ((0x0f, "AsyncSwap Router", "1", env.chainid, env.self, 0, []), w) := by
  rw [hd.body]
  simp [Router.Swarm.Eip712Domain.domainBody, EIP712Name_of_spec hc hs, EIP712Version_of_spec hc hs]

theorem eip712Domain_never_reverts_of_spec (hc : CtorSpec ext env0 pm hk p2) (hd : Eip712DomainSpec ext)
    (hs : ShortStringsSpec ext) (env : Env) (w : σ) (e : Revert) :
    ext.fn_EIP712_eip712Domain_1758 env w ≠ .error e := by
  rw [eip712Domain_spec_of_spec hc hd hs]; simp

theorem eip712Domain_ok_of_spec (hc : CtorSpec ext env0 pm hk p2) (hd : Eip712DomainSpec ext)
    (hs : ShortStringsSpec ext) (env : Env) (w w' : σ) f n v c a salt ex
    (h : ext.fn_EIP712_eip712Domain_1758 env w = .ok ((f, n, v, c, a, salt, ex), w')) :
    w' = w ∧ f = 0x0f ∧ n = "AsyncSwap Router" ∧ v = "1" ∧ c = env.chainid ∧
      a = env.self ∧ salt = 0 ∧ ex = [] := by
  rw [eip712Domain_spec_of_spec hc hd hs] at h
  simp only [Except.ok.injEq, Prod.mk.injEq] at h
  obtain ⟨⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩, rfl⟩ := h
  exact ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

/-- ERC-5267: with `H` the keccak256 of a string's bytes (at the two deployed names), the separator
rebuilt from `eip712Domain()`'s fields is `DOMAIN_SEPARATOR()`, in every environment. -/
theorem eip712Domain_matches_DOMAIN_SEPARATOR_of_spec (hc : CtorSpec ext env0 pm hk p2)
    (hd : Eip712DomainSpec ext) (hs : ShortStringsSpec ext) (H : String → Nat)
    (hHn : H "AsyncSwap Router" = HASH_ASYNCSWAP_ROUTER) (hHv : H "1" = HASH_ONE)
    (env : Env) (w w' : σ) f n v c a salt ex
    (h : ext.fn_EIP712_eip712Domain_1758 env w = .ok ((f, n, v, c, a, salt, ex), w')) :
    Router.DOMAIN_SEPARATOR ext env w =
      .ok (ext.keccak [EIP712.TYPE_HASH, H n, H v, c, a], w) := by
  obtain ⟨-, -, rfl, rfl, rfl, rfl, -, -⟩ := eip712Domain_ok_of_spec hc hd hs env w w' f n v c a salt ex h
  rw [hHn, hHv, DOMAIN_SEPARATOR_deployed hc]

end deployed

end Router.Swarm.SpecEip712
