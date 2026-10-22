import Generated.AsyncSwap
import Refinement.Monad
import AsyncSwapSpec.Hashing
import Refinement.Swarm.AsyncSwapSetExecutorWithSig
import Refinement.Swarm.AsyncSwapUpdatePriceWithSig

/-!
# Named specs for AsyncSwap's opaque signature helpers

formal-ast leaves four of the hook's signature helpers opaque (`Ext` fields):

* `SignatureChecker.isValidERC1271SignatureNow` (`ext.fn_SignatureChecker_isValidERC1271SignatureNow_2280`,
  "builtin staticcall"): `ERC1271Spec`;
* `MessageHashUtils.toTypedDataHash` (`ext.fn_MessageHashUtils_toTypedDataHash_9732`, assembly):
  `TypedDataHashSpec`;
* `OrderSignatures.hashSetExecutor` (`ext.fn_OrderSignatures_hashSetExecutor_9244`, "keccak256 of a
  non-literal constant"): `HashSetExecutorSpec`;
* `OrderSignatures.hashPoolKey` (`ext.fn_OrderSignatures_hashPoolKey_9171`, same reason; no generated
  def calls it, `hashSetExecutor` inlines it): `HashPoolKeySpec`.

Each spec is one `structure` whose fields are the properties: it never reverts (`total`), it writes
nothing (`readOnly`), and its result (`result`). The hashes are stated with the model's own
`ext.keccak` (keccak256 of the ABI encoding of a word list), the typehashes as the literal words
solc folds them to; the typed-data envelope `0x1901 ‖ domain ‖ struct` is not a word list, so its
spec takes a byte-level `keccak256 : List Nat → Nat`. The ERC-1271 spec is relative to the world's
answer to a `staticcall` (`StaticCall`): the verdict is `success && returndata.length >= 32 &&
word0 == bytes32(0x1626ba7e)`, the call data is `abi.encodeCall(IERC1271.isValidSignature, (hash, sig))`.

`HashingCompat` relates `ext.keccak` and the typehash words to `AsyncSwapSpec/Hashing.lean`'s
symbolic `Model`; under it the two struct hashes are exactly `Hashing.hashPoolKey` and
`Hashing.hashSetExecutor` (`poolKeyHash_eq_hashing`, `setExecutorHash_eq_hashing`).

Then every theorem of `AsyncSwapSetExecutorWithSig.lean` / `AsyncSwapUpdatePriceWithSig.lean` that
took an ad-hoc hypothesis about these functions (`hH`, `hH'`, `hD`, `PureCallees`, `h1271`, `hm`)
gets a wrapper `<theorem>_of_spec` with the same conclusion, taking the named specs instead.

The specs are checked on the bytecode by `test/formal/SpecSig.t.sol`.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.SpecSig

open AsyncSwap.Swarm.SetExecutorWithSig (Preserves burn grant poolIdOf)

variable {σ : Type} (ext : Ext σ)

/-! ## Words and encodings -/

/-- `OrderSignatures.POOL_KEY_TYPEHASH`
= `keccak256("PoolKey(address currency0,address currency1,uint24 fee,int24 tickSpacing,address hooks)")`. -/
def POOL_KEY_TYPEHASH : Nat := 0x90172dcd3ace21b906ae6acfb8cc73a023df1317b7cda09eeda9489ed5604ae5

/-- `OrderSignatures.SET_EXECUTOR_TYPEHASH` = `keccak256("SetExecutor(address maker,address executor,
bool allow,PoolKey pool,uint256 nonce,uint256 deadline)" ‖ POOL_KEY_TYPE)`. -/
def SET_EXECUTOR_TYPEHASH : Nat := 0xe4479d9c4dc3f7c35677efc85aaca516cb63a3977aae04f893f8c6b86986c965

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

/-- `hashSetExecutor(key, maker, executor, allow, nonce, deadline)` in the model's hash. -/
def setExecutorHash (k : PoolKey) (maker executor : Nat) (allow : Bool) (nonce deadline : Nat) : Nat :=
  ext.keccak [SET_EXECUTOR_TYPEHASH, maker, executor, ybool allow, poolKeyHash ext k, nonce, deadline]

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
    ext.fn_SignatureChecker_isValidERC1271SignatureNow_2280 signer hash sig env w = .ok (b, w')
  /-- It writes nothing (`view`; the call is a `staticcall`). -/
  readOnly : ∀ signer hash sig, Preserves (ext.fn_SignatureChecker_isValidERC1271SignatureNow_2280 signer hash sig)
  /-- Its result is OpenZeppelin's verdict on `signer.staticcall(isValidSignature(hash, signature))`. -/
  result : ∀ signer hash sig env w b w',
    ext.fn_SignatureChecker_isValidERC1271SignatureNow_2280 signer hash sig env w = .ok (b, w') →
      b = erc1271Verdict (sc env w signer (erc1271Calldata hash sig))

/-- **`MessageHashUtils.toTypedDataHash(domainSeparator, structHash)`**, relative to a byte-level
`keccak256`. -/
structure TypedDataHashSpec (keccak256 : List Nat → Nat) : Prop where
  /-- It never reverts. -/
  total : ∀ d s env w, ∃ r w', ext.fn_MessageHashUtils_toTypedDataHash_9732 d s env w = .ok (r, w')
  /-- It writes nothing (`pure`). -/
  readOnly : ∀ d s, Preserves (ext.fn_MessageHashUtils_toTypedDataHash_9732 d s)
  /-- It returns `keccak256("\x19\x01" ‖ domainSeparator ‖ structHash)`, whatever the environment
  and the state (`pure`). -/
  result : ∀ d s env w r w', ext.fn_MessageHashUtils_toTypedDataHash_9732 d s env w = .ok (r, w') →
    r = keccak256 (typedPreimage d s)

/-- **`OrderSignatures.hashSetExecutor(key, maker, executor, allow, nonce, deadline)`**. -/
structure HashSetExecutorSpec : Prop where
  /-- It never reverts. -/
  total : ∀ k m e a n d env w, ∃ r w', ext.fn_OrderSignatures_hashSetExecutor_9244 k m e a n d env w = .ok (r, w')
  /-- It writes nothing (`pure`). -/
  readOnly : ∀ k m e a n d, Preserves (ext.fn_OrderSignatures_hashSetExecutor_9244 k m e a n d)
  /-- It returns `setExecutorHash` (which inlines `hashPoolKey`), whatever the environment and state. -/
  result : ∀ k m e a n d env w r w', ext.fn_OrderSignatures_hashSetExecutor_9244 k m e a n d env w = .ok (r, w') →
    r = setExecutorHash ext k m e a n d

