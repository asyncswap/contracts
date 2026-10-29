#!/usr/bin/env bash
# Local development stack: an anvil chain with the current contracts and a funded USDC/asset market.
#
#   script/local/up.sh [wallet,wallet,...]    start anvil if needed, deploy, print the app's env lines
#   script/local/up.sh smoke                   a 1,000 USDC market buy from anvil account 1
#   script/local/up.sh down                    stop the anvil this script started
#
# Chain 31337 at http://127.0.0.1:18547 (what the app's "Anvil Local" chain expects). Mock USDC (6
# decimals) is the numeraire; the asset is a mock 18-decimal token priced at START_PRICE USDC. Each
# wallet passed in gets 1,000,000 USDC, 1,000 asset and 10 ETH. Nothing here touches a real chain.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE="$ROOT/.local"
PORT="${PORT:-18547}"
RPC="http://127.0.0.1:$PORT"
# anvil's first default account: public test key, owns the hook locally (FFIHelper.OWNER_ANVIL).
PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
OWNER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
CREATE2_DEPLOYER=0x4e59b44847b379578588920cA78FbF26c0B4956C
PERMIT2=0x000000000022D473030F116dDEE9F6B43aC78BA3
START_PRICE="${START_PRICE:-2500}"
mkdir -p "$STATE"

if [[ "${1:-}" == "down" ]]; then
  [[ -f "$STATE/anvil.pid" ]] && kill "$(cat "$STATE/anvil.pid")" 2>/dev/null && echo "anvil stopped."
  rm -f "$STATE/anvil.pid"
  exit 0
fi
if [[ "${1:-}" == "smoke" ]]; then
  # shellcheck disable=SC1091
  source "$STATE/addresses.env"
  cd "$ROOT"
  POOL_MANAGER="$POOL_MANAGER" HOOK="$HOOK" ROUTER="$ROUTER" USDC="$USDC" ASSET="$ASSET" forge script \
    script/local/Smoke.s.sol --rpc-url "$RPC" --broadcast --slow --disable-code-size-limit \
    --private-key 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d | grep -E "pool|asset|ONCHAIN"
  exit 0
fi
# Anvil account 1 always gets funds too: it's the wallet `up.sh smoke` trades from.
SMOKE_WALLET=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
FUND="${1:+$1,}$SMOKE_WALLET"

if ! cast chain-id --rpc-url "$RPC" >/dev/null 2>&1; then
  echo "Starting anvil on $RPC (log: $STATE/anvil.log)..."
  # The PoolManager built from dependencies is over EIP-170 (Uniswap ships an optimized build); local only.
  nohup anvil --port "$PORT" --chain-id 31337 --disable-code-size-limit >"$STATE/anvil.log" 2>&1 &
  echo $! >"$STATE/anvil.pid"
  until cast chain-id --rpc-url "$RPC" >/dev/null 2>&1; do sleep 0.3; done
fi
[[ "$(cast chain-id --rpc-url "$RPC")" == 31337 ]] || { echo "Refusing: $RPC is not chain 31337." >&2; exit 1; }
cd "$ROOT"
rm -rf "$ROOT/deployments/31337"

# Permit2 at its canonical address, from the runtime the tests already use.
permit2_code="0x$(python3 -c 'import re,sys; print(re.search(r"hex\"([0-9a-f]+)\"", open(sys.argv[1]).read()).group(1))' test/utils/Permit2Bytecode.sol)"
cast rpc anvil_setCode "$PERMIT2" "$permit2_code" --rpc-url "$RPC" >/dev/null

# --constructor-args takes every argument after it, so it goes last.
create() { forge create "$1" --rpc-url "$RPC" --private-key "$PK" --broadcast --constructor-args "${@:2}" | awk '/Deployed to:/ {print $3}'; }
USDC="$(create test/utils/MockERC20.sol:MockERC20 "USD Coin" USDC 6)"
ASSET="$(create test/utils/MockERC20.sol:MockERC20 "Test Ether" tETH 18)"
[[ -n "$USDC" && -n "$ASSET" ]] || { echo "Mock token deployment failed." >&2; exit 1; }

