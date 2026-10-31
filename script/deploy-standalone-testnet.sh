#!/usr/bin/env bash
# Bootstrap a self-owned v4 PoolManager, then use the normal hook/Router deployment.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
key="${1:?expected testnet key}"
mode="${2:-dry-run}"
case "$key" in
  megaEthTestnet)
    chain_id=6343
    rpc_env=RPC_URL_MEGAETH_TESTNET
    public_rpc=https://carrot.megaeth.com/rpc
    ;;
  hyperEvmTestnet)
    chain_id=998
    rpc_env=RPC_URL_HYPEREVM_TESTNET
    public_rpc=https://rpc.hyperliquid-testnet.xyz/evm
    ;;
  *) echo "Unsupported standalone testnet: $key" >&2; exit 2 ;;
esac

if [[ -f "$ROOT_DIR/.env.deploy" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env.deploy"
  set +a
fi
RPC_URL="${!rpc_env:-$public_rpc}"
export RPC_URL
printf -v "$rpc_env" '%s' "$RPC_URL"
export "$rpc_env"
[[ "$(cast chain-id --rpc-url "$RPC_URL")" == "$chain_id" ]] || {
  echo "RPC chain ID does not match $chain_id" >&2; exit 1;
}
read -r numeraire expected_decimals <<< "$(python3 - "$ROOT_DIR/script/config/chains.json" "$key" <<'PY'
import json, sys
chain = json.load(open(sys.argv[1]))['chains'][sys.argv[2]]
print(chain['contracts']['usdc'], 18 if chain['chainId'] == 6343 else 6)
PY
)"
[[ "$(cast code "$numeraire" --rpc-url "$RPC_URL")" != 0x ]] || {
  echo "Configured numeraire has no code on $key" >&2; exit 1;
}
[[ "$(cast call "$numeraire" 'decimals()(uint8)' --rpc-url "$RPC_URL")" == "$expected_decimals" ]] || {
  echo "Configured numeraire decimals differ from $expected_decimals on $key" >&2; exit 1;
}
for dependency in 0x000000000022D473030F116dDEE9F6B43aC78BA3 0x4e59b44847b379578588920cA78FbF26c0B4956C; do
  [[ "$(cast code "$dependency" --rpc-url "$RPC_URL")" != 0x ]] || {
    echo "Required dependency $dependency has no code on $key" >&2; exit 1;
  }
done

registry="$ROOT_DIR/deployments/$chain_id/$chain_id.json"
manager="$(python3 - "$registry" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
print(json.loads(p.read_text()).get('contracts', {}).get('PoolManager', {}).get('address', '') if p.exists() else '')
PY
)"
if [[ "$key" == hyperEvmTestnet && "$mode" == broadcast ]]; then
  : "${DEPLOYER_ACCOUNT:?Set DEPLOYER_ACCOUNT in .env.deploy}"
  signer="$(cast wallet address --account "$DEPLOYER_ACCOUNT")"
  # HyperEVM fast blocks cap at 3M gas; PoolManager's runtime code deposit alone exceeds that.
  # Big-block routing is an account-level HyperCore setting, not an EVM tx flag.
  using_big_blocks="$(cast rpc eth_usingBigBlocks "$signer" --rpc-url "$RPC_URL")"
  [[ "$using_big_blocks" == true ]] || {
    echo "HyperEVM deployer $signer is not using big blocks. Enable HyperCore evmUserModify usingBigBlocks=true before broadcasting: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm/dual-block-architecture" >&2
    exit 1
  }
fi
if [[ -z "$manager" ]]; then
  if [[ "$mode" != broadcast ]]; then
    echo "No PoolManager is deployed on $key; run this wrapper in broadcast mode after funding the deployer." >&2
    exit 2
  fi
  : "${DEPLOYER_ACCOUNT:?Set DEPLOYER_ACCOUNT in .env.deploy}"
  : "${DEPLOY_OWNER:?Set DEPLOY_OWNER to the Olive signer address in .env.deploy}"
  signer="$(cast wallet address --account "$DEPLOYER_ACCOUNT")"
  [[ "$(printf '%s' "$signer" | tr '[:upper:]' '[:lower:]')" == "$(printf '%s' "$DEPLOY_OWNER" | tr '[:upper:]' '[:lower:]')" ]] || {
    echo "DEPLOY_OWNER must equal the signer address for the PoolManager and Router broadcasts" >&2; exit 1;
  }
  echo "Deploying a PoolManager on $key from $DEPLOY_OWNER"
  (cd "$ROOT_DIR" && forge script script/00_DeployPoolManager.s.sol \
    --rpc-url "$RPC_URL" --sender "$DEPLOY_OWNER" --broadcast --account "$DEPLOYER_ACCOUNT")
  manager="$(python3 - "$registry" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))['contracts']['PoolManager']['address'])
PY
)"
  python3 "$ROOT_DIR/script/sync-poolmanager-receipt.py" \
    --chain-id "$chain_id" --registry "$registry" \
    --broadcast "$ROOT_DIR/broadcast/00_DeployPoolManager.s.sol/$chain_id/run-latest.json"
fi
manager_code=0x
for _ in 1 2 3 4 5 6 7 8 9 10; do
  manager_code="$(cast code "$manager" --rpc-url "$RPC_URL")"
  [[ "$manager_code" != 0x ]] && break
  sleep 2
done
[[ "$manager_code" != 0x ]] || {
  echo "PoolManager has no code at $manager on $key" >&2; exit 1;
}

# The normal deployment wrapper validates this address against live code. Record it only after that
# check succeeds, so a failed bootstrap never leaves the config falsely marked prepared.
python3 - "$ROOT_DIR/script/config/chains.json" "$key" "$manager" <<'PY'
import json, os, sys, tempfile
path, key, manager = sys.argv[1:]
with open(path, encoding='utf-8') as f:
    source = f.read()
config = json.loads(source)
chain = config['chains'][key]
if chain['contracts']['poolManager'] not in (None, manager):
    raise SystemExit('Configured PoolManager differs from the on-chain registry')
start = source.index(f'    "{key}": {{')
end = source.find('\n    "', start + 1)
if end < 0: end = len(source)
section = source[start:end]
section = section.replace('"poolManager": null', f'"poolManager": "{manager}"', 1)
section = section.replace('"status": "config_only"', '"status": "prepared"', 1)
updated = source[:start] + section + source[end:]
if json.loads(updated)['chains'][key]['contracts']['poolManager'] != manager:
    raise SystemExit('Could not update PoolManager config')
fd, tmp = tempfile.mkstemp(prefix='.chains-', dir=os.path.dirname(path))
try:
    with os.fdopen(fd, 'w', encoding='utf-8') as f:
        f.write(updated)
    os.replace(tmp, path)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
PY

exec "$ROOT_DIR/script/deploy.sh" "$key" "$mode"
