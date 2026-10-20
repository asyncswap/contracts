import Generated.Router
import Refinement.Monad
import AsyncSwapProtocol.V2.Spec

/-!
# `Router`: generated model ⟶ `AsyncSwapProtocol.V2`

`Generated/Router.lean` is formal-ast's translation of `src/Router.sol`. The Foundry scripts call
`Router.swap` (`script/03_Swap.s.sol`, `script/Trade.s.sol`), `Router.cancelOrder`
(`script/04_CancelOrder.s.sol`) and `Router.fillOrder` (`script/05_ExecuteOrder.s.sol`).

The spec's `swap` / `cancelOrder` / `fillOrder` (`AsyncSwapProtocol/V2/Model.lean`) are whole
transactions: a guard, then the Router → PoolManager → hook → FeeVault call sequence. The generated
Router is one contract of that sequence. Its defs check the caller-facing part of the guard, record the
caller in transient storage and hand the order to `PoolManager.unlock`; the PoolManager and the hook are
`Ext` calls. So each refinement theorem here proves, for one def:

* **sound**: every run that does not revert satisfies the conjuncts of the spec guard the Router checks;
* **complete**: when they hold, the def does exactly the spec's Router step (its transient writes and
  the `unlock` call carrying the same order), and nothing else.

The other conjuncts (book state, balances, executor approval) are the hook's and the PoolManager's;
see `Refinement/AsyncSwap.lean` and the report in `formal/README.md`.

Abstraction: a contract `AsyncOrder` is the spec `Order` with the pool key and price limit dropped
(`absOrder`); the spec's two currencies are the pool's (`false` = `currency0`, `true` = `currency1`, the
numeraire), and `Binds` says the spec `Config` describes this Router and this pool.
-/

open FormalAst Refinement
open AsyncSwapProtocol

namespace Router

/-! ## ABI encoding: what the Router encodes, it decodes back -/

theorem bytesWord_append (l : List Nat) (b : Nat) : bytesWord (l ++ [b]) = bytesWord l * 256 + b := by
  simp [bytesWord, List.foldl_append]

theorem bytesWord_bytes (n w : Nat) :
    bytesWord ((List.range n).map (fun i => (w >>> (8 * (n - 1 - i))) % 256)) = w % 2 ^ (8 * n) := by
  induction n generalizing w with
  | zero => simp [bytesWord, Nat.mod_one]
  | succ n ih =>
    rw [List.range_succ, List.map_append, List.map_singleton, bytesWord_append]
    have : (List.range n).map (fun i => (w >>> (8 * (n + 1 - 1 - i))) % 256)
        = (List.range n).map (fun i => ((w >>> 8) >>> (8 * (n - 1 - i))) % 256) := by
      apply List.map_congr_left
      intro i hi
      rw [List.mem_range] at hi
      rw [← Nat.shiftRight_add]
      congr 2
      omega
    rw [this, ih]
    simp only [Nat.add_sub_cancel, Nat.sub_self, Nat.mul_zero, Nat.shiftRight_eq_div_pow]
    rw [show 8 * (n + 1) = 8 + 8 * n by ring, pow_add, Nat.mod_mul]
    norm_num
    ring

theorem bytesWord_wordBytes (w : Nat) : bytesWord (wordBytes w) = w % 2 ^ 256 := by
  have := bytesWord_bytes 32 w
  simpa [wordBytes] using this

@[simp] theorem length_wordBytes (w : Nat) : (wordBytes w).length = 32 := by simp [wordBytes]


theorem abiEncode_cons (w : Nat) (ws : List Nat) : abiEncode (w :: ws) = wordBytes w ++ abiEncode ws := by
  simp [abiEncode]

@[simp] theorem length_abiEncode (ws : List Nat) : (abiEncode ws).length = 32 * ws.length := by
  induction ws with
  | nil => simp [abiEncode]
  | cons w ws ih => rw [abiEncode_cons, List.length_append, ih, length_wordBytes]; simp; ring

