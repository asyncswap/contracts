import Generated.AsyncSwap
import Refinement.Monad

/-!
# `AsyncSwap.executeOrder`

`function executeOrder(AsyncOrder calldata order, bytes calldata data) external`
(src/AsyncSwap.sol:325), through `AsyncMatching.fill` → `AsyncFiller.fill`.

With `filler = abi.decode(data, (address))`, `pid = order.key.toId()`,
`id = keccak(chainid, pid, owner, zeroForOne, salt)`, `output`/`input` the order's output/input
currency, and `pf(a) = (a / 997) * 3 + ((a % 997) * 3) / 997` (`calculatePoolFee`):

1. reverts `abi.decode` when `data` is shorter than a word or its first word is not an address;
2. native output (`output = 0`): reads `pending = tload(PENDING_NATIVE_DEPOSIT_SLOT)` and
   `(, m) = this.asyncOrderInfo(pid, id)` (a static self-call: a revert there is propagated);
   panics `0x11` when `m + pf(m)` overflows; reverts `UnaccountedNativeOutput` when
   `pending < m + pf(m)`; otherwise `tstore(PENDING_NATIVE_DEPOSIT_SLOT, pending - (m + pf(m)))`,
   the only write of this step (`tstoreWorld_frame`);
3. then, in the world step 2 left (`w1`), with `S = asyncOrders[pid]`, `info = S.orders[id]`:
   panics when `pf(info.amountOutMin)` overflows (impossible for a word, `pf_le`); reverts
   `NotAuthorizedExecutor` unless `S.isExecutor[order.owner][msg.sender]`; reverts `OrderNotFound`
   when `info.amountIn = 0`;
4. otherwise runs `fillTail` with `hook = address(this)`, the decoded `filler`,
   `feeVault = feeVault` (immutable), `fee = pf(info.amountOutMin)` and the *stored* `amountIn` /
   `amountOutMin`: `_remove` on `asyncOrders[pid]`/`priceBooks[pid]` (opaque: its `PriceLevelMissing`
   guard and the `orderCount`/`openOrderCount` decrements live there); for native output
   `settle{value: amountOutMin + fee}` (checked add); `mint` (native) / `take` (ERC20) of
   `amountOutMin` output to `order.owner`; if `fee ≠ 0`, `mint` of `fee` output claims to `feeVault`;
   `burn(address(this), input, amountIn)`; `mint`/`take` of `amountIn` input to `filler`;
   `settleOrderPriorityFee`; `orders[id] := default`.

Storage written: `transient[PENDING_NATIVE_DEPOSIT_SLOT]` (step 2), `asyncOrders[pid]` and
`priceBooks[pid]` (through `_remove`, the priority-fee settlement and the final delete), and
whatever the external calls do.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.ExecuteOrder

variable {σ : Type} (ext : Ext σ)

/-- `PoolIdLibrary.toId key` in the model. -/
def poolId (key : PoolKey) : Nat :=
  ext.keccak [key.currency0, key.currency1, key.fee, toUnsigned 256 key.tickSpacing, key.hooks]

/-- `AsyncOrderLibrary.orderId order` in the model. -/
def orderId (env : Env) (order : AsyncOrder) : Nat :=
  ext.keccak [env.chainid, poolId ext order.key, order.owner, ybool order.zeroForOne, order.salt]

def inputOf (order : AsyncOrder) : Nat :=
  if order.zeroForOne then order.key.currency0 else order.key.currency1
def outputOf (order : AsyncOrder) : Nat :=
  if order.zeroForOne then order.key.currency1 else order.key.currency0

/-- `calculatePoolFee(amount)` as written. -/
def pf (a : Nat) : Nat := a / 997 * 3 + a % 997 * 3 / 997

/-- The first ABI word of `data` (the `filler` address once it passes the decode check). -/
def fillerWord (data : List Nat) : Nat := bytesWord (data.take 32)

/-- The per-tx native deposit ledger, `tload(PENDING_NATIVE_DEPOSIT_SLOT)`. -/
def pending (w : σ) : Nat := (ext.get w).transient AsyncSwap.PENDING_NATIVE_DEPOSIT_SLOT

def selfGet (pid : Nat) : M σ AsyncFiller.State_ := do return ((ext.get (← get)).asyncOrders pid)
def selfSet (pid : Nat) : AsyncFiller.State_ → M σ Unit := fun x =>
  modify fun w => ext.set w (let s := ext.get w; { s with asyncOrders := upd (s.asyncOrders) pid x })
