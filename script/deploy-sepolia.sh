#!/usr/bin/env bash
# Ethereum Sepolia (11155111). Thin wrapper over the chain-agnostic script/deploy.sh.
set -euo pipefail
exec "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/deploy.sh" sepolia "$@"