/-- Word `n / 32` of an encoding: drop the words before it, read the next 32 bytes. -/
theorem take_drop_abiEncode_cons (w : Nat) (ws : List Nat) (n : Nat) :
    List.take 32 (List.drop n (abiEncode (w :: ws)))
      = if n = 0 then wordBytes w else if 32 ≤ n then List.take 32 (List.drop (n - 32) (abiEncode ws))
        else List.take 32 (List.drop n (wordBytes w ++ abiEncode ws)) := by
  rw [abiEncode_cons]
  split_ifs with h0 h32
  · subst h0; simp
  · rw [List.drop_append, List.drop_eq_nil_of_le (by simpa using h32)]; simp
  · rfl

@[simp] theorem take_abiEncode_cons (w : Nat) (ws : List Nat) :
    List.take 32 (abiEncode (w :: ws)) = wordBytes w := by
  simpa using take_drop_abiEncode_cons w ws 0

theorem bytesWord_wordBytes_of_lt {w : Nat} (h : w < 2 ^ 256) : bytesWord (wordBytes w) = w := by
  rw [bytesWord_wordBytes, Nat.mod_eq_of_lt h]


/-! ## Abstraction -/

variable {σ : Type} (ext : Ext σ)

/-- The spec's `Order`: the contract's `AsyncOrder` without the pool key and the price limit. -/
def absOrder (o : AsyncOrder) : V2.Order :=
  ⟨o.owner, o.zeroForOne, o.amountIn, o.amountOutMin, o.priorityFee, o.salt⟩

/-- `order.zeroForOne ? currency0 : currency1` -/
def inputCurrency (o : AsyncOrder) : Nat := if o.zeroForOne then o.key.currency0 else o.key.currency1

/-- The word at byte `pos` of ABI data. -/
def wordAt (bs : List Nat) (pos : Nat) : Nat := bytesWord ((bs.drop pos).take 32)

/-- `abi.decode(userData, (UserParams))`, word by word. -/
def userParamsOf (ud : List Nat) : V2.Protocol.UserParams := ⟨wordAt ud 0, wordAt ud 32, wordAt ud 64, wordAt ud 96⟩

/-- `tstore(slot, v)` on the Router's transient storage. -/
def tstore (w : σ) (slot v : Nat) : σ :=
  ext.set w { ext.get w with «transient» := upd (ext.get w).«transient» slot v }

/-- `abi.encode(SwapCallback({action, order, maxMatches}))`: what the Router hands to `PoolManager.unlock`. -/
def callbackData (action : Nat) (o : AsyncOrder) (maxMatches : Nat) : List Nat :=
  abiEncode [action, o.key.currency0, o.key.currency1, o.key.fee, toUnsigned 256 o.key.tickSpacing, o.key.hooks,
    o.owner, ybool o.zeroForOne, o.amountIn, o.amountOutMin, o.priorityFee, o.sqrtPrice, o.salt, maxMatches]

/-- The spec's `Config` describes this Router (`address(this)`) and the order's pool: `currency0` is native
exactly when it is `address(0)`, and the numeraire `currency1` never is. -/
structure Binds (cfg : V2.Config) (env : Env) (o : AsyncOrder) : Prop where
  router : cfg.router = env.self
  native0 : cfg.native0 = decide (o.key.currency0 = 0)
  numeraire : o.key.currency1 ≠ 0

theorem Binds.isNative_input {cfg : V2.Config} {env : Env} {o : AsyncOrder} (hb : Binds cfg env o) :
    cfg.isNative (absOrder o).input = decide (inputCurrency o = 0) := by
  have := hb.numeraire
  cases hz : o.zeroForOne <;>
    simp [V2.Config.isNative, V2.Order.input, V2.OrderKey.input, V2.Order.key, absOrder, inputCurrency, hz,
      hb.native0, this]

