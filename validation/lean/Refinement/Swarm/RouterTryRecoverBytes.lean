import Generated.Router
open FormalAst

/-!
# `ECDSA.tryRecover(hash, bytes signature)` in Router (def `tryRecover_5936`; `_5961` in the
regenerated model)

It never reverts on a bad length: any length other than 65 returns
`(0, 2 = InvalidSignatureLength, length)` with the state unchanged. A 65-byte signature is
exactly the 4-argument `tryRecover` on the decoded `v` (the first byte of the third word),
`r` and `s`.
-/

namespace Router.Swarm.Overloads
open Router
variable {σ : Type} (ext : Ext σ)

theorem tryRecoverBytes_bad_length (hash : Nat) (sig : List Nat) (env : Env) (st : σ)
    (h : sig.length ≠ 65) :
    ECDSA.tryRecover_5936 ext hash sig env st = Except.ok ((0, 2, sig.length), st) := by
  unfold ECDSA.tryRecover_5936
  have hb : (sig.length == 65) = false := by simpa using h
  simp [hb, pure, ReaderT.pure, StateT.pure, Except.pure]

theorem tryRecoverBytes_len65 (hash : Nat) (sig : List Nat) (env : Env) (st : σ)
    (h : sig.length = 65) :
    ECDSA.tryRecover_5936 ext hash sig env st =
      ECDSA.tryRecover ext hash ((ybyte 0 (bytesWordAt sig (0x60 - 32))) % 2 ^ 8)
        (bytesWordAt sig (0x20 - 32)) (bytesWordAt sig (0x40 - 32)) env st := by
  unfold ECDSA.tryRecover_5936
  simp [h]

end Router.Swarm.Overloads
