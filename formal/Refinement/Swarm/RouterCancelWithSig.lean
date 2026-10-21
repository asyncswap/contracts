import Generated.Router
import Refinement.Monad
import Refinement.Router

/-!
# `Router.cancelWithSig` (src/Router.sol:198)

`function cancelWithSig(AsyncOrder order, uint256 nonce, uint256 deadline, bytes signature) external`.

* Guards, in order: `block.timestamp > deadline` → `SignatureExpired`;
  `cancelNonceUsed[order.owner][nonce]` → `NonceAlreadyUsed`; the nonce is burnt; a revert of the
  `HOOK.asyncOrderInfo` view is the call's revert; `!isValidSignatureNow(order.owner, digest, signature)`
  → `InvalidSignature`, where `digest = _hashTypedDataV4(hashCancel(order, id, amountIn, nonce, deadline))`.
* On success the Router's only own write is `cancelNonceUsed[order.owner][nonce] = true`; then it makes
  one call, `POOLMANAGER.unlock(abi.encode(SwapCallback(Cancel = 2, order, 0)))`, from exactly that state.
  It writes no transient slot (in particular not `USER_LOCATION`) and moves no funds itself.
* Authorization (the maintainer's "fill/cancel someone else's order" worry): any caller may submit, but
  success implies `isValidSignatureNow` accepted `signature` **for `order.owner`** over the digest that
  binds the owner, the order's tokens, the live `amountIn`, the order id, the nonce and the deadline; and a
  `(owner, nonce)` pair can never be used twice (not even by re-entering from inside `unlock`).
-/

open FormalAst Refinement

namespace Router.Swarm.CancelWithSig

variable {σ : Type} (ext : Ext σ)

@[simp] theorem ite_pair_fst {α β : Type} (c : Prop) [Decidable c] (a b : α × β) :
    (if c then a else b).1 = if c then a.1 else b.1 := by split <;> rfl

@[simp] theorem ite_pair_snd {α β : Type} (c : Prop) [Decidable c] (a b : α × β) :
    (if c then a else b).2 = if c then a.2 else b.2 := by split <;> rfl

/-- A program that never changes storage (a `pure`/`view` callee or a `staticcall`). -/
def Preserves {α : Type} (p : M σ α) : Prop := ∀ env s r s', p env s = .ok (r, s') → s' = s

theorem tryRecover_preserves (hash v r s' : Nat) : Preserves (ECDSA.tryRecover ext hash v r s') := by
  intro env s a t h
  unfold ECDSA.tryRecover at h
  simp at h
  split at h
  · cases h; rfl
  · split at h <;> (cases h; rfl)

theorem tryRecover_5888_preserves (hash : Nat) (sig : List Nat) :
    Preserves (ECDSA.tryRecover_5888 ext hash sig) := by
  intro env s a t h
  unfold ECDSA.tryRecover_5888 at h
  simp at h
  split at h
  · exact tryRecover_preserves ext _ _ _ _ env s a t h
  · cases h; rfl

/-- `isValidSignatureNow` writes nothing, given that the ERC-1271 `staticcall` writes nothing. -/
theorem isValidSignatureNow_preserves (signer hash : Nat) (sig : List Nat)
    (h1271 : Preserves (ext.fn_SignatureChecker_isValidERC1271SignatureNow_1883 signer hash sig)) :
    Preserves (SignatureChecker.isValidSignatureNow ext signer hash sig) := by
  intro env s a t h
  unfold SignatureChecker.isValidSignatureNow at h
  simp at h
  rcases hr : ECDSA.tryRecover_5888 ext hash sig env s with e | ⟨r, s1⟩
  · simp [hr] at h
  · have hs1 := tryRecover_5888_preserves ext hash sig env s r s1 hr
    simp only [hr] at h
    split at h
    · rw [h1271 env s1 a t h, hs1]
    · cases h; exact hs1

