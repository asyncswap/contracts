import Generated.AsyncSwap
import Refinement.Monad

/-!
# `BaseHook.beforeSwap` (AsyncSwap, src/BaseHook.sol:143)

Guards, footprint and return value of the generated def. In order it:
* reverts `NotPoolManager` unless `msg.sender = poolManager`;
* reverts `ExactInputOnly` if `params.amountSpecified > 0`;
* panics `0x11` if `-params.amountSpecified` overflows `int256`;
* reverts `abi.decode` unless the hook data holds four words whose first two (user, executor) are
  addresses;
* reverts (`NotAuthorizedExecutor`, empty reason in the model) unless `sender = hookData.executor`;
* then calls `poolManager.mint(address(this), specified, amountTaken)` (claims escrow), then the
  (opaque in the model) `_createOrder(poolId, zeroForOne, amountTaken, hookData, specified == numeraire)`,
  and returns `(beforeSwap.selector = 0x575e24b4, toBeforeSwapDelta(int128(-amountSpecified), 0), 0)`.

The def itself writes no storage: every storage change (to `asyncOrders`, `priceBooks`) happens inside
the external `mint` call or `_createOrder`, which the model leaves opaque in `Ext`; the remaining
guards of the slice (`isExecutor`, zero amounts, priority fee rules, node id overflow) live there.
The `toInt128` inside the `HookSwap` emit is not modelled (emits are dropped); in Solidity it would
additionally revert for `amountTaken ≥ 2^127`, so the model is (safely) more permissive there.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.BeforeSwap

variable {σ : Type} (ext : Ext σ)

/-- The 32-byte word of the hook data at byte `pos`. -/
def hdWord (hd : List Nat) (pos : Nat) : Nat := bytesWord ((hd.drop pos).take 32)

/-- `abi.decode(hookData, (UserParams))` as the model computes it. -/
def hdParams (hd : List Nat) : AsyncSwap.UserParams :=
  { user := hdWord hd 0, executor := hdWord hd 32, amountOutMin := hdWord hd 64, priorityFee := hdWord hd 96 }

/-- The pool id `key.toId()`. -/
def poolId (key : PoolKey) : Nat :=
  ext.keccak [key.currency0, key.currency1, key.fee, toUnsigned 256 key.tickSpacing, key.hooks]

/-- The escrowed amount `uint256(-params.amountSpecified)`. -/
def amountTaken (params : SwapParams) : Nat := toUnsigned 256 (-params.amountSpecified)

/-- The specified currency. -/
def specified (key : PoolKey) (params : SwapParams) : Nat :=
  if params.zeroForOne then key.currency0 else key.currency1

/-- The returned `BeforeSwapDelta`, as `toBeforeSwapDelta(int128(-amountSpecified), 0)`. -/
def delta (params : SwapParams) : Int :=
  toSigned 256 (yor (yshl 128 (toUnsigned 256 (wrapI 128 (-params.amountSpecified))))
    (yand (ysub (yshl 128 1) 1) (toUnsigned 256 0)))

/-- The guards checked by the generated def itself (the rest live in the opaque `_createOrder`). -/
def guards (env : Env) (sender : Nat) (params : SwapParams) (hd : List Nat) : Prop :=
  env.sender = ext.poolManager
  ∧ params.amountSpecified ≤ 0
  ∧ fits 256 (-params.amountSpecified) = true
  ∧ 128 ≤ hd.length
  ∧ hdWord hd 0 < 2 ^ 160
  ∧ hdWord hd 32 < 2 ^ 160
  ∧ sender = hdWord hd 32

/-- What runs after the guards: `poolManager.mint(this, specified, amountTaken)`, then
`_createOrder(poolId, zeroForOne, amountTaken, hookData, specified == numeraire)`, then the return. -/
def tail (env : Env) (w : σ) (key : PoolKey) (params : SwapParams) (hd : List Nat) :
    Except Revert ((Nat × Int × Nat) × σ) :=
  match ext.call_IPoolManager_mint ext.poolManager env.self (specified key params)
      (amountTaken params) env w with
  | .error e => .error e
  | .ok (_, w1) =>
    match ext.fn_AsyncSwap_createOrder_1681 (poolId ext key) params.zeroForOne (amountTaken params)
        (hdParams hd) (specified key params == ext.numeraire) env w1 with
    | .error e => .error e
    | .ok (_, w2) => .ok ((0x575e24b4, delta params, 0), w2)

