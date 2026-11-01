#!/usr/bin/env bash
set -euo pipefail
proof_root="$(cd "$(dirname "$0")" && pwd)"
contract_root="${1:-$(cd "$proof_root/.." && pwd)}"
formal_cli="${FORMALMIND:-/tmp/priority-formalmind-0.1.1/formalmind}"
cd "$contract_root"
for entry in AsyncSwap Router TokenClaims NativeClaims FeeVault; do
  "$formal_cli" --root . "src/$entry.sol" lean "$proof_root/Specs/$entry.lean" --namespace "$entry"
done
