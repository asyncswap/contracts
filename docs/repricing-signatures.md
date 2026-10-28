# Signed price changes

A signed price change identifies one live order state with `orderId` and `uint64 sequence`, the order's
current queue sequence. Read it as the `sequence` returned by `orderBookOrder(poolId, orderId)` when
signing, and include it after `orderId` in the EIP-712 encoded message, matching the declared
`UpdatePrice` type.

Every reprice, direct or signed, moves the sequence on, so a reprice signature the maker never relayed
cannot undo a later reprice. Cancelling and recreating an identical order also gives it a new sequence,
so an unused signature for the cancelled order cannot change the replacement. Signatures made with the
earlier `createdSequence` field must be signed again. Signed cancels still bind `createdSequence`
(`orderCreatedSequence(poolId, orderId)`).

The original incarnation fix is described below; binding the queue sequence replaced it for repricing.

Regression tests reproduce the vulnerability before the fix in Solidity, native Huff, and Python.
After the fix, they check that the old signature is rejected, the replacement minimum and unused nonce
are preserved, and a fresh signature successfully reprices the replacement using that nonce.

Validation: 860 Solidity tests, 238 current Huff tests, and 43 Python model tests passed. Both Foundry
suites skipped one RPC-dependent fork test. Shared stateful/matching/hash vectors passed on both
implementations. Historical Huff storage-specific fixtures remain excluded from its current suite.
The regenerated Lean models build; the added refinement lemmas check the encoder and distinct
creation-sequence preimages, without claiming unconditional hash or signature security.

[Logs and source fingerprints](../audit/validation/reprice-incarnation-2026-10-24/results.json).