def bookGet (pid : Nat) : M σ AsyncFiller.Book := do return ((ext.get (← get)).priceBooks pid)
def bookSet (pid : Nat) : AsyncFiller.Book → M σ Unit := fun x =>
  modify fun w => ext.set w (let s := ext.get w; { s with priceBooks := upd (s.priceBooks) pid x })

theorem selfGet_run (pid : Nat) (env : Env) (w : σ) :
    selfGet ext pid env w = .ok ((ext.get w).asyncOrders pid, w) := rfl

/-- The world after `tstore(PENDING_NATIVE_DEPOSIT_SLOT, v)`. -/
def tstoreWorld (w : σ) (v : Nat) : σ :=
  ext.set w (let s := ext.get w;
    { s with «transient» := upd s.«transient» AsyncSwap.PENDING_NATIVE_DEPOSIT_SLOT v })

/-- Steps 3–4 (after the native-ledger step): the fee on the stored `amountOutMin`, then
`AsyncFiller.fill` with `hook = address(this)`, `executor = msg.sender`, `filler`,
`feeVault = feeVault` and that fee. -/
def afterNative (order : AsyncOrder) (filler : Nat) : M σ Unit := do
  let env ← read
  let w ← get
  let fee ← AsyncSwap.calculatePoolFee ext order.key.fee
    (((ext.get w).asyncOrders (poolId ext order.key)).orders (orderId ext env order)).amountOutMin
  AsyncFiller.fill ext (selfGet ext (poolId ext order.key)) (selfSet ext (poolId ext order.key))
    (bookGet ext (poolId ext order.key)) (bookSet ext (poolId ext order.key)) order
    (orderId ext env order) env.self env.sender filler ext.feeVault fee

/-- Everything `AsyncFiller.fill` does once both of its guards pass. -/
def fillTail (order : AsyncOrder) (pid id hook filler feeVault fee amountIn amountOutMin : Nat) :
    M σ Unit := do
  ext.fn_AsyncFiller_remove_6902 (selfGet ext pid) (selfSet ext pid) (bookGet ext pid) (bookSet ext pid) id
  if outputOf order = 0 then
    let s ← selfGet ext pid
    let g ← addc 256 amountOutMin fee
    let _ ← ext.callV_IPoolManager_settle s.poolManager g
  let s ← selfGet ext pid
  if outputOf order = 0 then
    ext.call_IPoolManager_mint s.poolManager order.owner (outputOf order) amountOutMin
  else
    ext.call_IPoolManager_take s.poolManager (outputOf order) order.owner amountOutMin
  if fee ≠ 0 then
    let s ← selfGet ext pid
    ext.call_IPoolManager_mint s.poolManager feeVault (outputOf order) fee
  let s ← selfGet ext pid
  ext.call_IPoolManager_burn s.poolManager hook (inputOf order) amountIn
  let s ← selfGet ext pid
  if inputOf order = 0 then
    ext.call_IPoolManager_mint s.poolManager filler (inputOf order) amountIn
  else
    ext.call_IPoolManager_take s.poolManager (inputOf order) filler amountIn
  AsyncFiller.settleOrderPriorityFee ext (selfGet ext pid) (selfSet ext pid) order.key id hook
  let s ← selfGet ext pid
  selfSet ext pid { s with orders := upd s.orders id default }

/-! ### `calculatePoolFee` -/

theorem pf_le (a : Nat) : pf a ≤ a := by unfold pf; omega

theorem calculatePoolFee_run (f a : Nat) (env : Env) (w : σ) :
    AsyncSwap.calculatePoolFee ext f a env w =
      if pf a < 2 ^ 256 then .ok (pf a, w) else .error (panic "0x11") := by
  unfold pf
  simp only [AsyncSwap.calculatePoolFee, divc, modc, mulc, addc, run_bind, run_ite, run_pure, run_throw]
  have h2 : a % 997 * 3 < 2 ^ 256 := by omega
  by_cases h : a / 997 * 3 + a % 997 * 3 / 997 < 2 ^ 256
  · have h1 : a / 997 * 3 < 2 ^ 256 := by omega
    simp [h, h1, h2]
  · by_cases h1 : a / 997 * 3 < 2 ^ 256 <;> simp [h, h1, h2]

/-! ### `AsyncFiller.fill` (as `executeOrder` calls it) -/

