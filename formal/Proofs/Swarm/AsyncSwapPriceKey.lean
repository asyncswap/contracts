import Specs.AsyncSwap
import Proofs.Monad
import Proofs.Swarm.AsyncSwapKey
open FormalAst Refinement

/-!
# `AsyncFiller._priceKey` (src/AsyncSwap.sol)

`_priceKey` is `do let k ← TickPrice.key …; return k`, i.e. `TickPrice.key` itself (monad right
identity). Its specification is therefore that of `key` (`AsyncSwapKey.lean`):

* `priceKey_eq`: `_priceKey` and `TickPrice.key` agree on every environment and state.
* `priceKey_spec`: with denominator `d = if zeroForOne then amountIn else amountOut`, either `d = 0`
  and `_priceKey` reverts with panic `0x12`, or `d ≠ 0` and it returns `k ∈ [1, 1774545]`
  (`= MAX_TICK - MIN_TICK + 1`) with the state unchanged (no storage writes, no external calls).
* `priceKey_reverts_iff`: `_priceKey` reverts iff `d = 0`.
* `priceKey_ok_inv`: any success leaves the state unchanged, has `d ≠ 0` and a key in range.
-/

namespace AsyncSwap.Swarm.PriceKey

theorem priceKey_eq {σ : Type} (ext : Ext σ) (isBuy zeroForOne : Bool) (amountIn amountOut : Nat)
    (env : Env) (s : σ) :
    AsyncFiller.«_priceKey» ext isBuy zeroForOne amountIn amountOut env s =
      TickPrice.key ext isBuy zeroForOne amountIn amountOut env s := by
  simp only [AsyncFiller.«_priceKey»]

theorem priceKey_spec {σ : Type} (ext : Ext σ) (isBuy zeroForOne : Bool) (amountIn amountOut : Nat)
    (env : Env) (s : σ) :
    ((if zeroForOne then amountIn else amountOut) = 0 ∧
        AsyncFiller.«_priceKey» ext isBuy zeroForOne amountIn amountOut env s =
          .error (panic "0x12")) ∨
    ((if zeroForOne then amountIn else amountOut) ≠ 0 ∧
        ∃ k, AsyncFiller.«_priceKey» ext isBuy zeroForOne amountIn amountOut env s = .ok (k, s) ∧
          1 ≤ k ∧ k ≤ 1774545) := by
  rw [priceKey_eq]
  exact AsyncSwap.Swarm.TickBounds.key_spec ext isBuy zeroForOne amountIn amountOut env s

theorem priceKey_reverts_iff {σ : Type} (ext : Ext σ) (isBuy zeroForOne : Bool)
    (amountIn amountOut : Nat) (env : Env) (s : σ) :
    (∃ e, AsyncFiller.«_priceKey» ext isBuy zeroForOne amountIn amountOut env s = .error e) ↔
      (if zeroForOne then amountIn else amountOut) = 0 := by
  rw [priceKey_eq]
  exact AsyncSwap.Swarm.TickBounds.key_reverts_iff ext isBuy zeroForOne amountIn amountOut env s

theorem priceKey_ok_inv {σ : Type} (ext : Ext σ) (isBuy zeroForOne : Bool)
    (amountIn amountOut : Nat) (env : Env) (s s' : σ) (k : Nat)
    (h : AsyncFiller.«_priceKey» ext isBuy zeroForOne amountIn amountOut env s = .ok (k, s')) :
    s' = s ∧ (if zeroForOne then amountIn else amountOut) ≠ 0 ∧ 1 ≤ k ∧ k ≤ 1774545 := by
  rcases priceKey_spec ext isBuy zeroForOne amountIn amountOut env s with
    ⟨_, he⟩ | ⟨hd, k', hk, k1, k2⟩
  · rw [he] at h; cases h
  · rw [hk] at h; cases h
    exact ⟨rfl, hd, k1, k2⟩

end AsyncSwap.Swarm.PriceKey