/-- **`OrderSignatures.hashPoolKey(key)`**. -/
structure HashPoolKeySpec : Prop where
  /-- It never reverts. -/
  total : ∀ k env w, ∃ r w', ext.fn_OrderSignatures_hashPoolKey_9171 k env w = .ok (r, w')
  /-- It writes nothing (`pure`). -/
  readOnly : ∀ k, Preserves (ext.fn_OrderSignatures_hashPoolKey_9171 k)
  /-- It returns `poolKeyHash`, whatever the environment and state. -/
  result : ∀ k env w r w', ext.fn_OrderSignatures_hashPoolKey_9171 k env w = .ok (r, w') → r = poolKeyHash ext k

/-! ## Each spec, run -/

section run
variable {ext}

theorem ERC1271Spec.run {sc : StaticCall σ} (h : ERC1271Spec ext sc) (signer hash : Nat) (sig : List Nat)
    (env : Env) (w : σ) :
    ext.fn_SignatureChecker_isValidERC1271SignatureNow_2280 signer hash sig env w
      = .ok (erc1271Verdict (sc env w signer (erc1271Calldata hash sig)), w) := by
  obtain ⟨b, w', hb⟩ := h.total signer hash sig env w
  have e1 := h.readOnly signer hash sig env w b w' hb
  have e2 := h.result signer hash sig env w b w' hb
  subst e1 e2
  exact hb

theorem TypedDataHashSpec.run {k256 : List Nat → Nat} (h : TypedDataHashSpec ext k256) (d s : Nat)
    (env : Env) (w : σ) :
    ext.fn_MessageHashUtils_toTypedDataHash_9732 d s env w = .ok (k256 (typedPreimage d s), w) := by
  obtain ⟨r, w', hr⟩ := h.total d s env w
  have e1 := h.readOnly d s env w r w' hr
  have e2 := h.result d s env w r w' hr
  subst e1 e2
  exact hr

