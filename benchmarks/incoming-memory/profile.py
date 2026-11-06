#!/usr/bin/env python3
"""Replay two saved transactions per profile on local Anvil; no wallet or public RPC.

Requires fixture exports from the crossing benchmark runner.
Only compact call trees and opcode aggregates are retained, not large step traces.
"""

import json
import re
import socket
import subprocess
import time
import urllib.request
import gzip
import collections
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "benchmarks/incoming-memory/results/crossing-traces"
OUT.mkdir(parents=True, exist_ok=True)
results = []
for suite, name in [
    ("crossing", "buy_one_same"),
    ("crossing", "buy_eight_same"),
    ("crossing", "buy_eight_levels"),
]:
    local = "crossing" if suite == "crossing" else "universal-capacity"
    prefix = "crossing" if suite == "crossing" else "universal-capacity"
    export = (ROOT / f".local/{local}/export.log").read_text()
    router = re.search(r"META\|" + name + r"\|(0x[0-9a-fA-F]+)", export)[1]
    commands = re.findall(
        r"TX\|" + name + r"\|(0x[0-9a-fA-F]+)\|(0x[0-9a-fA-F]+)", export
    )[:2]
    summary = json.load(
        open(ROOT / "benchmarks/incoming-memory/results/crossing/summary.json")
    )
    archive = json.load(
        gzip.open(ROOT / f"benchmarks/incoming-memory/results/crossing/{name}.json.gz")
    )
    measure = next(x for x in summary["measurements"] if x["workload"] == name)
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
            assert receipt["gasUsed"] == archive["receipts"][i]["gasUsed"], (
                "Replay differs from saved benchmark"
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
