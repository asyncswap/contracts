import Generated.Router
import Refinement.Monad
import AsyncSwapSpec.Hashing
import Refinement.Swarm.RouterCancelWithSig

/-!
# Named specs for the Router's opaque signature helpers

The Router counterparts of `SpecSigAsyncSwap.lean` (each generated model has its own `FormalAst`
prelude, so the two modules can't be imported together). formal-ast leaves opaque:

* `SignatureChecker.isValidERC1271SignatureNow` (`ext.fn_SignatureChecker_isValidERC1271SignatureNow_1883`):
  `ERC1271Spec`;
* `MessageHashUtils.toTypedDataHash` (`ext.fn_MessageHashUtils_toTypedDataHash_5799`): `TypedDataHashSpec`;
* `OrderSignatures.hashPoolKey` (`ext.fn_OrderSignatures_hashPoolKey_4949`; only the opaque
  `hashOrder` uses it): `HashPoolKeySpec`, equal to `Hashing.hashPoolKey` under `HashingCompat`.

The fields and their meaning are those of the AsyncSwap module. Every theorem of
`RouterCancelWithSig.lean` that took an ad-hoc hypothesis about these functions (`hD`, `PureCallees`,
`h1271`, `hm`) gets a wrapper `<theorem>_of_spec`. `RouterSwapWithSig.lean` takes none: the Router
reaches `setExecutorWithSig` as an external call (`ext.call_AsyncSwap_setExecutorWithSig`), whose
signature checks run in the hook and are covered there.

The specs are checked on the bytecode by `test/formal/SpecSig.t.sol`.
-/

open FormalAst Refinement

namespace Router.Swarm.SpecSig

open Router.Swarm.CancelWithSig (Preserves)

variable {σ : Type} (ext : Ext σ)

/-! ## Words and encodings -/

/-- `OrderSignatures.POOL_KEY_TYPEHASH`
= `keccak256("PoolKey(address currency0,address currency1,uint24 fee,int24 tickSpacing,address hooks)")`. -/
def POOL_KEY_TYPEHASH : Nat := 0x90172dcd3ace21b906ae6acfb8cc73a023df1317b7cda09eeda9489ed5604ae5

/-- `IERC1271.isValidSignature.selector` as bytes. -/
def ERC1271_SELECTOR : List Nat := [0x16, 0x26, 0xba, 0x7e]

/-- `bytes32(IERC1271.isValidSignature.selector)`: the selector left-aligned in a word. -/
def ERC1271_MAGIC : Nat := 0x1626ba7e * 2 ^ 224

/-- `abi.encodeCall(IERC1271.isValidSignature, (hash, signature))`. -/
def erc1271Calldata (hash : Nat) (sig : List Nat) : List Nat :=
  ERC1271_SELECTOR ++ abiEncode [hash, 0x40] ++ abiBytes sig

/-- OpenZeppelin's verdict on a `staticcall` outcome `(success, result)`:
`success && result.length >= 32 && abi.decode(result, (bytes32)) == bytes32(selector)`. -/
def erc1271Verdict (r : Bool × List Nat) : Bool :=
  r.1 && decide (32 ≤ r.2.length) && bytesWord (r.2.take 32) == ERC1271_MAGIC

/-- The 66 bytes `toTypedDataHash` hashes: `"\x19\x01" ‖ domainSeparator ‖ structHash`. -/
def typedPreimage (d s : Nat) : List Nat := [0x19, 0x01] ++ wordBytes d ++ wordBytes s

/-- The world's answer to a `staticcall(target, calldata)` made in environment `env` from world `w`:
`(success, returndata)`. A `staticcall` can't change the world, so there is no new state. -/
abbrev StaticCall (σ : Type) := Env → σ → Nat → List Nat → Bool × List Nat

/-- `hashPoolKey(key)` in the model's hash: `keccak256(abi.encode(POOL_KEY_TYPEHASH, c0, c1, fee,
tickSpacing, hooks))` (`int24 tickSpacing` sign-extended to a word). -/
def poolKeyHash (k : PoolKey) : Nat :=
  ext.keccak [POOL_KEY_TYPEHASH, k.currency0, k.currency1, k.fee, toUnsigned 256 k.tickSpacing, k.hooks]

/-- `_domainSeparatorV4()` in the model: the cached separator on the deployment chain and address,
else `_buildDomainSeparator()`. -/
def domainSep (env : Env) : Nat :=
  if env.self = ext._cachedThis ∧ env.chainid = ext._cachedChainId then ext._cachedDomainSeparator
  else ext.keccak [EIP712.TYPE_HASH, ext._hashedName, ext._hashedVersion, env.chainid, env.self]

/-! ## The named specs -/

/-- **`SignatureChecker.isValidERC1271SignatureNow(signer, hash, signature)`**, relative to the
world's `staticcall` answers `sc`. -/
structure ERC1271Spec (sc : StaticCall σ) : Prop where
  /-- It never reverts (a failed or reverting `staticcall` is a `false`, not a revert). -/
  total : ∀ signer hash sig env w, ∃ b w',
    ext.fn_SignatureChecker_isValidERC1271SignatureNow_1883 signer hash sig env w = .ok (b, w')
  /-- It writes nothing (`view`; the call is a `staticcall`). -/
  readOnly : ∀ signer hash sig, Preserves (ext.fn_SignatureChecker_isValidERC1271SignatureNow_1883 signer hash sig)
  /-- Its result is OpenZeppelin's verdict on `signer.staticcall(isValidSignature(hash, signature))`. -/
  result : ∀ signer hash sig env w b w',
    ext.fn_SignatureChecker_isValidERC1271SignatureNow_1883 signer hash sig env w = .ok (b, w') →
      b = erc1271Verdict (sc env w signer (erc1271Calldata hash sig))

/-- **`MessageHashUtils.toTypedDataHash(domainSeparator, structHash)`**, relative to a byte-level
`keccak256`. -/
structure TypedDataHashSpec (keccak256 : List Nat → Nat) : Prop where
  /-- It never reverts. -/
  total : ∀ d s env w, ∃ r w', ext.fn_MessageHashUtils_toTypedDataHash_5799 d s env w = .ok (r, w')
  /-- It writes nothing (`pure`). -/
  readOnly : ∀ d s, Preserves (ext.fn_MessageHashUtils_toTypedDataHash_5799 d s)
  /-- It returns `keccak256("\x19\x01" ‖ domainSeparator ‖ structHash)`, whatever the environment
  and the state (`pure`). -/
  result : ∀ d s env w r w', ext.fn_MessageHashUtils_toTypedDataHash_5799 d s env w = .ok (r, w') →
    r = keccak256 (typedPreimage d s)

/-- **`OrderSignatures.hashPoolKey(key)`**. -/
structure HashPoolKeySpec : Prop where
  /-- It never reverts. -/
  total : ∀ k env w, ∃ r w', ext.fn_OrderSignatures_hashPoolKey_4949 k env w = .ok (r, w')
  /-- It writes nothing (`pure`). -/
  readOnly : ∀ k, Preserves (ext.fn_OrderSignatures_hashPoolKey_4949 k)
  /-- It returns `poolKeyHash`, whatever the environment and state. -/
  result : ∀ k env w r w', ext.fn_OrderSignatures_hashPoolKey_4949 k env w = .ok (r, w') → r = poolKeyHash ext k

/-! ## Each spec, run -/

section run
variable {ext}

theorem ERC1271Spec.run {sc : StaticCall σ} (h : ERC1271Spec ext sc) (signer hash : Nat) (sig : List Nat)
    (env : Env) (w : σ) :
    ext.fn_SignatureChecker_isValidERC1271SignatureNow_1883 signer hash sig env w
      = .ok (erc1271Verdict (sc env w signer (erc1271Calldata hash sig)), w) := by
  obtain ⟨b, w', hb⟩ := h.total signer hash sig env w
  have e1 := h.readOnly signer hash sig env w b w' hb
  have e2 := h.result signer hash sig env w b w' hb
  subst e1 e2
  exact hb

theorem TypedDataHashSpec.run {k256 : List Nat → Nat} (h : TypedDataHashSpec ext k256) (d s : Nat)
    (env : Env) (w : σ) :
    ext.fn_MessageHashUtils_toTypedDataHash_5799 d s env w = .ok (k256 (typedPreimage d s), w) := by
  obtain ⟨r, w', hr⟩ := h.total d s env w
  have e1 := h.readOnly d s env w r w' hr
  have e2 := h.result d s env w r w' hr
  subst e1 e2
  exact hr

theorem HashPoolKeySpec.run (h : HashPoolKeySpec ext) (k : PoolKey) (env : Env) (w : σ) :
    ext.fn_OrderSignatures_hashPoolKey_4949 k env w = .ok (poolKeyHash ext k, w) := by
  obtain ⟨r, w', hr⟩ := h.total k env w
  have e1 := h.readOnly k env w r w' hr
  have e2 := h.result k env w r w' hr
  subst e1 e2
  exact hr

end run

/-! ## Bridge to `AsyncSwapSpec/Hashing.lean` -/

/-- The generated `PoolKey` as `AsyncSwap.Hashing.PoolKey` (`tickSpacing` as its ABI word). -/
def toSpecKey (k : PoolKey) : AsyncSwap.Hashing.PoolKey :=
  { currency0 := k.currency0, currency1 := k.currency1, fee := k.fee,
    tickSpacing := toUnsigned 256 k.tickSpacing, hooks := k.hooks }

/-- `ext.keccak` is `Hashing`'s `keccak` on `abi.encode` tuples, and the typehash word is
`Hashing`'s. -/
structure HashingCompat (Mh : AsyncSwap.Hashing.Model) : Prop where
  tuple : ∀ ws, ext.keccak ws = Mh.keccak (.tuple ws)
  poolKeyTypehash : POOL_KEY_TYPEHASH = AsyncSwap.Hashing.poolKeyTypehash Mh

theorem poolKeyHash_eq_hashing (Mh : AsyncSwap.Hashing.Model) (hc : HashingCompat ext Mh) (k : PoolKey) :
    poolKeyHash ext k = AsyncSwap.Hashing.hashPoolKey Mh (toSpecKey k) := by
  simp only [poolKeyHash, AsyncSwap.Hashing.hashPoolKey, hc.tuple, hc.poolKeyTypehash, toSpecKey]

/-! ## What the specs give the generated callers -/

/-- `_hashTypedDataV4(sh)` under `TypedDataHashSpec`: `keccak256(0x1901 ‖ _domainSeparatorV4() ‖ sh)`,
no write. -/
theorem hashTypedDataV4_run (k256 : List Nat → Nat) (hT : TypedDataHashSpec ext k256) (sh : Nat)
    (env : Env) (w : σ) :
    EIP712.«_hashTypedDataV4» ext sh env w = .ok (k256 (typedPreimage (domainSep ext env) sh), w) := by
  unfold domainSep
  by_cases hc : env.self = ext._cachedThis ∧ env.chainid = ext._cachedChainId
  · simp [EIP712.«_hashTypedDataV4», EIP712.«_domainSeparatorV4», hc, hT.run]
  · simp [EIP712.«_hashTypedDataV4», EIP712.«_domainSeparatorV4», EIP712.«_buildDomainSeparator», hc,
      hT.run]

theorem tryRecover_5888_ok (hash : Nat) (sig : List Nat) (env : Env) (w : σ) :
    ∃ t, ECDSA.tryRecover_5888 ext hash sig env w = .ok (t, w) := by
  rcases hr : ECDSA.tryRecover_5888 ext hash sig env w with e | ⟨t, w'⟩
  · exfalso
    unfold ECDSA.tryRecover_5888 ECDSA.tryRecover at hr
    simp at hr
    split at hr
    · split at hr
      · cases hr
      · split at hr <;> cases hr
    · cases hr
  · have := CancelWithSig.tryRecover_5888_preserves ext hash sig env w t w' hr
    subst this
    exact ⟨t, rfl⟩

/-- `isValidSignatureNow(signer, hash, sig)` under `ERC1271Spec`: never reverts, writes nothing, and
returns `(ECDSA recovered signer without error) || erc1271Verdict(staticcall)`. -/
theorem isValidSignatureNow_run (sc : StaticCall σ) (hE : ERC1271Spec ext sc) (signer hash : Nat)
    (sig : List Nat) (env : Env) (w : σ) :
    ∃ t, ECDSA.tryRecover_5888 ext hash sig env w = .ok (t, w) ∧
      SignatureChecker.isValidSignatureNow ext signer hash sig env w
        = .ok (((t.2.1 == 0) && (t.1 == signer)) ||
            erc1271Verdict (sc env w signer (erc1271Calldata hash sig)), w) := by
  obtain ⟨t, ht⟩ := tryRecover_5888_ok ext hash sig env w
  refine ⟨t, ht, ?_⟩
  by_cases hc : ((t.2.1 == 0) && (t.1 == signer)) = true
  · simp only [SignatureChecker.isValidSignatureNow, run_bind, ht, hc]
    simp_all
  · simp only [Bool.not_eq_true] at hc
    simp only [SignatureChecker.isValidSignatureNow, run_bind, ht, hc]
    simp_all [hE.run]

/-! ## Wrappers: `RouterCancelWithSig.lean` -/

section cancel
open Router.Swarm.CancelWithSig

theorem isValidSignatureNow_preserves_of_spec (sc : StaticCall σ) (hE : ERC1271Spec ext sc)
    (signer hash : Nat) (sig : List Nat) :
    Preserves (SignatureChecker.isValidSignatureNow ext signer hash sig) :=
  isValidSignatureNow_preserves ext signer hash sig (hE.readOnly signer hash sig)

theorem hashTypedDataV4_preserves_of_spec (k256 : List Nat → Nat) (hT : TypedDataHashSpec ext k256)
    (sh : Nat) : Preserves (EIP712.«_hashTypedDataV4» ext sh) :=
  hashTypedDataV4_preserves ext sh (fun d => hT.readOnly d sh)

variable (o : AsyncOrder) (nonce deadline : Nat) (signature : List Nat) (env : Env) (w : σ)

/-- The two specs give `CancelWithSig.PureCallees`. -/
theorem pureCallees_of_spec (k256 : List Nat → Nat) (sc : StaticCall σ) (hT : TypedDataHashSpec ext k256)
    (hE : ERC1271Spec ext sc) : PureCallees ext o signature :=
  ⟨fun d sh => hT.readOnly d sh, fun hash => hE.readOnly o.owner hash signature⟩

theorem cancelWithSig_invalid_sig_of_spec (k256 : List Nat → Nat) (hT : TypedDataHashSpec ext k256)
    (amountIn p : Nat) (w3 : σ) (ht : ¬ deadline < env.timestamp)
    (hn : (ext.get w).cancelNonceUsed o.owner nonce = false)
    (hi : ext.view_AsyncSwap_asyncOrderInfo env (CancelWithSig.burn ext w o.owner nonce) ext.HOOK (CancelWithSig.poolIdOf ext o)
      (CancelWithSig.orderIdOf ext env o) = .ok (amountIn, p))
    (hS : SignatureChecker.isValidSignatureNow ext o.owner
      (k256 (typedPreimage (domainSep ext env) (CancelWithSig.cancelHash ext o (CancelWithSig.orderIdOf ext env o) amountIn nonce deadline)))
      signature env (CancelWithSig.burn ext w o.owner nonce) = .ok (false, w3)) :
    Router.cancelWithSig ext o nonce deadline signature env w = .error ⟨"InvalidSignature"⟩ :=
  cancelWithSig_invalid_sig ext o nonce deadline signature env w amountIn p _ _ w3 ht hn hi
    (hashTypedDataV4_run ext k256 hT _ env _) hS

theorem cancelWithSig_ok_of_spec (k256 : List Nat → Nat) (hT : TypedDataHashSpec ext k256)
    (amountIn p : Nat) (w3 : σ) (ht : ¬ deadline < env.timestamp)
    (hn : (ext.get w).cancelNonceUsed o.owner nonce = false)
    (hi : ext.view_AsyncSwap_asyncOrderInfo env (CancelWithSig.burn ext w o.owner nonce) ext.HOOK (CancelWithSig.poolIdOf ext o)
      (CancelWithSig.orderIdOf ext env o) = .ok (amountIn, p))
    (hS : SignatureChecker.isValidSignatureNow ext o.owner
      (k256 (typedPreimage (domainSep ext env) (CancelWithSig.cancelHash ext o (CancelWithSig.orderIdOf ext env o) amountIn nonce deadline)))
      signature env (CancelWithSig.burn ext w o.owner nonce) = .ok (true, w3)) :
    Router.cancelWithSig ext o nonce deadline signature env w = CancelWithSig.tail ext o env w3 :=
  cancelWithSig_ok ext o nonce deadline signature env w amountIn p _ _ w3 ht hn hi
    (hashTypedDataV4_run ext k256 hT _ env _) hS

theorem cancelWithSig_ok_state_of_spec (k256 : List Nat → Nat) (sc : StaticCall σ)
    (hT : TypedDataHashSpec ext k256) (hE : ERC1271Spec ext sc) (w' : σ)
    (hok : Router.cancelWithSig ext o nonce deadline signature env w = .ok ((), w')) :
    (ext.get w).cancelNonceUsed o.owner nonce = false ∧
    ∃ r, ext.call_IPoolManager_unlock ext.POOLMANAGER (Router.callbackData 2 o 0) env
      (CancelWithSig.burn ext w o.owner nonce) = .ok (r, w') :=
  cancelWithSig_ok_state ext o nonce deadline signature env w w'
    (pureCallees_of_spec ext o signature k256 sc hT hE) hok

theorem cancelWithSig_no_replay_of_spec (k256 : List Nat → Nat) (sc : StaticCall σ)
    (hT : TypedDataHashSpec ext k256) (hE : ERC1271Spec ext sc) (w' : σ)
    (hget : ∀ w s, ext.get (ext.set w s) = s)
    (hmono : ∀ w₀ r w₁, ext.call_IPoolManager_unlock ext.POOLMANAGER (Router.callbackData 2 o 0) env w₀
      = .ok (r, w₁) → (ext.get w₀).cancelNonceUsed o.owner nonce = true →
        (ext.get w₁).cancelNonceUsed o.owner nonce = true)
    (hok : Router.cancelWithSig ext o nonce deadline signature env w = .ok ((), w'))
    (o' : AsyncOrder) (ho : o'.owner = o.owner) (deadline' : Nat) (signature' : List Nat) (env' : Env) :
    ∃ e, Router.cancelWithSig ext o' nonce deadline' signature' env' w' = .error e :=
  cancelWithSig_no_replay ext o nonce deadline signature env w w' hget
    (pureCallees_of_spec ext o signature k256 sc hT hE) hmono hok o' ho deadline' signature' env'

end cancel

end Router.Swarm.SpecSig
