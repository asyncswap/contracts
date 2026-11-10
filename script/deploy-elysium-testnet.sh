#!/usr/bin/env bash
# Elysium Testnet (99801). An Arbitrum Orbit L2 settling to HyperEVM testnet; gas is HYPE.
# There is no canonical Uniswap v4 PoolManager on testnet: deploy script/00_DeployPoolManager.s.sol
# first and point script/config/chains.json at the address it records. Thin wrapper over deploy.sh.
set -euo pipefail
exec "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/deploy.sh" elysiumTestnet "$@"