theorem HashSetExecutorSpec.run (h : HashSetExecutorSpec ext) (k : PoolKey) (m e : Nat) (a : Bool)
    (n d : Nat) (env : Env) (w : σ) :
    ext.fn_OrderSignatures_hashSetExecutor_9244 k m e a n d env w = .ok (setExecutorHash ext k m e a n d, w) := by
  obtain ⟨r, w', hr⟩ := h.total k m e a n d env w
  have e1 := h.readOnly k m e a n d env w r w' hr
  have e2 := h.result k m e a n d env w r w' hr
  subst e1 e2
  exact hr

theorem HashPoolKeySpec.run (h : HashPoolKeySpec ext) (k : PoolKey) (env : Env) (w : σ) :
    ext.fn_OrderSignatures_hashPoolKey_9171 k env w = .ok (poolKeyHash ext k, w) := by
  obtain ⟨r, w', hr⟩ := h.total k env w
  have e1 := h.readOnly k env w r w' hr
  have e2 := h.result k env w r w' hr
  subst e1 e2
  exact hr

end run

/-! ## Bridge to `AsyncSwapSpec/Hashing.lean` -/

/-- The generated `PoolKey` as `Hashing.PoolKey` (`tickSpacing` as its ABI word). -/
def toSpecKey (k : PoolKey) : Hashing.PoolKey :=
  { currency0 := k.currency0, currency1 := k.currency1, fee := k.fee,
    tickSpacing := toUnsigned 256 k.tickSpacing, hooks := k.hooks }

/-- `ext.keccak` is `Hashing`'s `keccak` on `abi.encode` tuples, and the two typehash words are
`Hashing`'s typehashes. -/
structure HashingCompat (Mh : Hashing.Model) : Prop where
  tuple : ∀ ws, ext.keccak ws = Mh.keccak (.tuple ws)
  poolKeyTypehash : POOL_KEY_TYPEHASH = Hashing.poolKeyTypehash Mh
  setExecutorTypehash : SET_EXECUTOR_TYPEHASH = Hashing.setExecutorTypehash Mh

theorem poolKeyHash_eq_hashing (Mh : Hashing.Model) (hc : HashingCompat ext Mh) (k : PoolKey) :
    poolKeyHash ext k = Hashing.hashPoolKey Mh (toSpecKey k) := by
  simp only [poolKeyHash, Hashing.hashPoolKey, hc.tuple, hc.poolKeyTypehash, toSpecKey]

theorem setExecutorHash_eq_hashing (Mh : Hashing.Model) (hc : HashingCompat ext Mh) (k : PoolKey)
    (maker executor : Nat) (allow : Bool) (nonce deadline : Nat) :
    setExecutorHash ext k maker executor allow nonce deadline
      = Hashing.hashSetExecutor Mh (toSpecKey k) maker executor allow nonce deadline := by
  have hb : ybool allow = Hashing.boolWord allow := by cases allow <;> rfl
  simp only [setExecutorHash, Hashing.hashSetExecutor, hc.tuple, hc.setExecutorTypehash, hb,
    poolKeyHash_eq_hashing ext Mh hc]

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

theorem tryRecover_9821_ok (hash : Nat) (sig : List Nat) (env : Env) (w : σ) :
    ∃ t, ECDSA.tryRecover_9821 ext hash sig env w = .ok (t, w) := by
  rcases hr : ECDSA.tryRecover_9821 ext hash sig env w with e | ⟨t, w'⟩
  · exfalso
    unfold ECDSA.tryRecover_9821 ECDSA.tryRecover at hr
    simp at hr
    split at hr
    · split at hr
      · cases hr
      · split at hr <;> cases hr
    · cases hr
  · have := SetExecutorWithSig.tryRecover_9821_preserves ext hash sig env w t w' hr
    subst this
    exact ⟨t, rfl⟩

