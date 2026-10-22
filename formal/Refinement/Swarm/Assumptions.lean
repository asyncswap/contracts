/-!
# Named assumptions for the opaque constructors (shared, contract-independent part)

formal-ast leaves `AsyncSwap.constructor` (`ext.fn_AsyncSwap__309`) and `Router.constructor`
(`ext.fn_Router__150`) opaque and models what they fix as `Ext` immutables. Each generated module
carries its own `FormalAst` prelude, so the two can't be imported together: this module holds the
contract-independent part of the constructor and `ShortStrings` assumptions, in plain Lean over
words, and `SpecEip712AsyncSwap.lean` / `RouterConstructor.lean` bundle it with each model's `Ext`
fields into one named assumption per contract (`AsyncSwap.Swarm.Constructor.CtorSpec`,
`Router.Swarm.Constructor.CtorSpec`). They are discharged by `test/formal/AsyncSwapConstructor.t.sol`,
`test/formal/RouterConstructor.t.sol` and `test/formal/SpecEip712.t.sol`.

* `ShortStr.toShortStringWithFallback`: OpenZeppelin `ShortStrings.toShortStringWithFallback`
  as a pure function of the string (`bytes32(bytes(s)) | len` when `len ≤ 31`, else the sentinel
  `0xFF` with the string written to the fallback slot). It is not a black box: the encoded
  immutables of `"AsyncSwap"`, `"1"` and `"AsyncSwap Router"` are computed below by the kernel.
* `ShortStr.decodeBytes`: the bytes OpenZeppelin `ShortStrings.toString(v)` returns, the first
  `v & 0xFF` bytes of the word (it reverts with `InvalidShortString` when `v & 0xFF > 31`).
* `EIP712Ctor`: the immutables the OpenZeppelin `EIP712(name, version)` constructor fixes.
-/

namespace Refinement.Swarm.Assumptions

/-- `ShortStrings.FALLBACK_SENTINEL`. -/
def FALLBACK_SENTINEL : Nat := 0xFF

/-- `keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")`. -/
def TYPE_HASH : Nat := 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f

namespace ShortStr

/-- Big-endian value of a byte string. -/
def bytesBE (l : List UInt8) : Nat := l.foldl (fun acc b => acc * 256 + b.toNat) 0

/-- `bytes(s)`. -/
def bytes (s : String) : List UInt8 := s.toUTF8.toList

/-- OpenZeppelin `toShortString(s)` when `bytes(s).length ≤ 31`:
`bytes32(uint256(bytes32(bytes(s))) | length)` (bytes left-aligned, length in the low byte). -/
def encode (s : String) : Nat :=
  bytesBE (bytes s) * 256 ^ (32 - (bytes s).length) + (bytes s).length

/-- The immutable `toShortStringWithFallback(s, store)` returns. -/
def toShortStringWithFallback (s : String) : Nat :=
  if (bytes s).length ≤ 31 then encode s else FALLBACK_SENTINEL

/-- What `toShortStringWithFallback(s, store)` writes to `store`: nothing for a short string,
`s` otherwise. -/
def fallbackStore (s : String) : Option String :=
  if (bytes s).length ≤ 31 then none else some s

/-- `byteLength(v)` before its guard: the low byte of the word. -/
def len (v : Nat) : Nat := v % 256

/-- Byte `i` (big-endian, `0 ≤ i < 32`) of the word `v`. -/
def byteAt (v i : Nat) : UInt8 := UInt8.ofNat (v / 256 ^ (31 - i) % 256)

/-- The bytes of `toString(v)` when `len v ≤ 31`: the first `len v` bytes of the word. -/
def decodeBytes (v : Nat) : List UInt8 := (List.range (len v)).map (byteAt v)

end ShortStr

/-- `keccak256("AsyncSwap")`. -/
def HASH_ASYNCSWAP : Nat := 0x72bb025359d2292b4e59f168b9de8e3967bb96d5053211bfa4d833b6867bdb86
/-- `keccak256("1")`. -/
def HASH_ONE : Nat := 0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6
/-- `keccak256("AsyncSwap Router")`. -/
def HASH_ASYNCSWAP_ROUTER : Nat := 0x08476627fc511b8f0bf0674a96c4492f05a5c5df2795822dac01ecd5bdbd9167