/-- `_hashTypedDataV4` writes nothing, given that `toTypedDataHash` (pure) writes nothing. -/
theorem hashTypedDataV4_preserves (sh : Nat)
    (hm : ∀ d, Preserves (ext.fn_MessageHashUtils_toTypedDataHash_5799 d sh)) :
    Preserves (EIP712.«_hashTypedDataV4» ext sh) := by
  intro env s a t h
  simp [EIP712.«_hashTypedDataV4», EIP712.«_domainSeparatorV4», EIP712.«_buildDomainSeparator»] at h
  by_cases hc : env.self = ext._cachedThis ∧ env.chainid = ext._cachedChainId
  · simp only [hc, and_self, ite_true] at h; exact hm _ env s a t h
  · simp only [hc, ite_false] at h; exact hm _ env s a t h

/-- The pool id `order.key.toId()`. -/
def poolIdOf (o : AsyncOrder) : Nat :=
  ext.keccak [o.key.currency0, o.key.currency1, o.key.fee, toUnsigned 256 o.key.tickSpacing, o.key.hooks]

/-- `_orderId(order)`. -/
def orderIdOf (env : Env) (o : AsyncOrder) : Nat :=
  ext.keccak [env.chainid, poolIdOf ext o, o.owner, ybool o.zeroForOne, o.salt]

/-- `OrderSignatures.hashCancel(order, id, amountIn, nonce, deadline)`: binds owner, tokenIn, tokenOut,
the live `amountIn`, the order id, the nonce and the deadline. -/
def cancelHash (o : AsyncOrder) (id amountIn nonce deadline : Nat) : Nat :=
  ext.keccak [OrderSignatures.CANCEL_ORDER_TYPEHASH, o.owner,
    (if o.zeroForOne then o.key.currency0 else o.key.currency1),
    (if o.zeroForOne then o.key.currency1 else o.key.currency0), amountIn, id, nonce, deadline]

/-- The nonce burn `cancelNonceUsed[maker][nonce] = true`. -/
def burn (w : σ) (maker nonce : Nat) : σ :=
  ext.set w { ext.get w with
    cancelNonceUsed := upd (ext.get w).cancelNonceUsed maker (upd ((ext.get w).cancelNonceUsed maker) nonce true) }

/-- The final step: `POOLMANAGER.unlock(abi.encode(SwapCallback(Cancel, order, 0)))` from state `w`. -/
def tail (o : AsyncOrder) (env : Env) (w : σ) :=
  ((fun _ => ()) <$> ext.call_IPoolManager_unlock ext.POOLMANAGER (Router.callbackData 2 o 0)) env w

variable (o : AsyncOrder) (nonce deadline : Nat) (signature : List Nat) (env : Env) (w : σ)

/-- Guard 1: an expired deadline reverts with `SignatureExpired`, before anything else. -/
theorem cancelWithSig_expired (ht : deadline < env.timestamp) :
    Router.cancelWithSig ext o nonce deadline signature env w = .error ⟨"SignatureExpired"⟩ := by
  simp [Router.cancelWithSig, ht]

/-- Guard 2: a used `(owner, nonce)` reverts with `NonceAlreadyUsed`. -/
theorem cancelWithSig_nonce_used (ht : ¬ deadline < env.timestamp)
    (hn : (ext.get w).cancelNonceUsed o.owner nonce = true) :
    Router.cancelWithSig ext o nonce deadline signature env w = .error ⟨"NonceAlreadyUsed"⟩ := by
  simp [Router.cancelWithSig, ht, hn]

/-- A revert of the `HOOK.asyncOrderInfo` view is the call's revert. -/
theorem cancelWithSig_info_revert (e : Revert) (ht : ¬ deadline < env.timestamp)
    (hn : (ext.get w).cancelNonceUsed o.owner nonce = false)
    (hi : ext.view_AsyncSwap_asyncOrderInfo env (burn ext w o.owner nonce) ext.HOOK (poolIdOf ext o)
      (orderIdOf ext env o) = .error e) :
    Router.cancelWithSig ext o nonce deadline signature env w = .error e := by
  simp only [burn, poolIdOf, orderIdOf] at hi
  simp [Router.cancelWithSig, Router.«_orderId», PoolIdLibrary.toId, view, ht, hn, hi]

