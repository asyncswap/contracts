import Generated.AsyncSwap
import Refinement.Monad

/-!
# `BaseHook.beforeInitialize` (AsyncSwap, src/BaseHook.sol:35)

Guards, footprint and return value of the generated def:
* reverts `NotPoolManager` unless `msg.sender = poolManager`;
* then reverts `NumeraireRequired` unless one of the pool's currencies is the numeraire;
* then reverts `DynamicFeeRequired` unless `key.fee = DYNAMIC_FEE_FLAG`;
* otherwise returns the selector `0xdc98354e` and writes exactly
  `asyncOrders[key.toId()].{poolManager, numeraire, feeVault}` (nothing else in the hook's storage).

The run theorem is exact and assumption-free; for the footprint stated on the hook's storage, the
only property of the storage locator used is `ext.get (ext.set w s) = s`. No external calls are made.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm

variable {σ : Type} (ext : Ext σ)

/-- The pool id `key.toId()` as computed by the model. -/
def beforeInit_poolId (key : PoolKey) : Nat :=
  ext.keccak [key.currency0, key.currency1, key.fee, toUnsigned 256 key.tickSpacing, key.hooks]

/-- The world after the three writes, exactly as the generated def performs them. -/
def beforeInit_world (w : σ) (key : PoolKey) : σ :=
  let k := beforeInit_poolId ext key
  let w1 := ext.set w { ext.get w with asyncOrders := upd (ext.get w).asyncOrders k { ((ext.get w).asyncOrders k) with poolManager := ext.poolManager } }
  let w2 := ext.set w1 { ext.get w1 with asyncOrders := upd (ext.get w1).asyncOrders k { ((ext.get w1).asyncOrders k) with numeraire := ext.numeraire } }
  ext.set w2 { ext.get w2 with asyncOrders := upd (ext.get w2).asyncOrders k { ((ext.get w2).asyncOrders k) with feeVault := ext.feeVault } }

/-- The pool record after the three writes of `beforeInitialize`. -/
def beforeInit_pool (pool : AsyncFiller.State_) : AsyncFiller.State_ :=
  { pool with poolManager := ext.poolManager, numeraire := ext.numeraire, feeVault := ext.feeVault }

/-- The hook's storage after a successful `beforeInitialize(key)`. -/
def beforeInit_state (s : State) (key : PoolKey) : State :=
  let k := beforeInit_poolId ext key
  let p := beforeInit_pool ext (s.asyncOrders k)
  { s with asyncOrders := upd s.asyncOrders k p }

/-- The guards that make `beforeInitialize` succeed. -/
def beforeInit_guards (env : Env) (key : PoolKey) : Prop :=
  env.sender = ext.poolManager
  ∧ (key.currency0 = ext.numeraire ∨ key.currency1 = ext.numeraire)
  ∧ key.fee = LPFeeLibrary.DYNAMIC_FEE_FLAG

/-- Guard 1: a caller other than the pool manager reverts `NotPoolManager`. -/
theorem beforeInitialize_notPoolManager (sender : Nat) (key : PoolKey) (sqrtPriceX96 : Nat)
    (env : Env) (w : σ) (h : env.sender ≠ ext.poolManager) :
    BaseHook.beforeInitialize ext sender key sqrtPriceX96 env w = .error ⟨"NotPoolManager"⟩ := by
  simp [BaseHook.beforeInitialize, ImmutableState.onlyPoolManager, h]

/-- Guard 2: a pool with no numeraire leg reverts `NumeraireRequired`. -/
theorem beforeInitialize_numeraireRequired (sender : Nat) (key : PoolKey) (sqrtPriceX96 : Nat)
    (env : Env) (w : σ) (hs : env.sender = ext.poolManager)
    (h : ¬(key.currency0 = ext.numeraire ∨ key.currency1 = ext.numeraire)) :
    BaseHook.beforeInitialize ext sender key sqrtPriceX96 env w = .error ⟨"NumeraireRequired"⟩ := by
  rw [not_or] at h
  simp [BaseHook.beforeInitialize, ImmutableState.onlyPoolManager, AsyncSwap.«_beforeInitialize»,
    hs, h.1, h.2]

/-- Guard 3: a static-fee pool reverts `DynamicFeeRequired`. -/
theorem beforeInitialize_dynamicFeeRequired (sender : Nat) (key : PoolKey) (sqrtPriceX96 : Nat)
    (env : Env) (w : σ) (hs : env.sender = ext.poolManager)
    (hn : key.currency0 = ext.numeraire ∨ key.currency1 = ext.numeraire)
    (h : key.fee ≠ LPFeeLibrary.DYNAMIC_FEE_FLAG) :
    BaseHook.beforeInitialize ext sender key sqrtPriceX96 env w = .error ⟨"DynamicFeeRequired"⟩ := by
  rcases hn with hn | hn <;>
  simp [BaseHook.beforeInitialize, ImmutableState.onlyPoolManager, AsyncSwap.«_beforeInitialize»,
    hs, h, hn]

/-- Success, exactly: under the guards the call returns `beforeInitialize.selector` (`0xdc98354e`)
and the world is `beforeInit_world` (the three writes of `asyncOrders[key.toId()]`). -/
theorem beforeInitialize_run_ok (sender : Nat) (key : PoolKey) (sqrtPriceX96 : Nat) (env : Env)
    (w : σ) (hg : beforeInit_guards ext env key) :
    BaseHook.beforeInitialize ext sender key sqrtPriceX96 env w
      = .ok (0xdc98354e, beforeInit_world ext w key) := by
  obtain ⟨hs, hn, hf⟩ := hg
  rcases hn with hn | hn <;>
  simp [BaseHook.beforeInitialize, ImmutableState.onlyPoolManager, AsyncSwap.«_beforeInitialize»,
    PoolIdLibrary.toId, hs, hf, hn, beforeInit_world, beforeInit_poolId]

/-- The hook's storage in `beforeInit_world` is `beforeInit_state`. -/
theorem beforeInit_world_get (hget : ∀ w s, ext.get (ext.set w s) = s) (w : σ) (key : PoolKey) :
    ext.get (beforeInit_world ext w key) = beforeInit_state ext (ext.get w) key := by
  simp only [beforeInit_world, beforeInit_state, beforeInit_pool, hget]
  congr 1
  funext x
  by_cases hx : x = beforeInit_poolId ext key <;> simp [upd, hx]

/-- Success: under the guards the call returns the selector and its one effect on the hook's
storage is `beforeInit_state`. -/
theorem beforeInitialize_ok (hget : ∀ w s, ext.get (ext.set w s) = s)
    (sender : Nat) (key : PoolKey) (sqrtPriceX96 : Nat) (env : Env) (w : σ)
    (hg : beforeInit_guards ext env key) :
    ∃ w', BaseHook.beforeInitialize ext sender key sqrtPriceX96 env w = .ok (0xdc98354e, w')
      ∧ ext.get w' = beforeInit_state ext (ext.get w) key :=
  ⟨_, beforeInitialize_run_ok ext sender key sqrtPriceX96 env w hg, beforeInit_world_get ext hget w key⟩

