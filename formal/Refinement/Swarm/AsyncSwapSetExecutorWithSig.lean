import Generated.AsyncSwap
import Refinement.Monad

/-!
# `AsyncSwap.setExecutorWithSig`

`function setExecutorWithSig(PoolKey key, address maker, address executor, bool allow, uint256 nonce,
uint256 deadline, bytes signature) external` (src/AsyncSwap.sol:533).

* Guards, in order (after the pure struct hash `OrderSignatures.hashSetExecutor`):
  `block.timestamp > deadline` → `SignatureExpired`; `nonceUsed[maker][nonce]` → `NonceAlreadyUsed`;
  the nonce is burnt; then `!isValidSignatureNow(maker, _hashTypedDataV4(structHash), signature)` →
  `InvalidSignature`.
* On success its only write besides the nonce burn is
  `asyncOrders[key.toId()].isExecutor[maker][executor] = allow`.
* Authorization: success implies `SignatureChecker.isValidSignatureNow` accepted `signature` for
  `maker` over the digest of exactly `(key, maker, executor, allow, nonce, deadline)`; a call can only
  touch `maker`'s own executor row, never another maker's, never orders/price books/ownership, and the
  same `(maker, nonce)` can never be replayed.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.SetExecutorWithSig

variable {σ : Type} (ext : Ext σ)

/-- A program that never changes storage (a `pure`/`view` callee or a `staticcall`). -/
def Preserves {α : Type} (p : M σ α) : Prop := ∀ env s r s', p env s = .ok (r, s') → s' = s

theorem tryRecover_preserves (hash v r s' : Nat) : Preserves (ECDSA.tryRecover ext hash v r s') := by
  intro env s a t h
  unfold ECDSA.tryRecover at h
  simp at h
  split at h
  · cases h; rfl
  · split at h <;> (cases h; rfl)

theorem tryRecover_9821_preserves (hash : Nat) (sig : List Nat) :
    Preserves (ECDSA.tryRecover_9821 ext hash sig) := by
  intro env s a t h
  unfold ECDSA.tryRecover_9821 at h
  simp at h
  split at h
  · exact tryRecover_preserves ext _ _ _ _ env s a t h
  · cases h; rfl

/-- `isValidSignatureNow` writes nothing, given that the ERC-1271 `staticcall` writes nothing. -/
theorem isValidSignatureNow_preserves (signer hash : Nat) (sig : List Nat)
    (h1271 : Preserves (ext.fn_SignatureChecker_isValidERC1271SignatureNow_2280 signer hash sig)) :
    Preserves (SignatureChecker.isValidSignatureNow ext signer hash sig) := by
  intro env s a t h
  unfold SignatureChecker.isValidSignatureNow at h
  simp at h
  rcases hr : ECDSA.tryRecover_9821 ext hash sig env s with e | ⟨r, s1⟩
  · simp [hr] at h
  · have hs1 := tryRecover_9821_preserves ext hash sig env s r s1 hr
    simp only [hr] at h
    split at h
    · rw [h1271 env s1 a t h, hs1]
    · cases h; exact hs1

/-- `_hashTypedDataV4` writes nothing, given that `toTypedDataHash` (pure) writes nothing. -/
theorem hashTypedDataV4_preserves (sh : Nat)
    (hm : ∀ d, Preserves (ext.fn_MessageHashUtils_toTypedDataHash_9732 d sh)) :
    Preserves (EIP712.«_hashTypedDataV4» ext sh) := by
  intro env s a t h
  simp [EIP712.«_hashTypedDataV4», EIP712.«_domainSeparatorV4», EIP712.«_buildDomainSeparator»] at h
  by_cases hc : env.self = ext._cachedThis ∧ env.chainid = ext._cachedChainId
  · simp only [hc, and_self, ite_true] at h; exact hm _ env s a t h
  · simp only [hc, ite_false] at h; exact hm _ env s a t h

/-- The pool id `key.toId()`. -/
def poolIdOf (key : PoolKey) : Nat :=
  ext.keccak [key.currency0, key.currency1, key.fee, toUnsigned 256 key.tickSpacing, key.hooks]

