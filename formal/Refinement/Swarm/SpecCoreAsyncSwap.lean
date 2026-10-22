import Generated.AsyncSwap
import Refinement.Monad
import Refinement.Swarm.AsyncSwapAddOrder
import Refinement.Swarm.AsyncSwapBeforeSwap
import Refinement.Swarm.AsyncSwapSweep
import Refinement.Swarm.AsyncSwapSwapAgainstPool

/-!
# Named specs for three opaque AsyncSwap functions

formal-ast leaves these functions of the AsyncSwap model opaque (`Ext` fields). Each spec below states
what the function does in terms of the rest of the model: the generated defs it runs, the low-level
call it makes, the storage it writes. `test/formal/SpecCore.t.sol` checks every field on the compiled
code.

* `CreateOrderSpec`: `AsyncSwap._createOrder` (`ext.fn_AsyncSwap_createOrder_1681`, src/AsyncSwap.sol:470).
  Formal-ast can't translate it because it `mload`s a computed offset (the executor word of `hookData`).
  The spec covers the two guards (executor authorised by the user, then nonzero `amountIn` and
  `amountOutMin`). It covers the contract-assigned salt and id, with the collision walk, and the
  `AsyncMatching.addOrder` call it makes. It also covers the transient hand-off of `(id, executor)`
  to the Router, and says there is nothing else.
* `TransferSpec`: v4-core `CurrencyLibrary.transfer` (`ext.fn_CurrencyLibrary_transfer_4290`), which is
  a Yul `call`. For native currency it calls `to` with value `amount` and empty calldata. For an
  ERC-20 it calls `transfer(to, amount)` with value 0 and accepts empty return data or a first
  return word of exactly 1. Any other outcome reverts through `CustomRevert.bubbleUpAndRevertWith`.
  It writes no contract storage of its own: the world afterwards is the one the call left.
* `PoolStateSlotSpec`: v4-core `StateLibrary._getPoolStateSlot`
  (`ext.fn_StateLibrary_getPoolStateSlot_12612`), which formal-ast can't translate because it hashes
  `abi.encodePacked`. It is pure and returns `keccak256(poolId ‖ POOLS_SLOT)`, `POOLS_SLOT = 6`.

The callers' theorems that took ad-hoc hypotheses about these functions get `_of_spec` versions here
that take the named spec instead.

* `beforeSwap_frame`'s `hcreate` (that `_createOrder` leaves the hook's storage unchanged) is **false
  for the real function**, which stores the new order. No correct spec implies it, so that theorem
  holds only vacuously for the deployed hook. `beforeSwap_frame_of_spec` gives the corrected
  footprint: only pool `poolId`'s state and book change, plus the two hand-off transient slots.
* `sweep_storage_unchanged`'s `htransfer` follows from `TransferSpec` once the low-level call itself
  leaves the hook's storage alone (`TransferSpec.frame`). That is the same kind of assumption the
  model makes for every external call.
* The `NoActiveLiquidity` theorems of `_swapAgainstPool` / `fillOrderFromPoolLiquidity` took a
  hypothesis on `getLiquidity`'s result. Under `PoolStateSlotSpec` that becomes a hypothesis on the
  PoolManager's `extsload` of `keccak256(poolId ‖ 6) + 3`.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.SpecCore

variable {σ : Type} (ext : Ext σ)

/-! ## `_createOrder` -/

/-- `tstore(slot, v)` in the model. -/
def tstoreW (slot v : Nat) : M σ Unit :=
  modify fun w => ext.set w (let s := ext.get w; { s with «transient» := upd s.«transient» slot v })

/-- Whether `hd.user` has authorised `hd.executor` on pool `pid`. -/
def authorised (w : σ) (pid : Nat) (hd : AsyncSwap.UserParams) : Prop :=
  ((ext.get w).asyncOrders pid).isExecutor hd.user hd.executor = true

/-- The first salt, `keccak256(abi.encode(block.timestamp, block.number, msg.sender, user, amountIn,
amountOutMin, priorityFee))`. -/
def salt0 (env : Env) (amountIn : Nat) (hd : AsyncSwap.UserParams) : Nat :=
  ext.keccak [env.timestamp, env.number, env.sender, hd.user, amountIn, hd.amountOutMin,
    hd.priorityFee]

/-- The salt after `k` steps of the collision walk (`salt = keccak256(abi.encode(salt))`). -/
def saltAt (env : Env) (amountIn : Nat) (hd : AsyncSwap.UserParams) : Nat → Nat
  | 0 => salt0 ext env amountIn hd
  | k + 1 => ext.keccak [saltAt env amountIn hd k]

/-- `keccak256(abi.encode(block.chainid, poolId, user, zeroForOne, salt))`, the preimage
`AsyncOrderLibrary.orderId` uses. -/
def idOf (env : Env) (pid : Nat) (zfo : Bool) (hd : AsyncSwap.UserParams) (salt : Nat) : Nat :=
  ext.keccak [env.chainid, pid, hd.user, ybool zfo, salt]

