#!/usr/bin/env python3
"""Measure released Universal Router, v4 periphery and Permit2 under a fixed block budget."""

import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "benchmarks/universal-router/results"
COUNT, BLOCK_GAS, FUNDS = 500, 30_000_000, 10**30
ASSET, QUOTE = (
    "0x0000000000000000000000000000000000100000",
    "0x0000000000000000000000000000000000200000",
)
OUT.mkdir(parents=True, exist_ok=True)
log = ROOT / ".local/universal-capacity/export.log"
log.parent.mkdir(parents=True, exist_ok=True)
env = dict(
    os.environ,
    FOUNDRY_TEST="benchmarks/universal-router/fixtures",
    FOUNDRY_OUT=".local/universal-capacity/out",
    FOUNDRY_CACHE_PATH=".local/universal-capacity/cache",
)
with log.open("w") as output:
    subprocess.run(
        [
            "forge",
            "test",
            "--match-contract",
            "UniversalCapacityTest",
            "--match-test",
            "test_universal",
            "--no-dynamic-test-linking",
            "--gas-limit",
            "10000000000",
            "-vv",
        ],
        cwd=ROOT,
        env=env,
        stdout=output,
        stderr=subprocess.STDOUT,
        check=True,
    )
export = log.read_text()
permits = dict(re.findall(r"PERMIT\|([^|\s]+)\|(0x[0-9a-fA-F]+)", export))
assert len(permits) == 4
build = json.loads((OUT / "build.json").read_text())
metas = re.findall(r"META\|([^|\s]+)\|([^|\s]+)\|([^|\s]+)\|([^|\s]+)\|(\d+)", export)
assert len(metas) == 4
SWAP = subprocess.check_output(
    [
        "cast",
        "keccak",
        "Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)",
    ],
    text=True,
).strip()
ALLOWANCE = subprocess.check_output(
    ["cast", "sig", "allowance(address,address,address)"], text=True
).strip()
BALANCE = subprocess.check_output(
    ["cast", "sig", "balanceOf(address)"], text=True
).strip()


def signed(word):
    x = int(word, 16)
    return x - 2**256 if x >= 2**255 else x