/-- Every success satisfies the guards, returns the selector and writes `beforeInit_state`. -/
theorem beforeInitialize_ok_inv (hget : ∀ w s, ext.get (ext.set w s) = s)
    (sender : Nat) (key : PoolKey) (sqrtPriceX96 : Nat) (env : Env) (w : σ) (r : Nat) (w' : σ)
    (h : BaseHook.beforeInitialize ext sender key sqrtPriceX96 env w = .ok (r, w')) :
    beforeInit_guards ext env key ∧ r = 0xdc98354e
      ∧ ext.get w' = beforeInit_state ext (ext.get w) key := by
  by_cases hs : env.sender = ext.poolManager
  · by_cases hn : key.currency0 = ext.numeraire ∨ key.currency1 = ext.numeraire
    · by_cases hf : key.fee = LPFeeLibrary.DYNAMIC_FEE_FLAG
      · rw [beforeInitialize_run_ok ext sender key sqrtPriceX96 env w ⟨hs, hn, hf⟩] at h
        cases h
        exact ⟨⟨hs, hn, hf⟩, rfl, beforeInit_world_get ext hget w key⟩
      · rw [beforeInitialize_dynamicFeeRequired ext sender key sqrtPriceX96 env w hs hn hf] at h
        cases h
    · rw [beforeInitialize_numeraireRequired ext sender key sqrtPriceX96 env w hs hn] at h
      cases h
  · rw [beforeInitialize_notPoolManager ext sender key sqrtPriceX96 env w hs] at h
    cases h

/-- Succeeds iff the three guards hold. -/
theorem beforeInitialize_succeeds_iff (sender : Nat) (key : PoolKey) (sqrtPriceX96 : Nat)
    (env : Env) (w : σ) :
    (∃ r w', BaseHook.beforeInitialize ext sender key sqrtPriceX96 env w = .ok (r, w'))
      ↔ beforeInit_guards ext env key := by
  constructor
  · rintro ⟨r, w', h⟩
    by_cases hs : env.sender = ext.poolManager
    · by_cases hn : key.currency0 = ext.numeraire ∨ key.currency1 = ext.numeraire
      · by_cases hf : key.fee = LPFeeLibrary.DYNAMIC_FEE_FLAG
        · exact ⟨hs, hn, hf⟩
        · rw [beforeInitialize_dynamicFeeRequired ext sender key sqrtPriceX96 env w hs hn hf] at h
          cases h
      · rw [beforeInitialize_numeraireRequired ext sender key sqrtPriceX96 env w hs hn] at h
        cases h
    · rw [beforeInitialize_notPoolManager ext sender key sqrtPriceX96 env w hs] at h
      cases h
  · intro hg
    exact ⟨_, _, beforeInitialize_run_ok ext sender key sqrtPriceX96 env w hg⟩

/-- Footprint: a successful call changes only `asyncOrders[key.toId()]`, and in it only
`poolManager`, `numeraire`, `feeVault`; every other pool and every other state variable is unchanged. -/
theorem beforeInitialize_frame (hget : ∀ w s, ext.get (ext.set w s) = s)
    (sender : Nat) (key : PoolKey) (sqrtPriceX96 : Nat) (env : Env) (w w' : σ) (r : Nat)
    (h : BaseHook.beforeInitialize ext sender key sqrtPriceX96 env w = .ok (r, w')) :
    { ext.get w' with asyncOrders := (ext.get w).asyncOrders } = ext.get w
    ∧ (∀ p, p ≠ beforeInit_poolId ext key → (ext.get w').asyncOrders p = (ext.get w).asyncOrders p)
    ∧ (ext.get w').asyncOrders (beforeInit_poolId ext key)
        = beforeInit_pool ext ((ext.get w).asyncOrders (beforeInit_poolId ext key)) := by
  obtain ⟨_, _, hw⟩ := beforeInitialize_ok_inv ext hget sender key sqrtPriceX96 env w r w' h
  rw [hw]
  refine ⟨rfl, fun p hp => ?_, ?_⟩ <;> simp_all [beforeInit_state, upd]

end AsyncSwap.Swarm
