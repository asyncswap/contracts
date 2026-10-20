#!/usr/bin/env bash
# Regenerate formal/Generated/*.lean from solc's AST with the `formalmind` CLI (Formal Mind's formal-ast,
# github.com/formalmind/formalmind releases `formalmind-cli-v<version>`; CI pins the version in
# .github/workflows/formal.yml). Run from anywhere; set FORMALMIND if the binary is not on PATH. After regenerating, `lake build` in formal/ re-checks the refinement proofs
# against the new model: a change to a refined function breaks them until they are updated.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
fa="${FORMALMIND:-formalmind}"
cd "$root"
"$fa" --root . src/Router.sol lean formal/Generated/Router.lean --namespace Router
"$fa" --root . src/AsyncSwap.sol lean formal/Generated/AsyncSwap.lean --namespace AsyncSwap
