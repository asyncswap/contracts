#!/usr/bin/env bash
# Regenerate formal/Generated/*.lean from solc's AST with Formal Mind's formal-ast
# (github.com/asyncswap/formalmind, crates/formal-ast). Run from anywhere; set FORMAL_AST if the
# binary is not on PATH. After regenerating, `lake build` in formal/ re-checks the refinement proofs
# against the new model: a change to a refined function breaks them until they are updated.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
fa="${FORMAL_AST:-formal-ast}"
cd "$root"
"$fa" --root . src/Router.sol lean formal/Generated/Router.lean --namespace Router
"$fa" --root . src/AsyncSwap.sol lean formal/Generated/AsyncSwap.lean --namespace AsyncSwap
