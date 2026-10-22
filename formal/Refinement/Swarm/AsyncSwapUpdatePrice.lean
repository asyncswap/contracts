import Generated.AsyncSwap
import Refinement.Monad

/-!
# `AsyncSwap.updatePrice`

`function updatePrice(AsyncOrder calldata order, uint256 newAmountOutMin) external`
(src/AsyncSwap.sol:418), through `AsyncMatching.updatePrice` → `AsyncFiller.updatePrice`.

With `pid = order.key.toId()`, `id = keccak(chainid, pid, owner, zeroForOne, salt)`,
`S = asyncOrders[pid]`, `info = S.orders[id]`:

* reverts `NotOrderOwner` unless `msg.sender = order.owner` (no executor path);
* reverts `ZeroAmount` when `newAmountOutMin = 0`;
* reverts `OrderNotFound` when `info.amountIn = 0`;
* otherwise runs `_remove` (opaque in the model; the `RadixPriceTree` guards `leafId == 0`,
  `id == 0` and the `orderCount`/`openOrderCount` decrements live there), then `mid`
  (`amountOutMin := n`, `price := _priceKey(isBuy, amountIn, n)` ∈ [1, 2^128),
  `nextSequence := nextSequence + 1` (checked uint64), `sequence := nextSequence`), then
  `_append` (opaque).

`updatePrice` makes no external call and moves no tokens. Between `_remove` and `_append` it
writes only `orders[id].amountOutMin/price/sequence` and `priceBooks[pid].nextSequence`; the
escrowed `amountIn`, `owner`, `isBuy`, `zeroForOne` and the priority-fee fields of the order,
every other order, every other pool and all other storage are unchanged. Only the order's owner
can call it, and `id` hashes `msg.sender`'s address, so nobody can reprice another user's order.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.UpdatePrice

variable {σ : Type} (ext : Ext σ)

/-- `PoolIdLibrary.toId key` in the model. -/
def poolId (key : PoolKey) : Nat :=
  ext.keccak [key.currency0, key.currency1, key.fee, toUnsigned 256 key.tickSpacing, key.hooks]

/-- `AsyncOrderLibrary.orderId order` in the model. -/
def orderId (env : Env) (order : AsyncOrder) : Nat :=
  ext.keccak [env.chainid, poolId ext order.key, order.owner, ybool order.zeroForOne, order.salt]

def selfGet (pid : Nat) : M σ AsyncFiller.State_ := do return ((ext.get (← get)).asyncOrders pid)
def selfSet (pid : Nat) : AsyncFiller.State_ → M σ Unit := fun x =>
  modify fun w => ext.set w (let s := ext.get w; { s with asyncOrders := upd (s.asyncOrders) pid x })
def bookGet (pid : Nat) : M σ AsyncFiller.Book := do return ((ext.get (← get)).priceBooks pid)
def bookSet (pid : Nat) : AsyncFiller.Book → M σ Unit := fun x =>
  modify fun w => ext.set w (let s := ext.get w; { s with priceBooks := upd (s.priceBooks) pid x })

/-- The writes between `_remove` and `_append`. -/
def mid (pid id n : Nat) : M σ Unit := do
  let s ← selfGet ext pid
  selfSet ext pid { s with orders := upd s.orders id { s.orders id with amountOutMin := n } }
  let s ← selfGet ext pid
  let p ← AsyncFiller.«_priceKey» ext (s.orders id).isBuy (s.orders id).amountIn n
  let s ← selfGet ext pid
  selfSet ext pid { s with orders := upd s.orders id { s.orders id with price := p } }
  let b ← bookGet ext pid
  let q ← addc 64 b.nextSequence 1
  let b ← bookGet ext pid
  bookSet ext pid { b with nextSequence := q }
  let s ← selfGet ext pid
  selfSet ext pid { s with orders := upd s.orders id { s.orders id with sequence := q } }

/-- Everything `updatePrice` does once the three guards pass. -/
def tail (pid id n : Nat) : M σ Unit := do
  ext.fn_AsyncFiller_remove_6902 (selfGet ext pid) (selfSet ext pid) (bookGet ext pid) (bookSet ext pid) id
  mid ext pid id n
  ext.fn_AsyncFiller_append_6737 (selfGet ext pid) (selfSet ext pid) (bookGet ext pid) (bookSet ext pid) id

