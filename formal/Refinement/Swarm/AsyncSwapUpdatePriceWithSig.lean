import Generated.AsyncSwap
import Refinement.Monad
import Refinement.Swarm.AsyncSwapUpdatePrice
import Refinement.Swarm.AsyncSwapSetExecutorWithSig

/-!
# `AsyncSwap.updatePriceWithSig`

`function updatePriceWithSig(AsyncOrder order, uint256 newAmountOutMin, uint256 nonce,
uint256 deadline, bytes signature) external` (src/AsyncSwap.sol:555).

With `pid = order.key.toId()`, `id = order.orderId()`, `amountIn = asyncOrders[pid].orders[id].amountIn`
(read in the initial state) and `sh = hashUpdatePrice(order, id, amountIn, n, nonce, deadline)`:

* `_verify(order.owner, sh, nonce, deadline, signature)`:
  `block.timestamp > deadline` → `SignatureExpired`; `nonceUsed[owner][nonce]` → `NonceAlreadyUsed`;
  the nonce is burnt; `!isValidSignatureNow(owner, _hashTypedDataV4(sh), signature)` → `InvalidSignature`.
* `AsyncFiller.updatePrice(.., caller = order.owner)`: the `NotOrderOwner` guard can never fire (the
  caller passed is the owner itself, authorization is the signature); `n = 0` → `ZeroAmount`;
  `amountIn = 0` → `OrderNotFound`; then `_remove` (opaque; the `RadixPriceTree` guards
  `leafId == 0` / `id == 0` live there), the writes `mid` of `AsyncSwap.updatePrice`, `_append` (opaque).
* On success (storage-neutral signature callees, lawful `ext`): the owner signed exactly
  `(owner, tokenIn, tokenOut, amountIn, n, id, nonce, deadline)`, the nonce was fresh and is now burnt,
  and the storage is `_append ∘ mid ∘ _remove` of the burnt state; the only `staticcall` is the
  ERC-1271 check, made with `(owner, digest, signature)`.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.UpdatePriceWithSig

open AsyncSwap.Swarm.UpdatePrice (poolId orderId selfGet selfSet bookGet bookSet mid tail midState
  mid_ok midState_frame)
open AsyncSwap.Swarm.SetExecutorWithSig (Preserves burn isValidSignatureNow_preserves
  hashTypedDataV4_preserves)

variable {σ : Type} (ext : Ext σ)

/-- `OrderSignatures.hashUpdatePrice(order, id, amountIn, n, nonce, deadline)` in the model, with
`amountIn` read from `asyncOrders[pid].orders[id]` in the call's initial state `w`. -/
def structHash (env : Env) (w : σ) (order : AsyncOrder) (n nonce deadline : Nat) : Nat :=
  let id := orderId ext env order
  let amt := (((ext.get w).asyncOrders (poolId ext order.key)).orders id).amountIn
  let tk := if order.zeroForOne then (order.key.currency0, order.key.currency1)
    else (order.key.currency1, order.key.currency0)
  ext.keccak [OrderSignatures.UPDATE_PRICE_TYPEHASH, order.owner, tk.1, tk.2, amt, n, id, nonce, deadline]

/-- What `_verify` does, step by step. -/
def verifyRun (maker sh nonce deadline : Nat) (sig : List Nat) (env : Env) (w : σ) :
    Except Revert (Unit × σ) :=
  if deadline < env.timestamp then .error ⟨"SignatureExpired"⟩
  else if (ext.get w).nonceUsed maker nonce = true then .error ⟨"NonceAlreadyUsed"⟩
  else match EIP712.«_hashTypedDataV4» ext sh env (burn ext w maker nonce) with
    | .error e => .error e
    | .ok (d, w2) => match SignatureChecker.isValidSignatureNow ext maker d sig env w2 with
      | .error e => .error e
      | .ok (b, w3) => if b = true then .ok ((), w3) else .error ⟨"InvalidSignature"⟩