/-- Everything before the signature check, run: `simp` form of the prefix up to `hashTypedDataV4`. -/
theorem cancelWithSig_eq_prefix (amountIn p : Nat) (ht : ¬ deadline < env.timestamp)
    (hn : (ext.get w).cancelNonceUsed o.owner nonce = false)
    (hi : ext.view_AsyncSwap_asyncOrderInfo env (burn ext w o.owner nonce) ext.HOOK (poolIdOf ext o)
      (orderIdOf ext env o) = .ok (amountIn, p)) :
    Router.cancelWithSig ext o nonce deadline signature env w =
      (match EIP712.«_hashTypedDataV4» ext (cancelHash ext o (orderIdOf ext env o) amountIn nonce deadline) env
          (burn ext w o.owner nonce) with
        | .ok (d, w2) =>
          match SignatureChecker.isValidSignatureNow ext o.owner d signature env w2 with
          | .ok (b, w3) => if b = false then .error ⟨"InvalidSignature"⟩ else tail ext o env w3
          | .error e => .error e
        | .error e => .error e) := by
  simp only [burn, poolIdOf, orderIdOf] at hi
  simp [Router.cancelWithSig, Router.«_orderId», PoolIdLibrary.toId, view, OrderSignatures.hashCancel,
    OrderSignatures.tokens, ht, hn, hi, tail, Router.callbackData, burn, cancelHash, poolIdOf, orderIdOf]
  rcases EIP712.«_hashTypedDataV4» ext _ env _ with _ | ⟨d, w2⟩
  · rfl
  · simp only
    rcases SignatureChecker.isValidSignatureNow ext o.owner d signature env w2 with _ | ⟨b, w3⟩
    · rfl
    · simp only

/-- Guard 3: a signature rejected for `order.owner` reverts with `InvalidSignature`. -/
theorem cancelWithSig_invalid_sig (amountIn p d : Nat) (w2 w3 : σ) (ht : ¬ deadline < env.timestamp)
    (hn : (ext.get w).cancelNonceUsed o.owner nonce = false)
    (hi : ext.view_AsyncSwap_asyncOrderInfo env (burn ext w o.owner nonce) ext.HOOK (poolIdOf ext o)
      (orderIdOf ext env o) = .ok (amountIn, p))
    (hD : EIP712.«_hashTypedDataV4» ext (cancelHash ext o (orderIdOf ext env o) amountIn nonce deadline) env
      (burn ext w o.owner nonce) = .ok (d, w2))
    (hS : SignatureChecker.isValidSignatureNow ext o.owner d signature env w2 = .ok (false, w3)) :
    Router.cancelWithSig ext o nonce deadline signature env w = .error ⟨"InvalidSignature"⟩ := by
  rw [cancelWithSig_eq_prefix ext o nonce deadline signature env w amountIn p ht hn hi, hD]
  simp only [hS]; rfl

/-- Success path: all guards pass and the call is exactly `unlock(SwapCallback(Cancel, order, 0))` from
the state the signature check left. -/
theorem cancelWithSig_ok (amountIn p d : Nat) (w2 w3 : σ) (ht : ¬ deadline < env.timestamp)
    (hn : (ext.get w).cancelNonceUsed o.owner nonce = false)
    (hi : ext.view_AsyncSwap_asyncOrderInfo env (burn ext w o.owner nonce) ext.HOOK (poolIdOf ext o)
      (orderIdOf ext env o) = .ok (amountIn, p))
    (hD : EIP712.«_hashTypedDataV4» ext (cancelHash ext o (orderIdOf ext env o) amountIn nonce deadline) env
      (burn ext w o.owner nonce) = .ok (d, w2))
    (hS : SignatureChecker.isValidSignatureNow ext o.owner d signature env w2 = .ok (true, w3)) :
    Router.cancelWithSig ext o nonce deadline signature env w = tail ext o env w3 := by
  rw [cancelWithSig_eq_prefix ext o nonce deadline signature env w amountIn p ht hn hi, hD]
  simp only [hS]; rfl

