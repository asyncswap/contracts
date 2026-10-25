# AuditAgent report 2: resolution

Report: `auditagent_report_2_e73aa801-4ee2-4796-9bf6-5ee08d526d36.md`.

1. **Exact price priority: fixed locally.** Tick levels only partition the book. Within the best
   level, `bestAtPrice` selects the exact minimum ask or maximum bid using subtree extrema;
   the eligibility search breaks equal-exact-price ties by remaining fee and queue age.
   `_bookPair` selects these extrema on both sides. A noncrossing pair of extrema implies
   no pair crosses at that boundary. This also handles saturated end levels without assuming
   their price spread is bounded. Tests cover the report's 10,100/10,800 USDC example and
   worse prices with higher bids and earlier ages *inside the same tick*, on both sides.
2. **Repriced sell bid floor: fixed locally.** Increasing a sell's minimum output requires its
   remaining escrowed fee to meet the new bid floor. Unchanged or reduced terms can retain
   a prorated bid. This includes increases above the cap after a partial fill. Direct and
   signed repricing share the same check; rejection leaves order state unchanged.
3. **Cancellation revocation and replacement replay: fixed locally.** Router cancellation uses
   the hook's maker-scoped nonce store. `invalidateNonce` revokes cancellations as well as
   hook signatures. The cancellation typed data also binds `uint64 createdSequence`, the
   immutable live order incarnation, preventing an unused old signature from cancelling an
   identical replacement. A reverted attempt restores its nonce. This changes the CancelOrder
   typed-data schema; clients must sign the new schema and query `orderCreatedSequence`.

The proof source was deliberately retired in commit `f243b0b`. Historical sources are recovered
at `/Users/meek/developer/asyncswap/contracts-validation-proofs/formal`; current generated models
and focused proofs are under the sibling `current/` folder. Historical whole-protocol invariants
are not claimed for the current contracts. See that project's README for exact proof boundaries.

TickPrice is linked separately to keep the matching library deployable with 43,690 optimizer runs.
The deployment wrapper builds and links TickPrice before AsyncMatching. No broadcast is part of
this validation. Local gas measurements and final validation results are recorded separately.