/-- Guard: a caller other than the pool manager reverts `NotPoolManager`. -/
theorem beforeSwap_notPoolManager (sender : Nat) (key : PoolKey) (params : SwapParams)
    (hd : List Nat) (env : Env) (w : σ) (h : env.sender ≠ ext.poolManager) :
    BaseHook.beforeSwap ext sender key params hd env w = .error ⟨"NotPoolManager"⟩ := by
  simp [BaseHook.beforeSwap, ImmutableState.onlyPoolManager, h]

/-- Guard: an exact-output swap (`amountSpecified > 0`) reverts `ExactInputOnly`. -/
theorem beforeSwap_exactInputOnly (sender : Nat) (key : PoolKey) (params : SwapParams)
    (hd : List Nat) (env : Env) (w : σ) (hs : env.sender = ext.poolManager)
    (h : 0 < params.amountSpecified) :
    BaseHook.beforeSwap ext sender key params hd env w = .error ⟨"ExactInputOnly"⟩ := by
  simp [BaseHook.beforeSwap, ImmutableState.onlyPoolManager, AsyncSwap.«_beforeSwap», hs, h]

/-- Guard: `-amountSpecified` overflowing `int256` (i.e. `type(int256).min`) panics `0x11`. -/
theorem beforeSwap_negOverflow (sender : Nat) (key : PoolKey) (params : SwapParams)
    (hd : List Nat) (env : Env) (w : σ) (hs : env.sender = ext.poolManager)
    (ha : params.amountSpecified ≤ 0) (h : fits 256 (-params.amountSpecified) = false) :
    BaseHook.beforeSwap ext sender key params hd env w = .error (panic "0x11") := by
  have ha' : ¬ (0 < params.amountSpecified) := by omega
  simp [BaseHook.beforeSwap, ImmutableState.onlyPoolManager, AsyncSwap.«_beforeSwap», hs, ha',
    negcI, h, PoolIdLibrary.toId]

/-- Guard: hook data that does not decode as `UserParams` (too short, or an address word out of
range) reverts `abi.decode`. -/
theorem beforeSwap_badDecode (sender : Nat) (key : PoolKey) (params : SwapParams)
    (hd : List Nat) (env : Env) (w : σ) (hs : env.sender = ext.poolManager)
    (ha : params.amountSpecified ≤ 0) (hf : fits 256 (-params.amountSpecified) = true)
    (h : ¬ (128 ≤ hd.length ∧ hdWord hd 0 < 2 ^ 160 ∧ hdWord hd 32 < 2 ^ 160)) :
    BaseHook.beforeSwap ext sender key params hd env w = .error ⟨"abi.decode"⟩ := by
  have ha' : ¬ (0 < params.amountSpecified) := by omega
  simp only [hdWord] at h
  by_cases h0 : 32 ≤ hd.length
  · by_cases hu : bytesWord ((hd.drop 0).take 32) < 2 ^ 160
    · by_cases h1 : 64 ≤ hd.length
      · by_cases he : bytesWord ((hd.drop 32).take 32) < 2 ^ 160
        · by_cases h2 : 96 ≤ hd.length
          · have h3 : ¬ (128 ≤ hd.length) := fun h3 => h ⟨h3, hu, he⟩
            simp at hu
            simp [BaseHook.beforeSwap, ImmutableState.onlyPoolManager, AsyncSwap.«_beforeSwap», hs,
              ha', negcI, hf, PoolIdLibrary.toId, abiWordAt, abiUint, hu, he,
              show 0 + 32 ≤ hd.length by omega, show 32 + 32 ≤ hd.length by omega,
              show 64 + 32 ≤ hd.length by omega, show ¬ (96 + 32 ≤ hd.length) by omega]
          · simp at hu
            simp [BaseHook.beforeSwap, ImmutableState.onlyPoolManager, AsyncSwap.«_beforeSwap», hs,
              ha', negcI, hf, PoolIdLibrary.toId, abiWordAt, abiUint, hu, he,
              show 0 + 32 ≤ hd.length by omega, show 32 + 32 ≤ hd.length by omega,
              show ¬ (64 + 32 ≤ hd.length) by omega]
        · simp at hu
          simp [BaseHook.beforeSwap, ImmutableState.onlyPoolManager, AsyncSwap.«_beforeSwap», hs,
            ha', negcI, hf, PoolIdLibrary.toId, abiWordAt, abiUint, hu, he,
            show 0 + 32 ≤ hd.length by omega, show 32 + 32 ≤ hd.length by omega]
      · simp at hu
        simp [BaseHook.beforeSwap, ImmutableState.onlyPoolManager, AsyncSwap.«_beforeSwap», hs,
          ha', negcI, hf, PoolIdLibrary.toId, abiWordAt, abiUint, hu,
          show 0 + 32 ≤ hd.length by omega, show ¬ (32 + 32 ≤ hd.length) by omega]
    · have hu' : ¬ bytesWord (List.take 32 hd) < 1461501637330902918203684832716283019655932542976 := by
        simpa using hu
      simp [BaseHook.beforeSwap, ImmutableState.onlyPoolManager, AsyncSwap.«_beforeSwap», hs,
        ha', negcI, hf, PoolIdLibrary.toId, abiWordAt, abiUint, hu',
        show 0 + 32 ≤ hd.length by omega]
  · simp [BaseHook.beforeSwap, ImmutableState.onlyPoolManager, AsyncSwap.«_beforeSwap», hs,
      ha', negcI, hf, PoolIdLibrary.toId, abiWordAt, abiUint,
      show ¬ (0 + 32 ≤ hd.length) by omega]