/-- The id after `k` steps of the walk. -/
def idAt (env : Env) (pid : Nat) (zfo : Bool) (amountIn : Nat) (hd : AsyncSwap.UserParams)
    (k : Nat) : Nat :=
  idOf ext env pid zfo hd (saltAt ext env amountIn hd k)

/-- The walk stops at step `k`: the `k`-th id's slot is free (`amountIn = 0`), and every earlier
one is taken. -/
def StopsAt (env : Env) (w : σ) (pid : Nat) (zfo : Bool) (amountIn : Nat)
    (hd : AsyncSwap.UserParams) (k : Nat) : Prop :=
  (((ext.get w).asyncOrders pid).orders (idAt ext env pid zfo amountIn hd k)).amountIn = 0 ∧
  ∀ j < k, (((ext.get w).asyncOrders pid).orders (idAt ext env pid zfo amountIn hd j)).amountIn ≠ 0

/-- The `NewOrder` handed to `addOrder`. -/
def newOrderOf (id amountIn : Nat) (hd : AsyncSwap.UserParams) (isBuy zfo : Bool) :
    AsyncFiller.NewOrder :=
  { id := id, owner := hd.user, amountIn := amountIn, amountOutMin := hd.amountOutMin,
    isBuy := isBuy, zeroForOne := zfo, priorityFee := hd.priorityFee }

/-- What `_createOrder` runs once the guards pass and the walk picked `id`:
`AsyncMatching.addOrder(asyncOrders[pid], priceBooks[pid], newOrder)`, then
`tstore(PENDING_MATCH_ID_SLOT, id)`, `tstore(PENDING_MATCH_EXECUTOR_SLOT, executor)`. -/
def createBody (pid : Nat) (zfo : Bool) (amountIn : Nat) (hd : AsyncSwap.UserParams) (isBuy : Bool)
    (id : Nat) : M σ Unit := do
  AsyncMatching.addOrder ext (AddOrder.selfGet ext pid) (AddOrder.selfSet ext pid)
    (AddOrder.bookGet ext pid) (AddOrder.bookSet ext pid) (newOrderOf id amountIn hd isBuy zfo)
  tstoreW ext AsyncSwap.PENDING_MATCH_ID_SLOT id
  tstoreW ext AsyncSwap.PENDING_MATCH_EXECUTOR_SLOT hd.executor

/-- **Named spec of `AsyncSwap._createOrder(poolId, zeroForOne, amountIn, hookData, isBuy)`.**
The guards run in source order. Then the call is exactly `createBody` with the id where the
collision walk stops. Nothing else is read or written. -/
structure CreateOrderSpec : Prop where
  /-- `isExecutor[user][executor]` unset reverts `AsyncFiller.NotAuthorizedExecutor()`. -/
  notAuthorised : ∀ pid zfo amountIn hd isBuy env w, ¬ authorised ext w pid hd →
    ext.fn_AsyncSwap_createOrder_1681 pid zfo amountIn hd isBuy env w
      = .error ⟨"NotAuthorizedExecutor"⟩
  /-- Authorised, with `amountIn = 0` or `amountOutMin = 0`: reverts `AsyncFiller.ZeroAmount()`. -/
  zeroAmount : ∀ pid zfo amountIn hd isBuy env w, authorised ext w pid hd →
    (amountIn = 0 ∨ hd.amountOutMin = 0) →
    ext.fn_AsyncSwap_createOrder_1681 pid zfo amountIn hd isBuy env w = .error ⟨"ZeroAmount"⟩
  /-- Past the guards, with the walk stopping at step `k`, the call is `createBody` for that id. -/
  run : ∀ pid zfo amountIn hd isBuy env w k, authorised ext w pid hd → amountIn ≠ 0 →
    hd.amountOutMin ≠ 0 → StopsAt ext env w pid zfo amountIn hd k →
    ext.fn_AsyncSwap_createOrder_1681 pid zfo amountIn hd isBuy env w
      = createBody ext pid zfo amountIn hd isBuy (idAt ext env pid zfo amountIn hd k) env w

