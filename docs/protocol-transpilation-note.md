# Future bytecode reverse-engineering project

Decision updated October 24, 2026. Deferred until a new request to begin work.

EVM bytecode is the source of truth. Reverse engineer it into a shared semantic model in Lean,
then generate executable Python and other language representations from that model.

The goal is to preserve observable execution behavior, including storage, arithmetic, external
calls, events, reverts, and transaction rollback. Recovering the original source, variable names,
or formatting is secondary. Solidity and Huff are authoring languages; their ASTs and source maps
may help recover readable structure and provenance, but cannot override the bytecode.

The canonical execution context must identify the EVM revision, linked runtime bytecode,
constructor inputs and resulting initial state, addresses, and external-contract behavior.
Distinguish creation bytecode from deployed runtime bytecode.

Build support incrementally and reject unsupported constructs explicitly. Record unresolved
external behavior as assumptions, not translated or proven behavior. Validate generated language
representations against execution of the canonical bytecode using shared traces and an independent
oracle. Generated agreement alone cannot detect a mistake shared by the reverse-engineering or
translation pipeline.

Use the same conformance checks for the Solidity and `v2-raff` Huff implementations when bringing
them into sync. AST or ABI agreement alone does not establish behavioral equivalence.

No implementation work is scheduled or authorized by this note; revisit the design later.
