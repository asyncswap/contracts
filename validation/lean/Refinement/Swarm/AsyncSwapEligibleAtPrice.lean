import Generated.AsyncSwap
import Refinement.Monad

/-!
# Plan item 230: `AsyncFiller.eligibleAtPrice` (blocked on the model)

The model this Lake project builds (`validation/lean/Generated/AsyncSwap.lean:455`) has no
`def AsyncFiller.eligibleAtPrice`: formal-ast left the function opaque as the uninterpreted
field `Ext.fn_AsyncFiller_eligibleAtPrice_6878` ("can't write through Conditional", the
`isBuy ? book.bidLevels[price] : book.askLevels[price]` storage reference). A probe theorem
mentioning `AsyncFiller.eligibleAtPrice` fails with `Unknown identifier`.

Once formal-ast's conditional storage-reference support is written into this model, the
intended theorem is the decomposition, proved by `unfold` and a case split on `found`:

  eligibleAtPrice ext bg bs isBuy price limit
    = do let (found, rank) ← EligiblePrice.best ext (level).priorityOrders … limit isBuy
         if found then return (← level).priorityOrderIds rank else return 0

That is: no guards of its own (every revert is `best`'s), it writes only through `best`'s
setters, and it returns 0 exactly when `best` reports not found.
-/