theorem fill_run (order : AsyncOrder) (pid id hook executor filler feeVault fee : Nat) (env : Env)
    (w : σ) :
    AsyncFiller.fill ext (selfGet ext pid) (selfSet ext pid) (bookGet ext pid) (bookSet ext pid)
        order id hook executor filler feeVault fee env w =
      let S := (ext.get w).asyncOrders pid
      let info := S.orders id
      if S.isExecutor order.owner executor = false then .error ⟨"NotAuthorizedExecutor"⟩
      else if info.amountIn = 0 then .error ⟨"OrderNotFound"⟩
      else fillTail ext order pid id hook filler feeVault fee info.amountIn info.amountOutMin env w := by
  unfold fillTail
  simp only [AsyncFiller.fill, CurrencySettler.settle, CurrencySettler.take,
      CurrencyLibrary.toId, CurrencyLibrary.isAddressZero, CurrencyLibrary.ADDRESS_ZERO]
  by_cases ho : outputOf order = 0 <;> by_cases hi : inputOf order = 0 <;> by_cases hf : fee = 0 <;>
  · simp only [outputOf] at ho
    simp only [inputOf] at hi
    simp only [ho, hi, hf, outputOf, inputOf, beq_self_eq_true, ite_true, ite_false, bne_iff_ne, ne_eq,
      not_true, not_false_eq_true, beq_iff_eq, Bool.false_eq_true,
      bind_pure_unit, bind_assoc, pure_bind]
    simp only [selfGet_run, run_bind, run_throw, run_ite]
    by_cases h1 : ((ext.get w).asyncOrders pid).isExecutor order.owner executor <;>
    by_cases h2 : (((ext.get w).asyncOrders pid).orders id).amountIn = 0 <;>
    simp only [h1, h2, Bool.not_true, Bool.not_false, Bool.false_eq_true, Bool.true_eq_false, ite_true,
      ite_false]

/-- Steps 3–4: fee overflow, then the two `fill` guards, then `fillTail`. -/
theorem afterNative_run (order : AsyncOrder) (filler : Nat) (env : Env) (w : σ) :
    afterNative ext order filler env w =
      let pid := poolId ext order.key
      let id := orderId ext env order
      let S := (ext.get w).asyncOrders pid
      let info := S.orders id
      if 2 ^ 256 ≤ pf info.amountOutMin then .error (panic "0x11")
      else if S.isExecutor order.owner env.sender = false then .error ⟨"NotAuthorizedExecutor"⟩
      else if info.amountIn = 0 then .error ⟨"OrderNotFound"⟩
      else fillTail ext order pid id env.self filler ext.feeVault (pf info.amountOutMin)
        info.amountIn info.amountOutMin env w := by
  simp only [afterNative, run_bind, run_read, run_get, calculatePoolFee_run]
  by_cases hp : pf (((ext.get w).asyncOrders (poolId ext order.key)).orders
      (orderId ext env order)).amountOutMin < 2 ^ 256
  · have : ¬ 2 ^ 256 ≤ pf (((ext.get w).asyncOrders (poolId ext order.key)).orders
        (orderId ext env order)).amountOutMin := by omega
    simp only [hp, this, ite_true, ite_false]
    rw [fill_run]
  · have : 2 ^ 256 ≤ pf (((ext.get w).asyncOrders (poolId ext order.key)).orders
        (orderId ext env order)).amountOutMin := by omega
    simp only [hp, this, ite_true, ite_false]

/-! ### `AsyncSwap.executeOrder` -/