/-- **Inversion.** Any successful run passed every guard: the deadline held, `(owner, nonce)` was fresh,
and `isValidSignatureNow` accepted `signature` **for `order.owner`** over the EIP-712 digest of
`hashCancel(order, _orderId(order), amountIn, nonce, deadline)` with `amountIn` the hook's live value;
the rest of the run is the `unlock` call carrying `SwapCallback(Cancel, order, 0)`. -/
theorem cancelWithSig_ok_inv (w' : σ)
    (hok : Router.cancelWithSig ext o nonce deadline signature env w = .ok ((), w')) :
    ∃ amountIn p d w2 w3 r,
      ¬ deadline < env.timestamp ∧
      (ext.get w).cancelNonceUsed o.owner nonce = false ∧
      ext.view_AsyncSwap_asyncOrderInfo env (burn ext w o.owner nonce) ext.HOOK (poolIdOf ext o)
        (orderIdOf ext env o) = .ok (amountIn, p) ∧
      EIP712.«_hashTypedDataV4» ext (cancelHash ext o (orderIdOf ext env o) amountIn nonce deadline) env
        (burn ext w o.owner nonce) = .ok (d, w2) ∧
      SignatureChecker.isValidSignatureNow ext o.owner d signature env w2 = .ok (true, w3) ∧
      ext.call_IPoolManager_unlock ext.POOLMANAGER (Router.callbackData 2 o 0) env w3 = .ok (r, w') := by
  by_cases ht : deadline < env.timestamp
  · rw [cancelWithSig_expired ext o nonce deadline signature env w ht] at hok; cases hok
  by_cases hn : (ext.get w).cancelNonceUsed o.owner nonce = true
  · rw [cancelWithSig_nonce_used ext o nonce deadline signature env w ht hn] at hok; cases hok
  have hn' : (ext.get w).cancelNonceUsed o.owner nonce = false := by simpa using hn
  rcases hi : ext.view_AsyncSwap_asyncOrderInfo env (burn ext w o.owner nonce) ext.HOOK (poolIdOf ext o)
      (orderIdOf ext env o) with e | ⟨amountIn, p⟩
  · rw [cancelWithSig_info_revert ext o nonce deadline signature env w e ht hn' hi] at hok; cases hok
  rw [cancelWithSig_eq_prefix ext o nonce deadline signature env w amountIn p ht hn' hi] at hok
  rcases hD : EIP712.«_hashTypedDataV4» ext (cancelHash ext o (orderIdOf ext env o) amountIn nonce deadline)
      env (burn ext w o.owner nonce) with e | ⟨d, w2⟩
  · rw [hD] at hok; cases hok
  rw [hD] at hok
  rcases hS : SignatureChecker.isValidSignatureNow ext o.owner d signature env w2 with e | ⟨b, w3⟩
  · simp only [hS] at hok; cases hok
  simp only [hS] at hok
  cases b
  · simp at hok
  · simp only [tail, Bool.true_eq_false, ite_false] at hok
    rcases hu : ext.call_IPoolManager_unlock ext.POOLMANAGER (Router.callbackData 2 o 0) env w3
      with e | ⟨r, w4⟩
    · simp [hu] at hok
    · simp [hu] at hok
      subst hok
      exact ⟨amountIn, p, d, w2, w3, r, ht, hn', rfl, hD, hS, hu⟩

/-- The callees the model leaves abstract are storage-neutral: `toTypedDataHash` is `pure`, the
ERC-1271 check is a `staticcall`. -/
structure PureCallees : Prop where
  typed : ∀ d sh, Preserves (ext.fn_MessageHashUtils_toTypedDataHash_5799 d sh)
  erc1271 : ∀ hash, Preserves (ext.fn_SignatureChecker_isValidERC1271SignatureNow_1883 o.owner hash signature)

/-- **Footprint.** With storage-neutral callees, a successful call found `(owner, nonce)` fresh, and the
state it hands to `unlock(SwapCallback(Cancel, order, 0))` is the initial state with only
`cancelNonceUsed[order.owner][nonce] = true` written: no transient slot, no other storage. -/
theorem cancelWithSig_ok_state (w' : σ) (hpure : PureCallees ext o signature)
    (hok : Router.cancelWithSig ext o nonce deadline signature env w = .ok ((), w')) :
    (ext.get w).cancelNonceUsed o.owner nonce = false ∧
    ∃ r, ext.call_IPoolManager_unlock ext.POOLMANAGER (Router.callbackData 2 o 0) env
      (burn ext w o.owner nonce) = .ok (r, w') := by
  obtain ⟨amountIn, p, d, w2, w3, r, _, hn, _, hD, hS, hu⟩ :=
    cancelWithSig_ok_inv ext o nonce deadline signature env w w' hok
  have e2 := hashTypedDataV4_preserves ext _ (fun d => hpure.typed d _) env _ d w2 hD
  subst e2
  have e3 := isValidSignatureNow_preserves ext o.owner d signature (hpure.erc1271 d) env _ true w3 hS
  subst e3
  exact ⟨hn, r, hu⟩

/-- The burn sets exactly `(owner, nonce)` and leaves every other nonce and every other field of the
Router's storage unchanged. -/
theorem burn_frame (hget : ∀ w s, ext.get (ext.set w s) = s) (maker : Nat) :
    (ext.get (burn ext w maker nonce)).cancelNonceUsed maker nonce = true
    ∧ (∀ m n, (m ≠ maker ∨ n ≠ nonce) →
        (ext.get (burn ext w maker nonce)).cancelNonceUsed m n = (ext.get w).cancelNonceUsed m n)
    ∧ { ext.get (burn ext w maker nonce) with cancelNonceUsed := (ext.get w).cancelNonceUsed } = ext.get w := by
  refine ⟨by simp [burn, hget, upd], fun m n hmn => ?_, by simp [burn, hget]⟩
  rcases hmn with hm | hn
  · simp [burn, hget, upd, hm]
  · by_cases hm : m = maker
    · subst hm; simp [burn, hget, upd, hn]
    · simp [burn, hget, upd, hm]

/-- **No replay, even re-entrantly.** In the state handed to `unlock` the pair `(owner, nonce)` is already
burnt, so a `cancelWithSig` with the same owner and nonce (any order fields, deadline, signature,
environment) made from inside the callback reverts. -/
theorem cancelWithSig_reentry_reverts (hget : ∀ w s, ext.get (ext.set w s) = s)
    (o' : AsyncOrder) (ho : o'.owner = o.owner) (deadline' : Nat) (signature' : List Nat) (env' : Env) :
    ∃ e, Router.cancelWithSig ext o' nonce deadline' signature' env' (burn ext w o.owner nonce) = .error e := by
  have hused := (burn_frame ext nonce w hget o.owner).1
  rw [← ho] at hused ⊢
  by_cases ht : deadline' < env'.timestamp
  · exact ⟨_, cancelWithSig_expired ext o' nonce deadline' signature' env' _ ht⟩
  · exact ⟨_, cancelWithSig_nonce_used ext o' nonce deadline' signature' env' _ ht hused⟩

/-- **No replay after the call.** If `unlock` never clears a burnt cancel nonce (the Router has no code
that sets one back to `false`), then after a successful call, any later `cancelWithSig` with the same
`(owner, nonce)` reverts. -/
theorem cancelWithSig_no_replay (w' : σ) (hget : ∀ w s, ext.get (ext.set w s) = s)
    (hpure : PureCallees ext o signature)
    (hmono : ∀ w₀ r w₁, ext.call_IPoolManager_unlock ext.POOLMANAGER (Router.callbackData 2 o 0) env w₀
      = .ok (r, w₁) → (ext.get w₀).cancelNonceUsed o.owner nonce = true →
        (ext.get w₁).cancelNonceUsed o.owner nonce = true)
    (hok : Router.cancelWithSig ext o nonce deadline signature env w = .ok ((), w'))
    (o' : AsyncOrder) (ho : o'.owner = o.owner) (deadline' : Nat) (signature' : List Nat) (env' : Env) :
    ∃ e, Router.cancelWithSig ext o' nonce deadline' signature' env' w' = .error e := by
  obtain ⟨_, r, hu⟩ := cancelWithSig_ok_state ext o nonce deadline signature env w w' hpure hok
  have hused := hmono _ r w' hu (burn_frame ext nonce w hget o.owner).1
  rw [← ho] at hused
  by_cases ht : deadline' < env'.timestamp
  · exact ⟨_, cancelWithSig_expired ext o' nonce deadline' signature' env' _ ht⟩
  · exact ⟨_, cancelWithSig_nonce_used ext o' nonce deadline' signature' env' _ ht hused⟩

end Router.Swarm.CancelWithSig
