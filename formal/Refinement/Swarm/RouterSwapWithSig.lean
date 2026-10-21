import Generated.Router
import Refinement.Monad
import Refinement.Router

/-!
# `Router.swapWithSig` (src/Router.sol:178)

Guard: the order's input currency must not be native (`address(0)`), else it reverts with
`"Native input needs swap()"`. Then, only when `grant.signature` is non-empty and the hook does not
already list this Router as the owner's executor (`HOOK.isExecutor`, a view call), it calls
`HOOK.setExecutorWithSig(key, owner, address(this), true, nonce, deadline, sig)`. It then does two
transient stores, `USER_LOCATION := order.owner` and `ASYNC_FILLER_LOCATION := address(this)`, and
makes one call, `POOLMANAGER.unlock(abi.encode(SwapCallback(SwapWithSig = 3, order, 0), permit))`.
The Router writes no persistent storage of its own.

What this means for an attacker: anyone can call `swapWithSig` with any order. The Router itself
never moves funds and never credits the caller. It records `order.owner`, not `msg.sender`, as the
user, so whatever the callback pulls through Permit2 comes from the owner and needs the owner's
signature (`permit`). That check happens in the callback, not here.
-/

open FormalAst Refinement

namespace Router

variable {σ : Type} (ext : Ext σ)

/-- The calldata `swapWithSig` hands to `PoolManager.unlock`:
`abi.encode(SwapCallback(3, order, 0), permit)`. The head is the 14 callback words followed by the
offset (480) of the dynamic `permit` tuple. The tail is `(nonce, deadline, offset 96, signature bytes)`. -/
def swapWithSigData (o : AsyncOrder) (p : Router.PermitData) : List Nat :=
  abiEncode [3, o.key.currency0, o.key.currency1, o.key.fee, toUnsigned 256 o.key.tickSpacing, o.key.hooks,
    o.owner, ybool o.zeroForOne, o.amountIn, o.amountOutMin, o.priorityFee, o.sqrtPrice, o.salt, 0, 480]
  ++ (abiEncode [p.nonce, p.deadline, 96] ++ abiBytes p.signature)

/-- The state `unlock` starts from: the order's **owner** (not the caller) as the user, and
`address(this)` as the filler, both in transient storage. -/
def swapWithSigPre (o : AsyncOrder) (env : Env) (w : σ) : σ :=
  tstore ext (tstore ext w Router.USER_LOCATION o.owner) Router.ASYNC_FILLER_LOCATION env.self

/-- The `unlock` step, run from a state `w`. -/
def swapWithSigTail (o : AsyncOrder) (p : Router.PermitData) (env : Env) (w : σ) :=
  ((fun _ => ()) <$> ext.call_IPoolManager_unlock ext.POOLMANAGER (swapWithSigData o p)) env
    (swapWithSigPre ext o env w)

/-- **Guard**: a native input reverts with `"Native input needs swap()"`, before any external call. -/
theorem swapWithSig_native (o : AsyncOrder) (p : Router.PermitData) (g : Router.ExecutorGrant) (env : Env) (w : σ)
    (h : inputCurrency o = 0) :
    Router.swapWithSig ext o p g env w = .error ⟨"Native input needs swap()"⟩ := by
  simp only [inputCurrency] at h
  simp [Router.swapWithSig, CurrencyLibrary.isAddressZero, CurrencyLibrary.ADDRESS_ZERO, h]

/-- **No grant**: with an ERC-20 input and an empty grant signature, the call is exactly the two
transient stores and the `unlock` call. -/
theorem swapWithSig_noGrant (o : AsyncOrder) (p : Router.PermitData) (g : Router.ExecutorGrant) (env : Env) (w : σ)
    (h : inputCurrency o ≠ 0) (hs : g.signature = []) :
    Router.swapWithSig ext o p g env w = swapWithSigTail ext o p env w := by
  simp only [inputCurrency] at h
  simp [Router.swapWithSig, CurrencyLibrary.isAddressZero, CurrencyLibrary.ADDRESS_ZERO, h, hs,
    swapWithSigTail, swapWithSigPre, swapWithSigData, tstore]

/-- **Already an executor**: if the hook already lists this Router as the owner's executor, a
non-empty grant is ignored (no `setExecutorWithSig` call). -/
theorem swapWithSig_alreadyExecutor (o : AsyncOrder) (p : Router.PermitData) (g : Router.ExecutorGrant)
    (env : Env) (w : σ) (h : inputCurrency o ≠ 0) (hs : g.signature ≠ [])
    (hx : ext.view_AsyncSwap_isExecutor env w ext.HOOK (ext.keccak [o.key.currency0, o.key.currency1, o.key.fee,
      toUnsigned 256 o.key.tickSpacing, o.key.hooks]) o.owner env.self = .ok true) :
    Router.swapWithSig ext o p g env w = swapWithSigTail ext o p env w := by
  simp only [inputCurrency] at h
  have hl : g.signature.length ≠ 0 := by simpa using hs
  simp [Router.swapWithSig, CurrencyLibrary.isAddressZero, CurrencyLibrary.ADDRESS_ZERO, PoolIdLibrary.toId,
    view, h, hl, hx, swapWithSigTail, swapWithSigPre, swapWithSigData, tstore]

