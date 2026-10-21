import Generated.AsyncSwap
import Refinement.Monad

/-!
# `AsyncSwap.matchBook`

`function matchBook(PoolKey calldata key, uint8 maxMatches) external returns (uint8)`
(src/AsyncSwap.sol:412), through `AsyncMatching.matchBook` (src/libraries/AsyncMatching.sol:180).

With `pid = key.toId()`:

* **Delegation** (`matchBook_eq`): the call is exactly `AsyncMatching.matchBook` on the storage
  slots `asyncOrders[pid]` and `priceBooks[pid]` (and nothing else), with `hook = address(this)`.
  Every storage write the function itself performs goes through those two accessors
  (`selfSet_frame`, `bookSet_frame`: each touches only its own pool's slot); the opaque external
  calls (`donate`, `burn`/`settle`/`take`/`mint`, the opaque `_remove`/`bestAtPrice`) are
  whatever `Ext` says.
* **Guard** (`matchBook_invalidBound`, `matchBook_ok`): it reverts `InvalidMatchBound` when
  `maxMatches = 0` or `maxMatches > MAX_MATCHES_PER_CALL = 8`, before touching storage.
  (The `RadixPriceTree` `leafId == 0` / `NodeIdOverflow` guards sit inside the opaque
  tree / `_remove` / `_append` calls.)
* **Return** (`matchBook_ok`): on success `1 ≤ maxMatches ≤ 8` and the returned count of matches
  is at most `maxMatches`. In particular the `unchecked ++matched` on a `uint8` never wraps: the
  loop only increments after checking `matched < maxMatches ≤ 8`.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.MatchBook

variable {σ : Type}

/-! ## A small partial-correctness calculus for `M σ` -/

/-- Every successful run of `x` returns a value satisfying `Q`. -/
def Returns {α : Type} (x : M σ α) (Q : α → Prop) : Prop :=
  ∀ env w a w', x env w = .ok (a, w') → Q a

theorem returns_pure {α : Type} {a : α} {Q : α → Prop} (h : Q a) : Returns (pure a : M σ α) Q := by
  intro env w a' w' hx
  simp only [run_pure, Except.ok.injEq, Prod.mk.injEq] at hx
  exact hx.1 ▸ h

theorem returns_bind {α β : Type} {x : M σ α} {f : α → M σ β} {R : α → Prop} {Q : β → Prop}
    (hx : Returns x R) (hf : ∀ a, R a → Returns (f a) Q) : Returns (x >>= f) Q := by
  intro env w b w' h
  rw [run_bind] at h
  split at h
  · rename_i a w1 h1
    exact hf a (hx env w a w1 h1) env w1 b w' h
  · cases h

theorem returns_bind_any {α β : Type} {x : M σ α} {f : α → M σ β} {Q : β → Prop}
    (hf : ∀ a, Returns (f a) Q) : Returns (x >>= f) Q :=
  returns_bind (R := fun _ => True) (fun _ _ _ _ _ => trivial) (fun a _ => hf a)

theorem returns_ite {α : Type} {c : Prop} [Decidable c] {x y : M σ α} {Q : α → Prop}
    (h1 : c → Returns x Q) (h2 : ¬c → Returns y Q) : Returns (if c then x else y) Q := by
  by_cases hc : c
  · simpa [hc] using h1 hc
  · simpa [hc] using h2 hc

/-- The state carried by a loop step. -/
def stepVal {β : Type} : ForInStep β → β
  | .done b => b
  | .yield b => b

/-- Loop invariant over a list. -/
theorem returns_forIn_list {β : Type} (P : β → Prop) (f : Nat → β → M σ (ForInStep β))
    (hf : ∀ i b, P b → Returns (f i b) (fun r => P (stepVal r))) :
    ∀ (l : List Nat) (b : β), P b → Returns (forIn l b f) P := by
  intro l
  induction l with
  | nil => intro b hb; simpa using (returns_pure hb : Returns (pure b : M σ β) P)
  | cons i l ih =>
    intro b hb
    rw [List.forIn_cons]
    refine returns_bind (hf i b hb) ?_
    intro r hr
    cases r with
    | done b' => exact returns_pure hr
    | yield b' => exact ih b' hr