theorem verify_run (maker sh nonce deadline : Nat) (sig : List Nat) (env : Env) (w : σ) :
    AsyncSwap.«_verify» ext maker sh nonce deadline sig env w =
      verifyRun ext maker sh nonce deadline sig env w := by
  unfold verifyRun
  by_cases ht : deadline < env.timestamp
  · simp [AsyncSwap.«_verify», ht]
  · by_cases hn : (ext.get w).nonceUsed maker nonce = true
    · simp [AsyncSwap.«_verify», ht, hn]
    · rcases hD : EIP712.«_hashTypedDataV4» ext sh env (burn ext w maker nonce) with e | ⟨d, w2⟩
      · simp only [burn] at hD
        simp [AsyncSwap.«_verify», ht, hn, hD]
      · rcases hS : SignatureChecker.isValidSignatureNow ext maker d sig env w2 with e | ⟨b, w3⟩
        · simp only [burn] at hD
          simp [AsyncSwap.«_verify», ht, hn, hD, hS]
        · simp only [burn] at hD
          cases b <;> simp [AsyncSwap.«_verify», ht, hn, hD, hS]

/-- **Full characterization.** `_verify` over the struct hash of the arguments (with `amountIn` read
before it), then `ZeroAmount`, `OrderNotFound` (on the post-`_verify` state), then `tail`
(`_remove`, `mid`, `_append`). The `NotOrderOwner` guard is gone: `caller = order.owner`. -/
theorem updatePriceWithSig_run (order : AsyncOrder) (n nonce deadline : Nat) (sig : List Nat)
    (env : Env) (w : σ) :
    AsyncSwap.updatePriceWithSig ext order n nonce deadline sig env w =
      match AsyncSwap.«_verify» ext order.owner (structHash ext env w order n nonce deadline)
          nonce deadline sig env w with
      | .error e => .error e
      | .ok (_, w1) =>
        if n = 0 then .error ⟨"ZeroAmount"⟩
        else if (((ext.get w1).asyncOrders (poolId ext order.key)).orders
            (orderId ext env order)).amountIn = 0 then .error ⟨"OrderNotFound"⟩
        else tail ext (poolId ext order.key) (orderId ext env order) n env w1 := by
  unfold structHash tail mid selfGet selfSet bookGet bookSet orderId poolId
  simp only [AsyncSwap.updatePriceWithSig, AsyncFiller.updatePrice, OrderSignatures.hashUpdatePrice,
    OrderSignatures.tokens, AsyncOrderLibrary.orderId, PoolIdLibrary.toId, bind_pure_unit,
    bind_assoc, pure_bind]
  simp only [run_bind, run_read, run_get, run_modify, run_throw, run_ite]
  generalize ext.keccak [order.key.currency0, order.key.currency1, order.key.fee,
    toUnsigned 256 order.key.tickSpacing, order.key.hooks] = pid
  generalize ext.keccak [env.chainid, pid, order.owner, ybool order.zeroForOne, order.salt] = oid
  split
  · rename_i w1 _
    by_cases h2 : n = 0 <;>
    by_cases h3 : (((ext.get w1).asyncOrders pid).orders oid).amountIn = 0 <;>
    simp_all
  · simp_all

variable (order : AsyncOrder) (n nonce deadline : Nat) (sig : List Nat) (env : Env) (w : σ)

/-- Guard 1 (AsyncSwap.sol:592): an expired deadline reverts `SignatureExpired`. -/
theorem updatePriceWithSig_expired (ht : deadline < env.timestamp) :
    AsyncSwap.updatePriceWithSig ext order n nonce deadline sig env w
      = .error ⟨"SignatureExpired"⟩ := by
  rw [updatePriceWithSig_run, verify_run]; simp [verifyRun, ht]

/-- Guard 2 (AsyncSwap.sol:593): a used `(owner, nonce)` reverts `NonceAlreadyUsed`. -/
theorem updatePriceWithSig_nonceUsed (ht : ¬ deadline < env.timestamp)
    (hn : (ext.get w).nonceUsed order.owner nonce = true) :
    AsyncSwap.updatePriceWithSig ext order n nonce deadline sig env w
      = .error ⟨"NonceAlreadyUsed"⟩ := by
  rw [updatePriceWithSig_run, verify_run]; simp [verifyRun, ht, hn]

