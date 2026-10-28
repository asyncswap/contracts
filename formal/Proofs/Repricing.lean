import Specs.AsyncSwap
import Proofs.Monad
open FormalAst Refinement
namespace AsyncSwap.CurrentRepricing
variable {σ : Type}

/-- The words passed to Keccak by the generated signed-repricing encoder. -/
def message (order : AsyncOrder) (id amount minimum generation nonce deadline : Nat) : List Nat :=
  [OrderSignatures.UPDATE_PRICE_TYPEHASH, order.owner,
   if order.zeroForOne then order.key.currency0 else order.key.currency1,
   if order.zeroForOne then order.key.currency1 else order.key.currency0,
   amount, minimum, id, generation, nonce, deadline]

/-- The generated implementation hashes creation sequence in its declared EIP-712 position. -/
theorem hash_run (ext : Ext σ) (order : AsyncOrder)
    (id amount minimum generation nonce deadline : Nat) (env : Env) (w : σ) :
    OrderSignatures.hashUpdatePrice ext order id amount minimum generation nonce deadline env w =
    .ok (ext.keccak (message order id amount minimum generation nonce deadline), w) := by
  cases h : order.zeroForOne <;>
    simp [OrderSignatures.hashUpdatePrice, OrderSignatures.tokens, message, h,
      run_bind, run_pure]

/-- Recreating an order with a distinct sequence changes the encoded message even if all other
fields are identical. This is a preimage statement, not an unconditional claim about hash collisions
or signature unforgeability; those cryptographic obligations remain external. -/
theorem replacement_message_distinct (order : AsyncOrder)
    (id amount minimum oldGeneration newGeneration nonce deadline : Nat)
    (h : oldGeneration ≠ newGeneration) :
    message order id amount minimum oldGeneration nonce deadline ≠
    message order id amount minimum newGeneration nonce deadline := by
  simp [message, h]
end AsyncSwap.CurrentRepricing