/-- Full characterization of `AsyncSwap.updatePrice`: three guards, then `tail`. -/
theorem updatePrice_run (order : AsyncOrder) (n : Nat) (env : Env) (w : σ) :
    AsyncSwap.updatePrice ext order n env w =
      let S := (ext.get w).asyncOrders (poolId ext order.key)
      if env.sender ≠ order.owner then .error ⟨"NotOrderOwner"⟩
      else if n = 0 then .error ⟨"ZeroAmount"⟩
      else if (S.orders (orderId ext env order)).amountIn = 0 then .error ⟨"OrderNotFound"⟩
      else tail ext (poolId ext order.key) (orderId ext env order) n env w := by
  unfold tail mid selfGet selfSet bookGet bookSet orderId poolId
  simp only [AsyncSwap.updatePrice, AsyncMatching.updatePrice, AsyncFiller.updatePrice,
    AsyncOrderLibrary.orderId, PoolIdLibrary.toId, bind_pure_unit, bind_assoc, pure_bind]
  simp only [run_bind, run_read, run_get, run_modify, run_throw, run_ite]
  generalize ext.keccak [order.key.currency0, order.key.currency1, order.key.fee,
    toUnsigned 256 order.key.tickSpacing, order.key.hooks] = pid
  generalize ext.keccak [env.chainid, pid, order.owner, ybool order.zeroForOne, order.salt] = oid
  by_cases h1 : env.sender = order.owner <;>
  by_cases h2 : n = 0 <;>
  by_cases h3 : (((ext.get w).asyncOrders pid).orders oid).amountIn = 0 <;>
  simp [h1, h2, h3]

/-- Guard 1: anyone but `order.owner` reverts `NotOrderOwner` (no executor may reprice). -/
theorem updatePrice_notOwner (order : AsyncOrder) (n : Nat) (env : Env) (w : σ)
    (hs : env.sender ≠ order.owner) :
    AsyncSwap.updatePrice ext order n env w = .error ⟨"NotOrderOwner"⟩ := by
  rw [updatePrice_run]; simp [hs]

/-- Guard 2: a zero new minimum output reverts `ZeroAmount`. -/
theorem updatePrice_zero (order : AsyncOrder) (env : Env) (w : σ)
    (hs : env.sender = order.owner) :
    AsyncSwap.updatePrice ext order 0 env w = .error ⟨"ZeroAmount"⟩ := by
  rw [updatePrice_run]; simp [hs]

/-- Guard 3: an order with no stored input reverts `OrderNotFound`. -/
theorem updatePrice_notFound (order : AsyncOrder) (n : Nat) (env : Env) (w : σ)
    (hs : env.sender = order.owner) (hn : n ≠ 0)
    (h0 : (((ext.get w).asyncOrders (poolId ext order.key)).orders (orderId ext env order)).amountIn = 0) :
    AsyncSwap.updatePrice ext order n env w = .error ⟨"OrderNotFound"⟩ := by
  rw [updatePrice_run]; simp [hs, hn, h0]