/-- Guard 3 (AsyncSwap.sol:596): a signature rejected for `order.owner` over the EIP-712 digest of
`structHash` reverts `InvalidSignature`. -/
theorem updatePriceWithSig_invalidSig (d : Nat) (w2 w3 : σ) (ht : ¬ deadline < env.timestamp)
    (hn : (ext.get w).nonceUsed order.owner nonce = false)
    (hD : EIP712.«_hashTypedDataV4» ext (structHash ext env w order n nonce deadline) env
      (burn ext w order.owner nonce) = .ok (d, w2))
    (hS : SignatureChecker.isValidSignatureNow ext order.owner d sig env w2 = .ok (false, w3)) :
    AsyncSwap.updatePriceWithSig ext order n nonce deadline sig env w
      = .error ⟨"InvalidSignature"⟩ := by
  rw [updatePriceWithSig_run, verify_run]; simp [verifyRun, ht, hn, hD, hS]

/-- Guard 4 (AsyncFiller.sol:279): once `_verify` passes, `n = 0` reverts `ZeroAmount`. -/
theorem updatePriceWithSig_zero (w1 : σ)
    (hV : AsyncSwap.«_verify» ext order.owner (structHash ext env w order 0 nonce deadline)
      nonce deadline sig env w = .ok ((), w1)) :
    AsyncSwap.updatePriceWithSig ext order 0 nonce deadline sig env w = .error ⟨"ZeroAmount"⟩ := by
  rw [updatePriceWithSig_run, hV]; simp

/-- Guard 5 (AsyncFiller.sol:281): once `_verify` passes, a missing order reverts `OrderNotFound`. -/
theorem updatePriceWithSig_notFound (w1 : σ)
    (hV : AsyncSwap.«_verify» ext order.owner (structHash ext env w order n nonce deadline)
      nonce deadline sig env w = .ok ((), w1)) (hn : n ≠ 0)
    (h0 : (((ext.get w1).asyncOrders (poolId ext order.key)).orders (orderId ext env order)).amountIn = 0) :
    AsyncSwap.updatePriceWithSig ext order n nonce deadline sig env w
      = .error ⟨"OrderNotFound"⟩ := by
  rw [updatePriceWithSig_run, hV]; simp [hn, h0]

/-- Guard (AsyncFiller.sol:278) `caller != order.owner` never fires: every revert comes from
`_verify`, `ZeroAmount`, `OrderNotFound` or the `tail` (`_remove`/`mid`/`_append`), since
`updatePriceWithSig` passes `order.owner` itself as the caller. -/
theorem updatePriceWithSig_noOwnerGuard :
    ∀ e, AsyncSwap.updatePriceWithSig ext order n nonce deadline sig env w = .error e →
      (∃ w1, AsyncSwap.«_verify» ext order.owner (structHash ext env w order n nonce deadline)
          nonce deadline sig env w = .ok ((), w1) ∧ n ≠ 0 ∧
          (((ext.get w1).asyncOrders (poolId ext order.key)).orders (orderId ext env order)).amountIn ≠ 0 ∧
          tail ext (poolId ext order.key) (orderId ext env order) n env w1 = .error e)
      ∨ AsyncSwap.«_verify» ext order.owner (structHash ext env w order n nonce deadline)
          nonce deadline sig env w = .error e
      ∨ e = ⟨"ZeroAmount"⟩ ∨ e = ⟨"OrderNotFound"⟩ := by
  intro e h
  rw [updatePriceWithSig_run] at h
  rcases hV : AsyncSwap.«_verify» ext order.owner (structHash ext env w order n nonce deadline)
    nonce deadline sig env w with e' | ⟨u, w1⟩
  · rw [hV] at h; cases h; exact Or.inr (Or.inl rfl)
  · cases u
    rw [hV] at h
    simp only at h
    by_cases hn : n = 0
    · rw [if_pos hn] at h; cases h; exact Or.inr (Or.inr (Or.inl rfl))
    · rw [if_neg hn] at h
      by_cases h0 :
          (((ext.get w1).asyncOrders (poolId ext order.key)).orders (orderId ext env order)).amountIn = 0
      · rw [if_pos h0] at h; cases h; exact Or.inr (Or.inr (Or.inr rfl))
      · rw [if_neg h0] at h; exact Or.inl ⟨w1, rfl, hn, h0, h⟩