/-- A walk stops at only one step. -/
theorem StopsAt.unique {env : Env} {w : σ} {pid : Nat} {zfo : Bool} {a : Nat}
    {hd : AsyncSwap.UserParams} {k k' : Nat} (h : StopsAt ext env w pid zfo a hd k)
    (h' : StopsAt ext env w pid zfo a hd k') : k = k' := by
  rcases Nat.lt_trichotomy k k' with hlt | heq | hgt
  · exact absurd h.1 (h'.2 k hlt)
  · exact heq
  · exact absurd h'.1 (h.2 k' hgt)

/-- The storage `createBody` and the transient writes leave alone: everything outside pool `pid`'s
order state and book. Transient storage changes only at the two hand-off slots. -/
def PoolFrame (pid : Nat) (s s' : AsyncSwap.State) : Prop :=
  s'.owner = s.owner ∧ s'.pendingOwner = s.pendingOwner ∧ s'.nonceUsed = s.nonceUsed ∧
  s'.«_nameFallback» = s.«_nameFallback» ∧ s'.«_versionFallback» = s.«_versionFallback» ∧
  (∀ q, q ≠ pid → s'.asyncOrders q = s.asyncOrders q ∧ s'.priceBooks q = s.priceBooks q) ∧
  (∀ t, t ≠ AsyncSwap.PENDING_MATCH_ID_SLOT → t ≠ AsyncSwap.PENDING_MATCH_EXECUTOR_SLOT →
    s'.«transient» t = s.«transient» t)

theorem PoolFrame.trans {pid : Nat} {a b c : AsyncSwap.State} (h1 : PoolFrame pid a b)
    (h2 : PoolFrame pid b c) : PoolFrame pid a c := by
  obtain ⟨o1, p1, n1, f1, v1, q1, t1⟩ := h1
  obtain ⟨o2, p2, n2, f2, v2, q2, t2⟩ := h2
  refine ⟨o2.trans o1, p2.trans p1, n2.trans n1, f2.trans f1, v2.trans v1, ?_, ?_⟩
  · intro q hq
    exact ⟨(q2 q hq).1.trans (q1 q hq).1, (q2 q hq).2.trans (q1 q hq).2⟩
  · intro t ht1 ht2
    exact (t2 t ht1 ht2).trans (t1 t ht1 ht2)

theorem PoolFrame.of_eq {pid : Nat} {a b : AsyncSwap.State} (h : b = a) : PoolFrame pid a b := by
  subst h; exact ⟨rfl, rfl, rfl, rfl, rfl, fun _ _ => ⟨rfl, rfl⟩, fun _ _ _ => rfl⟩

/-- `_append` on pool `pid`'s accessors changes nothing outside pool `pid`. This is an assumption
about the opaque `AsyncFiller._append` (`ext.fn_AsyncFiller_append_6737`), which another group's
spec covers; it is kept here as a named hypothesis. -/
def AppendPoolLocal : Prop :=
  ∀ pid id env (v : σ) u v', ext.fn_AsyncFiller_append_6737 (AddOrder.selfGet ext pid)
    (AddOrder.selfSet ext pid) (AddOrder.bookGet ext pid) (AddOrder.bookSet ext pid) id env v
      = .ok (u, v') →
    PoolFrame pid (ext.get v) (ext.get v') ∧ (ext.get v').«transient» = (ext.get v).«transient»

/-- **Footprint of `createBody`.** With a lawful `ext` and `_append` pool-local, a successful
`createBody` changes only pool `pid`'s order state and book, plus the two hand-off transient slots.
Those two slots then hold `id` and `executor`. -/
theorem createBody_frame (hget : ∀ w s, ext.get (ext.set w s) = s)
    (happend : AppendPoolLocal ext) (pid : Nat) (zfo : Bool) (a : Nat) (hd : AsyncSwap.UserParams)
    (b : Bool) (id : Nat) (env : Env) (w w' : σ)
    (h : createBody ext pid zfo a hd b id env w = .ok ((), w')) :
    PoolFrame pid (ext.get w) (ext.get w') ∧
    (ext.get w').«transient» AsyncSwap.PENDING_MATCH_ID_SLOT = id ∧
    (ext.get w').«transient» AsyncSwap.PENDING_MATCH_EXECUTOR_SLOT = hd.executor := by
  simp only [createBody, tstoreW, run_bind, run_modify] at h
  split at h
  · rename_i u w2 hadd
    obtain ⟨-, -, -, -, p, w1, -, -, -, hw1, hap⟩ :=
      AddOrder.matching_addOrder_ok ext hget pid _ env w w2 hadd
    obtain ⟨hf2, ht2⟩ := happend pid _ env w1 () w2 hap
    have hf1 : PoolFrame pid (ext.get w) (ext.get w1) := by
      rw [hw1]
      obtain ⟨o, p', n, t, f, v⟩ := AddOrder.addState_frame (ext.get w) pid _ _ _
      refine ⟨o, p', n, f, v, fun q hq => AddOrder.addState_other_pool _ _ _ _ _ q hq, ?_⟩
      intro s _ _; rw [t]
    have ht1 : (ext.get w1).«transient» = (ext.get w).«transient» := by
      rw [hw1]; exact (AddOrder.addState_frame (ext.get w) pid _ _ _).2.2.2.1
    cases h
    have hne : AsyncSwap.PENDING_MATCH_EXECUTOR_SLOT ≠ AsyncSwap.PENDING_MATCH_ID_SLOT := by
      unfold AsyncSwap.PENDING_MATCH_EXECUTOR_SLOT AsyncSwap.PENDING_MATCH_ID_SLOT; decide
    refine ⟨?_, ?_, ?_⟩
    · refine (hf1.trans hf2).trans ?_
      refine ⟨by simp [hget], by simp [hget], by simp [hget], by simp [hget], by simp [hget],
        fun q _ => ⟨by simp [hget], by simp [hget]⟩, ?_⟩
      intro t h1 h2
      simp [hget, upd, h1, h2]
    · simp [hget, upd, Ne.symm hne]
    · simp [hget, upd]
  · cases h

/-! ### `beforeSwap` under `CreateOrderSpec` -/

section BeforeSwap
open AsyncSwap.Swarm.BeforeSwap

/-- `beforeSwap`'s `_createOrder` arguments: pool id, side, escrowed amount, decoded hook data. -/
abbrev pidB (key : PoolKey) : Nat := BeforeSwap.poolId ext key

/-- `beforeSwap` with `_createOrder`'s executor guard failing on the post-`mint` world: reverts
`NotAuthorizedExecutor`. -/
theorem beforeSwap_notAuthorised_of_spec (hs : CreateOrderSpec ext) (sender : Nat) (key : PoolKey)
    (params : SwapParams) (hd : List Nat) (env : Env) (w w1 : σ)
    (hg : guards ext env sender params hd)
    (hm : ext.call_IPoolManager_mint ext.poolManager env.self (specified key params)
      (amountTaken params) env w = .ok ((), w1))
    (hx : ¬ authorised ext w1 (pidB ext key) (hdParams hd)) :
    BaseHook.beforeSwap ext sender key params hd env w = .error ⟨"NotAuthorizedExecutor"⟩ := by
  rw [beforeSwap_run_ok ext sender key params hd env w hg]
  simp only [tail, hm, hs.notAuthorised _ _ _ _ _ env w1 hx]

/-- `beforeSwap` with zero escrow or a zero `amountOutMin`, executor authorised: reverts `ZeroAmount`. -/
theorem beforeSwap_zeroAmount_of_spec (hs : CreateOrderSpec ext) (sender : Nat) (key : PoolKey)
    (params : SwapParams) (hd : List Nat) (env : Env) (w w1 : σ)
    (hg : guards ext env sender params hd)
    (hm : ext.call_IPoolManager_mint ext.poolManager env.self (specified key params)
      (amountTaken params) env w = .ok ((), w1))
    (hx : authorised ext w1 (pidB ext key) (hdParams hd))
    (hz : amountTaken params = 0 ∨ (hdParams hd).amountOutMin = 0) :
    BaseHook.beforeSwap ext sender key params hd env w = .error ⟨"ZeroAmount"⟩ := by
  rw [beforeSwap_run_ok ext sender key params hd env w hg]
  simp only [tail, hm, hs.zeroAmount _ _ _ _ _ env w1 hx hz]

/-- **`beforeSwap_run_ok` with `_createOrder` opened up.** Under the guards, after a successful
`mint`, with the executor authorised, nonzero amounts and the walk stopping at `k`, `beforeSwap`
does `createBody` for that id (addOrder, then the transient hand-off) and returns
`(0x575e24b4, delta, 0)`. -/
theorem beforeSwap_run_of_spec (hs : CreateOrderSpec ext) (sender : Nat) (key : PoolKey)
    (params : SwapParams) (hd : List Nat) (env : Env) (w w1 : σ) (k : Nat)
    (hg : guards ext env sender params hd)
    (hm : ext.call_IPoolManager_mint ext.poolManager env.self (specified key params)
      (amountTaken params) env w = .ok ((), w1))
    (hx : authorised ext w1 (pidB ext key) (hdParams hd))
    (ha : amountTaken params ≠ 0) (ho : (hdParams hd).amountOutMin ≠ 0)
    (hk : StopsAt ext env w1 (pidB ext key) params.zeroForOne (amountTaken params) (hdParams hd) k) :
    BaseHook.beforeSwap ext sender key params hd env w =
      match createBody ext (pidB ext key) params.zeroForOne (amountTaken params) (hdParams hd)
          (specified key params == ext.numeraire)
          (idAt ext env (pidB ext key) params.zeroForOne (amountTaken params) (hdParams hd) k)
          env w1 with
      | .error e => .error e
      | .ok (_, w2) => .ok ((0x575e24b4, delta params, 0), w2) := by
  rw [beforeSwap_run_ok ext sender key params hd env w hg]
  simp only [tail, hm, hs.run _ _ _ _ _ env w1 k hx ha ho hk]
  generalize createBody ext _ _ _ _ _ _ env w1 = r
  rcases r with _ | ⟨_, _⟩ <;> rfl

/-- **Corrected footprint of `beforeSwap`** (replaces `beforeSwap_frame`, whose `hcreate` the real
`_createOrder` violates). Suppose `ext` is lawful, `mint` leaves the hook's storage alone, and
`_append` is pool-local, and the collision walk stops (some id along it is free; only an infinite
chain of taken ids breaks this, and then the bytecode runs out of gas). Then a successful `beforeSwap` changes only pool `poolId`'s order state and
book, plus the two hand-off transient slots, which end up holding the new order's id (for some step
`k` of the walk) and `hookData.executor`. -/
theorem beforeSwap_frame_of_spec (hs : CreateOrderSpec ext)
    (hget : ∀ w s, ext.get (ext.set w s) = s) (happend : AppendPoolLocal ext)
    (sender : Nat) (key : PoolKey) (params : SwapParams) (hd : List Nat) (env : Env) (w : σ)
    (r : Nat × Int × Nat) (w' : σ)
    (hmint : ∀ a b c d (v : σ) u v', ext.call_IPoolManager_mint a b c d env v = .ok (u, v') →
      ext.get v' = ext.get v)
    (hwalk : ∃ k, StopsAt ext env w (pidB ext key) params.zeroForOne (amountTaken params)
      (hdParams hd) k)
    (h : BaseHook.beforeSwap ext sender key params hd env w = .ok (r, w')) :
    PoolFrame (pidB ext key) (ext.get w) (ext.get w') ∧
    (∃ w1 k, (ext.get w1) = (ext.get w) ∧
      StopsAt ext env w1 (pidB ext key) params.zeroForOne (amountTaken params) (hdParams hd) k ∧
      (ext.get w').«transient» AsyncSwap.PENDING_MATCH_ID_SLOT
        = idAt ext env (pidB ext key) params.zeroForOne (amountTaken params) (hdParams hd) k) ∧
    (ext.get w').«transient» AsyncSwap.PENDING_MATCH_EXECUTOR_SLOT = (hdParams hd).executor := by
  obtain ⟨hg, ht⟩ := beforeSwap_ok_inv ext sender key params hd env w r w' h
  simp only [tail] at ht
  split at ht
  · cases ht
  · rename_i u w1 hm
    have hw1 := hmint _ _ _ _ _ _ _ hm
    split at ht
    · cases ht
    · rename_i u2 w2 hc
      cases ht
      -- the guards of `_createOrder` passed
      have hx : authorised ext w1 (pidB ext key) (hdParams hd) := by
        by_contra hx
        rw [hs.notAuthorised _ _ _ _ _ env w1 hx] at hc; cases hc
      have hz : ¬ (amountTaken params = 0 ∨ (hdParams hd).amountOutMin = 0) := by
        intro hz
        rw [hs.zeroAmount _ _ _ _ _ env w1 hx hz] at hc; cases hc
      have ha : amountTaken params ≠ 0 := fun e => hz (Or.inl e)
      have ho : (hdParams hd).amountOutMin ≠ 0 := fun e => hz (Or.inr e)
      have hk : ∃ k, StopsAt ext env w1 (pidB ext key) params.zeroForOne (amountTaken params)
          (hdParams hd) k := by
        obtain ⟨k, hk⟩ := hwalk
        exact ⟨k, by simpa only [StopsAt, hw1] using hk⟩
      obtain ⟨k, hk⟩ := hk
      rw [hs.run _ _ _ _ _ env w1 k hx ha ho hk] at hc
      obtain ⟨hf, hid, hex⟩ := createBody_frame ext hget happend _ _ _ _ _ _ env w1 _ hc
      refine ⟨?_, ⟨w1, k, hw1, hk, hid⟩, hex⟩
      exact (PoolFrame.of_eq hw1).trans hf

end BeforeSwap

/-! ## `CurrencyLibrary.transfer` -/

/-- `CurrencyLibrary.NativeTransferFailed.selector`. -/
def NATIVE_TRANSFER_FAILED : Nat := 0xf4b3b1bc
/-- `CurrencyLibrary.ERC20TransferFailed.selector`. -/
def ERC20_TRANSFER_FAILED : Nat := 0xf27f64e4
/-- `IERC20Minimal.transfer.selector`. -/
def TRANSFER_SELECTOR : Nat := 0xa9059cbb

/-- The calldata `CurrencyLibrary.transfer` builds: `transfer(address,uint256)`'s selector, then `dst`
masked to 160 bits, then `amount`. -/
def transferCalldata (dst amount : Nat) : List Nat :=
  (wordBytes (TRANSFER_SELECTOR * 2 ^ 224)).take 4 ++ abiEncode [dst % 2 ^ 160, amount]

/-- The ERC-20 return-data check: no return data, or at least 32 bytes whose first word is exactly 1. -/
def okReturn (rd : List Nat) : Bool :=
  rd.length == 0 || (decide (32 ≤ rd.length) && bytesWord (rd.take 32) == 1)

/-- **Named spec of v4-core `CurrencyLibrary.transfer(currency, dst, amount)`.** -/
structure TransferSpec : Prop where
  /-- Native (`currency = 0`): one call to `dst` with value `amount` and empty calldata. On failure it
  reverts through `bubbleUpAndRevertWith(dst, 0, NativeTransferFailed)`. On success the world is
  the one the call left. -/
  native : ∀ dst amount env w,
    ext.fn_CurrencyLibrary_transfer_4290 CurrencyLibrary.ADDRESS_ZERO dst amount env w =
      match ext.lowCall dst amount [] env w with
      | .error e => .error e
      | .ok ((ok, _), w1) =>
        if ok then .ok ((), w1)
        else CustomRevert.bubbleUpAndRevertWith ext dst 0 NATIVE_TRANSFER_FAILED env w1
  /-- ERC-20 (`currency ≠ 0`): one call to `currency` with value 0 and `transferCalldata dst amount`.
  It succeeds iff the call succeeded and `okReturn` holds; otherwise it reverts through
  `bubbleUpAndRevertWith(currency, transfer.selector, ERC20TransferFailed)`. On success the world
  is the one the call left. -/
  erc20 : ∀ currency dst amount env w, currency ≠ CurrencyLibrary.ADDRESS_ZERO →
    ext.fn_CurrencyLibrary_transfer_4290 currency dst amount env w =
      match ext.lowCall currency 0 (transferCalldata dst amount) env w with
      | .error e => .error e
      | .ok ((ok, rd), w1) =>
        if ok && okReturn rd then .ok ((), w1)
        else CustomRevert.bubbleUpAndRevertWith ext currency TRANSFER_SELECTOR ERC20_TRANSFER_FAILED
          env w1

theorem bubbleUp_error (a b c : Nat) (env : Env) (w : σ) :
    CustomRevert.bubbleUpAndRevertWith ext a b c env w = .error ⟨"revert"⟩ := by
  simp [CustomRevert.bubbleUpAndRevertWith]

/-- **When `transfer` succeeds.** It succeeds in world `w'` iff its one call succeeded into `w'`.
For an ERC-20 the call's return data must also pass `okReturn`. -/
theorem TransferSpec.ok_iff (hs : TransferSpec ext) (currency dst amount : Nat) (env : Env)
    (w w' : σ) :
    ext.fn_CurrencyLibrary_transfer_4290 currency dst amount env w = .ok ((), w') ↔
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
    · cases ok <;> cases hr : okReturn rd <;> simp [bubbleUp_error, hc, hr]

/-- **Footprint.** `transfer` writes no storage of its own. If its low-level call leaves this
contract's storage alone, so does a successful `transfer`. -/
theorem TransferSpec.frame (hs : TransferSpec ext) (env : Env)
    (hcall : ∀ a v d (v0 : σ) r v', ext.lowCall a v d env v0 = .ok (r, v') → ext.get v' = ext.get v0)
    (currency dst amount : Nat) (w w' : σ)
    (h : ext.fn_CurrencyLibrary_transfer_4290 currency dst amount env w = .ok ((), w')) :
    ext.get w' = ext.get w := by
  rcases (hs.ok_iff ext currency dst amount env w w').1 h with ⟨-, rd, hc⟩ | ⟨-, rd, hc, -⟩
  · exact hcall _ _ _ _ _ _ hc
  · exact hcall _ _ _ _ _ _ hc

/-- `sweep_storage_unchanged` with `htransfer` derived from `TransferSpec` (`TransferSpec.frame`). -/
theorem sweep_storage_unchanged_of_spec (hs : TransferSpec ext) (currency dst : Nat) (env : Env)
    (w w' : σ) (u : Unit)
    (hcall : ∀ a v d (v0 : σ) r v', ext.lowCall a v d env v0 = .ok (r, v') → ext.get v' = ext.get v0)
    (hok : AsyncSwap.sweep ext currency dst env w = .ok (u, w')) :
    ext.get w' = ext.get w :=
  AsyncSwap.Swarm.sweep_storage_unchanged ext currency dst env w w' u
    (fun amount v v' ht => hs.frame ext env hcall currency dst amount v v' ht) hok

/-! ## `StateLibrary._getPoolStateSlot` -/

/-- `StateLibrary.POOLS_SLOT`: the PoolManager's `pools` mapping is at storage slot 6. -/
def POOLS_SLOT : Nat := 6

/-- **Named spec of v4-core `StateLibrary._getPoolStateSlot(poolId)`.** -/
structure PoolStateSlotSpec : Prop where
  /-- Pure: it never reverts and leaves the world unchanged. -/
  pure_ok : ∀ pid env (w : σ), ∃ v, ext.fn_StateLibrary_getPoolStateSlot_12612 pid env w = .ok (v, w)
  /-- It returns `keccak256(abi.encodePacked(poolId, POOLS_SLOT))`. -/
  value : ∀ pid env (w : σ) v w', ext.fn_StateLibrary_getPoolStateSlot_12612 pid env w = .ok (v, w') →
    v = ext.keccak [pid, POOLS_SLOT]

theorem PoolStateSlotSpec.eq (hs : PoolStateSlotSpec ext) (pid : Nat) (env : Env) (w : σ) :
    ext.fn_StateLibrary_getPoolStateSlot_12612 pid env w = .ok (ext.keccak [pid, POOLS_SLOT], w) := by
  obtain ⟨v, hv⟩ := hs.pure_ok pid env w
  rw [hv, hs.value pid env w v w hv]

/-- **`getLiquidity` under the spec.** It reads `extsload(keccak256(poolId ‖ 6) + 3)` (checked add)
and returns the low 128 bits, without changing the world. -/
theorem getLiquidity_of_spec (hs : PoolStateSlotSpec ext) (manager pid : Nat) (env : Env) (w : σ) :
    StateLibrary.getLiquidity ext manager pid env w =
      if ext.keccak [pid, POOLS_SLOT] + StateLibrary.LIQUIDITY_OFFSET < 2 ^ 256 then
        match ext.view_IExtsload_extsload env w manager
            (ext.keccak [pid, POOLS_SLOT] + StateLibrary.LIQUIDITY_OFFSET) with
        | .ok v => .ok (v % 2 ^ 128, w)
        | .error e => .error e
      else .error (panic "0x11") := by
  unfold StateLibrary.getLiquidity
  by_cases hc : ext.keccak [pid, POOLS_SLOT] + StateLibrary.LIQUIDITY_OFFSET < 2 ^ 256
  · simp only [run_bind, hs.eq ext pid env w, addc, hc, ite_true, run_pure, view, run_read, run_get]
    cases ext.view_IExtsload_extsload env w manager
      (ext.keccak [pid, POOLS_SLOT] + StateLibrary.LIQUIDITY_OFFSET) <;> rfl
  · simp only [Nat.reducePow] at hc
    simp [hs.eq ext pid env w, addc, hc]

/-- The slot0 fields `getSlot0` decodes from the packed word. -/
def slot0Of (data : Nat) : Nat × Int × Nat × Nat :=
  ((yand data 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) % 2 ^ 160,
   toSigned 24 (ysignextend 2 (yshr 160 data)),
   (yand (yshr 184 data) 0xFFFFFF) % 2 ^ 24,
   (yand (yshr 208 data) 0xFFFFFF) % 2 ^ 24)

/-- **`getSlot0` under the spec.** It reads `extsload(keccak256(poolId ‖ 6))` and decodes it,
without changing the world. -/
theorem getSlot0_of_spec (hs : PoolStateSlotSpec ext) (manager pid : Nat) (env : Env) (w : σ) :
    StateLibrary.getSlot0 ext manager pid env w =
      match ext.view_IExtsload_extsload env w manager (ext.keccak [pid, POOLS_SLOT]) with
      | .ok data => .ok (slot0Of data, w)
      | .error e => .error e := by
  unfold StateLibrary.getSlot0
  simp only [run_bind, hs.eq ext pid env w, view, run_read, run_get]
  cases ext.view_IExtsload_extsload env w manager (ext.keccak [pid, POOLS_SLOT]) <;> rfl

section Liquidity
open AsyncSwap.Swarm.FillOrderFromPoolLiquidity

/-- `getLiquidity` reads 0 when the slot add doesn't overflow and the low 128 bits of
`extsload(slot + 3)` are 0. -/
theorem getLiquidity_zero_of_spec (hs : PoolStateSlotSpec ext) (manager pid : Nat) (env : Env)
    (w : σ) (v : Nat)
    (hslot : ext.keccak [pid, POOLS_SLOT] + StateLibrary.LIQUIDITY_OFFSET < 2 ^ 256)
    (hv : ext.view_IExtsload_extsload env w manager
      (ext.keccak [pid, POOLS_SLOT] + StateLibrary.LIQUIDITY_OFFSET) = .ok v)
    (h0 : v % 2 ^ 128 = 0) :
    StateLibrary.getLiquidity ext manager pid env w = .ok (0, w) := by
  simp only [Nat.reducePow] at hslot h0
  rw [getLiquidity_of_spec ext hs]; simp [hslot, hv, h0]

/-- `swapAgainstPool_noLiquidity` with the `getLiquidity` hypothesis replaced by the PoolManager's
storage under `PoolStateSlotSpec`. -/
theorem swapAgainstPool_noLiquidity_of_spec (hs : PoolStateSlotSpec ext) (manager : Nat)
    (key : PoolKey) (zfo : Bool) (amtIn amtOutMin hook : Nat) (env : Env) (w : σ) (v : Nat)
    (hslot : ext.keccak [pidOf ext key, POOLS_SLOT] + StateLibrary.LIQUIDITY_OFFSET < 2 ^ 256)
    (hv : ext.view_IExtsload_extsload env w manager
      (ext.keccak [pidOf ext key, POOLS_SLOT] + StateLibrary.LIQUIDITY_OFFSET) = .ok v)
    (h0 : v % 2 ^ 128 = 0) :
    AsyncMatching.«_swapAgainstPool» ext manager key zfo amtIn amtOutMin hook env w
      = .error ⟨"NoActiveLiquidity"⟩ :=
  AsyncSwap.Swarm.SwapAgainstPool.swapAgainstPool_noLiquidity ext manager key zfo amtIn amtOutMin
    hook env w w (getLiquidity_zero_of_spec ext hs _ _ env w v hslot hv h0)

/-- `fillOrderFromPoolLiquidity_noLiquidity` with the `getLiquidity` hypothesis replaced by the
PoolManager's storage under `PoolStateSlotSpec`. -/
theorem fillOrderFromPoolLiquidity_noLiquidity_of_spec (hs : PoolStateSlotSpec ext)
    (order : AsyncOrder) (id : Nat) (env : Env) (w : σ) (v : Nat)
    (hsend : env.sender = env.self)
    (h0 : (((ext.get w).asyncOrders (pidOf ext order.key)).orders id).amountIn ≠ 0)
    (hslot : ext.keccak [pidOf ext order.key, POOLS_SLOT] + StateLibrary.LIQUIDITY_OFFSET < 2 ^ 256)
    (hv : ext.view_IExtsload_extsload env w ((ext.get w).asyncOrders (pidOf ext order.key)).poolManager
      (ext.keccak [pidOf ext order.key, POOLS_SLOT] + StateLibrary.LIQUIDITY_OFFSET) = .ok v)
    (hz : v % 2 ^ 128 = 0) :
    AsyncSwap.fillOrderFromPoolLiquidity ext order id env w = .error ⟨"NoActiveLiquidity"⟩ :=
  fillOrderFromPoolLiquidity_noLiquidity ext order id env w w hsend h0
    (getLiquidity_zero_of_spec ext hs _ _ env w v hslot hv hz)

/-- `swapAgainstPool_spec` with the `getLiquidity` and `getSlot0` hypotheses replaced by the
PoolManager's storage under `PoolStateSlotSpec`. The liquidity read leaves `w` unchanged
(`w0 = w`) and returns the low 128 bits of `extsload(slot + 3)`. The slot0 read leaves `w1`
unchanged and decodes `extsload(slot)`. -/
theorem swapAgainstPool_spec_of_spec (hs : PoolStateSlotSpec ext) (manager : Nat) (key : PoolKey)
    (zfo : Bool) (amtIn amtOutMin hook : Nat) (env : Env) (w w1 w3 w4 w' : σ) (vL data : Nat)
    (delta : Int)
    (hslot : ext.keccak [pidOf ext key, POOLS_SLOT] + StateLibrary.LIQUIDITY_OFFSET < 2 ^ 256)
    (hvL : ext.view_IExtsload_extsload env w manager
      (ext.keccak [pidOf ext key, POOLS_SLOT] + StateLibrary.LIQUIDITY_OFFSET) = .ok vL)
    (hL0 : vL % 2 ^ 128 ≠ 0)
    (hb : ext.call_IPoolManager_burn manager hook (if zfo then key.currency0 else key.currency1) amtIn
      env w = .ok ((), w1))
    (hvs : ext.view_IExtsload_extsload env w1 manager (ext.keccak [pidOf ext key, POOLS_SLOT])
      = .ok data)
    (hf : ext.call_IPoolManager_updateDynamicLPFee manager key 3000 env w1 = .ok ((), w3))
    (hsw : ext.call_IPoolManager_swap manager key
        { zeroForOne := zfo, amountSpecified := -(amtIn : Int),
          sqrtPriceLimitX96 := if zfo then TickMath.MIN_SQRT_PRICE + 1 else TickMath.MAX_SQRT_PRICE - 1 }
        [] env w3 = .ok (delta, w4))
    (hr : ext.call_IPoolManager_updateDynamicLPFee manager key (slot0Of data).2.2.2 env w4 = .ok ((), w'))
    (h127 : amtIn < 2 ^ 127) :
    AsyncMatching.«_swapAgainstPool» ext manager key zfo amtIn amtOutMin hook env w =
      if (if zfo then amount0 delta else amount1 delta) ≠ -(amtIn : Int) then
        .error ⟨"PartialLiquidityFill"⟩
      else if (if zfo then amount1 delta else amount0 delta) ≤ 0 ∨
          toUnsigned 128 (if zfo then amount1 delta else amount0 delta) < amtOutMin then
        .error ⟨"LimitPriceNotMet"⟩
      else .ok (toUnsigned 128 (if zfo then amount1 delta else amount0 delta), w') := by
  have hL : StateLibrary.getLiquidity ext manager (pidOf ext key) env w = .ok (vL % 2 ^ 128, w) := by
    simp only [Nat.reducePow] at hslot
    rw [getLiquidity_of_spec ext hs]; simp [hslot, hvL]
  have hs0 : StateLibrary.getSlot0 ext manager (pidOf ext key) env w1 = .ok (slot0Of data, w1) := by
    rw [getSlot0_of_spec ext hs, hvs]
  exact AsyncSwap.Swarm.SwapAgainstPool.swapAgainstPool_spec ext manager key zfo amtIn amtOutMin hook
    env w w w1 w1 w3 w4 w' _ _ delta hL hL0 hb hs0 hf hsw hr h127

end Liquidity

end AsyncSwap.Swarm.SpecCore