/-- The nonce burn of `_verify`: `nonceUsed[maker][nonce] = true`. -/
def burn (w : σ) (maker nonce : Nat) : σ :=
  ext.set w { ext.get w with
    nonceUsed := upd (ext.get w).nonceUsed maker (upd ((ext.get w).nonceUsed maker) nonce true) }

/-- The final write `asyncOrders[poolId].isExecutor[maker][executor] = allow`. -/
def grant (w : σ) (poolId maker executor : Nat) (allow : Bool) : σ :=
  ext.set w { ext.get w with
    asyncOrders := upd (ext.get w).asyncOrders poolId
      { (ext.get w).asyncOrders poolId with
        isExecutor := upd ((ext.get w).asyncOrders poolId).isExecutor maker
          (upd (((ext.get w).asyncOrders poolId).isExecutor maker) executor allow) } }

variable (key : PoolKey) (maker executor : Nat) (allow : Bool) (nonce deadline : Nat)
  (signature : List Nat) (env : Env) (w : σ)

/-- Guard 1: an expired deadline reverts with `SignatureExpired`. -/
theorem setExecutorWithSig_expired (h : Nat) (w1 : σ)
    (hH : ext.fn_OrderSignatures_hashSetExecutor_9244 key maker executor allow nonce deadline env w
      = .ok (h, w1))
    (ht : deadline < env.timestamp) :
    AsyncSwap.setExecutorWithSig ext key maker executor allow nonce deadline signature env w
      = .error ⟨"SignatureExpired"⟩ := by
  simp [AsyncSwap.setExecutorWithSig, AsyncSwap.«_verify», hH, ht]

/-- Guard 2: a used nonce reverts with `NonceAlreadyUsed`. -/
theorem setExecutorWithSig_nonce_used (h : Nat) (w1 : σ)
    (hH : ext.fn_OrderSignatures_hashSetExecutor_9244 key maker executor allow nonce deadline env w
      = .ok (h, w1))
    (ht : ¬ deadline < env.timestamp) (hn : (ext.get w1).nonceUsed maker nonce = true) :
    AsyncSwap.setExecutorWithSig ext key maker executor allow nonce deadline signature env w
      = .error ⟨"NonceAlreadyUsed"⟩ := by
  simp [AsyncSwap.setExecutorWithSig, AsyncSwap.«_verify», hH, ht, hn]

/-- Guard 3: a signature rejected for `maker` reverts with `InvalidSignature`. -/
theorem setExecutorWithSig_invalid_sig (h d : Nat) (w1 w2 w3 : σ)
    (hH : ext.fn_OrderSignatures_hashSetExecutor_9244 key maker executor allow nonce deadline env w
      = .ok (h, w1))
    (ht : ¬ deadline < env.timestamp) (hn : (ext.get w1).nonceUsed maker nonce = false)
    (hD : EIP712.«_hashTypedDataV4» ext h env (burn ext w1 maker nonce) = .ok (d, w2))
    (hS : SignatureChecker.isValidSignatureNow ext maker d signature env w2 = .ok (false, w3)) :
    AsyncSwap.setExecutorWithSig ext key maker executor allow nonce deadline signature env w
      = .error ⟨"InvalidSignature"⟩ := by
  simp only [burn] at hD
  simp [AsyncSwap.setExecutorWithSig, AsyncSwap.«_verify», hH, ht, hn, hD, hS]

/-- Success: all guards pass, and the result is the nonce burn followed by the single executor write. -/
theorem setExecutorWithSig_ok (h d : Nat) (w1 w2 w3 : σ)
    (hH : ext.fn_OrderSignatures_hashSetExecutor_9244 key maker executor allow nonce deadline env w
      = .ok (h, w1))
    (ht : ¬ deadline < env.timestamp) (hn : (ext.get w1).nonceUsed maker nonce = false)
    (hD : EIP712.«_hashTypedDataV4» ext h env (burn ext w1 maker nonce) = .ok (d, w2))
    (hS : SignatureChecker.isValidSignatureNow ext maker d signature env w2 = .ok (true, w3)) :
    AsyncSwap.setExecutorWithSig ext key maker executor allow nonce deadline signature env w
      = .ok ((), grant ext w3 (poolIdOf ext key) maker executor allow) := by
  simp only [burn] at hD
  simp [AsyncSwap.setExecutorWithSig, AsyncSwap.«_verify», PoolIdLibrary.toId, hH, ht, hn, hD, hS,
    grant, poolIdOf]