/-! ## `swap` -/

/-- The conjuncts of the spec's `swapGuard` that `Router.swap` checks: the caller is the owner, the
`UserParams` name the owner, this Router and the order's limits, and `msg.value` carries exactly a native
input. -/
def swapRouterGuard (cfg : V2.Config) (sender : V2.Address) (o : V2.Order) (value : ℕ) (up : V2.Protocol.UserParams) :
    Prop :=
  o.owner = sender ∧ up.user = o.owner ∧ up.executor = cfg.router ∧ up.amountOutMin = o.amountOutMin
  ∧ up.priorityFee = o.priorityFee ∧ (if cfg.isNative o.input then value = o.amountIn else value = 0)

/-- Every spec `swap` that succeeds passes the Router's checks. -/
theorem swapGuard_router {cfg : V2.Config} {w : V2.World} {sender : V2.Address} {o : V2.Order} {value : ℕ}
    {up : V2.Protocol.UserParams} (h : V2.Protocol.swapGuard cfg w sender o value up) :
    swapRouterGuard cfg sender o value up := by
  obtain ⟨h1, h2, h3, h4, h5, h6, -⟩ := h
  refine ⟨h1, h2, h3, h4, h5, ?_⟩
  split_ifs at h6 ⊢ <;> simp_all

/-- **`Router.swap` is sound for the spec's `swapGuard`.** A call that does not revert had at least four
words of `userData`, and the caller, those `UserParams` and `msg.value` satisfy every conjunct of
`swapGuard` the Router is responsible for. -/
theorem swap_sound {cfg : V2.Config} {env : Env} {o : AsyncOrder} (hb : Binds cfg env o) (ud : List Nat)
    (w w' : σ) (h : Router.swap ext o ud env w = .ok ((), w')) :
    128 ≤ ud.length ∧ swapRouterGuard cfg env.sender (absOrder o) env.value (userParamsOf ud) := by
  have hn := hb.isNative_input
  simp only [swapRouterGuard, hn, hb.router]
  simp only [absOrder, userParamsOf, wordAt, inputCurrency]
  simp [Router.swap, abiWordAt, abiUint, CurrencyLibrary.isAddressZero, CurrencyLibrary.ADDRESS_ZERO] at h
  repeat' split at h
  all_goals simp_all

/-- **`Router.swap` is complete for the spec's `swapGuard`.** When the Router's conjuncts hold (and the
two address words are addresses), the call records the caller and the filler in transient storage and
hands `SwapCallback(Swap, order, 0)` to `PoolManager.unlock`: the spec's `swapBody` starts from there. -/
theorem swap_complete {cfg : V2.Config} {env : Env} {o : AsyncOrder} (hb : Binds cfg env o) (ud : List Nat)
    (w : σ) (hlen : 128 ≤ ud.length) (hu : wordAt ud 0 < 2 ^ 160) (he : wordAt ud 32 < 2 ^ 160)
    (hg : swapRouterGuard cfg env.sender (absOrder o) env.value (userParamsOf ud)) :
    Router.swap ext o ud env w
      = ((fun _ => ()) <$> ext.call_IPoolManager_unlock ext.POOLMANAGER (callbackData 0 o 0)) env
          (tstore ext (tstore ext w Router.USER_LOCATION env.sender) Router.ASYNC_FILLER_LOCATION env.self) := by
  have hn := hb.isNative_input
  simp only [swapRouterGuard, hn, hb.router] at hg
  simp only [absOrder, userParamsOf, wordAt, inputCurrency] at hg hu he
  obtain ⟨h1, h2, h3, h4, h5, h6⟩ := hg
  have l1 : 32 ≤ ud.length := by omega
  have l2 : 64 ≤ ud.length := by omega
  have l3 : 96 ≤ ud.length := by omega
  simp [Router.swap, abiWordAt, abiUint, CurrencyLibrary.isAddressZero, CurrencyLibrary.ADDRESS_ZERO, l1, l2, l3,
    hlen, h1, h3, h4, h5, callbackData, tstore]
  split_ifs at h6 ⊢ <;> simp_all