/-- `isValidSignatureNow(signer, hash, sig)` under `ERC1271Spec`: never reverts, writes nothing, and
returns `(ECDSA recovered signer without error) || erc1271Verdict(staticcall)`. -/
theorem isValidSignatureNow_run (sc : StaticCall σ) (hE : ERC1271Spec ext sc) (signer hash : Nat)
    (sig : List Nat) (env : Env) (w : σ) :
    ∃ t, ECDSA.tryRecover_9821 ext hash sig env w = .ok (t, w) ∧
      SignatureChecker.isValidSignatureNow ext signer hash sig env w
        = .ok (((t.2.1 == 0) && (t.1 == signer)) ||
            erc1271Verdict (sc env w signer (erc1271Calldata hash sig)), w) := by
  obtain ⟨t, ht⟩ := tryRecover_9821_ok ext hash sig env w
  refine ⟨t, ht, ?_⟩
  by_cases hc : ((t.2.1 == 0) && (t.1 == signer)) = true
  · simp only [SignatureChecker.isValidSignatureNow, run_bind, ht, hc]
    simp_all
  · simp only [Bool.not_eq_true] at hc
    simp only [SignatureChecker.isValidSignatureNow, run_bind, ht, hc]
    simp_all [hE.run]

/-! ## Wrappers: `AsyncSwapSetExecutorWithSig.lean` -/

section setExecutor
open AsyncSwap.Swarm.SetExecutorWithSig

theorem isValidSignatureNow_preserves_of_spec (sc : StaticCall σ) (hE : ERC1271Spec ext sc)
    (signer hash : Nat) (sig : List Nat) :
    Preserves (SignatureChecker.isValidSignatureNow ext signer hash sig) :=
  isValidSignatureNow_preserves ext signer hash sig (hE.readOnly signer hash sig)

theorem hashTypedDataV4_preserves_of_spec (k256 : List Nat → Nat) (hT : TypedDataHashSpec ext k256)
    (sh : Nat) : Preserves (EIP712.«_hashTypedDataV4» ext sh) :=
  hashTypedDataV4_preserves ext sh (fun d => hT.readOnly d sh)

variable (key : PoolKey) (maker executor : Nat) (allow : Bool) (nonce deadline : Nat)
  (signature : List Nat) (env : Env) (w : σ)

/-- The three specs give `SetExecutorWithSig.PureCallees`. -/
theorem pureCallees_of_spec (k256 : List Nat → Nat) (sc : StaticCall σ) (hH : HashSetExecutorSpec ext)
    (hT : TypedDataHashSpec ext k256) (hE : ERC1271Spec ext sc) :
    PureCallees ext key maker executor allow nonce deadline signature :=
  ⟨hH.readOnly key maker executor allow nonce deadline, fun d sh => hT.readOnly d sh,
    fun hash => hE.readOnly maker hash signature⟩

theorem setExecutorWithSig_expired_of_spec (hH : HashSetExecutorSpec ext) (ht : deadline < env.timestamp) :
    AsyncSwap.setExecutorWithSig ext key maker executor allow nonce deadline signature env w
      = .error ⟨"SignatureExpired"⟩ :=
  setExecutorWithSig_expired ext key maker executor allow nonce deadline signature env w _ w
    (hH.run key maker executor allow nonce deadline env w) ht

theorem setExecutorWithSig_nonce_used_of_spec (hH : HashSetExecutorSpec ext)
    (ht : ¬ deadline < env.timestamp) (hn : (ext.get w).nonceUsed maker nonce = true) :
    AsyncSwap.setExecutorWithSig ext key maker executor allow nonce deadline signature env w
      = .error ⟨"NonceAlreadyUsed"⟩ :=
  setExecutorWithSig_nonce_used ext key maker executor allow nonce deadline signature env w _ w
    (hH.run key maker executor allow nonce deadline env w) ht hn

