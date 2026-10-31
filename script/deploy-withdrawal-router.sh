#!/usr/bin/env bash
# Deploy only the updated Router; preserve the hook and its original creation Router.
set -euo pipefail
cd "$(dirname "$0")/.."
chain_key="${1:?Pass a chain key from script/config/chains.json}"
mode="${2:-dry-run}"
[[ "$mode" == dry-run || "$mode" == broadcast ]] || exit 2
set -a
source .env.deploy
set +a
read -r chain_id rpc_env < <(python3 - "$chain_key" <<'PY'
import json,sys
c=json.load(open('script/config/chains.json'))['chains'][sys.argv[1]]
print(c['chainId'],c['rpcUrlEnv'])
PY
)
rpc_url="${!rpc_env}"
# Sepolia charges more deployment gas than the local simulation estimates.
gas_multiplier=150
[[ "$chain_id" != 11155111 ]] || gas_multiplier=300
args=(script/DeployWithdrawalRouter.s.sol:DeployWithdrawalRouter --rpc-url "$rpc_url" --gas-estimate-multiplier "$gas_multiplier")
if [[ "$mode" == broadcast ]]; then args+=(--broadcast --account "$DEPLOYER_ACCOUNT"); fi
forge script "${args[@]}"
if [[ "$mode" == broadcast ]]; then
python3 - "$chain_id" <<'PY'
import json,sys,time
from pathlib import Path
id=sys.argv[1]
b=json.loads(Path(f'broadcast/DeployWithdrawalRouter.s.sol/{id}/run-latest.json').read_text())
txs=[t for t in b['transactions'] if t.get('contractName')=='Router' and t.get('transactionType')=='CREATE']
assert len(txs)==1, 'Expected one Router deployment'
tx=txs[0]; address=tx['contractAddress']
r=next(r for r in b['receipts'] if r['transactionHash'].lower()==tx['hash'].lower())
assert int(str(r['status']),16)==1, 'Deployment reverted'
p=Path(f'deployments/{id}/{id}.json');d=json.loads(p.read_text())
d['contracts']['WithdrawalRouter']={'address':address,'startBlock':int(str(r['blockNumber']),16),'txHash':r['transactionHash']}
d['updatedAt']=int(time.time())
p.write_text(json.dumps(d,indent=2)+'\n')
print(f'WithdrawalRouter {id}: {address}')
PY
fi