script() { forge script "$@" --rpc-url "$RPC" --private-key "$PK" --sender "$OWNER" --broadcast --slow --disable-code-size-limit >"$STATE/last-script.log" 2>&1 || { cat "$STATE/last-script.log" >&2; exit 1; }; }
addr() { cast create2 --deployer "$CREATE2_DEPLOYER" --salt "$(cast keccak "$1")" --init-code-hash "$(cast keccak "$2")" | awk '/Address:/ {print $2} /^0x/ {print $1}' | tail -1; }

echo "Deploying PoolManager and libraries..."
script script/00_DeployPoolManager.s.sol
tick_addr="$(addr asyncswap.v2.TickPrice "$(forge inspect src/libraries/TickPrice.sol:TickPrice bytecode)")"
tick_flag="src/libraries/TickPrice.sol:TickPrice:$tick_addr"
ordering_addr="$(addr asyncswap.v2.DynamicFeeOrdering "$(forge inspect src/libraries/DynamicFeeOrdering.sol:DynamicFeeOrdering bytecode)")"
ordering_flag="src/libraries/DynamicFeeOrdering.sol:DynamicFeeOrdering:$ordering_addr"
lib_addr="$(addr asyncswap.v2.AsyncMatching "$(forge inspect src/libraries/AsyncMatching.sol:AsyncMatching bytecode --libraries "$tick_flag" --libraries "$ordering_flag")")"
script script/00_DeployTickPrice.s.sol
script script/00_DeployDynamicFeeOrdering.s.sol
script script/00_DeployMatchingLibrary.s.sol --libraries "$tick_flag" --libraries "$ordering_flag"

echo "Deploying the hook and Router (mining the hook salt)..."
DEPLOY_NUMERAIRE_ADDRESS="$USDC" script script/01_DeployHook.s.sol --ffi \
  --libraries "src/libraries/AsyncMatching.sol:AsyncMatching:$lib_addr" --libraries "$tick_flag" --libraries "$ordering_flag"
registry="$ROOT/deployments/31337/31337.json"
HOOK="$(jq -r '.contracts.AsyncSwap.address' "$registry")"
ROUTER="$(jq -r '.contracts.Router.address' "$registry")"
POOL_MANAGER="$(jq -r '.contracts.PoolManager.address' "$registry")"

# Tick for START_PRICE USDC per asset; v4 prices currency1 in currency0, in base units.
INIT_TICK="$(python3 - "$USDC" "$ASSET" "$START_PRICE" <<'PY'
import math, sys
usdc, asset, price = sys.argv[1].lower(), sys.argv[2].lower(), float(sys.argv[3])
raw = price * 10**6 / 10**18          # USDC base units per asset base unit
if int(usdc, 16) < int(asset, 16):    # USDC is currency0: price is asset per USDC
    raw = 1 / raw
print(int(math.floor(math.log(raw) / math.log(1.0001))))
PY
)"

echo "Initializing the USDC/tETH market at $START_PRICE USDC..."
POOL_MANAGER="$POOL_MANAGER" HOOK="$HOOK" USDC="$USDC" ASSET="$ASSET" INIT_TICK="$INIT_TICK" FUND="$FUND" \
  LIQUIDITY="${LIQUIDITY:-50000000000000000}" script script/local/LocalMarket.s.sol

cat >"$STATE/addresses.env" <<EOF
POOL_MANAGER=$POOL_MANAGER
HOOK=$HOOK
ROUTER=$ROUTER
USDC=$USDC
ASSET=$ASSET
EOF
cat >"$STATE/app.env" <<EOF
VITE_ASYNCSWAP_HOOK_31337=$HOOK
VITE_ASYNCSWAP_ROUTER_31337=$ROUTER
EOF
cat <<EOF

Local stack is up on $RPC (chain 31337).
  PoolManager  $POOL_MANAGER
  AsyncSwap    $HOOK
  Router       $ROUTER
  USDC         $USDC
  tETH         $ASSET
App env (also in .local/app.env):
$(cat "$STATE/app.env")
Owner/test key: anvil account 0 ($OWNER). Smoke test: script/local/up.sh smoke. Stop: script/local/up.sh down
EOF
