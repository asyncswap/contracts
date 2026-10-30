#!/usr/bin/env bash
# Unichain Sepolia (1301). Thin wrapper over the chain-agnostic script/deploy.sh.
set -euo pipefail
exec "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/deploy.sh" unichainSepolia "$@"