/-- Loop invariant over a `[a:b]` range. -/
theorem returns_forIn_range {β : Type} (P : β → Prop) (r : Std.Legacy.Range) (b : β)
    (f : Nat → β → M σ (ForInStep β))
    (hf : ∀ i b, P b → Returns (f i b) (fun r => P (stepVal r))) (hb : P b) :
    Returns (forIn r b f) P := by
  rw [Std.Legacy.Range.forIn_eq_forIn_range']
  exact returns_forIn_list P f hf _ b hb

/-! ## The library loop -/

/-- `AsyncMatching.matchBook`, for any storage accessors: a success had `1 ≤ maxMatches ≤ 8`
and returns at most `maxMatches`. -/
theorem asyncMatching_matchBook_ok (ext : Ext σ) (sg : M σ AsyncFiller.State_)
    (ss : AsyncFiller.State_ → M σ Unit) (bg : M σ AsyncFiller.Book)
    (bs : AsyncFiller.Book → M σ Unit) (key : PoolKey) (m hook : Nat) (env : Env) (w : σ)
    (n : Nat) (w' : σ)
    (h : AsyncMatching.matchBook ext sg ss bg bs key m hook env w = .ok (n, w')) :
    1 ≤ m ∧ m ≤ AsyncMatching.MAX_MATCHES_PER_CALL ∧ n ≤ m := by
  simp only [AsyncMatching.matchBook] at h
  simp only [run_bind, run_pure, run_throw, run_ite] at h
  split at h
  · cases h
  · rename_i hg
    have hm : 1 ≤ m ∧ m ≤ AsyncMatching.MAX_MATCHES_PER_CALL := by
      simp only [Bool.or_eq_true, beq_iff_eq, decide_eq_true_eq, not_or] at hg
      omega
    refine ⟨hm.1, hm.2, ?_⟩
    split at h
    · rename_i a s' hfor
      have hP := returns_forIn_range (σ := σ) (β := Nat × Bool) (fun b => b.1 ≤ m)
      have hinv := hP _ _ _ ?_ ?_ env w a s' hfor
      · split at h
        · cases h
        · simp only [Except.ok.injEq, Prod.mk.injEq] at h
          obtain ⟨rfl, rfl⟩ := h
          exact hinv
      · intro i b hb
        have hm8 : m ≤ 8 := hm.2
        refine returns_ite (fun _ => returns_pure hb) (fun hlt => ?_)
        have hlt' : b.1 < m := by simpa using hlt
        repeat' (first
          | ((with_reducible apply returns_ite) <;> intro _)
          | ((with_reducible apply returns_bind_any); intro _)
          | (with_reducible apply returns_pure))
        all_goals simp only [stepVal]
        all_goals first
          | exact hb
          | (simp only [addw, Nat.reducePow]; omega)
      · exact Nat.zero_le _
    · cases h

/-! ## `AsyncSwap.matchBook` -/

/-- `PoolIdLibrary.toId key` in the model. -/
def poolId (ext : Ext σ) (key : PoolKey) : Nat :=
  ext.keccak [key.currency0, key.currency1, key.fee, toUnsigned 256 key.tickSpacing, key.hooks]

def selfGet (ext : Ext σ) (pid : Nat) : M σ AsyncFiller.State_ := do
  return ((ext.get (← get)).asyncOrders pid)
def selfSet (ext : Ext σ) (pid : Nat) : AsyncFiller.State_ → M σ Unit := fun x =>
  modify fun w => ext.set w (let s := ext.get w; { s with asyncOrders := upd (s.asyncOrders) pid x })
def bookGet (ext : Ext σ) (pid : Nat) : M σ AsyncFiller.Book := do
  return ((ext.get (← get)).priceBooks pid)
def bookSet (ext : Ext σ) (pid : Nat) : AsyncFiller.Book → M σ Unit := fun x =>
  modify fun w => ext.set w (let s := ext.get w; { s with priceBooks := upd (s.priceBooks) pid x })

/-- **Delegation.** `AsyncSwap.matchBook` is exactly `AsyncMatching.matchBook` on
`asyncOrders[pid]` / `priceBooks[pid]` with `hook = address(this)`; same result, same state. -/
theorem matchBook_eq (ext : Ext σ) (key : PoolKey) (m : Nat) (env : Env) (w : σ) :
    AsyncSwap.matchBook ext key m env w =
      AsyncMatching.matchBook ext (selfGet ext (poolId ext key)) (selfSet ext (poolId ext key))
        (bookGet ext (poolId ext key)) (bookSet ext (poolId ext key)) key m env.self env w := by
  simp only [AsyncSwap.matchBook, PoolIdLibrary.toId, selfGet, bookGet, poolId,
    run_bind, run_pure, run_read]
  rfl

/-- **Guard.** `maxMatches = 0` or `maxMatches > 8` reverts `InvalidMatchBound`. -/
theorem matchBook_invalidBound (ext : Ext σ) (key : PoolKey) (m : Nat) (env : Env) (w : σ)
    (hm : m = 0 ∨ AsyncMatching.MAX_MATCHES_PER_CALL < m) :
    AsyncSwap.matchBook ext key m env w = .error ⟨"InvalidMatchBound"⟩ := by
  rw [matchBook_eq]
  simp only [AsyncMatching.matchBook, run_bind, run_pure, run_throw, run_ite]
  have hc : (m == 0 || decide (m > AsyncMatching.MAX_MATCHES_PER_CALL)) = true := by
    simp only [Bool.or_eq_true, beq_iff_eq, decide_eq_true_eq]
    exact hm
  simp only [hc, ite_true]

/-- **Success.** A successful `matchBook` had `1 ≤ maxMatches ≤ 8` and returns at most
`maxMatches` matches (so the unchecked `uint8` counter never wraps). -/
theorem matchBook_ok (ext : Ext σ) (key : PoolKey) (m : Nat) (env : Env) (w : σ) (n : Nat) (w' : σ)
    (h : AsyncSwap.matchBook ext key m env w = .ok (n, w')) :
    1 ≤ m ∧ m ≤ AsyncMatching.MAX_MATCHES_PER_CALL ∧ n ≤ m := by
  rw [matchBook_eq] at h
  exact asyncMatching_matchBook_ok ext _ _ _ _ key m env.self env w n w' h

/-- **Guard, as non-success.** Outside `1 ≤ maxMatches ≤ 8` there is no successful run. -/
theorem matchBook_bound_noOk (ext : Ext σ) (key : PoolKey) (m : Nat) (env : Env) (w : σ)
    (hm : m = 0 ∨ AsyncMatching.MAX_MATCHES_PER_CALL < m) :
    ∀ r, AsyncSwap.matchBook ext key m env w ≠ .ok r := by
  intro r h
  rw [matchBook_invalidBound ext key m env w hm] at h
  cases h

/-! ## Footprint of the accessors handed to the library -/

theorem selfSet_run (ext : Ext σ) (pid : Nat) (x : AsyncFiller.State_) (env : Env) (w : σ) :
    selfSet ext pid x env w =
      .ok ((), ext.set w { ext.get w with asyncOrders := upd (ext.get w).asyncOrders pid x }) := rfl

theorem bookSet_run (ext : Ext σ) (pid : Nat) (x : AsyncFiller.Book) (env : Env) (w : σ) :
    bookSet ext pid x env w =
      .ok ((), ext.set w { ext.get w with priceBooks := upd (ext.get w).priceBooks pid x }) := rfl

/-- The getters read the current `asyncOrders[pid]` / `priceBooks[pid]` and change nothing. -/
theorem selfGet_run (ext : Ext σ) (pid : Nat) (env : Env) (w : σ) :
    selfGet ext pid env w = .ok ((ext.get w).asyncOrders pid, w) := rfl

theorem bookGet_run (ext : Ext σ) (pid : Nat) (env : Env) (w : σ) :
    bookGet ext pid env w = .ok ((ext.get w).priceBooks pid, w) := rfl

/-- The `asyncOrders` setter handed to the library writes only `asyncOrders[pid]`. -/
theorem selfSet_frame (ext : Ext σ) (hget : ∀ w s, ext.get (ext.set w s) = s) (pid : Nat)
    (x : AsyncFiller.State_) (env : Env) (w w' : σ) (h : selfSet ext pid x env w = .ok ((), w')) :
    (ext.get w').asyncOrders pid = x ∧
    (∀ p, p ≠ pid → (ext.get w').asyncOrders p = (ext.get w).asyncOrders p) ∧
    (ext.get w').priceBooks = (ext.get w).priceBooks ∧
    (ext.get w').owner = (ext.get w).owner ∧
    (ext.get w').pendingOwner = (ext.get w).pendingOwner ∧
    (ext.get w').nonceUsed = (ext.get w).nonceUsed ∧
    (ext.get w').transient = (ext.get w).transient := by
  rw [selfSet_run] at h
  simp only [Except.ok.injEq, Prod.mk.injEq, true_and] at h
  subst h
  refine ⟨by simp [hget, upd], fun p hp => by simp [hget, upd, hp], by simp [hget], by simp [hget],
    by simp [hget], by simp [hget], by simp [hget]⟩

/-- The `priceBooks` setter handed to the library writes only `priceBooks[pid]`. -/
theorem bookSet_frame (ext : Ext σ) (hget : ∀ w s, ext.get (ext.set w s) = s) (pid : Nat)
    (x : AsyncFiller.Book) (env : Env) (w w' : σ) (h : bookSet ext pid x env w = .ok ((), w')) :
    (ext.get w').priceBooks pid = x ∧
    (∀ p, p ≠ pid → (ext.get w').priceBooks p = (ext.get w).priceBooks p) ∧
    (ext.get w').asyncOrders = (ext.get w).asyncOrders ∧
    (ext.get w').owner = (ext.get w).owner ∧
    (ext.get w').pendingOwner = (ext.get w).pendingOwner ∧
    (ext.get w').nonceUsed = (ext.get w).nonceUsed ∧
    (ext.get w').transient = (ext.get w).transient := by
  rw [bookSet_run] at h
  simp only [Except.ok.injEq, Prod.mk.injEq, true_and] at h
  subst h
  refine ⟨by simp [hget, upd], fun p hp => by simp [hget, upd, hp], by simp [hget], by simp [hget],
    by simp [hget], by simp [hget], by simp [hget]⟩

end AsyncSwap.Swarm.MatchBook
