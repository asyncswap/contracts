#!/usr/bin/env bash
set -euo pipefail

# Local-only Anvil stress test. Never targets a configured or remote RPC.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${STRESS_PORT:-18546}"
RPC_URL="http://127.0.0.1:${PORT}"
ACCOUNT="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
TMP_DIR="$(mktemp -d)"
ANVIL_PID=""

cleanup() {
  if [[ -n "$ANVIL_PID" ]]; then kill "$ANVIL_PID" 2>/dev/null || true; fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

for tool in anvil forge cast python3; do
  command -v "$tool" >/dev/null || { echo "Missing required command: $tool" >&2; exit 1; }
done

python3 - "$PORT" <<'PY'
import socket, sys
with socket.socket() as sock:
    if sock.connect_ex(("127.0.0.1", int(sys.argv[1]))) == 0:
        raise SystemExit("Stress port is in use; choose another STRESS_PORT")
PY

anvil --host 127.0.0.1 --port "$PORT" --gas-limit 30000000 --silent >"$TMP_DIR/anvil.log" 2>&1 &
ANVIL_PID=$!
for _ in $(seq 1 50); do
  if cast chain-id --rpc-url "$RPC_URL" >/dev/null 2>&1; then break; fi
  if ! kill -0 "$ANVIL_PID" 2>/dev/null; then cat "$TMP_DIR/anvil.log" >&2; exit 1; fi
  sleep 0.2
done
[[ "$(cast chain-id --rpc-url "$RPC_URL")" == "31337" ]] || { echo "Expected local Anvil chain 31337" >&2; exit 1; }

DEPLOY_OUTPUT="$(cd "$ROOT_DIR" && forge create src/MatchingEngine.sol:MatchingEngine --rpc-url "$RPC_URL" --unlocked --from "$ACCOUNT" --broadcast)"
printf '%s\n' "$DEPLOY_OUTPUT" | sed -n '1,4p'
ENGINE="$(printf '%s\n' "$DEPLOY_OUTPUT" | awk '/Deployed to:/ {print $3}')"
[[ -n "$ENGINE" ]] || { echo "Could not parse deployed address" >&2; exit 1; }
cast rpc anvil_setAutomine false --rpc-url "$RPC_URL" >/dev/null

send_order() {
  cast send --async --rpc-url "$RPC_URL" --unlocked --from "$ACCOUNT" --nonce "$1" --gas-limit 1000000 \
    "$ENGINE" 'placeOrder(bytes32,bool,uint128,uint128)' "$2" "$3" "$4" "$5" >/dev/null
}

report_block() {
  cast rpc anvil_mine 1 --rpc-url "$RPC_URL" >/dev/null
  python3 - "$RPC_URL" "$(cast block-number --rpc-url "$RPC_URL")" <<'PY'
import json, sys, urllib.request
url, number = sys.argv[1], int(sys.argv[2])
def rpc(method, params):
    data=json.dumps({"jsonrpc":"2.0","id":1,"method":method,"params":params}).encode()
    req=urllib.request.Request(url,data=data,headers={"Content-Type":"application/json"})
    return json.loads(urllib.request.urlopen(req).read())["result"]
block=rpc("eth_getBlockByNumber",[hex(number),True])
gas=[int(rpc("eth_getTransactionReceipt",[tx["hash"]])["gasUsed"],16) for tx in block["transactions"]]
limit,used=int(block["gasLimit"],16),int(block["gasUsed"],16)
if not gas:
    print(f"block {number}: 0 txs, {used:,}/{limit:,} gas (empty)")
    raise SystemExit
print(f"block {number}: {len(gas)} txs, {used:,}/{limit:,} gas ({used/limit*100:.2f}%), avg {sum(gas)//len(gas):,}, max {max(gas):,}")
PY
}

echo "100 transactions with ordinary distinct prices"
market=0x1111111111111111111111111111111111111111111111111111111111111111
for i in $(seq 0 99); do send_order "$((i + 1))" "$market" false 1000000000000000000 "$((1000000000000000000 + i * 1000000000000))"; done
report_block

echo "100 adversarial high-bit prices; queued transactions continue next block if needed"
market=0x2222222222222222222222222222222222222222222222222222222222222222
python3 - <<'PY' >"$TMP_DIR/prices.txt"
for i in range(100): print(2 ** (127 - i))
PY
nonce=101
while IFS= read -r price; do send_order "$nonce" "$market" false 1000000000000000000 "$price"; nonce=$((nonce + 1)); done < "$TMP_DIR/prices.txt"
report_block
report_block

echo "Seed eight blocks of asks, then stress 100 transactions at eight fills each"
market=0x3333333333333333333333333333333333333333333333333333333333333333
nonce=201
for _ in $(seq 0 7); do
  for _ in $(seq 0 99); do send_order "$nonce" "$market" false 1000000000000000000 2000000000000000000; nonce=$((nonce + 1)); done
  report_block
done
for _ in $(seq 0 99); do send_order "$nonce" "$market" true 8000000000000000000 2000000000000000000; nonce=$((nonce + 1)); done
report_block