/-- Guard: a swap caller other than the declared `hookData.executor` reverts
(`NotAuthorizedExecutor`; the model records an empty reason). -/
theorem beforeSwap_notExecutor (sender : Nat) (key : PoolKey) (params : SwapParams)
    (hd : List Nat) (env : Env) (w : σ) (hs : env.sender = ext.poolManager)
    (ha : params.amountSpecified ≤ 0) (hf : fits 256 (-params.amountSpecified) = true)
    (hl : 128 ≤ hd.length) (hu : hdWord hd 0 < 2 ^ 160) (he : hdWord hd 32 < 2 ^ 160)
    (h : sender ≠ hdWord hd 32) :
    BaseHook.beforeSwap ext sender key params hd env w = .error ⟨""⟩ := by
  have ha' : ¬ (0 < params.amountSpecified) := by omega
  simp only [hdWord] at hu he h
  simp at hu
  simp [BaseHook.beforeSwap, ImmutableState.onlyPoolManager, AsyncSwap.«_beforeSwap», hs,
    ha', negcI, hf, PoolIdLibrary.toId, abiWordAt, abiUint, hu, he, h,
    show 0 + 32 ≤ hd.length by omega, show 32 + 32 ≤ hd.length by omega,
    show 64 + 32 ≤ hd.length by omega, show 96 + 32 ≤ hd.length by omega]

/-- Success path, exactly: under the guards the call is `poolManager.mint(this, specified,
amountTaken)`, then `_createOrder(poolId, zeroForOne, amountTaken, decode(hookData),
specified == numeraire)`, then returns `(0x575e24b4, delta, 0)` in the world they leave. The def
writes nothing of its own. -/
theorem beforeSwap_run_ok (sender : Nat) (key : PoolKey) (params : SwapParams)
    (hd : List Nat) (env : Env) (w : σ) (hg : guards ext env sender params hd) :
    BaseHook.beforeSwap ext sender key params hd env w = tail ext env w key params hd := by
  obtain ⟨hs, ha, hf, hl, hu, he, hx⟩ := hg
  have ha' : ¬ (0 < params.amountSpecified) := by omega
  simp only [hdWord] at hu he hx
  simp at hu
  simp only [tail, hdParams, hdWord, poolId, amountTaken, specified, delta]
  simp [BaseHook.beforeSwap, ImmutableState.onlyPoolManager, AsyncSwap.«_beforeSwap», hs,
    ha', negcI, hf, PoolIdLibrary.toId, abiWordAt, abiUint, hu, he, hx,
    CurrencySettler.take, CurrencyLibrary.toId, Free.toBeforeSwapDelta,
    show 0 + 32 ≤ hd.length by omega, show 32 + 32 ≤ hd.length by omega,
    show 64 + 32 ≤ hd.length by omega, show 96 + 32 ≤ hd.length by omega]
  split <;> simp_all
  split <;> simp_all