/-- **Guard (view call)**: a revert of `HOOK.isExecutor` is the call's revert. -/
theorem swapWithSig_isExecutor_revert (o : AsyncOrder) (p : Router.PermitData) (g : Router.ExecutorGrant)
    (env : Env) (w : σ) (h : inputCurrency o ≠ 0) (hs : g.signature ≠ []) (e : Revert)
    (hx : ext.view_AsyncSwap_isExecutor env w ext.HOOK (ext.keccak [o.key.currency0, o.key.currency1, o.key.fee,
      toUnsigned 256 o.key.tickSpacing, o.key.hooks]) o.owner env.self = .error e) :
    Router.swapWithSig ext o p g env w = .error e := by
  simp only [inputCurrency] at h
  have hl : g.signature.length ≠ 0 := by simpa using hs
  simp [Router.swapWithSig, CurrencyLibrary.isAddressZero, CurrencyLibrary.ADDRESS_ZERO, PoolIdLibrary.toId,
    view, h, hl, hx]

/-- **Grant used**: with a non-empty grant signature and the Router not yet an executor, the Router
calls `HOOK.setExecutorWithSig(key, owner, address(this), true, nonce, deadline, sig)`. A revert there
is the call's revert. Otherwise it continues from the state that call leaves. -/
theorem swapWithSig_grant (o : AsyncOrder) (p : Router.PermitData) (g : Router.ExecutorGrant)
    (env : Env) (w : σ) (h : inputCurrency o ≠ 0) (hs : g.signature ≠ [])
    (hx : ext.view_AsyncSwap_isExecutor env w ext.HOOK (ext.keccak [o.key.currency0, o.key.currency1, o.key.fee,
      toUnsigned 256 o.key.tickSpacing, o.key.hooks]) o.owner env.self = .ok false) :
    Router.swapWithSig ext o p g env w
      = match ext.call_AsyncSwap_setExecutorWithSig ext.HOOK o.key o.owner env.self true g.nonce g.deadline
            g.signature env w with
        | .ok (_, w1) => swapWithSigTail ext o p env w1
        | .error e => .error e := by
  simp only [inputCurrency] at h
  have hl : g.signature.length ≠ 0 := by simpa using hs
  simp [Router.swapWithSig, CurrencyLibrary.isAddressZero, CurrencyLibrary.ADDRESS_ZERO, PoolIdLibrary.toId,
    view, h, hl, hx]
  rcases ext.call_AsyncSwap_setExecutorWithSig ext.HOOK o.key o.owner env.self true g.nonce g.deadline
    g.signature env w with _ | ⟨_, w1⟩
  · rfl
  · simp only [swapWithSigTail, swapWithSigPre, swapWithSigData, tstore, run_map]

/-- **Success needs an ERC-20 input**: a call that does not revert had a non-native input currency. -/
theorem swapWithSig_ok_input (o : AsyncOrder) (p : Router.PermitData) (g : Router.ExecutorGrant) (env : Env)
    (w w' : σ) (hok : Router.swapWithSig ext o p g env w = .ok ((), w')) : inputCurrency o ≠ 0 := by
  intro h
  rw [swapWithSig_native ext o p g env w h] at hok
  cases hok

/-- **Footprint**: the Router's own writes before `unlock` only touch the `transient` field. The
user slot holds `order.owner` (whoever the caller is) and the filler slot holds `address(this)`.
Every persistent field (`cancelNonceUsed`, the EIP-712 fallbacks) is unchanged. -/
theorem swapWithSigPre_get (o : AsyncOrder) (env : Env) (w : σ) (hget : ∀ w s, ext.get (ext.set w s) = s) :
    ext.get (swapWithSigPre ext o env w)
      = (let s := ext.get w
         let t := upd (upd s.«transient» Router.USER_LOCATION o.owner) Router.ASYNC_FILLER_LOCATION env.self
         { s with «transient» := t }) := by
  simp [swapWithSigPre, tstore, hget]

/-- The user slot `unlock` sees is the order's owner, never the caller. -/
theorem swapWithSigPre_user (o : AsyncOrder) (env : Env) (w : σ) (hget : ∀ w s, ext.get (ext.set w s) = s) :
    (ext.get (swapWithSigPre ext o env w)).«transient» Router.USER_LOCATION = o.owner := by
  rw [swapWithSigPre_get ext o env w hget]
  simp [upd, Router.USER_LOCATION, Router.ASYNC_FILLER_LOCATION]

/-- The filler slot `unlock` sees is the Router itself. -/
theorem swapWithSigPre_filler (o : AsyncOrder) (env : Env) (w : σ) (hget : ∀ w s, ext.get (ext.set w s) = s) :
    (ext.get (swapWithSigPre ext o env w)).«transient» Router.ASYNC_FILLER_LOCATION = env.self := by
  rw [swapWithSigPre_get ext o env w hget]
  simp [upd]

end Router
