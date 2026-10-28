import Specs.AsyncSwap
import Proofs.Monad

open FormalAst Refinement

namespace AsyncSwap
namespace Refinement.Swarm.AsyncSwapPayFiller

theorem payFiller_setter_irrelevant {σ : Type} (ext : Ext σ)
    (get : M σ AsyncFiller.State_)
    (set₁ set₂ : AsyncFiller.State_ → M σ Unit)
    (id input hook filler feeVault amountIn : Nat) :
    AsyncFiller.«_payFiller» ext get set₁ id input hook filler feeVault amountIn =
      AsyncFiller.«_payFiller» ext get set₂ id input hook filler feeVault amountIn := by
  rfl

theorem payFiller_expands {σ : Type} (ext : Ext σ)
    (get : M σ AsyncFiller.State_) (set : AsyncFiller.State_ → M σ Unit)
    (id input hook filler feeVault amountIn : Nat) :
    AsyncFiller.«_payFiller» ext get set id input hook filler feeVault amountIn =
      (do
        let tradeFeeIn ← AsyncFiller.tradeFee ext amountIn
        let st₁ ← get
        CurrencySettler.settle ext input st₁.poolManager hook amountIn true
        let st₂ ← get
        let net ← subc amountIn tradeFeeIn
        let zero ← CurrencyLibrary.isAddressZero ext input
        CurrencySettler.take ext input st₂.poolManager filler net zero
        if tradeFeeIn != 0 then
          let st₃ ← get
          CurrencySettler.take ext input st₃.poolManager feeVault tradeFeeIn true
        pure ()) := by
  rfl

end Refinement.Swarm.AsyncSwapPayFiller
end AsyncSwap