theorem post_ok (q p : Nat) (w w' : σ)
    (h : (if q = 0 then Except.ok (1, w)
      else if 340282366920938463463374607431768211455 < q then Except.ok (340282366920938463463374607431768211455, w)
      else Except.ok (q % 340282366920938463463374607431768211456, w)) =
        (Except.ok (p, w') : Except Revert (Nat × σ))) :
    w' = w ∧ 1 ≤ p ∧ p < 2 ^ 128 := by
  by_cases hq0 : q = 0
  · simp only [hq0, ↓reduceIte, Except.ok.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl⟩ := h; exact ⟨rfl, by decide, by decide⟩
  · by_cases hq1 : 340282366920938463463374607431768211455 < q
    · simp only [hq0, hq1, ↓reduceIte, Except.ok.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl⟩ := h; exact ⟨rfl, by decide, by decide⟩
    · simp only [hq0, hq1, ↓reduceIte, Except.ok.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      rw [Nat.mod_eq_of_lt (by omega)]; exact ⟨rfl, by omega, by omega⟩

/-- `_priceKey` does not touch storage and returns a key in `[1, 2^128)`. -/
theorem priceKey_ok (b : Bool) (a n p : Nat) (env : Env) (w w' : σ)
    (h : AsyncFiller.«_priceKey» ext b a n env w = .ok (p, w')) :
    w' = w ∧ 1 ≤ p ∧ p < 2 ^ 128 := by
  -- The clamp, for any price computation `m` that leaves the world alone. Stated over an
  -- abstract `m` so the kernel never unfolds `mulDivFloor` (whose `x * PRICE_SCALE < 2^256` guard
  -- it would otherwise try to evaluate on a symbolic `x`).
  have tail : ∀ m : M σ Nat, (∀ q w₁, m env w = .ok (q, w₁) → w₁ = w) →
      (do
        let t ← m
        if (t == 0) = true then pure 1
          else if decide (t > 2 ^ 128 - 1) = true then pure (2 ^ 128 - 1)
          else pure (t % 2 ^ 128) : M σ Nat) env w = .ok (p, w') →
      w' = w ∧ 1 ≤ p ∧ p < 2 ^ 128 := by
    intro m hm hr
    simp only [run_bind] at hr
    rcases hq : m env w with e | ⟨q, w₁⟩ <;> rw [hq] at hr
    · cases hr
    · rw [hm q w₁ hq] at hr
      exact post_ok q p w w' (by simpa using hr)
  have frame : ∀ x y d q w₁, mulDivFloor (σ := σ) x y d env w = .ok (q, w₁) → w₁ = w := by
    intro x y d q w₁ hm
    unfold mulDivFloor at hm
    simp only [run_ite, run_throw, run_pure] at hm
    repeat' split at hm
    all_goals (simp only [reduceCtorEq, Except.ok.injEq, Prod.mk.injEq] at hm; try exact hm.2.symm)
  unfold AsyncFiller.«_priceKey» at h
  cases b
  · rw [ite_eq_right_of_eq_false _ _ Bool.false_eq_true] at h
    exact tail _ (frame _ _ _) h
  · rw [ite_eq_left_of_eq_true _ _ (eq_self true)] at h
    exact tail _ (frame _ _ _) h

theorem upd_upd {κ β : Type} [DecidableEq κ] (f : κ → β) (k : κ) (v v' : β) :
    upd (upd f k v) k v' = upd f k v' := by
  funext x; by_cases hx : x = k <;> simp [upd, hx]

/-- The state `mid` leaves: `orders[id]` gets the new `amountOutMin`, price key `p` and
sequence `seq`; pool `pid`'s book gets `nextSequence := seq`. Nothing else changes. -/
def midState (G : AsyncSwap.State) (pid id n p seq : Nat) : AsyncSwap.State :=
  let S := G.asyncOrders pid
  let B := G.priceBooks pid
  let o := S.orders id
  { G with
    asyncOrders := upd G.asyncOrders pid
      { S with orders := upd S.orders id { o with amountOutMin := n, price := p, sequence := seq } },
    priceBooks := upd G.priceBooks pid { B with nextSequence := seq } }

/-- With a lawful `ext` (`get ∘ set = id`), a successful `mid` writes exactly `midState`, where
`p` is `_priceKey(isBuy, amountIn, n)` and the sequence bump did not overflow uint64. -/
theorem mid_ok (hget : ∀ w s, ext.get (ext.set w s) = s) (pid id n : Nat) (env : Env) (w1 w2 : σ)
    (h : mid ext pid id n env w1 = .ok ((), w2)) :
    let o := ((ext.get w1).asyncOrders pid).orders id
    let seq := ((ext.get w1).priceBooks pid).nextSequence + 1
    ∃ p w0, AsyncFiller.«_priceKey» ext o.isBuy o.amountIn n env w0 = .ok (p, w0) ∧
      1 ≤ p ∧ p < 2 ^ 128 ∧
      seq < 2 ^ 64 ∧ ext.get w2 = midState (ext.get w1) pid id n p seq := by
  intro o seq
  unfold mid selfGet selfSet bookGet bookSet addc at h
  simp only [run_bind, run_pure, run_get, run_modify, run_ite, run_throw, hget, upd_same] at h
  split at h
  next p w0 hp =>
    obtain ⟨rfl, hp1, hp2⟩ := priceKey_ok ext _ _ _ _ _ _ _ hp
    refine ⟨p, _, hp, hp1, hp2, ?_⟩
    simp only [hget, upd_same] at h
    by_cases hs : seq < 2 ^ 64
    · simp only [seq] at hs
      simp only [hs, ↓reduceIte, hget, upd_same, Except.ok.injEq, Prod.mk.injEq] at h
      obtain ⟨-, rfl⟩ := h
      refine ⟨hs, ?_⟩
      simp only [hget, midState, seq]
      congr 1 <;> funext k <;> by_cases hk : k = pid <;> simp [upd_upd, hk] <;> simp [upd, hk]
    · simp only [seq] at hs
      simp [hs] at h
  next => cases h

/-- The repricing never changes the order's escrowed input, its owner, side or fee fields. -/
theorem midState_order (G : AsyncSwap.State) (pid id n p seq : Nat) :
    let o := (G.asyncOrders pid).orders id
    let o' := ((midState G pid id n p seq).asyncOrders pid).orders id
    o'.amountIn = o.amountIn ∧ o'.owner = o.owner ∧ o'.isBuy = o.isBuy ∧
      o'.zeroForOne = o.zeroForOne ∧ o'.priorityFee = o.priorityFee ∧
      o'.priorityFeeEscrowed = o.priorityFeeEscrowed ∧
      o'.amountOutMin = n ∧ o'.price = p ∧ o'.sequence = seq := by
  simp [midState, upd]

/-- Every other order in the pool is untouched. -/
theorem midState_other_order (G : AsyncSwap.State) (pid id n p seq j : Nat) (hj : j ≠ id) :
    ((midState G pid id n p seq).asyncOrders pid).orders j = (G.asyncOrders pid).orders j := by
  simp [midState, upd, hj]

/-- Every other pool (orders and book) is untouched. -/
theorem midState_other_pool (G : AsyncSwap.State) (pid id n p seq q : Nat) (hq : q ≠ pid) :
    (midState G pid id n p seq).asyncOrders q = G.asyncOrders q ∧
      (midState G pid id n p seq).priceBooks q = G.priceBooks q := by
  simp [midState, upd, hq]

theorem midState_frame (G : AsyncSwap.State) (pid id n p seq : Nat) :
    let G' := midState G pid id n p seq
    G'.owner = G.owner ∧ G'.pendingOwner = G.pendingOwner ∧ G'.nonceUsed = G.nonceUsed ∧
      G'.transient = G.transient ∧
      (G'.asyncOrders pid).poolManager = (G.asyncOrders pid).poolManager ∧
      (G'.asyncOrders pid).isExecutor = (G.asyncOrders pid).isExecutor ∧
      (G'.priceBooks pid).openOrderCount = (G.priceBooks pid).openOrderCount ∧
      (G'.priceBooks pid).orderingMode = (G.priceBooks pid).orderingMode := by
  simp [midState, upd]

/-- **Success.** A successful `updatePrice` was sent by `order.owner`, with `n ≠ 0`, on a live
order (`amountIn ≠ 0`); it ran `_remove`, then wrote exactly `midState` (new `amountOutMin`,
price key in `[1, 2^128)`, fresh sequence), then `_append`. No external call, no token moves. -/
theorem updatePrice_ok (hget : ∀ w s, ext.get (ext.set w s) = s)
    (order : AsyncOrder) (n : Nat) (env : Env) (w w' : σ)
    (h : AsyncSwap.updatePrice ext order n env w = .ok ((), w')) :
    let pid := poolId ext order.key
    let id := orderId ext env order
    env.sender = order.owner ∧ n ≠ 0 ∧ (((ext.get w).asyncOrders pid).orders id).amountIn ≠ 0 ∧
    ∃ w1 w2 p,
      ext.fn_AsyncFiller_remove_6902 (selfGet ext pid) (selfSet ext pid) (bookGet ext pid)
        (bookSet ext pid) id env w = .ok ((), w1) ∧
      1 ≤ p ∧ p < 2 ^ 128 ∧ ((ext.get w1).priceBooks pid).nextSequence + 1 < 2 ^ 64 ∧
      ext.get w2 = midState (ext.get w1) pid id n p (((ext.get w1).priceBooks pid).nextSequence + 1) ∧
      ext.fn_AsyncFiller_append_6737 (selfGet ext pid) (selfSet ext pid) (bookGet ext pid)
        (bookSet ext pid) id env w2 = .ok ((), w') := by
  intro pid id
  rw [updatePrice_run] at h
  simp only at h
  split at h
  · cases h
  · rename_i hs
    split at h
    · cases h
    · rename_i hn
      split at h
      · cases h
      · rename_i h0
        refine ⟨by simpa using hs, hn, h0, ?_⟩
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

end AsyncSwap.Swarm.UpdatePrice