/-- The signature callees the model leaves abstract are storage-neutral: `toTypedDataHash` is
`pure`, and the ERC-1271 check is a `staticcall`. -/
structure PureCallees (maker : Nat) (sig : List Nat) : Prop where
  typed : ∀ d sh, Preserves (ext.fn_MessageHashUtils_toTypedDataHash_9732 d sh)
  erc1271 : ∀ hash, Preserves (ext.fn_SignatureChecker_isValidERC1271SignatureNow_2280 maker hash sig)

/-- A successful `_verify` passed the deadline, found the nonce fresh, got the signature accepted
for `maker` over `_hashTypedDataV4(sh)`, and left exactly the nonce burn. -/
theorem verify_ok_inv (maker sh : Nat) (hp : PureCallees ext maker sig) (w1 : σ)
    (h : AsyncSwap.«_verify» ext maker sh nonce deadline sig env w = .ok ((), w1)) :
    ¬ deadline < env.timestamp ∧ (ext.get w).nonceUsed maker nonce = false ∧
    (∃ d, EIP712.«_hashTypedDataV4» ext sh env (burn ext w maker nonce)
        = .ok (d, burn ext w maker nonce) ∧
      SignatureChecker.isValidSignatureNow ext maker d sig env (burn ext w maker nonce)
        = .ok (true, burn ext w maker nonce)) ∧
    w1 = burn ext w maker nonce := by
  rw [verify_run] at h
  unfold verifyRun at h
  by_cases ht : deadline < env.timestamp
  · simp [ht] at h
  by_cases hn : (ext.get w).nonceUsed maker nonce = true
  · simp [ht, hn] at h
  simp only [ht, hn, ite_false] at h
  rcases hD : EIP712.«_hashTypedDataV4» ext sh env (burn ext w maker nonce) with e | ⟨d, w2⟩
  · simp [hD] at h
  have e2 := hashTypedDataV4_preserves ext sh (fun d => hp.typed d sh) env _ d w2 hD
  subst e2
  rcases hS : SignatureChecker.isValidSignatureNow ext maker d sig env (burn ext w maker nonce)
    with e | ⟨b, w3⟩
  · simp [hD, hS] at h
  have e3 := isValidSignatureNow_preserves ext maker d sig (hp.erc1271 d) env _ b w3 hS
  subst e3
  cases b
  · simp [hD, hS] at h
  · simp [hD, hS] at h
    exact ⟨ht, by simpa using hn, ⟨d, by first | rfl | exact hD, hS⟩,
      by first | exact h.symm | exact h⟩

theorem burn_asyncOrders (hget : ∀ w s, ext.get (ext.set w s) = s) (m k : Nat) :
    (ext.get (burn ext w m k)).asyncOrders = (ext.get w).asyncOrders ∧
    (ext.get (burn ext w m k)).priceBooks = (ext.get w).priceBooks := by
  simp [burn, hget]