/-- Every success satisfies the guards and is the `mint`-then-`_createOrder` tail. -/
theorem beforeSwap_ok_inv (sender : Nat) (key : PoolKey) (params : SwapParams)
    (hd : List Nat) (env : Env) (w : σ) (r : Nat × Int × Nat) (w' : σ)
    (h : BaseHook.beforeSwap ext sender key params hd env w = .ok (r, w')) :
    guards ext env sender params hd ∧ tail ext env w key params hd = .ok (r, w') := by
  by_cases hs : env.sender = ext.poolManager
  · by_cases ha : params.amountSpecified ≤ 0
    · cases hf : fits 256 (-params.amountSpecified)
      · rw [beforeSwap_negOverflow ext sender key params hd env w hs ha hf] at h; cases h
      · by_cases hd3 : 128 ≤ hd.length ∧ hdWord hd 0 < 2 ^ 160 ∧ hdWord hd 32 < 2 ^ 160
        · obtain ⟨hl, hu, he⟩ := hd3
          by_cases hx : sender = hdWord hd 32
          · have hg : guards ext env sender params hd := ⟨hs, ha, hf, hl, hu, he, hx⟩
            rw [beforeSwap_run_ok ext sender key params hd env w hg] at h
            exact ⟨hg, h⟩
          · rw [beforeSwap_notExecutor ext sender key params hd env w hs ha hf hl hu he hx] at h
            cases h
        · rw [beforeSwap_badDecode ext sender key params hd env w hs ha hf hd3] at h; cases h
    · rw [beforeSwap_exactInputOnly ext sender key params hd env w hs (by omega)] at h; cases h
  · rw [beforeSwap_notPoolManager ext sender key params hd env w hs] at h; cases h

/-- Return value: every success returns `beforeSwap.selector`, the `delta` of `-amountSpecified`,
and a zero LP-fee override. -/
theorem beforeSwap_ok_returns (sender : Nat) (key : PoolKey) (params : SwapParams)
    (hd : List Nat) (env : Env) (w : σ) (r : Nat × Int × Nat) (w' : σ)
    (h : BaseHook.beforeSwap ext sender key params hd env w = .ok (r, w')) :
    r = (0x575e24b4, delta params, 0) := by
  have := (beforeSwap_ok_inv ext sender key params hd env w r w' h).2
  simp only [tail] at this
  split at this
  · cases this
  · split at this
    · cases this
    · cases this; rfl

/-- Succeeds iff the def's guards hold and the external `mint` and `_createOrder` succeed. -/
theorem beforeSwap_succeeds_iff (sender : Nat) (key : PoolKey) (params : SwapParams)
    (hd : List Nat) (env : Env) (w : σ) :
    (∃ r w', BaseHook.beforeSwap ext sender key params hd env w = .ok (r, w'))
      ↔ guards ext env sender params hd ∧ ∃ r w', tail ext env w key params hd = .ok (r, w') := by
  constructor
  · rintro ⟨r, w', h⟩
    obtain ⟨hg, ht⟩ := beforeSwap_ok_inv ext sender key params hd env w r w' h
    exact ⟨hg, r, w', ht⟩
  · rintro ⟨hg, r, w', ht⟩
    exact ⟨r, w', by rw [beforeSwap_run_ok ext sender key params hd env w hg]; exact ht⟩

/-- Footprint: the def performs no storage write of its own. If the `mint` call and `_createOrder`
leave the hook's storage unchanged, so does `beforeSwap`; all writes to `asyncOrders`/`priceBooks`
come from them. -/
theorem beforeSwap_frame (sender : Nat) (key : PoolKey) (params : SwapParams)
    (hd : List Nat) (env : Env) (w : σ) (r : Nat × Int × Nat) (w' : σ)
    (hmint : ∀ a b c d (v : σ) u v', ext.call_IPoolManager_mint a b c d env v = .ok (u, v') →
      ext.get v' = ext.get v)
    (hcreate : ∀ a b c d e (v : σ) u v', ext.fn_AsyncSwap_createOrder_1681 a b c d e env v = .ok (u, v') →
      ext.get v' = ext.get v)
    (h : BaseHook.beforeSwap ext sender key params hd env w = .ok (r, w')) :
    ext.get w' = ext.get w := by
  have ht := (beforeSwap_ok_inv ext sender key params hd env w r w' h).2
  simp only [tail] at ht
  split at ht
  · cases ht
  · rename_i u w1 hm
    split at ht
    · cases ht
    · rename_i u2 w2 hc
      cases ht
      rw [hcreate _ _ _ _ _ _ _ _ hc, hmint _ _ _ _ _ _ _ hm]

/-- The escrowed amount is exactly `-amountSpecified` under the guards. -/
theorem amountTaken_eq (params : SwapParams) (ha : params.amountSpecified ≤ 0)
    (hf : fits 256 (-params.amountSpecified) = true) :
    (amountTaken params : Int) = -params.amountSpecified := by
  have h0 : 0 ≤ -params.amountSpecified := by omega
  unfold fits smin smax at hf
  simp only [decide_eq_true_eq] at hf
  simp at hf
  have h1 : (-params.amountSpecified) % ((2 ^ 256 : Nat) : Int) = -params.amountSpecified :=
    Int.emod_eq_of_lt h0 (by simp; omega)
  simp only [amountTaken, toUnsigned, h1, Int.toNat_of_nonneg h0]

/-- The returned delta packs `-amountSpecified` in the upper 128 bits (specified delta) and 0 in the
lower 128 (unspecified) whenever `-amountSpecified` fits `int128`. -/
theorem delta_eq (params : SwapParams) (h0 : 0 ≤ -params.amountSpecified)
    (h1 : -params.amountSpecified < 2 ^ 127) :
    delta params = -params.amountSpecified * 2 ^ 128 := by
  unfold delta
  generalize -params.amountSpecified = x at h0 h1 ⊢
  obtain ⟨n, rfl⟩ := Int.eq_ofNat_of_zero_le h0
  have hn : n < 2 ^ 127 := by omega
  have hw : wrapI 128 (n : Int) = n := by
    unfold wrapI
    have : (n : Int) % ((2 ^ 128 : Nat) : Int) = n := Int.emod_eq_of_lt h0 (by simp; omega)
    simp only [this]; simp; omega
  have hu : toUnsigned 256 (n : Int) = n := by
    unfold toUnsigned
    have : (n : Int) % ((2 ^ 256 : Nat) : Int) = n := Int.emod_eq_of_lt h0 (by simp; omega)
    simp only [this]; simp
  have hz : toUnsigned 256 0 = 0 := by simp [toUnsigned]
  have hs : yshl 128 n = n * 2 ^ 128 := by
    unfold yshl W
    simp only [Nat.shiftLeft_eq]
    simp; omega
  simp only [hw, hu, hz, yand, Nat.and_zero, yor, Nat.or_zero, hs, toSigned]
  unfold wrapI
  have : ((n * 2 ^ 128 : Nat) : Int) % ((2 ^ 256 : Nat) : Int) = ((n * 2 ^ 128 : Nat) : Int) :=
    Int.emod_eq_of_lt (by omega) (by simp; omega)
  simp only [this]; simp; omega

/-- On success with `amountTaken < 2^127` (the range where Solidity's `toInt128` in the emit does
not revert), the hook returns the selector, a delta of exactly `amountTaken << 128`, and fee 0. -/
theorem beforeSwap_ok_delta (sender : Nat) (key : PoolKey) (params : SwapParams)
    (hd : List Nat) (env : Env) (w : σ) (r : Nat × Int × Nat) (w' : σ)
    (h : BaseHook.beforeSwap ext sender key params hd env w = .ok (r, w'))
    (hsmall : -params.amountSpecified < 2 ^ 127) :
    r = (0x575e24b4, (amountTaken params : Int) * 2 ^ 128, 0) := by
  obtain ⟨⟨_, ha, hf, _⟩, _⟩ := beforeSwap_ok_inv ext sender key params hd env w r w' h
  rw [beforeSwap_ok_returns ext sender key params hd env w r w' h,
    delta_eq params (by omega) hsmall, amountTaken_eq params ha hf]

end AsyncSwap.Swarm.BeforeSwap
