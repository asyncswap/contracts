import Specs.AsyncSwap
import Proofs.Monad
open FormalAst Refinement

/-!
# `ClaimTransfers.flush` (src/AsyncSwap.sol)

`for (i = 0; i < batch.count; ++i) manager.transfer(item.recipient, item.currency.toId(), item.amount)`
over `item = batch.credits[i]`: the deferred ERC-6909 claim transfers of a matching batch.

* `flushSpec`: the transfers, one `IERC6909Claims.transfer(recipient, id, amount)` per credit, in order.
* `forIn_flush`: the loop invariant, by induction on the iterated list.
* `flush_eq`: when `batch.count ≤ batch.credits.length` (no out-of-bounds read) and
  `batch.count < 2^64` (the loop bound), `flush` *is* `flushSpec` over the first `count` credits:
  exactly those transfers, in order, nothing else (no storage writes of its own).
* `flush_empty`: `count = 0` makes no call and leaves the world unchanged.
-/

namespace AsyncSwap.Swarm.ClaimTransfersFlush

/-- The transfers `flush` should make, in order. -/
def flushSpec {σ : Type} (ext : Ext σ) (manager : Nat) : List ClaimTransfers.Credit → M σ Unit
  | [] => pure ()
  | c :: cs => do
      let _ ← ext.call_IERC6909Claims_transfer manager c.recipient c.currency c.amount
      flushSpec ext manager cs

/-- Loop invariant: from loop state `(i, false)` with `i ≤ count`, and enough iterations left, the
loop performs the transfers of credits `i, …, count-1` and ends in `(count, true)`. -/
theorem forIn_flush {σ : Type} (ext : Ext σ) (manager : Nat) (credits : List ClaimTransfers.Credit)
    (count : Nat) (hc : count ≤ credits.length)
    (f : Nat → Nat × Bool → M σ (ForInStep (Nat × Bool)))
    (hdone : ∀ x, f x (count, false) = pure (.done (count, true)))
    (hstep : ∀ x i (h : i < count), f x (i, false) =
      (do let _ ← ext.call_IERC6909Claims_transfer manager (credits[i]'(by omega)).recipient
            (credits[i]'(by omega)).currency (credits[i]'(by omega)).amount
          pure (.yield (i + 1, false)))) :
    ∀ (l : List Nat) (i : Nat), i ≤ count → count - i < l.length →
      forIn l (i, false) f =
        (do flushSpec ext manager ((credits.take count).drop i); pure (count, true)) := by
  intro l
  induction l with
  | nil => intro i _ h; simp at h
  | cons x l ih =>
    intro i hi hl
    rw [List.forIn_cons]
    by_cases heq : i = count
    · subst heq
      rw [hdone]
      simp [flushSpec]
    · have hlt : i < count := by omega
      rw [hstep x i hlt]
      have hdrop : (credits.take count).drop i =
          (credits[i]'(by omega)) :: (credits.take count).drop (i + 1) := by
        have hlen : i < (credits.take count).length := by simp; omega
        rw [List.drop_eq_getElem_cons hlen, List.getElem_take]
      rw [hdrop]
      simp only [bind_assoc, pure_bind, flushSpec]
      congr 1
      funext _
      exact ih (i + 1) (by omega) (by simp at hl; omega)

/-- **flush = its spec.** With `count ≤ credits.length` and `count < 2^64`, `flush` makes exactly the
transfers of the first `count` credits, in order, and nothing else. -/
theorem flush_eq {σ : Type} (ext : Ext σ) (batch : ClaimTransfers.Batch) (manager : Nat)
    (hc : batch.count ≤ batch.credits.length) (hb : batch.count < 2 ^ 64) :
    ClaimTransfers.flush ext batch manager =
      flushSpec ext manager (batch.credits.take batch.count) := by
  have hsz : ([:loopBound] : Std.Legacy.Range).size = 2 ^ 64 := by
    simp [Std.Legacy.Range.size, loopBound]
  unfold ClaimTransfers.flush
  simp only [Std.Legacy.Range.forIn_eq_forIn_range', hsz]
  rw [show (default : Nat) = 0 from rfl]
  rw [forIn_flush ext manager batch.credits batch.count hc _ ?hdone ?hstep (List.range' _ _ _) 0
    (Nat.zero_le _) (by simp; omega)]
  case hdone =>
    intro x
    simp
  case hstep =>
    intro x i h
    have hl : i < batch.credits.length := by omega
    have hadd : i + 1 < 2 ^ 256 := by omega
    simp [h, idx, hl, CurrencyLibrary.toId, addc, hadd]
  simp [bind_assoc]

/-- An empty batch makes no call and leaves the world unchanged. -/
theorem flush_empty {σ : Type} (ext : Ext σ) (batch : ClaimTransfers.Batch) (manager : Nat)
    (h0 : batch.count = 0) (env : Env) (w : σ) :
    ClaimTransfers.flush ext batch manager env w = .ok ((), w) := by
  rw [flush_eq ext batch manager (by omega) (by omega), h0]
  rfl

end AsyncSwap.Swarm.ClaimTransfersFlush