theorem setExecutorWithSig_invalid_sig_of_spec (k256 : List Nat → Nat) (hH : HashSetExecutorSpec ext)
    (hT : TypedDataHashSpec ext k256) (w3 : σ)
    (ht : ¬ deadline < env.timestamp) (hn : (ext.get w).nonceUsed maker nonce = false)
    (hS : SignatureChecker.isValidSignatureNow ext maker
      (k256 (typedPreimage (domainSep ext env) (setExecutorHash ext key maker executor allow nonce deadline)))
      signature env (burn ext w maker nonce) = .ok (false, w3)) :
    AsyncSwap.setExecutorWithSig ext key maker executor allow nonce deadline signature env w
      = .error ⟨"InvalidSignature"⟩ :=
  setExecutorWithSig_invalid_sig ext key maker executor allow nonce deadline signature env w _ _ w _ w3
    (hH.run key maker executor allow nonce deadline env w) ht hn (hashTypedDataV4_run ext k256 hT _ env _) hS

theorem setExecutorWithSig_ok_of_spec (k256 : List Nat → Nat) (hH : HashSetExecutorSpec ext)
    (hT : TypedDataHashSpec ext k256) (w3 : σ)
    (ht : ¬ deadline < env.timestamp) (hn : (ext.get w).nonceUsed maker nonce = false)
    (hS : SignatureChecker.isValidSignatureNow ext maker
      (k256 (typedPreimage (domainSep ext env) (setExecutorHash ext key maker executor allow nonce deadline)))
      signature env (burn ext w maker nonce) = .ok (true, w3)) :
    AsyncSwap.setExecutorWithSig ext key maker executor allow nonce deadline signature env w
      = .ok ((), grant ext w3 (poolIdOf ext key) maker executor allow) :=
  setExecutorWithSig_ok ext key maker executor allow nonce deadline signature env w _ _ w _ w3
    (hH.run key maker executor allow nonce deadline env w) ht hn (hashTypedDataV4_run ext k256 hT _ env _) hS

