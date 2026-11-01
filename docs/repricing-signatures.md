# Signed price changes

```
UpdatePrice(address maker,address tokenIn,address tokenOut,uint256 amountIn,uint256 newAmountOutMin,bytes32 orderId,uint64 createdSequence,uint32 reprices,uint256 nonce,uint256 deadline)
CancelOrder(address maker,address tokenIn,address tokenOut,bytes32 orderId,uint64 createdSequence,uint256 nonce,uint256 deadline)
```

A signed price change identifies one order with `orderId` and `uint64 createdSequence`
(`orderCreatedSequence(poolId, orderId)`), and one price version of it with `uint32 reprices`
(`orderReprices(poolId, orderId)`), the number of times it has been repriced. `amountIn` is the order's
input when signed; the relayer passes it to `updatePriceWithSig(order, amountIn, newAmountOutMin, nonce,
deadline, signature)`.

Every reprice, direct or signed, increments `reprices`, so a reprice signature the maker never relayed
cannot undo a later reprice. Matches do not move it: if partial matches shrink the order before the reprice
lands, the signed `amountIn` and `newAmountOutMin` are applied as a price to the remainder, with the minimum
rounded up, instead of the signature failing (L-01 in
[the 2026-11-01 review](../audit/lsp_security_review_2026-11-01.md)). A live input larger than the signed
one is rejected. Cancelling and recreating an identical order gives it a new `createdSequence`, so an unused
signature for the cancelled order cannot change the replacement.

Signed cancels bind `createdSequence` but not the order's size: a cancel covers whatever remains.

Earlier versions bound the order's queue `sequence` (which a partial match can also move) and, before that,
`createdSequence` alone; signatures of either kind must be signed again. The original incarnation fix is
described below.

Regression tests reproduce the vulnerability before the fix in Solidity, native Huff, and Python.
After the fix, they check that the old signature is rejected, the replacement minimum and unused nonce
are preserved, and a fresh signature successfully reprices the replacement using that nonce.

Validation: 860 Solidity tests, 238 current Huff tests, and 43 Python model tests passed. Both Foundry
suites skipped one RPC-dependent fork test. Shared stateful/matching/hash vectors passed on both
implementations. Historical Huff storage-specific fixtures remain excluded from its current suite.
The regenerated Lean models build; the added refinement lemmas check the encoder and distinct
creation-sequence preimages, without claiming unconditional hash or signature security.

[Logs and source fingerprints](../audit/validation/reprice-incarnation-2026-10-24/results.json).
