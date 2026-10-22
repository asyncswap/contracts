import Generated.Router
import Refinement.Monad

/-!
# Named spec for the Router's opaque `CurrencyLibrary.transfer`

The Router's model leaves v4-core `CurrencyLibrary.transfer` opaque
(`ext.fn_CurrencyLibrary_transfer_2524`) because it is a Yul `call`. This module gives the same spec
as `AsyncSwap.Swarm.SpecCore.TransferSpec` (`SpecCoreAsyncSwap.lean`), stated over the Router's
`Ext`. The two generated models each carry their own `FormalAst` prelude and can't be imported
together.

* Native currency: one call to `dst` with value `amount` and empty calldata. On failure it reverts
  with `WrappedError(dst, 0, reason, NativeTransferFailed)`.
* ERC-20: one call to `currency` with value 0 and `transfer(dst, amount)` calldata. It succeeds iff
  the call succeeded and returned nothing, or returned at least 32 bytes whose first word is 1.
  Otherwise it reverts with `WrappedError(currency, transfer.selector, reason, ERC20TransferFailed)`.
* No storage write of its own: the world afterwards is the one the call left.

Its caller in the Router model is `CurrencySettler.settle`, on the branch where the Router pays the
PoolManager from its own balance (`payer = address(this)`, ERC-20, no burn).
`settle_selfPay_ok_iff_of_spec` opens that branch up under the spec. No existing Router theorem took
a hypothesis about `fn_CurrencyLibrary_transfer_2524`, so there are no `_of_spec` wrappers here.
`test/formal/SpecCore.t.sol` checks the spec's fields on the compiled library code.
-/

open FormalAst Refinement

namespace Router.Swarm.SpecCore

variable {σ : Type} (ext : Ext σ)

/-- `CurrencyLibrary.NativeTransferFailed.selector`. -/
def NATIVE_TRANSFER_FAILED : Nat := 0xf4b3b1bc
/-- `CurrencyLibrary.ERC20TransferFailed.selector`. -/
def ERC20_TRANSFER_FAILED : Nat := 0xf27f64e4
/-- `IERC20Minimal.transfer.selector`. -/
def TRANSFER_SELECTOR : Nat := 0xa9059cbb

/-- `transfer(address,uint256)` calldata, with `dst` masked to 160 bits. -/
def transferCalldata (dst amount : Nat) : List Nat :=
  (wordBytes (TRANSFER_SELECTOR * 2 ^ 224)).take 4 ++ abiEncode [dst % 2 ^ 160, amount]

/-- The ERC-20 return-data check: no return data, or at least 32 bytes whose first word is exactly 1. -/
def okReturn (rd : List Nat) : Bool :=
  rd.length == 0 || (decide (32 ≤ rd.length) && bytesWord (rd.take 32) == 1)

/-- **Named spec of v4-core `CurrencyLibrary.transfer(currency, dst, amount)`** (Router model). -/
structure TransferSpec : Prop where
  /-- Native: one call to `dst` with value `amount`; a failed call reverts through
  `bubbleUpAndRevertWith(dst, 0, NativeTransferFailed)`. -/
  native : ∀ dst amount env w,
    ext.fn_CurrencyLibrary_transfer_2524 CurrencyLibrary.ADDRESS_ZERO dst amount env w =
      match ext.lowCall dst amount [] env w with
      | .error e => .error e
      | .ok ((ok, _), w1) =>
        if ok then .ok ((), w1)
        else CustomRevert.bubbleUpAndRevertWith ext dst 0 NATIVE_TRANSFER_FAILED env w1
  /-- ERC-20: one call to `currency` with `transfer(dst, amount)`; it succeeds iff the call succeeded
  and `okReturn` holds, and otherwise reverts through
  `bubbleUpAndRevertWith(currency, transfer.selector, ERC20TransferFailed)`. -/
  erc20 : ∀ currency dst amount env w, currency ≠ CurrencyLibrary.ADDRESS_ZERO →
    ext.fn_CurrencyLibrary_transfer_2524 currency dst amount env w =
      match ext.lowCall currency 0 (transferCalldata dst amount) env w with
      | .error e => .error e
      | .ok ((ok, rd), w1) =>
        if ok && okReturn rd then .ok ((), w1)
        else CustomRevert.bubbleUpAndRevertWith ext currency TRANSFER_SELECTOR ERC20_TRANSFER_FAILED
          env w1

theorem bubbleUp_error (a b c : Nat) (env : Env) (w : σ) :
    CustomRevert.bubbleUpAndRevertWith ext a b c env w = .error ⟨"revert"⟩ := by
  simp [CustomRevert.bubbleUpAndRevertWith]