def measure(meta):
    name, adapter, manager, pool, amount = meta
    amount = int(amount)
    permit = permits[name]
    sell = name.endswith("sell")
    commands = re.findall(
        r"TX\|" + name + r"\|(0x[0-9a-fA-F]+)\|(0x[0-9a-fA-F]+)", export
    )
    assert len(commands) == COUNT
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    url = f"http://127.0.0.1:{port}"
    process = subprocess.Popen(
        [
            "anvil",
            "--host",
            "127.0.0.1",
            "--port",
            str(port),
            "--chain-id",
            "31337",
            "--gas-limit",
            str(BLOCK_GAS),
            "--hardfork",
            "cancun",
            "--base-fee",
            "0",
            "--timestamp",
            "1",
            "--order",
            "fifo",
            "--silent",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )

    def batch(items):
        payload = [
            {"jsonrpc": "2.0", "id": i, "method": m, "params": p}
            for i, (m, p) in enumerate(items)
        ]
        request = urllib.request.Request(
            url,
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"},
        )
        response = json.load(urllib.request.urlopen(request, timeout=120))
        response.sort(key=lambda x: x["id"])
        assert len(response) == len(items) and all(
            "error" not in x for x in response
        ), response
        return [x["result"] for x in response]

    def rpc(method, params=None):
        return batch([(method, params or [])])[0]

    def balance(token, actor):
        return (
            "eth_call",
            [{"to": token, "data": BALANCE + actor[2:].zfill(64)}, "latest"],
        )

    try:
        for _ in range(100):
            assert process.poll() is None, process.stderr.read().decode()
            try:
                assert rpc("eth_chainId") == "0x7a69"
                break
            except OSError:
                time.sleep(0.05)
        else:
            raise RuntimeError("Anvil startup timeout")
        assert "anvil" in rpc("web3_clientVersion").lower()
        fixture = ROOT / f"deployments/universal-capacity-{name}.json"
        state = json.loads(fixture.read_text())
        updates = []
        for address, account in state.items():
            if account["code"] != "0x":
                updates.append(("anvil_setCode", [address, account["code"]]))
            if int(account["balance"], 16):
                updates.append(("anvil_setBalance", [address, account["balance"]]))
            if int(account["nonce"], 16):
                updates.append(("anvil_setNonce", [address, account["nonce"]]))
            updates.extend(
                ("anvil_setStorageAt", [address, slot, value])
                for slot, value in account["storage"].items()
                if int(value, 16)
            )
        for start in range(0, len(updates), 200):
            batch(updates[start : start + 200])
        assert (len(rpc("eth_getCode", [adapter, "latest"])) - 2) // 2 == 23233
        assert (len(rpc("eth_getCode", [permit, "latest"])) - 2) // 2 == 9152
        initial_pool = [
            int(v, 16)
            for v in batch([balance(ASSET, manager), balance(QUOTE, manager)])
        ]
        for actor, _ in commands:
            batch(
                [
                    ("anvil_impersonateAccount", [actor]),
                    ("anvil_setBalance", [actor, hex(10**20)]),
                    ("anvil_setNonce", [actor, "0x0"]),
                ]
            )
        estimate = int(
            rpc(
                "eth_estimateGas",
                [
                    {
                        "from": commands[0][0],
                        "to": adapter,
                        "data": commands[0][1],
                        "gasPrice": "0x0",
                    }
                ],
            ),
            16,
        )
        # Use the identical gas-limit headroom and FIFO admission policy as Async Swap's benchmark.
        gas_limit = ((estimate * 120 + 99) // 100 + 999) // 1000 * 1000
        assert gas_limit < BLOCK_GAS
        rpc("evm_setAutomine", [False])
        rpc("evm_setNextBlockTimestamp", [1000])
        hashes = []
        for actor, data in commands:
            hashes.append(
                rpc(
                    "eth_sendTransaction",
                    [
                        {
                            "from": actor,
                            "to": adapter,
                            "data": data,
                            "nonce": "0x0",
                            "gas": hex(gas_limit),
                            "gasPrice": "0x0",
                        }
                    ],
                )
            )
        blocks = []
        seen = []
        for _ in range(100):
            rpc("evm_mine")
            block = rpc("eth_getBlockByNumber", ["latest", False])
            current = block["transactions"]
            assert current
            assert current == hashes[len(seen) : len(seen) + len(current)]
            receipts = batch([("eth_getTransactionReceipt", [h]) for h in current])
            assert all(r["status"] == "0x1" for r in receipts)
            used = sum(int(r["gasUsed"], 16) for r in receipts)
            assert used == int(block["gasUsed"], 16) <= BLOCK_GAS
            assert int(block["gasLimit"], 16) == BLOCK_GAS
            blocks.append(
                {
                    "number": int(block["number"], 16),
                    "hash": block["hash"],
                    "transactions": len(current),
                    "gasUsed": used,
                    "gasLimit": BLOCK_GAS,
                }
            )
            seen += current
            if len(seen) == COUNT:
                break
        assert seen == hashes and blocks[0]["transactions"] < COUNT, (
            "Queue must saturate the first block"
        )
        receipts = batch([("eth_getTransactionReceipt", [h]) for h in hashes])
        checks = []
        expected = []
        delta = [0, 0]
        outputs = []
        ticks = []
        for (actor, _), receipt in zip(commands, receipts):
            events = [
                e
                for e in receipt["logs"]
                if e["address"].lower() == manager.lower() and e["topics"][0] == SWAP
            ]
            assert len(events) == 1
            event = events[0]
            assert event["topics"][1].lower() == pool.lower()
            assert event["topics"][2][-40:].lower() == adapter[2:].lower()
            words = [
                event["data"][i : i + 64] for i in range(2, len(event["data"]), 64)
            ]
            assert len(words) == 6
            d0, d1 = signed(words[0]), signed(words[1])
            input_delta, output_delta = (d0, d1) if sell else (d1, d0)
            assert input_delta == -amount and output_delta > 0
            assert output_delta >= (990_000_000 if sell else 990_000_000_000_000_000)
            assert int(words[3], 16) == 10**22 and int(words[5], 16) == 3000
            assert (
                (900_000_000 < output_delta < 1_100_000_000)
                if sell
                else (9 * 10**17 < output_delta < 11 * 10**17)
            )
            ticks.append(signed(words[4]))
            outputs.append(output_delta)
            delta[0] += d0
            delta[1] += d1
            checks.extend([balance(ASSET, actor), balance(QUOTE, actor)])
            expected.extend([FUNDS + d0, FUNDS + d1])
        # Exact wallet changes and pool conservation verify real token settlement, beyond emitted event counts.
        for start in range(0, len(checks), 200):
            assert [int(v, 16) for v in batch(checks[start : start + 200])] == expected[
                start : start + 200
            ]
        final_pool = [
            int(v, 16)
            for v in batch([balance(ASSET, manager), balance(QUOTE, manager)])
        ]
        assert final_pool == [initial_pool[i] - delta[i] for i in [0, 1]]
        assert [
            int(v, 16)
            for v in batch([balance(ASSET, adapter), balance(QUOTE, adapter)])
        ] == [0, 0]
        assert min(ticks) > -887220 and max(ticks) < 887220
        allowance_calls = [
            (
                "eth_call",
                [
                    {
                        "to": permit,
                        "data": ALLOWANCE
                        + actor[2:].zfill(64)
                        + (ASSET if sell else QUOTE)[2:].zfill(64)
                        + adapter[2:].zfill(64),
                    },
                    "latest",
                ],
            )
            for actor, _ in commands
        ]
        for start in range(0, len(allowance_calls), 200):
            for value in batch(allowance_calls[start : start + 200]):
                assert int(value[2:66], 16) == (
                    2**160 - 1 if name.startswith("max") else 0
                )
                assert int(value[66:130], 16) == 2**48 - 1 and int(value[130:], 16) == 0
        assert [
            int(v, 16) for v in batch([balance(ASSET, permit), balance(QUOTE, permit)])
        ] == [0, 0]
        gas = [int(r["gasUsed"], 16) for r in receipts]
        row = {
            "workload": name,
            "adapter": "UniversalRouter 2.2.0",
            "permit2Allowance": "unlimited"
            if name.startswith("max")
            else "finite exact input",
            "transactions": COUNT,
            "swaps": COUNT,
            "initialGasEstimate": estimate,
            "transactionGasLimit": gas_limit,
            "firstBlockTransactions": blocks[0]["transactions"],
            "fits100InFirstBlock": blocks[0]["transactions"] >= 100,
            "totalReceiptGas": sum(gas),
            "meanReceiptGas": sum(gas) / COUNT,
            "minReceiptGas": min(gas),
            "maxReceiptGas": max(gas),
            "blocks": blocks,
            "tickRange": [min(ticks), max(ticks)],
            "initializedTicksCrossed": 0,
            "outputRange": [str(min(outputs)), str(max(outputs))],
            "assertions": {
                "allSuccessful": True,
                "exactInput": True,
                "oneSwapPerTransaction": True,
                "walletBalances": True,
                "poolTokenConservation": True,
                "zeroAdapterTokenBalances": True,
                "withinSeededLiquidityRange": True,
                "permit2AllowanceAfter": True,
                "zeroPermit2TokenBalances": True,
                "deadlineAndMinimumOutputGuardsInFixture": True,
            },
            "fixtureSha256": hashlib.sha256(fixture.read_bytes()).hexdigest(),
        }
        archive = {**row, "receipts": receipts}
        (OUT / f"{name}.json.gz").write_bytes(
            gzip.compress(json.dumps(archive, separators=(",", ":")).encode(), mtime=0)
        )
        print(
            name,
            "first block",
            blocks[0]["transactions"],
            "mean gas",
            sum(gas) / COUNT,
            "blocks",
            len(blocks),
            flush=True,
        )
        return row
    finally:
        process.terminate()
        process.wait(timeout=10)


rows = [measure(m) for m in sorted(metas)]
core = ROOT / "dependencies/v4-core"
summary = {
    "blockGasLimit": BLOCK_GAS,
    "chainId": 31337,
    "hardfork": "cancun",
    "compiler": "solc 0.8.26",
    "poolManagerOptimizerRuns": 10000,
    "routerBuild": build,
    "checkoutBaseCommit": subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
    ).strip(),
    "v4CoreCommit": subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=core, text=True
    ).strip(),
    "forge": subprocess.check_output(["forge", "--version"], text=True).strip(),
    "anvil": subprocess.check_output(["anvil", "--version"], text=True).strip(),
    "gasLimitPolicy": "120% of the first transaction estimate, rounded up to 1000; fixed per workload. FIFO admission uses the same policy as benchmarks/crossing.",
    "fixture": "No hook, single-hop pool, 0.3% LP fee, deep full-range liquidity, 18/6-decimal mock ERC20 pair, 500 unique actors prefunded with both tokens. No initialized liquidity tick crossings.",
    "adapterScope": "Released Universal Router execute(commands,inputs,deadline), V4_SWAP, SWAP_EXACT_IN_SINGLE, SETTLE_ALL, TAKE_ALL, standing Permit2 allowances. Deadline and 99% reference minimum-output checks enabled. Approval setup and in-transaction permit signatures excluded. Unused route integrations are configured as zero addresses.",
    "comparison": "Async Swap creates persistent order/bid state, settles maker/taker claims, and can match eight pairs per transaction; Universal Router settles a single-hop AMM swap through v4 periphery and Permit2 to ERC20 balances. Gas-workload comparison, not equivalent execution semantics or universal TPS.",
    "measurements": rows,
}
(OUT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
