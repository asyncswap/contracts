import Generated.AsyncSwap

/-!
# `AsyncMatching._creditPriorityFee` (src/AsyncSwap.sol)

The function has no guards and no storage writes of its own:
* `amount = 0`: it returns at once, no read, no write, no revert;
* `amount ≠ 0`: it reads `poolManager`, `numeraire`, `feeVault` from the filler state and
  hands them, with `batch` and `amount`, to `ClaimTransfers.credit` (opaque, in `Ext`);
  its whole effect (state change or revert) is that call's.
-/

open FormalAst

namespace AsyncSwap.Swarm.CreditPriorityFee

/-- Zero amount: the function is `pure ()` — never reverts, touches no storage. -/
theorem creditPriorityFee_zero {σ : Type} (ext : Ext σ)
    (self_get : M σ AsyncFiller.State_) (self_set : AsyncFiller.State_ → M σ Unit)
    (key : PoolKey) (id maker : Nat) (batch : ClaimTransfers.Batch) :
    AsyncMatching.«_creditPriorityFee» ext self_get self_set key id maker 0 batch = pure () := by
  simp [AsyncMatching.«_creditPriorityFee»]

/-- Nonzero amount, for any getter: three reads then the `credit` call, nothing else
(`self_set` is never used, so no own storage write). -/
theorem creditPriorityFee_nonzero {σ : Type} (ext : Ext σ)
    (self_get : M σ AsyncFiller.State_) (self_set : AsyncFiller.State_ → M σ Unit)
    (key : PoolKey) (id maker amount : Nat) (batch : ClaimTransfers.Batch) (h : amount ≠ 0) :
    AsyncMatching.«_creditPriorityFee» ext self_get self_set key id maker amount batch =
      (do
        let t1 ← self_get
        let t2 ← self_get
        let t3 ← self_get
        ext.fn_ClaimTransfers_credit_14414 batch t1.poolManager t2.numeraire t3.feeVault amount
        return ()) := by
  have : (amount == 0) = false := by simpa using h
  simp only [AsyncMatching.«_creditPriorityFee», this]
  rfl

/-- Nonzero amount with a pure-read getter: the run is exactly the `credit` call with the
state's `poolManager`, `numeraire`, `feeVault`; it reverts iff that call reverts, and its
final state is that call's. -/
theorem creditPriorityFee_run {σ : Type} (ext : Ext σ)
    (self_get : M σ AsyncFiller.State_) (self_set : AsyncFiller.State_ → M σ Unit)
    (view : σ → AsyncFiller.State_)
    (hget : ∀ env s, self_get env s = Except.ok (view s, s))
    (key : PoolKey) (id maker amount : Nat) (batch : ClaimTransfers.Batch) (h : amount ≠ 0)
    (env : Env) (s : σ) :
    AsyncMatching.«_creditPriorityFee» ext self_get self_set key id maker amount batch env s =
      ext.fn_ClaimTransfers_credit_14414 batch (view s).poolManager (view s).numeraire
        (view s).feeVault amount env s := by
  rw [creditPriorityFee_nonzero ext self_get self_set key id maker amount batch h]
  simp only [bind, ReaderT.bind, StateT.bind, Except.bind, hget, pure, ReaderT.pure,
    StateT.pure, Except.pure]
  generalize ext.fn_ClaimTransfers_credit_14414 batch (view s).poolManager (view s).numeraire
    (view s).feeVault amount env s = r
  rcases r with e | ⟨⟨⟩, s'⟩ <;> rfl

end AsyncSwap.Swarm.CreditPriorityFee
