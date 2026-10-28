import Specs.AsyncSwap
import Proofs.Monad

open FormalAst

namespace AsyncSwap

variable {σ : Type} (ext : Ext σ)

def receivePost (r : Env) (s : σ) : σ :=
  ext.set s { ext.get s with
    «transient» := upd (ext.get s).«transient» AsyncSwap.PENDING_NATIVE_DEPOSIT_SLOT
      (yadd ((ext.get s).«transient» AsyncSwap.PENDING_NATIVE_DEPOSIT_SLOT) r.value) }

theorem receive_run (r : Env) (s : σ) :
    AsyncSwap.«_2198» ext r s = .ok ((), receivePost ext r s) := by
  unfold AsyncSwap.«_2198» receivePost
  rfl

theorem receive_never_reverts (r : Env) (s : σ) (e : Revert) :
    AsyncSwap.«_2198» ext r s ≠ .error e := by
  rw [receive_run]
  simp

theorem receive_pending (r : Env) (s s' : σ) (u : Unit)
    (hget : ∀ w st, ext.get (ext.set w st) = st)
    (hok : AsyncSwap.«_2198» ext r s = .ok (u, s')) :
    (ext.get s').«transient» AsyncSwap.PENDING_NATIVE_DEPOSIT_SLOT =
      ((ext.get s).«transient» AsyncSwap.PENDING_NATIVE_DEPOSIT_SLOT + r.value) % 2 ^ 256 := by
  rw [receive_run] at hok
  cases hok
  simp [receivePost, hget, upd_same, yadd, W]

theorem receive_other_transient (r : Env) (s s' : σ) (u : Unit) (k : Nat)
    (hget : ∀ w st, ext.get (ext.set w st) = st)
    (hok : AsyncSwap.«_2198» ext r s = .ok (u, s'))
    (hk : k ≠ AsyncSwap.PENDING_NATIVE_DEPOSIT_SLOT) :
    (ext.get s').«transient» k = (ext.get s).«transient» k := by
  rw [receive_run] at hok
  cases hok
  simp [receivePost, hget, upd_other _ _ _ _ hk]

end AsyncSwap