/-- **When `transfer` succeeds**: exactly when its one call succeeds into `w'`, and for an ERC-20
only if the return data passes `okReturn`. -/
theorem TransferSpec.ok_iff (hs : TransferSpec ext) (currency dst amount : Nat) (env : Env)
    (w w' : σ) :
    ext.fn_CurrencyLibrary_transfer_2524 currency dst amount env w = .ok ((), w') ↔
      (currency = 0 ∧ ∃ rd, ext.lowCall dst amount [] env w = .ok ((true, rd), w')) ∨
      (currency ≠ 0 ∧ ∃ rd, ext.lowCall currency 0 (transferCalldata dst amount) env w
        = .ok ((true, rd), w') ∧ okReturn rd = true) := by
  by_cases hc : currency = 0
  · subst hc
    rw [show (0 : Nat) = CurrencyLibrary.ADDRESS_ZERO from rfl, hs.native]
    rcases hcall : ext.lowCall dst amount [] env w with e | ⟨⟨ok, rd⟩, w1⟩
    · simp
    · cases ok <;> simp [bubbleUp_error, CurrencyLibrary.ADDRESS_ZERO]
  · rw [hs.erc20 _ _ _ _ _ hc]
    rcases hcall : ext.lowCall currency 0 (transferCalldata dst amount) env w with e | ⟨⟨ok, rd⟩, w1⟩
    · simp [hc]
    · cases ok <;> cases hr : okReturn rd <;> simp [bubbleUp_error, hc, hr] <;>
        exact ⟨fun h => ⟨rd, ⟨rfl, h⟩, hr⟩, fun ⟨_, ⟨_, h2⟩, _⟩ => h2⟩

/-- **Footprint.** If the low-level call leaves the Router's storage alone, so does a successful
`transfer`. -/
theorem TransferSpec.frame (hs : TransferSpec ext) (env : Env)
    (hcall : ∀ a v d (v0 : σ) r v', ext.lowCall a v d env v0 = .ok (r, v') → ext.get v' = ext.get v0)
    (currency dst amount : Nat) (w w' : σ)
    (h : ext.fn_CurrencyLibrary_transfer_2524 currency dst amount env w = .ok ((), w')) :
    ext.get w' = ext.get w := by
  rcases (hs.ok_iff ext currency dst amount env w w').1 h with ⟨-, rd, hc⟩ | ⟨-, rd, hc, -⟩
  · exact hcall _ _ _ _ _ _ hc
  · exact hcall _ _ _ _ _ _ hc

/-- **`CurrencySettler.settle` paying from the Router's own balance** (ERC-20, no burn,
`payer = address(this)`) under the spec. It succeeds into `w'` iff `sync(currency)` succeeds, then
the `transfer(manager, amount)` call succeeds with acceptable return data, then `settle()` succeeds
into `w'`. -/
theorem settle_selfPay_ok_iff_of_spec (hs : TransferSpec ext) (currency manager amount : Nat)
    (env : Env) (w w' : σ) (hc : currency ≠ 0) :
    CurrencySettler.settle ext currency manager env.self amount false env w = .ok ((), w') ↔
      ∃ w1 w2 rd n, ext.call_IPoolManager_sync manager currency env w = .ok ((), w1) ∧
        ext.lowCall currency 0 (transferCalldata manager amount) env w1 = .ok ((true, rd), w2) ∧
        okReturn rd = true ∧
        ext.call_IPoolManager_settle manager env w2 = .ok (n, w') := by
  have hz : (currency == CurrencyLibrary.ADDRESS_ZERO) = false := by
    simpa [CurrencyLibrary.ADDRESS_ZERO] using hc
  simp only [CurrencySettler.settle, CurrencyLibrary.isAddressZero, hz, run_bind, run_pure,
    run_read, Bool.false_eq_true, ite_false, bne_self_eq_false, pure_bind]
  constructor
  · intro h
    rcases h1 : ext.call_IPoolManager_sync manager currency env w with e | ⟨⟨⟩, w1⟩
    · rw [h1] at h; simp at h
    · rw [h1] at h
      simp only at h
      rcases h2 : ext.fn_CurrencyLibrary_transfer_2524 currency manager amount env w1 with
        e | ⟨⟨⟩, w2⟩
      · rw [h2] at h; simp at h
      · rw [h2] at h
        simp only at h
        rcases h3 : ext.call_IPoolManager_settle manager env w2 with e | ⟨n, w3⟩
        · rw [h3] at h; simp at h
        · rw [h3] at h
          simp only [Except.ok.injEq, Prod.mk.injEq] at h
          obtain ⟨-, rfl⟩ := h
          rcases (hs.ok_iff ext currency manager amount env w1 w2).1 h2 with
            ⟨hc0, -⟩ | ⟨-, rd, hl, hr⟩
          · exact absurd hc0 hc
          · exact ⟨w1, w2, rd, n, rfl, hl, hr, h3⟩
  · rintro ⟨w1, w2, rd, n, h1, hl, hr, h3⟩
    have h2 : ext.fn_CurrencyLibrary_transfer_2524 currency manager amount env w1 = .ok ((), w2) :=
      (hs.ok_iff ext currency manager amount env w1 w2).2 (Or.inr ⟨hc, rd, hl, hr⟩)
    simp [h1, h2, h3]

end Router.Swarm.SpecCore