/-- What OpenZeppelin `EIP712(name, version)`'s constructor fixes, deployed at address `addr` on chain
`chainid`, with `hName = keccak256(bytes(name))`, `hVersion = keccak256(bytes(version))`:
`_name`/`_version` are `toShortStringWithFallback` of the strings, `_hashedName`/`_hashedVersion`
their hashes, `_cachedChainId = block.chainid`, `_cachedThis = address(this)` and
`_cachedDomainSeparator = _buildDomainSeparator()` at deployment. -/
structure EIP712Ctor (name version : String) (hName hVersion : Nat) (keccak : List Nat → Nat)
    (chainid addr : Nat)
    (nameW versionW hashedName hashedVersion cachedSep cachedChainId cachedThis : Nat) : Prop where
  name_eq : nameW = ShortStr.toShortStringWithFallback name
  version_eq : versionW = ShortStr.toShortStringWithFallback version
  hashedName_eq : hashedName = hName
  hashedVersion_eq : hashedVersion = hVersion
  cachedChainId_eq : cachedChainId = chainid
  cachedThis_eq : cachedThis = addr
  cachedSep_eq : cachedSep = keccak [TYPE_HASH, hashedName, hashedVersion, chainid, addr]

/-! ## The deployed names, computed -/

theorem asyncSwap_short : ShortStr.toShortStringWithFallback "AsyncSwap" =
    0x4173796e63537761700000000000000000000000000000000000000000000009 := by decide +kernel

theorem one_short : ShortStr.toShortStringWithFallback "1" =
    0x3100000000000000000000000000000000000000000000000000000000000001 := by decide +kernel

theorem asyncSwapRouter_short : ShortStr.toShortStringWithFallback "AsyncSwap Router" =
    0x4173796e635377617020526f7574657200000000000000000000000000000010 := by decide +kernel

/-- None of the three names is long, so no fallback slot is written. -/
theorem fallbackStore_none : ShortStr.fallbackStore "AsyncSwap" = none ∧
    ShortStr.fallbackStore "1" = none ∧ ShortStr.fallbackStore "AsyncSwap Router" = none := by
  refine ⟨?_, ?_, ?_⟩ <;> decide +kernel

/-- `toString` decodes each deployed immutable back to its string (the encoding round-trips). -/
theorem decode_asyncSwap :
    ShortStr.decodeBytes (ShortStr.toShortStringWithFallback "AsyncSwap") = ShortStr.bytes "AsyncSwap" := by
  decide +kernel

theorem decode_one : ShortStr.decodeBytes (ShortStr.toShortStringWithFallback "1") = ShortStr.bytes "1" := by
  decide +kernel

theorem decode_asyncSwapRouter :
    ShortStr.decodeBytes (ShortStr.toShortStringWithFallback "AsyncSwap Router") =
      ShortStr.bytes "AsyncSwap Router" := by
  decide +kernel

/-- The deployed immutables pass `byteLength`'s guard and are not the fallback sentinel. -/
theorem deployed_short :
    ShortStr.len (ShortStr.toShortStringWithFallback "AsyncSwap") ≤ 31 ∧
    ShortStr.len (ShortStr.toShortStringWithFallback "1") ≤ 31 ∧
    ShortStr.len (ShortStr.toShortStringWithFallback "AsyncSwap Router") ≤ 31 ∧
    ShortStr.toShortStringWithFallback "AsyncSwap" ≠ FALLBACK_SENTINEL ∧
    ShortStr.toShortStringWithFallback "1" ≠ FALLBACK_SENTINEL ∧
    ShortStr.toShortStringWithFallback "AsyncSwap Router" ≠ FALLBACK_SENTINEL := by
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_⟩ <;> decide +kernel

end Refinement.Swarm.Assumptions