theorem setExecutorWithSig_ok_state_of_spec (k256 : List Nat → Nat) (sc : StaticCall σ)
    (hH : HashSetExecutorSpec ext) (hT : TypedDataHashSpec ext k256) (hE : ERC1271Spec ext sc) (w' : σ)
    (hok : AsyncSwap.setExecutorWithSig ext key maker executor allow nonce deadline signature env w
      = .ok ((), w')) :
    (ext.get w).nonceUsed maker nonce = false ∧
    w' = grant ext (burn ext w maker nonce) (poolIdOf ext key) maker executor allow :=
  setExecutorWithSig_ok_state ext key maker executor allow nonce deadline signature env w w'
    (pureCallees_of_spec ext key maker executor allow nonce deadline signature k256 sc hH hT hE) hok

theorem setExecutorWithSig_frame_of_spec (k256 : List Nat → Nat) (sc : StaticCall σ)
    (hH : HashSetExecutorSpec ext) (hT : TypedDataHashSpec ext k256) (hE : ERC1271Spec ext sc) (w' : σ)
    (hget : ∀ w s, ext.get (ext.set w s) = s)
    (hok : AsyncSwap.setExecutorWithSig ext key maker executor allow nonce deadline signature env w
      = .ok ((), w')) :
    (ext.get w').nonceUsed maker nonce = true
    ∧ (∀ m n, (m ≠ maker ∨ n ≠ nonce) → (ext.get w').nonceUsed m n = (ext.get w).nonceUsed m n)
    ∧ ((ext.get w').asyncOrders (poolIdOf ext key)).isExecutor maker executor = allow
    ∧ (∀ p m, m ≠ maker →
        ((ext.get w').asyncOrders p).isExecutor m = ((ext.get w).asyncOrders p).isExecutor m)
    ∧ (∀ p e, (p ≠ poolIdOf ext key ∨ e ≠ executor) →
        ((ext.get w').asyncOrders p).isExecutor maker e = ((ext.get w).asyncOrders p).isExecutor maker e)
    ∧ (∀ p, ((ext.get w').asyncOrders p).orders = ((ext.get w).asyncOrders p).orders)
    ∧ (∀ p, p ≠ poolIdOf ext key → (ext.get w').asyncOrders p = (ext.get w).asyncOrders p)
    ∧ (ext.get w').priceBooks = (ext.get w).priceBooks
    ∧ (ext.get w').owner = (ext.get w).owner
    ∧ (ext.get w').pendingOwner = (ext.get w).pendingOwner :=
  setExecutorWithSig_frame ext key maker executor allow nonce deadline signature env w w' hget
    (pureCallees_of_spec ext key maker executor allow nonce deadline signature k256 sc hH hT hE) hok

theorem setExecutorWithSig_no_replay_of_spec (k256 : List Nat → Nat) (sc : StaticCall σ)
    (hH : HashSetExecutorSpec ext) (hT : TypedDataHashSpec ext k256) (hE : ERC1271Spec ext sc) (w' : σ)
    (hget : ∀ w s, ext.get (ext.set w s) = s)
    (hok : AsyncSwap.setExecutorWithSig ext key maker executor allow nonce deadline signature env w
      = .ok ((), w'))
    (key' : PoolKey) (executor' : Nat) (allow' : Bool) (deadline' : Nat) (signature' : List Nat)
    (env' : Env) :
    ∃ e, AsyncSwap.setExecutorWithSig ext key' maker executor' allow' nonce deadline' signature' env' w'
      = .error e :=
  setExecutorWithSig_no_replay ext key maker executor allow nonce deadline signature env w w' hget
    (pureCallees_of_spec ext key maker executor allow nonce deadline signature k256 sc hH hT hE) hok
    key' executor' allow' deadline' signature' env' _ (hH.run key' maker executor' allow' nonce deadline' env' w')

end setExecutor

/-! ## Wrappers: `AsyncSwapUpdatePriceWithSig.lean` -/

section updatePrice
open AsyncSwap.Swarm.UpdatePriceWithSig
open AsyncSwap.Swarm.UpdatePrice (poolId orderId selfGet selfSet bookGet bookSet midState)

variable (order : AsyncOrder) (n nonce deadline : Nat) (sig : List Nat) (env : Env) (w : σ)

/-- The two specs give `UpdatePriceWithSig.PureCallees`. -/
theorem updatePrice_pureCallees_of_spec (k256 : List Nat → Nat) (sc : StaticCall σ)
    (hT : TypedDataHashSpec ext k256) (hE : ERC1271Spec ext sc) (maker : Nat) :
    UpdatePriceWithSig.PureCallees ext maker sig :=
  ⟨fun d sh => hT.readOnly d sh, fun hash => hE.readOnly maker hash sig⟩

theorem updatePriceWithSig_invalidSig_of_spec (k256 : List Nat → Nat) (hT : TypedDataHashSpec ext k256)
    (w3 : σ) (ht : ¬ deadline < env.timestamp)
    (hn : (ext.get w).nonceUsed order.owner nonce = false)
    (hS : SignatureChecker.isValidSignatureNow ext order.owner
      (k256 (typedPreimage (domainSep ext env) (structHash ext env w order n nonce deadline))) sig env
      (burn ext w order.owner nonce) = .ok (false, w3)) :
    AsyncSwap.updatePriceWithSig ext order n nonce deadline sig env w
      = .error ⟨"InvalidSignature"⟩ :=
  updatePriceWithSig_invalidSig ext order n nonce deadline sig env w _ _ w3 ht hn
    (hashTypedDataV4_run ext k256 hT _ env _) hS

theorem verify_ok_inv_of_spec (k256 : List Nat → Nat) (sc : StaticCall σ) (hT : TypedDataHashSpec ext k256)
    (hE : ERC1271Spec ext sc) (maker sh : Nat) (w1 : σ)
    (h : AsyncSwap.«_verify» ext maker sh nonce deadline sig env w = .ok ((), w1)) :
    ¬ deadline < env.timestamp ∧ (ext.get w).nonceUsed maker nonce = false ∧
    (∃ d, EIP712.«_hashTypedDataV4» ext sh env (burn ext w maker nonce)
        = .ok (d, burn ext w maker nonce) ∧
      SignatureChecker.isValidSignatureNow ext maker d sig env (burn ext w maker nonce)
        = .ok (true, burn ext w maker nonce)) ∧
    w1 = burn ext w maker nonce :=
  verify_ok_inv ext nonce deadline sig env w maker sh
    (updatePrice_pureCallees_of_spec ext sig k256 sc hT hE maker) w1 h

theorem updatePriceWithSig_missing_reverts_of_spec (k256 : List Nat → Nat) (sc : StaticCall σ)
    (hT : TypedDataHashSpec ext k256) (hE : ERC1271Spec ext sc)
    (hget : ∀ w s, ext.get (ext.set w s) = s)
    (h0 : n = 0 ∨
      (((ext.get w).asyncOrders (poolId ext order.key)).orders (orderId ext env order)).amountIn = 0) :
    ∃ e, AsyncSwap.updatePriceWithSig ext order n nonce deadline sig env w = .error e :=
  updatePriceWithSig_missing_reverts ext order n nonce deadline sig env w hget
    (updatePrice_pureCallees_of_spec ext sig k256 sc hT hE order.owner) h0

theorem updatePriceWithSig_ok_of_spec (k256 : List Nat → Nat) (sc : StaticCall σ)
    (hT : TypedDataHashSpec ext k256) (hE : ERC1271Spec ext sc)
    (hget : ∀ w s, ext.get (ext.set w s) = s) (w' : σ)
    (h : AsyncSwap.updatePriceWithSig ext order n nonce deadline sig env w = .ok ((), w')) :
    let pid := poolId ext order.key
    let id := orderId ext env order
    let wb := burn ext w order.owner nonce
    ¬ deadline < env.timestamp ∧ (ext.get w).nonceUsed order.owner nonce = false ∧
    (∃ d, EIP712.«_hashTypedDataV4» ext (structHash ext env w order n nonce deadline) env wb
        = .ok (d, wb) ∧
      SignatureChecker.isValidSignatureNow ext order.owner d sig env wb = .ok (true, wb)) ∧
    n ≠ 0 ∧ (((ext.get w).asyncOrders pid).orders id).amountIn ≠ 0 ∧
    ∃ w1 w2 p,
      ext.fn_AsyncFiller_remove_6902 (selfGet ext pid) (selfSet ext pid) (bookGet ext pid)
        (bookSet ext pid) id env wb = .ok ((), w1) ∧
      1 ≤ p ∧ p < 2 ^ 128 ∧ ((ext.get w1).priceBooks pid).nextSequence + 1 < 2 ^ 64 ∧
      ext.get w2 = midState (ext.get w1) pid id n p (((ext.get w1).priceBooks pid).nextSequence + 1) ∧
      ext.fn_AsyncFiller_append_6737 (selfGet ext pid) (selfSet ext pid) (bookGet ext pid)
        (bookSet ext pid) id env w2 = .ok ((), w') :=
  updatePriceWithSig_ok ext order n nonce deadline sig env w hget
    (updatePrice_pureCallees_of_spec ext sig k256 sc hT hE order.owner) w' h

theorem updatePriceWithSig_burns_nonce_of_spec (k256 : List Nat → Nat) (sc : StaticCall σ)
    (hT : TypedDataHashSpec ext k256) (hE : ERC1271Spec ext sc)
    (hget : ∀ w s, ext.get (ext.set w s) = s)
    (hrem : KeepsNonces ext (ext.fn_AsyncFiller_remove_6902 (selfGet ext (poolId ext order.key))
      (selfSet ext (poolId ext order.key)) (bookGet ext (poolId ext order.key))
      (bookSet ext (poolId ext order.key)) (orderId ext env order)))
    (happ : KeepsNonces ext (ext.fn_AsyncFiller_append_6737 (selfGet ext (poolId ext order.key))
      (selfSet ext (poolId ext order.key)) (bookGet ext (poolId ext order.key))
      (bookSet ext (poolId ext order.key)) (orderId ext env order)))
    (w' : σ)
    (h : AsyncSwap.updatePriceWithSig ext order n nonce deadline sig env w = .ok ((), w')) :
    (ext.get w').nonceUsed = upd (ext.get w).nonceUsed order.owner
      (upd ((ext.get w).nonceUsed order.owner) nonce true) ∧
    ∀ (order' : AsyncOrder) n' deadline' sig' env', order'.owner = order.owner →
      ∃ e, AsyncSwap.updatePriceWithSig ext order' n' nonce deadline' sig' env' w' = .error e :=
  updatePriceWithSig_burns_nonce ext order n nonce deadline sig env w hget
    (updatePrice_pureCallees_of_spec ext sig k256 sc hT hE order.owner) hrem happ w' h

end updatePrice

end AsyncSwap.Swarm.SpecSig
