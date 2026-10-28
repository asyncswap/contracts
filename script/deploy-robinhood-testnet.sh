#!/usr/bin/env bash
# Robinhood Chain testnet (46630). Gas is ETH. Thin wrapper over the chain-agnostic script/deploy.sh.
set -euo pipefail
exec "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/deploy.sh" robinhoodChainTestnet "$@"
