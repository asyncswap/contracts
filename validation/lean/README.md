# Current generated models and focused refinements

Run `lake build` here with the pinned Lean toolchain and dependency manifest. Generated models
cover the hook, Router, claim redeemers, and FeeVault. Refinements check selected properties;
opaque calls and cryptographic assumptions remain explicit. This is not a full protocol proof.

`Refinement/Repricing.lean` checks that the generated signed-repricing encoder includes creation
sequence and that distinct creation sequences produce distinct encoded preimages. Runtime replay
rejection is also tested in Solidity, native Huff, and Python.

To regenerate, set `FORMALMIND` to the FormalMind 0.1.1 executable and run `./generate.sh`.
The checked-in generated files permit builds without that generator. Regeneration may rename
opaque-call identifiers, requiring corresponding updates to the refinement references.
