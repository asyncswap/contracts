import Specs.AsyncSwap
import Proofs.Monad

open FormalAst Refinement

namespace AsyncSwap
namespace Refinement.Swarm.AsyncSwapPoolBeatsBook

/-- The generated definition is exactly the computation consisting of pool-id
resolution, side-dependent book search, the no-book/no-liquidity early return,
and the strict pool-versus-book comparison. -/
theorem poolBeatsBook_def {σ : Type} (ext : Ext σ) (key : PoolKey) (isBuy : Bool) :
    AsyncSwap.«_poolBeatsBook» ext key isBuy =
      (do
        let __t1 ← PoolIdLibrary.toId ext key
        let mut poolId : Nat := __t1
        let mut __t4 : (Bool × Nat) := default
        if isBuy then
          let __t2 ← RadixPriceTree.best ext (do return (((ext.get (← get)).priceBooks poolId)).asks) (fun x => modify fun w => ext.set w (let s := ext.get w; { s with priceBooks := upd (s.priceBooks) poolId ({ ((s.priceBooks poolId)) with asks := x }) })) false
          __t4 := __t2
        else
          let __t3 ← RadixPriceTree.best ext (do return (((ext.get (← get)).priceBooks poolId)).bids) (fun x => modify fun w => ext.set w (let s := ext.get w; { s with priceBooks := upd (s.priceBooks) poolId ({ ((s.priceBooks poolId)) with bids := x }) })) true
          __t4 := __t3
        let mut found : Bool := __t4.1
        let mut bookKey : Nat := __t4.2
        let mut __t6 : Bool := (!found)
        if !__t6 then
          let __t5 ← StateLibrary.getLiquidity ext ext.poolManager poolId
          __t6 := (__t5 == 0)
        if __t6 then
          return false
        let __t7 ← StateLibrary.getSlot0 ext ext.poolManager poolId
        let mut tick : Int := __t7.2.1
        let mut __t12 : Nat := default
        if (((key).currency1) == ext.numeraire) then
          let __t8 ← subcI 24 tick TickMath.MIN_TICK
          let __t9 ← addc 128 (toUnsigned 24 __t8) 1
          __t12 := __t9
        else
          let __t10 ← subcI 24 TickMath.MAX_TICK tick
          let __t11 ← addc 128 (toUnsigned 24 __t10) 1
          __t12 := __t11
        let mut poolKey : Nat := __t12
        return (if isBuy then (decide (poolKey < bookKey))
          else (decide (poolKey > bookKey)))) := by
  rfl

end Refinement.Swarm.AsyncSwapPoolBeatsBook
end AsyncSwap
