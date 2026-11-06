#!/usr/bin/env python3
"""Compare noncrossing order admission using saved fixture states.

Usage: controls.py REPOSITORY_WITH_EXPORTS OUTPUT_DIRECTORY
Records real transaction receipts and verifies that all four orders remain open.
"""

import sys
import json
import re
import socket
import subprocess
import time
import urllib.request
import gzip
import collections
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
OUT = Path(sys.argv[2]).resolve()
OUT.mkdir(parents=True, exist_ok=True)
results = []
# Require twice the output in both ABI copies, so each arrival rests without crossing.
for suite, name in [("crossing", "buy_one_same"), ("crossing", "sell_one_same")]:
    local = "crossing" if suite == "crossing" else "universal-capacity"
    prefix = "crossing" if suite == "crossing" else "universal-capacity"
    export = (ROOT / f".local/{local}/export.log").read_text()
    router = re.search(r"META\|" + name + r"\|(0x[0-9a-fA-F]+)", export)[1]
    commands = re.findall(
        r"TX\|" + name + r"\|(0x[0-9a-fA-F]+)\|(0x[0-9a-fA-F]+)", export
    )[:2]
    patched = []
    for actor, data in commands:
        words = [data[j : j + 64] for j in range(10, len(data), 64)]
        assert len(words) == 18 and words[8] == words[16]
        words[8] = words[16] = f"{int(words[8], 16) * 2:064x}"
        patched.append((actor, data[:10] + "".join(words)))
    commands = patched
    measure = {"transactionGasLimit": 2_000_000}
    match_topic = subprocess.check_output(
        [
            "cast",
            "keccak",
            "AsyncOrdersMatched(bytes32,bytes32,bytes32,uint256,uint256)",
        ],
        text=True,
    ).strip()
    create_topic = subprocess.check_output(
        [
            "cast",
            "keccak",
            "AsyncOrderCreated(bytes32,bytes32,address,bool,uint256,uint256,bytes32)",
        ],
        text=True,
    ).strip()
    info_selector = subprocess.check_output(
        ["cast", "sig", "asyncOrderInfo(bytes32,bytes32)"], text=True
    ).strip()
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
    proc = subprocess.Popen(
        [
            "anvil",
            "--host",
            "127.0.0.1",
            "--port",
            str(port),
            "--chain-id",
            "31337",
            "--gas-limit",
            "30000000",
            "--hardfork",
            "cancun",
            "--base-fee",
            "0",
            "--timestamp",
            "1",
            "--order",
            "fifo",
            "--steps-tracing",
            "--silent",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )

    def batch(items):
        req = urllib.request.Request(
            f"http://127.0.0.1:{port}",
            data=json.dumps(
                [
                    {"jsonrpc": "2.0", "id": i, "method": m, "params": p}
                    for i, (m, p) in enumerate(items)
                ]
            ).encode(),
            headers={"Content-Type": "application/json"},
        )
        ans = sorted(
            json.load(urllib.request.urlopen(req, timeout=120)), key=lambda x: x["id"]
        )
        assert all("error" not in x for x in ans), ans
        return [x["result"] for x in ans]

    def rpc(m, p=[]):
        return batch([(m, p)])[0]

    try:
        for _ in range(100):
            try:
                rpc("eth_chainId")
                break
            except OSError:
                time.sleep(0.05)
        updates = []
        for addr, acct in json.load(
            open(ROOT / f"deployments/{prefix}-{name}.json")
        ).items():
            for field, method in [
                ("code", "anvil_setCode"),
                ("balance", "anvil_setBalance"),
                ("nonce", "anvil_setNonce"),
            ]:
                if (
                    acct[field] != "0x"
                    if field == "code"
                    else int(acct[field], 16) != 0
                ):
                    updates.append((method, [addr, acct[field]]))
            updates.extend(
                ("anvil_setStorageAt", [addr, k, v])
                for k, v in acct["storage"].items()
                if int(v, 16)
            )
        for start in range(0, len(updates), 200):
            batch(updates[start : start + 200])
        rpc("evm_setAutomine", [False])
        rpc("evm_setNextBlockTimestamp", [1000])
        hashes = []
        for actor, data in commands:
            batch(
                [
                    ("anvil_impersonateAccount", [actor]),
                    ("anvil_setBalance", [actor, hex(10**20)]),
                    ("anvil_setNonce", [actor, "0x0"]),
                ]
            )
            hashes.append(
                rpc(
                    "eth_sendTransaction",
                    [
                        {
                            "from": actor,
                            "to": router,
                            "data": data,
                            "nonce": "0x0",
                            "gas": hex(measure["transactionGasLimit"]),
                            "gasPrice": "0x0",
                        }
                    ],
                )
            )
        rpc("evm_mine")
        for i, h in enumerate(hashes):
            receipt = rpc("eth_getTransactionReceipt", [h])
            assert receipt["status"] == "0x1"
            call = rpc("debug_traceTransaction", [h, {"tracer": "callTracer"}])
            trace = rpc(
                "debug_traceTransaction",
                [
                    h,
                    {
                        "disableMemory": True,
                        "disableStack": True,
                        "disableStorage": True,
                    },
                ],
            )
            logs = trace["structLogs"]
            opgas = collections.Counter()
            opcount = collections.Counter()
            stores = collections.Counter()
            for x in logs:
                opgas[x["op"]] += x["gasCost"]
                opcount[x["op"]] += 1
                if x["op"] == "SSTORE":
                    stores[x["gasCost"]] += 1
            # Root gas delta includes child execution once; summing CALL gas costs would double-count it.
            roots = [x for x in logs if x["depth"] == logs[0]["depth"]]
            gross = roots[0]["gas"] - roots[-1]["gas"] + roots[-1]["gasCost"]
            intrinsic = 21000 + sum(
                4 if b == 0 else 16 for b in bytes.fromhex(commands[i][1][2:])
            )
            used = int(receipt["gasUsed"], 16)
            assert not any(x["topics"][0] == match_topic for x in receipt["logs"])
            creates = [x for x in receipt["logs"] if x["topics"][0] == create_topic]
            assert len(creates) == 1
            event = creates[0]
            data = commands[i][1]
            order_info = rpc(
                "eth_call",
                [
                    {
                        "to": event["address"],
                        "data": info_selector
                        + event["topics"][1][2:]
                        + event["topics"][2][2:],
                    },
                    "latest",
                ],
            )
            assert int(order_info[2:66], 16) == int(data[10 + 7 * 64 : 10 + 8 * 64], 16)
            assert int(order_info[66:130], 16) == int(
                data[10 + 8 * 64 : 10 + 9 * 64], 16
            )
            assert 0 <= gross + intrinsic - used <= (gross + intrinsic) // 5
            record = {
                "suite": suite,
                "workload": name,
                "transactionIndex": i,
                "receiptGas": used,
                "intrinsicGas": intrinsic,
                "grossExecutionGas": gross,
                "appliedRefund": gross + intrinsic - used,
                "storageWriteGas": opgas["SSTORE"],
                "storageReadGas": opgas["SLOAD"],
                "logGas": sum(v for k, v in opgas.items() if k.startswith("LOG")),
                "sstoreCount": opcount["SSTORE"],
                "sloadCount": opcount["SLOAD"],
                "sstoreCostHistogram": dict(stores),
                "hash": h,
            }
            results.append(record)
            with gzip.open(OUT / f"{name}-{i}.json.gz", "wt") as f:
                json.dump(
                    {
                        "receipt": receipt,
                        "calls": call,
                        "opcodeGas": dict(opgas),
                        "opcodeCounts": dict(opcount),
                    },
                    f,
                )
            print(json.dumps(record), flush=True)
    finally:
        proc.terminate()
        proc.wait(timeout=10)
(OUT / "summary.json").write_text(json.dumps(results, indent=2) + "\n")