/-- A missing order (or `n = 0`) always reverts, whatever the signature. -/
theorem updatePriceWithSig_missing_reverts (hget : ∀ w s, ext.get (ext.set w s) = s)
    (hp : PureCallees ext order.owner sig)
    (h0 : n = 0 ∨
      (((ext.get w).asyncOrders (poolId ext order.key)).orders (orderId ext env order)).amountIn = 0) :
    ∃ e, AsyncSwap.updatePriceWithSig ext order n nonce deadline sig env w = .error e := by
  rw [updatePriceWithSig_run]
  rcases hV : AsyncSwap.«_verify» ext order.owner (structHash ext env w order n nonce deadline)
    nonce deadline sig env w with e | ⟨u, w1⟩
  · exact ⟨e, rfl⟩
  · cases u
    obtain ⟨-, -, -, rfl⟩ := verify_ok_inv ext nonce deadline sig env w _ _ hp w1 hV
    by_cases hn : n = 0
    · exact ⟨⟨"ZeroAmount"⟩, by simp [hn]⟩
    · have h0' : (((ext.get w).asyncOrders (poolId ext order.key)).orders
          (orderId ext env order)).amountIn = 0 := h0.resolve_left hn
      refine ⟨⟨"OrderNotFound"⟩, ?_⟩
      simp [hn, (burn_asyncOrders ext w hget _ _).1, h0']

/-- **Success.** A successful call (lawful `ext`, storage-neutral signature callees): the deadline
held; `(owner, nonce)` was fresh; `isValidSignatureNow` accepted `sig` **for `order.owner`** over the
EIP-712 digest of `structHash` (binding owner, tokens, current `amountIn`, `n`, order id, nonce,
deadline); `n ≠ 0`; the order exists; and the storage is the nonce burn, then `_remove`, then
`midState` (new `amountOutMin`, price key in `[1, 2^128)`, fresh uint64 sequence), then `_append`. -/
theorem updatePriceWithSig_ok (hget : ∀ w s, ext.get (ext.set w s) = s)
    (hp : PureCallees ext order.owner sig) (w' : σ)
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
        (bookSet ext pid) id env w2 = .ok ((), w') := by
  intro pid id wb
  rw [updatePriceWithSig_run] at h
  rcases hV : AsyncSwap.«_verify» ext order.owner (structHash ext env w order n nonce deadline)
    nonce deadline sig env w with e | ⟨u, w1⟩
  · rw [hV] at h; cases h
  cases u
  rw [hV] at h
  obtain ⟨ht, hn, hsig, rfl⟩ := verify_ok_inv ext nonce deadline sig env w _ _ hp w1 hV
  simp only at h
  by_cases hn0 : n = 0
  · rw [if_pos hn0] at h; cases h
  rw [if_neg hn0] at h
  by_cases h0 : (((ext.get (burn ext w order.owner nonce)).asyncOrders pid).orders id).amountIn = 0
  · rw [if_pos h0] at h; cases h
  rw [if_neg h0] at h
  rw [(burn_asyncOrders ext w hget _ _).1] at h0
  refine ⟨ht, hn, hsig, hn0, h0, ?_⟩
  simp only [tail, run_bind] at h
  split at h
  next a w1 hr =>
    cases a
    split at h
    next b w2 hm =>
      cases b
      obtain ⟨p, _, _, hp1, hp2, hs64, hw2⟩ := mid_ok ext hget pid id n env w1 w2 hm
      exact ⟨w1, w2, p, hr, hp1, hp2, hs64, hw2, h⟩
    next => cases h
  next => cases h

/-- The opaque `_remove`/`_append` keep `nonceUsed` (they only go through the pool's
`asyncOrders`/`priceBooks` accessors). -/
def KeepsNonces (p : M σ Unit) : Prop :=
  ∀ env s s', p env s = .ok ((), s') → (ext.get s').nonceUsed = (ext.get s).nonceUsed

/-- **Nonce burnt, no replay.** After a successful call, `nonceUsed` is exactly the old map with
`(order.owner, nonce)` set, and any later `updatePriceWithSig` with the same owner and nonce
reverts (whatever order, price, deadline or signature). -/
theorem updatePriceWithSig_burns_nonce (hget : ∀ w s, ext.get (ext.set w s) = s)
    (hp : PureCallees ext order.owner sig)
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
      ∃ e, AsyncSwap.updatePriceWithSig ext order' n' nonce deadline' sig' env' w' = .error e := by
  obtain ⟨-, -, -, -, -, w1, w2, p, hr, -, -, -, hw2, ha⟩ :=
    updatePriceWithSig_ok ext order n nonce deadline sig env w hget hp w' h
  have hN : (ext.get w').nonceUsed = upd (ext.get w).nonceUsed order.owner
      (upd ((ext.get w).nonceUsed order.owner) nonce true) := by
    rw [happ env w2 w' ha, hw2, (midState_frame _ _ _ _ _ _).2.2.1, hrem env _ w1 hr]
    simp [burn, hget]
  refine ⟨hN, fun order' n' deadline' sig' env' ho => ?_⟩
  by_cases ht : deadline' < env'.timestamp
  · exact ⟨_, updatePriceWithSig_expired ext order' n' nonce deadline' sig' env' w' ht⟩
  · refine ⟨_, updatePriceWithSig_nonceUsed ext order' n' nonce deadline' sig' env' w' ht ?_⟩
    rw [hN, ho]; simp [upd]

end AsyncSwap.Swarm.UpdatePriceWithSig