/-- `UserParams` round-trip: the `abi.encode(UserParams)` that `Router.unlockCallback` passes to
`PoolManager.swap` as hook data decodes back to the same four fields. -/
theorem userParamsOf_abiEncode (u e a p : Nat) (hu : u < 2 ^ 256) (he : e < 2 ^ 256) (ha : a < 2 ^ 256)
    (hp : p < 2 ^ 256) : userParamsOf (abiEncode [u, e, a, p]) = ⟨u, e, a, p⟩ := by
  simp only [userParamsOf, wordAt, take_drop_abiEncode_cons]
  simp [bytesWord_wordBytes_of_lt hu, bytesWord_wordBytes_of_lt he, bytesWord_wordBytes_of_lt ha,
    bytesWord_wordBytes_of_lt hp]

/-! ## `cancelOrder` -/

/-- **`Router.cancelOrder` is sound for the spec's `cancelOrder`**: a call that does not revert came from
the order's owner, the spec's first conjunct (`sender = o.owner`). -/
theorem cancelOrder_sound (o : AsyncOrder) (env : Env) (w w' : σ)
    (h : Router.cancelOrder ext o env w = .ok ((), w')) : env.sender = (absOrder o).owner := by
  simp [Router.cancelOrder] at h
  split at h
  · assumption
  · simp at h

/-- **`Router.cancelOrder` is complete for the spec's `cancelOrder`**: from the owner, it records the
caller and hands `SwapCallback(Cancel, order, 0)` to `PoolManager.unlock`. -/
theorem cancelOrder_complete (o : AsyncOrder) (env : Env) (w : σ) (h : env.sender = (absOrder o).owner) :
    Router.cancelOrder ext o env w
      = ((fun _ => ()) <$> ext.call_IPoolManager_unlock ext.POOLMANAGER (callbackData 2 o 0)) env
          (tstore ext w Router.USER_LOCATION env.sender) := by
  simp [absOrder] at h
  simp [Router.cancelOrder, h, callbackData, tstore]

/-- The spec agrees: its `cancelOrder` only succeeds for the owner. -/
theorem spec_cancelOrder_owner {cfg : V2.Config} {W W' : V2.World} {sender : V2.Address} {o : V2.Order}
    (h : V2.Protocol.cancelOrder cfg W sender o = some W') : sender = o.owner := by
  simp only [V2.Protocol.cancelOrder] at h
  split_ifs at h with hg
  exact hg.1


/-! ## `unlockCallback`: the callback decodes to the order the Router sent -/

/-- The order's fields fit their ABI types, so `abi.decode` in `unlockCallback` accepts what the Router
encoded (any order a caller could pass in calldata does). -/
structure Encodable (o : AsyncOrder) : Prop where
  currency0 : o.key.currency0 < 2 ^ 160
  currency1 : o.key.currency1 < 2 ^ 160
  fee : o.key.fee < 2 ^ 24
  tickSpacing : fits 24 o.key.tickSpacing = true
  hooks : o.key.hooks < 2 ^ 160
  owner : o.owner < 2 ^ 160
  amountIn : o.amountIn < 2 ^ 256
  amountOutMin : o.amountOutMin < 2 ^ 256
  priorityFee : o.priorityFee < 2 ^ 256
  sqrtPrice : o.sqrtPrice < 2 ^ 160
  salt : o.salt < 2 ^ 256

@[simp] theorem ybool_le_one (b : Bool) : ybool b ≤ 1 := by cases b <;> simp [ybool]
@[simp] theorem ybool_beq_one (b : Bool) : (ybool b == 1) = b := by cases b <;> simp [ybool]

theorem toUnsigned_lt (x : Int) : toUnsigned 256 x < 2 ^ 256 := by
  simp only [toUnsigned]
  have h1 : 0 ≤ x % ((2 ^ 256 : Nat) : Int) := Int.emod_nonneg _ (by norm_num)
  have h2 : x % ((2 ^ 256 : Nat) : Int) < ((2 ^ 256 : Nat) : Int) := Int.emod_lt_of_pos _ (by norm_num)
  omega

theorem toSigned_toUnsigned {x : Int} (h : fits 24 x = true) : toSigned 256 (toUnsigned 256 x) = x := by
  have hfit : -(2 ^ 23 : Int) ≤ x ∧ x ≤ 2 ^ 23 - 1 := by
    simp only [fits, smin, smax] at h; norm_num at h ⊢; exact h
  have hc : ((toUnsigned 256 x : Nat) : Int) = x % (2 : Int) ^ 256 := by
    simp only [toUnsigned]; push_cast; exact Int.toNat_of_nonneg (Int.emod_nonneg _ (by norm_num))
  simp only [toSigned, wrapI]
  push_cast
  rw [hc]
  norm_num at hfit ⊢
  rcases le_or_gt 0 x with hx | hx
  · rw [Int.emod_eq_of_lt hx (by omega)]
    split_ifs <;> omega
  · have : x % 115792089237316195423570985008687907853269984665640564039457584007913129639936
        = x + 115792089237316195423570985008687907853269984665640564039457584007913129639936 := by
      omega
    rw [this]
    split_ifs <;> omega

set_option maxHeartbeats 4000000 in
/-- **`Router.unlockCallback` routes a Cancel callback to the hook.** From the PoolManager, the callback
the Router's `cancelOrder` encodes decodes back to the same order and becomes
`HOOK.cancelOrder(order)`, the hook half of the spec's `cancelOrder` (`cancelHookGuard`, `cancelBody`). -/
theorem unlockCallback_cancel (hget : ∀ w s, ext.get (ext.set w s) = s) (o : AsyncOrder) (he : Encodable o)
    (env : Env) (hpm : env.sender = ext.POOLMANAGER) (w : σ) :
    Router.unlockCallback ext (callbackData 2 o 0) env w
      = ((fun _ => []) <$> ext.call_AsyncSwap_cancelOrder ext.HOOK o) env (tstore ext w Router.ACTION_LOCATION 2) := by
  obtain ⟨h0, h1, hf, ht, hh, ho, hi, hm, hp, hs, hz⟩ := he
  have ht' := toSigned_toUnsigned ht
  have hu := toUnsigned_lt o.key.tickSpacing
  have m := fun {x : Nat} (h : x < 2 ^ 160) => Nat.mod_eq_of_lt (b := 2 ^ 256) (lt_trans h (by norm_num))
  have hyb : ybool o.zeroForOne < 2 ^ 256 := by cases o.zeroForOne <;> simp [ybool]
  have e := fun {x : Nat} (h : x < 2 ^ 256) => Nat.mod_eq_of_lt (b := 2 ^ 256) h
  have mf := Nat.mod_eq_of_lt (b := 2 ^ 256) (lt_trans hf (by norm_num))
  have r0 := m h0; have r1 := m h1; have rh := m hh; have ro := m ho; have rs := m hs
  have ry := e hyb
  norm_num at h0 h1 hf hh ho hi hm hp hs hz hu r0 r1 rh ro rs ry mf
  simp [Router.unlockCallback, Router.onlyPoolManager, hpm, callbackData, abiWordAt, abiWordOr0, abiEnum, abiUint,
    abiInt, abiBool, take_drop_abiEncode_cons, tstore, hget, upd, bytesWord_wordBytes, Nat.mod_eq_of_lt, h0, h1, hf,
    hh, ho, hi, hm, hp, hs, hz, hu, ht', ht, r0, r1, rh, ro, rs, ry, mf]


/-! ## `fillOrder`

`Router.fillOrder` is not translated: its body sends ETH with `address(HOOK).call{value: msg.value}("")`,
which formal-ast leaves opaque (`Ext.fn_Router_fillOrder_403`). What it does before `unlock` is record
the caller and `maxPrice` in transient storage and hand `SwapCallback(FillOrder, order, 0)` to
`PoolManager.unlock`. The fill's checks run in `unlockCallback`'s FillOrder branch, which is translated. -/

/-- `order.key.toId()` -/
def poolIdOf (key : PoolKey) : Nat :=
  ext.keccak [key.currency0, key.currency1, key.fee, toUnsigned 256 key.tickSpacing, key.hooks]

/-- `_orderId(order)` -/
def orderIdOf (env : Env) (o : AsyncOrder) : Nat :=
  ext.keccak [env.chainid, poolIdOf ext o.key, o.owner, ybool o.zeroForOne, o.salt]

set_option maxHeartbeats 4000000 in
/-- **The FillOrder callback enforces the spec's price bound.** When the hook's `asyncOrderInfo` reports
the spec world's stored order and `calculatePoolFee` is the spec's `poolFee`, a FillOrder callback that
does not revert had `liveGross W key ≤ maxPrice`, the `fillGuard` conjunct the Router checks
(`Price exceeds maxPrice`); `maxPrice` is what `fillOrder` stored in transient storage. -/
theorem unlockCallback_fill_maxPrice (hget : ∀ w s, ext.get (ext.set w s) = s) (o : AsyncOrder)
    (he : Encodable o) (env : Env) (hpm : env.sender = ext.POOLMANAGER) (w : σ) (W : V2.World)
    (hinfo : ext.view_AsyncSwap_asyncOrderInfo env (tstore ext w Router.ACTION_LOCATION 1) ext.HOOK
      (poolIdOf ext o.key) (orderIdOf ext env o)
        = .ok ((W.orders (absOrder o).key).amountIn, (W.orders (absOrder o).key).amountOutMin))
    (hfee : ∀ x, ext.view_AsyncSwap_calculatePoolFee env (tstore ext w Router.ACTION_LOCATION 1) ext.HOOK o.key.fee x
        = .ok (poolFee x))
    (r : List Nat) (w' : σ) (h : Router.unlockCallback ext (callbackData 1 o 0) env w = .ok (r, w')) :
    V2.Protocol.liveGross W (absOrder o).key ≤ (ext.get w).«transient» Router.MAX_PRICE_LOCATION := by
  by_contra hc
  rw [not_le] at hc
  simp only [V2.Protocol.liveGross, gross] at hc
  simp only [tstore, poolIdOf, orderIdOf] at hinfo hfee
  have hne : Router.MAX_PRICE_LOCATION ≠ Router.ACTION_LOCATION := by simp [Router.MAX_PRICE_LOCATION, Router.ACTION_LOCATION]
  obtain ⟨h0, h1, hf, ht, hh, ho, hi, hm, hp, hs, hz⟩ := he
  have ht' := toSigned_toUnsigned ht
  have hu := toUnsigned_lt o.key.tickSpacing
  have m := fun {x : Nat} (h : x < 2 ^ 160) => Nat.mod_eq_of_lt (b := 2 ^ 256) (lt_trans h (by norm_num))
  have hyb : ybool o.zeroForOne < 2 ^ 256 := by cases o.zeroForOne <;> simp [ybool]
  have e := fun {x : Nat} (h : x < 2 ^ 256) => Nat.mod_eq_of_lt (b := 2 ^ 256) h
  have mf := Nat.mod_eq_of_lt (b := 2 ^ 256) (lt_trans hf (by norm_num))
  have r0 := m h0; have r1 := m h1; have rh := m hh; have ro := m ho; have rs := m hs
  have ry := e hyb
  norm_num at h0 h1 hf hh ho hi hm hp hs hz hu r0 r1 rh ro rs ry mf
  simp [Router.unlockCallback, Router.onlyPoolManager, hpm, callbackData, abiWordAt, abiWordOr0, abiEnum, abiUint,
    abiInt, abiBool, take_drop_abiEncode_cons, hget, upd, bytesWord_wordBytes, Nat.mod_eq_of_lt, h0, h1, hf,
    hh, ho, hi, hm, hp, hs, hz, hu, ht', ht, r0, r1, rh, ro, rs, ry, mf, Router._orderId, PoolIdLibrary.toId, view,
    hinfo, hfee, addc] at h
  split at h
  · next heq =>
    simp only [ite_ok_error_eq_ok, Prod.mk.injEq] at heq
    obtain ⟨-, rfl, rfl⟩ := heq
    simp [hget, upd, hne, hc] at h
  · simp at h


open Ext (fn_Router_fillOrder_403)

/-- What `Router.fillOrder`'s Solidity body (`src/Router.sol:146-170`) and `PoolManager.unlock` do, stated
because formal-ast leaves the body opaque: a call that does not revert ran the FillOrder callback, from the
PoolManager, in a world whose transient `maxPrice` slot holds the caller's `maxPrice` and where the hook's
views report the spec world's stored order and fee. -/
def FillOrderReachesCallback (o : AsyncOrder) (maxPrice : Nat) (W : V2.World) (env : Env) : Prop :=
  ∃ (env₀ : Env) (w₀ : σ) (r : List Nat) (w₁ : σ),
    env₀.sender = ext.POOLMANAGER ∧ (ext.get w₀).«transient» Router.MAX_PRICE_LOCATION = maxPrice
    ∧ ext.view_AsyncSwap_asyncOrderInfo env₀ (tstore ext w₀ Router.ACTION_LOCATION 1) ext.HOOK
        (poolIdOf ext o.key) (orderIdOf ext env₀ o)
        = .ok ((W.orders (absOrder o).key).amountIn, (W.orders (absOrder o).key).amountOutMin)
    ∧ (∀ x, ext.view_AsyncSwap_calculatePoolFee env₀ (tstore ext w₀ Router.ACTION_LOCATION 1) ext.HOOK o.key.fee x
        = .ok (poolFee x))
    ∧ Router.unlockCallback ext (callbackData 1 o 0) env₀ w₀ = .ok (r, w₁)
    ∧ env₀.chainid = env.chainid

/-- **`Router.fillOrder` enforces the spec's price bound** (conditional on its untranslated body): a call
of the generated model's `fn_Router_fillOrder_403` that does not revert, and that reached the FillOrder
callback as its Solidity body does, filled only at `liveGross W key ≤ maxPrice`, the conjunct of the
spec's `fillGuard` the Router owns. The rest of `fillGuard` (executor approval, open order, escrowed bid,
the filler's balance) is the hook's. -/
theorem fillOrder_maxPrice (hget : ∀ w s, ext.get (ext.set w s) = s) (o : AsyncOrder) (he : Encodable o)
    (maxPrice : Nat) (d : List Nat) (env : Env) (w w' : σ) (W : V2.World)
    (hcall : fn_Router_fillOrder_403 ext o maxPrice d env w = .ok ((), w'))
    (hbody : fn_Router_fillOrder_403 ext o maxPrice d env w = .ok ((), w') →
      FillOrderReachesCallback ext o maxPrice W env) :
    V2.Protocol.liveGross W (absOrder o).key ≤ maxPrice := by
  obtain ⟨env₀, w₀, r, w₁, hpm, hmax, hinfo, hfee, hcb, -⟩ := hbody hcall
  rw [← hmax]
  exact unlockCallback_fill_maxPrice ext hget o he env₀ hpm w₀ W hinfo hfee r w₁ hcb

end Router