/-- **Full characterization** of `AsyncSwap.executeOrder`: decode guard, the native-ledger step
(view, overflow, `UnaccountedNativeOutput`, `tstore`), then `afterNative`. -/
theorem executeOrder_run (order : AsyncOrder) (data : List Nat) (env : Env) (w : σ) :
    AsyncSwap.executeOrder ext order data env w =
      if data.length < 32 ∨ 2 ^ 160 ≤ fillerWord data then .error ⟨"abi.decode"⟩
      else if outputOf order = 0 then
        match ext.view_AsyncSwap_asyncOrderInfo env w env.self (poolId ext order.key)
            (orderId ext env order) with
        | .error e => .error e
        | .ok (_, m) =>
          if 2 ^ 256 ≤ m + pf m then .error (panic "0x11")
          else if pending ext w < m + pf m then .error ⟨"UnaccountedNativeOutput"⟩
          else afterNative ext order (fillerWord data) env
            (tstoreWorld ext w (ysub (pending ext w) (m + pf m)))
      else afterNative ext order (fillerWord data) env w := by
  unfold afterNative orderId poolId outputOf fillerWord pending tstoreWorld selfGet selfSet bookGet bookSet
  simp only [AsyncSwap.executeOrder, AsyncMatching.fill, AsyncOrderLibrary.orderId, PoolIdLibrary.toId,
    CurrencyLibrary.isAddressZero, CurrencyLibrary.ADDRESS_ZERO, abiWordAt, abiUint, view, addc,
    bind_pure_unit, bind_assoc, pure_bind]
  simp only [run_bind, run_pure, run_read, run_get, run_modify, run_throw, run_ite, List.drop_zero,
    Nat.zero_add]
  generalize ext.keccak [order.key.currency0, order.key.currency1, order.key.fee,
    toUnsigned 256 order.key.tickSpacing, order.key.hooks] = pid
  generalize ext.keccak [env.chainid, pid, order.owner, ybool order.zeroForOne, order.salt] = oid
  by_cases hl : data.length < 32
  · have : ¬ 32 ≤ data.length := by omega
    simp [hl, this]
  have hl' : 32 ≤ data.length := by omega
  by_cases hw : 2 ^ 160 ≤ bytesWord (List.take 32 data)
  · have : ¬ bytesWord (List.take 32 data) < 2 ^ 160 := by omega
    simp [hl', hw, this]
  have hw' : bytesWord (List.take 32 data) < 2 ^ 160 := by omega
  simp only [hl', hw', hl, hw, or_self, ite_true, ite_false, beq_iff_eq]
  by_cases ho : (if order.zeroForOne = true then order.key.currency1 else order.key.currency0) = 0
  · simp only [ho, ite_true]
    rcases hv : ext.view_AsyncSwap_asyncOrderInfo env w env.self pid oid with e | ⟨x, m⟩
    · rfl
    · simp only [run_pure, calculatePoolFee_run ext order.key.fee m, pf]
      by_cases hp : m / 997 * 3 + m % 997 * 3 / 997 < 2 ^ 256
      · by_cases hs : m + (m / 997 * 3 + m % 997 * 3 / 997) < 2 ^ 256
        · have : ¬ 2 ^ 256 ≤ m + (m / 997 * 3 + m % 997 * 3 / 997) := by omega
          simp only [hp, hs, this, ite_true, ite_false, decide_eq_true_eq]
          by_cases hq : (ext.get w).transient AsyncSwap.PENDING_NATIVE_DEPOSIT_SLOT <
              m + (m / 997 * 3 + m % 997 * 3 / 997) <;> simp only [hq, ite_true, ite_false]
        · have : 2 ^ 256 ≤ m + (m / 997 * 3 + m % 997 * 3 / 997) := by omega
          simp [hp, hs, this]
      · have : 2 ^ 256 ≤ m + (m / 997 * 3 + m % 997 * 3 / 997) := by omega
        simp [hp, this]
  · simp only [ho, ite_false]

/-- **Guard (decode).** `data` too short, or a first word that is not an address, reverts. -/
theorem executeOrder_decode (order : AsyncOrder) (data : List Nat) (env : Env) (w : σ)
    (h : data.length < 32 ∨ 2 ^ 160 ≤ fillerWord data) :
    AsyncSwap.executeOrder ext order data env w = .error ⟨"abi.decode"⟩ := by
  rw [executeOrder_run, if_pos h]

/-- **Guard (native ledger).** For native output, if the same-tx deposit ledger holds less than the
order's `amountOutMin + pf(amountOutMin)` (read via `asyncOrderInfo`), it reverts
`UnaccountedNativeOutput`. -/
theorem executeOrder_unaccountedNative (order : AsyncOrder) (data : List Nat) (env : Env) (w : σ)
    (hd : ¬ (data.length < 32 ∨ 2 ^ 160 ≤ fillerWord data)) (ho : outputOf order = 0) (x m : Nat)
    (hv : ext.view_AsyncSwap_asyncOrderInfo env w env.self (poolId ext order.key)
      (orderId ext env order) = .ok (x, m))
    (hs : m + pf m < 2 ^ 256) (hp : pending ext w < m + pf m) :
    AsyncSwap.executeOrder ext order data env w = .error ⟨"UnaccountedNativeOutput"⟩ := by
  have : ¬ 2 ^ 256 ≤ m + pf m := by omega
  rw [executeOrder_run, if_neg hd, if_pos ho, hv]
  simp only [this, hp, ite_true, ite_false]

/-- **Guard (native overflow).** `amountOutMin + pf(amountOutMin)` overflowing panics. -/
theorem executeOrder_nativeOverflow (order : AsyncOrder) (data : List Nat) (env : Env) (w : σ)
    (hd : ¬ (data.length < 32 ∨ 2 ^ 160 ≤ fillerWord data)) (ho : outputOf order = 0) (x m : Nat)
    (hv : ext.view_AsyncSwap_asyncOrderInfo env w env.self (poolId ext order.key)
      (orderId ext env order) = .ok (x, m))
    (hs : 2 ^ 256 ≤ m + pf m) :
    AsyncSwap.executeOrder ext order data env w = .error (panic "0x11") := by
  rw [executeOrder_run, if_neg hd, if_pos ho, hv]
  simp only [hs, ite_true]

/-- A revert of the `asyncOrderInfo` self-call is propagated. -/
theorem executeOrder_viewRevert (order : AsyncOrder) (data : List Nat) (env : Env) (w : σ)
    (hd : ¬ (data.length < 32 ∨ 2 ^ 160 ≤ fillerWord data)) (ho : outputOf order = 0) (e : Revert)
    (hv : ext.view_AsyncSwap_asyncOrderInfo env w env.self (poolId ext order.key)
      (orderId ext env order) = .error e) :
    AsyncSwap.executeOrder ext order data env w = .error e := by
  rw [executeOrder_run, if_neg hd, if_pos ho, hv]

/-- **Guard (executor).** With an ERC20 output, a caller that the order's owner has not authorised
as executor in this pool reverts `NotAuthorizedExecutor`. -/
theorem executeOrder_unauthorized (order : AsyncOrder) (data : List Nat) (env : Env) (w : σ)
    (hd : ¬ (data.length < 32 ∨ 2 ^ 160 ≤ fillerWord data)) (ho : outputOf order ≠ 0)
    (hw : (((ext.get w).asyncOrders (poolId ext order.key)).orders
      (orderId ext env order)).amountOutMin < 2 ^ 256)
    (hx : ((ext.get w).asyncOrders (poolId ext order.key)).isExecutor order.owner env.sender = false) :
    AsyncSwap.executeOrder ext order data env w = .error ⟨"NotAuthorizedExecutor"⟩ := by
  have hp := pf_le (((ext.get w).asyncOrders (poolId ext order.key)).orders
      (orderId ext env order)).amountOutMin
  have : ¬ 2 ^ 256 ≤ pf (((ext.get w).asyncOrders (poolId ext order.key)).orders
      (orderId ext env order)).amountOutMin := by omega
  rw [executeOrder_run, if_neg hd, if_neg ho, afterNative_run]
  simp only [this, hx, ite_true, ite_false]

/-- **Guard (order exists).** With an ERC20 output and an authorised caller, an order with no stored
input reverts `OrderNotFound`. -/
theorem executeOrder_notFound (order : AsyncOrder) (data : List Nat) (env : Env) (w : σ)
    (hd : ¬ (data.length < 32 ∨ 2 ^ 160 ≤ fillerWord data)) (ho : outputOf order ≠ 0)
    (hw : (((ext.get w).asyncOrders (poolId ext order.key)).orders
      (orderId ext env order)).amountOutMin < 2 ^ 256)
    (hx : ((ext.get w).asyncOrders (poolId ext order.key)).isExecutor order.owner env.sender = true)
    (h0 : (((ext.get w).asyncOrders (poolId ext order.key)).orders (orderId ext env order)).amountIn = 0) :
    AsyncSwap.executeOrder ext order data env w = .error ⟨"OrderNotFound"⟩ := by
  have hp := pf_le (((ext.get w).asyncOrders (poolId ext order.key)).orders
      (orderId ext env order)).amountOutMin
  have : ¬ 2 ^ 256 ≤ pf (((ext.get w).asyncOrders (poolId ext order.key)).orders
      (orderId ext env order)).amountOutMin := by omega
  rw [executeOrder_run, if_neg hd, if_neg ho, afterNative_run]
  simp only [this, hx, h0, ite_true, ite_false, Bool.true_eq_false]

/-- The native step's write touches only `transient[PENDING_NATIVE_DEPOSIT_SLOT]`: with a lawful
`ext` (`get ∘ set = id`) every other field (in particular `asyncOrders`, `priceBooks`) and every
other transient slot is unchanged. -/
theorem tstoreWorld_frame (hget : ∀ w s, ext.get (ext.set w s) = s) (w : σ) (v : Nat) :
    (ext.get (tstoreWorld ext w v)).asyncOrders = (ext.get w).asyncOrders ∧
    (ext.get (tstoreWorld ext w v)).priceBooks = (ext.get w).priceBooks ∧
    (ext.get (tstoreWorld ext w v)).owner = (ext.get w).owner ∧
    (ext.get (tstoreWorld ext w v)).nonceUsed = (ext.get w).nonceUsed ∧
    pending ext (tstoreWorld ext w v) = v ∧
    ∀ k, k ≠ AsyncSwap.PENDING_NATIVE_DEPOSIT_SLOT →
      (ext.get (tstoreWorld ext w v)).transient k = (ext.get w).transient k := by
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_⟩ <;> simp [tstoreWorld, pending, hget, upd]
  intro k hk; simp [hk]

/-- **Success.** A successful `executeOrder` decoded an address `filler`; for native output the
`asyncOrderInfo` amount `m` satisfied `m + pf(m) ≤ pending` and the ledger was decremented by exactly
`m + pf(m)` (world `w1`), else `w1 = w`; in `w1` the caller is the owner's authorised executor and
the order has stored input `amountIn ≠ 0`; and the rest is `fillTail` with `hook = address(this)`,
that `filler`, `feeVault`, `fee = pf(stored amountOutMin)` and the stored amounts. -/
theorem executeOrder_ok (order : AsyncOrder) (data : List Nat) (env : Env) (w w' : σ)
    (h : AsyncSwap.executeOrder ext order data env w = .ok ((), w')) :
    32 ≤ data.length ∧ fillerWord data < 2 ^ 160 ∧
    ∃ w1,
      (if outputOf order = 0 then
        ∃ x m, ext.view_AsyncSwap_asyncOrderInfo env w env.self (poolId ext order.key)
            (orderId ext env order) = .ok (x, m) ∧ m + pf m < 2 ^ 256 ∧ m + pf m ≤ pending ext w ∧
          w1 = tstoreWorld ext w (ysub (pending ext w) (m + pf m))
       else w1 = w) ∧
      let S := (ext.get w1).asyncOrders (poolId ext order.key)
      let info := S.orders (orderId ext env order)
      S.isExecutor order.owner env.sender = true ∧ info.amountIn ≠ 0 ∧
      fillTail ext order (poolId ext order.key) (orderId ext env order) env.self (fillerWord data)
        ext.feeVault (pf info.amountOutMin) info.amountIn info.amountOutMin env w1 = .ok ((), w') := by
  rw [executeOrder_run] at h
  by_cases hd : data.length < 32 ∨ 2 ^ 160 ≤ fillerWord data
  · rw [if_pos hd] at h; cases h
  rw [if_neg hd] at h
  refine ⟨by omega, by omega, ?_⟩
  have tail : ∀ w1, afterNative ext order (fillerWord data) env w1 = .ok ((), w') →
      let S := (ext.get w1).asyncOrders (poolId ext order.key)
      let info := S.orders (orderId ext env order)
      S.isExecutor order.owner env.sender = true ∧ info.amountIn ≠ 0 ∧
      fillTail ext order (poolId ext order.key) (orderId ext env order) env.self (fillerWord data)
        ext.feeVault (pf info.amountOutMin) info.amountIn info.amountOutMin env w1 = .ok ((), w') := by
    intro w1 h1
    rw [afterNative_run] at h1
    simp only at h1
    split at h1
    · cases h1
    split at h1
    · cases h1
    split at h1
    · cases h1
    rename_i _ hx h0
    exact ⟨by simpa using hx, h0, h1⟩
  by_cases ho : outputOf order = 0
  · rw [if_pos ho] at h
    rcases hv : ext.view_AsyncSwap_asyncOrderInfo env w env.self (poolId ext order.key)
        (orderId ext env order) with e | ⟨x, m⟩
    · rw [hv] at h; cases h
    · rw [hv] at h
      simp only at h
      split at h
      · cases h
      split at h
      · cases h
      rename_i hs hp
      refine ⟨_, ?_, tail _ h⟩
      rw [if_pos ho]
      exact ⟨x, m, rfl, by omega, by omega, rfl⟩
  · rw [if_neg ho] at h
    refine ⟨w, ?_, tail w h⟩
    rw [if_neg ho]

end AsyncSwap.Swarm.ExecuteOrder
