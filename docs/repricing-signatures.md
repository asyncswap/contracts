# Signed price changes

A signed price change identifies one live order incarnation with `orderId` and `uint64 createdSequence`.
Read the sequence using `orderCreatedSequence(poolId, orderId)` when signing. Include it after `orderId`
in the EIP-712 encoded message, matching the declared `UpdatePrice` type.

Cancelling and recreating an identical order in the same block can reuse the order ID. Its creation
sequence increases, so an unused signature for the cancelled order cannot change the replacement.
Ordinary repricing preserves creation sequence; legitimate same-block repricing remains allowed.
Signatures made using the earlier encoding without creation sequence must be signed again.

Regression tests reproduce the vulnerability before the fix in Solidity, native Huff, and Python.
After the fix, they check that the old signature is rejected, the replacement minimum and unused nonce
are preserved, and a fresh signature successfully reprices the replacement using that nonce.

Validation: 860 Solidity tests, 238 current Huff tests, and 43 Python model tests passed. Both Foundry
suites skipped one RPC-dependent fork test. Shared stateful/matching/hash vectors passed on both
implementations. Historical Huff storage-specific fixtures remain excluded from its current suite.
The regenerated Lean models build; the added refinement lemmas check the encoder and distinct
creation-sequence preimages, without claiming unconditional hash or signature security.

[Logs and source fingerprints](../audit/validation/reprice-incarnation-2026-10-24/results.json).