/-- **Inversion.** Any successful run passed every guard: the deadline held, `(maker, nonce)` was
fresh, and `isValidSignatureNow` accepted `signature` **for `maker`** over the EIP-712 digest of the
struct hash of exactly these arguments; the final state is the executor write on top of that. -/
theorem setExecutorWithSig_ok_inv (w' : σ)
    (hok : AsyncSwap.setExecutorWithSig ext key maker executor allow nonce deadline signature env w
      = .ok ((), w')) :
    ∃ h d w1 w2 w3,
      ext.fn_OrderSignatures_hashSetExecutor_9244 key maker executor allow nonce deadline env w
        = .ok (h, w1) ∧
      ¬ deadline < env.timestamp ∧
      (ext.get w1).nonceUsed maker nonce = false ∧
      EIP712.«_hashTypedDataV4» ext h env (burn ext w1 maker nonce) = .ok (d, w2) ∧
      SignatureChecker.isValidSignatureNow ext maker d signature env w2 = .ok (true, w3) ∧
      w' = grant ext w3 (poolIdOf ext key) maker executor allow := by
  rcases hH : ext.fn_OrderSignatures_hashSetExecutor_9244 key maker executor allow nonce deadline env w
    with e | ⟨h, w1⟩
  · simp [AsyncSwap.setExecutorWithSig, hH] at hok
  by_cases ht : deadline < env.timestamp
  · rw [setExecutorWithSig_expired ext key maker executor allow nonce deadline signature env w h w1 hH ht]
      at hok
    cases hok
  by_cases hn : (ext.get w1).nonceUsed maker nonce = true
  · rw [setExecutorWithSig_nonce_used ext key maker executor allow nonce deadline signature env w h w1
      hH ht hn] at hok
    cases hok
  have hn' : (ext.get w1).nonceUsed maker nonce = false := by simpa using hn
  rcases hD : EIP712.«_hashTypedDataV4» ext h env (burn ext w1 maker nonce) with e | ⟨d, w2⟩
  · simp only [burn] at hD
    simp [AsyncSwap.setExecutorWithSig, AsyncSwap.«_verify», hH, ht, hn', hD] at hok
  rcases hS : SignatureChecker.isValidSignatureNow ext maker d signature env w2 with e | ⟨b, w3⟩
  · simp only [burn] at hD
    simp [AsyncSwap.setExecutorWithSig, AsyncSwap.«_verify», hH, ht, hn', hD, hS] at hok
  cases b
  · rw [setExecutorWithSig_invalid_sig ext key maker executor allow nonce deadline signature env w h d
      w1 w2 w3 hH ht hn' hD hS] at hok
    cases hok
  · rw [setExecutorWithSig_ok ext key maker executor allow nonce deadline signature env w h d
      w1 w2 w3 hH ht hn' hD hS] at hok
    cases hok
    exact ⟨h, d, w1, w2, w3, rfl, ht, hn', hD, hS, rfl⟩

/-- The callees that the model leaves abstract are storage-neutral: the struct hash and
`toTypedDataHash` are `pure`, the ERC-1271 check is a `staticcall`. -/
structure PureCallees : Prop where
  hash : Preserves (ext.fn_OrderSignatures_hashSetExecutor_9244 key maker executor allow nonce deadline)
  typed : ∀ d sh, Preserves (ext.fn_MessageHashUtils_toTypedDataHash_9732 d sh)
  erc1271 : ∀ hash, Preserves (ext.fn_SignatureChecker_isValidERC1271SignatureNow_2280 maker hash signature)

/-- **Exact effect on storage.** With storage-neutral callees, a successful call's final state is
`nonceUsed[maker][nonce] = true` (it was `false`) followed by
`asyncOrders[key.toId()].isExecutor[maker][executor] = allow`, on top of the initial state. -/
theorem setExecutorWithSig_ok_state (w' : σ)
    (hpure : PureCallees ext key maker executor allow nonce deadline signature)
    (hok : AsyncSwap.setExecutorWithSig ext key maker executor allow nonce deadline signature env w
      = .ok ((), w')) :
    (ext.get w).nonceUsed maker nonce = false ∧
    w' = grant ext (burn ext w maker nonce) (poolIdOf ext key) maker executor allow := by
  obtain ⟨h, d, w1, w2, w3, hH, _, hn, hD, hS, rfl⟩ :=
    setExecutorWithSig_ok_inv ext key maker executor allow nonce deadline signature env w w' hok
  have e1 := hpure.hash env w h w1 hH
  subst e1
  have e2 := hashTypedDataV4_preserves ext h (fun d => hpure.typed d h) env _ d w2 hD
  subst e2
  have e3 := isValidSignatureNow_preserves ext maker d signature (hpure.erc1271 d) env _ true w3 hS
  subst e3
  exact ⟨hn, rfl⟩

/-- **Frame (no fund movement, no cross-user authority).** On success: only `maker`'s executor row
of pool `key.toId()` changes; every other maker's executor rows, every pool's orders, every other
pool, the price books, ownership and every other nonce are unchanged; `(maker, nonce)` is now burnt. -/
theorem setExecutorWithSig_frame (w' : σ)
    (hget : ∀ w s, ext.get (ext.set w s) = s)
    (hpure : PureCallees ext key maker executor allow nonce deadline signature)
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
    ∧ (ext.get w').pendingOwner = (ext.get w).pendingOwner := by
  obtain ⟨_, rfl⟩ :=
    setExecutorWithSig_ok_state ext key maker executor allow nonce deadline signature env w w' hpure hok
  refine ⟨?_, fun m n hmn => ?_, ?_, fun p m hm => ?_, fun p e hpe => ?_, fun p => ?_, fun p hp => ?_,
    ?_, ?_, ?_⟩
  · simp [grant, burn, hget, upd]
  · rcases hmn with hm | hn
    · simp [grant, burn, hget, upd, hm]
    · by_cases hm : m = maker
      · subst hm; simp [grant, burn, hget, upd, hn]
      · simp [grant, burn, hget, upd, hm]
  · simp [grant, burn, hget, upd]
  · by_cases hp : p = poolIdOf ext key
    · subst hp; simp [grant, burn, hget, upd, hm]
    · simp [grant, burn, hget, upd, hp]
  · rcases hpe with hp | he
    · simp [grant, burn, hget, upd, hp]
    · by_cases hp : p = poolIdOf ext key
      · subst hp; simp [grant, burn, hget, upd, he]
      · simp [grant, burn, hget, upd, hp]
  · by_cases hp : p = poolIdOf ext key
    · subst hp; simp [grant, burn, hget, upd]
    · simp [grant, burn, hget, upd, hp]
  · simp [grant, burn, hget, upd, hp]
  · simp [grant, burn, hget]
  · simp [grant, burn, hget]
  · simp [grant, burn, hget]

/-- **No replay.** After a successful call, repeating it with the same `(maker, nonce)` (any other
arguments, any signature) reverts with `NonceAlreadyUsed` (or earlier with `SignatureExpired`). -/
theorem setExecutorWithSig_no_replay (w' : σ)
    (hget : ∀ w s, ext.get (ext.set w s) = s)
    (hpure : PureCallees ext key maker executor allow nonce deadline signature)
    (hok : AsyncSwap.setExecutorWithSig ext key maker executor allow nonce deadline signature env w
      = .ok ((), w'))
    (key' : PoolKey) (executor' : Nat) (allow' : Bool) (deadline' : Nat) (signature' : List Nat)
    (env' : Env) (h' : Nat)
    (hH' : ext.fn_OrderSignatures_hashSetExecutor_9244 key' maker executor' allow' nonce deadline' env' w'
      = .ok (h', w')) :
    ∃ e, AsyncSwap.setExecutorWithSig ext key' maker executor' allow' nonce deadline' signature' env' w'
      = .error e := by
  have hused := (setExecutorWithSig_frame ext key maker executor allow nonce deadline signature env w w'
    hget hpure hok).1
  by_cases ht : deadline' < env'.timestamp
  · exact ⟨_, setExecutorWithSig_expired ext key' maker executor' allow' nonce deadline' signature' env' w'
      h' w' hH' ht⟩
  · exact ⟨_, setExecutorWithSig_nonce_used ext key' maker executor' allow' nonce deadline' signature' env'
      w' h' w' hH' ht hused⟩

end AsyncSwap.Swarm.SetExecutorWithSig
