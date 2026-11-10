#!/usr/bin/env bash
# Elysium Testnet (99801) has no canonical Uniswap v4 PoolManager. Deploy an AsyncSwap-owned one
# before running deploy-elysium-testnet.sh; the script records it in deployments/99801/99801.json.
# Run under Olive so the keystore password is released by Touch ID:
#   olive exec new-deployer -- script/deploy-elysium-testnet-poolmanager.sh
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

set -a
# shellcheck disable=SC1091
source "$ROOT_DIR/.env.deploy"
set +a

: "${DEPLOYER_ACCOUNT:?Set DEPLOYER_ACCOUNT in .env.deploy}"
RPC_URL="${RPC_URL_ELYSIUM_TESTNET:-${RPC_URL:?Set RPC_URL_ELYSIUM_TESTNET in .env.deploy}}"

chain_id="$(cast chain-id --rpc-url "$RPC_URL")"
[[ "$chain_id" == "99801" ]] || { echo "Refusing: RPC returned chain ID $chain_id, expected 99801." >&2; exit 1; }

if [[ -z "${DEPLOY_OWNER:-}" ]]; then
  DEPLOY_OWNER="$(cast wallet address --account "$DEPLOYER_ACCOUNT")"
  export DEPLOY_OWNER
fi

forge script "$ROOT_DIR/script/00_DeployPoolManager.s.sol" \
  --rpc-url "$RPC_URL" \
  --sender "$DEPLOY_OWNER" \
  --broadcast \
  --account "$DEPLOYER_ACCOUNT" \
  "$@"
