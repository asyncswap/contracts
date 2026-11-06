#!/usr/bin/env python3
"""Bounded public-testnet soak. Explicit broadcast, Olive new-deployer only; no send retries."""

import argparse
import json
import subprocess
import time
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OWNER = "0x33ce69DA05c3ad30A3b525625F950fAda8673205"
NETWORKS = {
    1301: "https://sepolia.unichain.org",
    46630: "https://rpc.testnet.chain.robinhood.com",
}
ORDER = "((address,address,uint24,int24,address),address,bool,uint256,uint256,uint256,uint160,bytes32)"
ZERO = "0x" + "00" * 32
CYCLES = 12
DELTA = 1000
GAS = 1000000
MAX_FEE = 20000000
p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--broadcast", action="store_true", required=True)
p.add_argument("--output", type=Path, required=True)
p.add_argument("--monitor", type=Path, required=True)
a = p.parse_args()
assert not a.output.exists(), (
    "Never overwrite/replay a prior soak; reconcile its hashes first."
)


def cast(*args):
    try:
        return subprocess.check_output(
            ["cast", *map(str, args)], text=True, timeout=60
        ).strip()
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        # Do not copy signed transaction arguments into failure logs.
        raise RuntimeError(f"cast {args[0]} failed: {type(error).__name__}") from None


assert cast("wallet", "address", "--account", "new-deployer").lower() == OWNER.lower()
evidence = {
    "startedAt": time.time(),
    "complete": False,
    "owner": OWNER,
    "cyclesPerChain": CYCLES,
    "maxFeePerGas": MAX_FEE,
    "gasLimit": GAS,
    "maxTransactionsPerChain": 52,
    "chains": {},
    "transactions": [],
    "orders": [],
}


def save():
    tmp = a.output.with_suffix(".tmp")
    tmp.write_text(json.dumps(evidence, indent=2) + "\n")
    os.replace(tmp, a.output)


def monitor_ok():
    m = json.loads(a.monitor.read_text())
    assert time.time() - m["updatedAt"] < 30, "Monitor stale"
    assert m["connected"], "WebSocket disconnected"
    assert not m.get("abort"), "Monitor requested stop"


class Chain:
    def __init__(self, c, url):
        self.c = c
        self.url = url
        self.active = None
        self.uncertain = False
        self.n = 0
        d = json.loads((ROOT / f"deployments/{c}/{c}.json").read_text())
        self.d = d["contracts"]
        self.k = json.loads((ROOT / f"deployments/{c}/{c}-pool.json").read_text())
        self.h = self.d["AsyncSwap"]["address"]
        self.r = self.d["Router"]["address"]
        self.pm = self.d["PoolManager"]["address"]
        self.token = self.k["currency1"]
        assert d["release"] == "v1.3.0" and self.k["hooks"].lower() == self.h.lower()
        assert int(self.rpc("eth_chainId", []), 16) == c
        self.pool = cast(
            "keccak",
            cast(
                "abi-encode",
                "f(address,address,uint24,int24,address)",
                self.k["currency0"],
                self.token,
                self.k["fee"],
                self.k["tickSpacing"],
                self.h,
            ),
        )
        self.key = f"({self.k['currency0']},{self.token},{self.k['fee']},{self.k['tickSpacing']},{self.h})"
        self.nonce = int(self.rpc("eth_getTransactionCount", [OWNER, "pending"]), 16)
        assert self.nonce == int(
            self.rpc("eth_getTransactionCount", [OWNER, "latest"]), 16
        ), "Existing pending transaction"
        self.start_native = int(self.rpc("eth_getBalance", [OWNER, "latest"]), 16)
        self.start_quote = self.num(self.token, "balanceOf(address)", OWNER)
        assert self.start_native >= 1200000000000000 and self.start_quote >= 2000000
        assert self.num(self.token, "allowance(address,address)", OWNER, self.r) == 0, (
            "Existing allowance must be reviewed"
        )
        self.vault = self.num(
            self.pm,
            "balanceOf(address,uint256)",
            self.d["FeeVault"]["address"],
            int(self.token, 16),
        )
        evidence["chains"][str(c)] = {
            "hook": self.h,
            "router": self.r,
            "poolId": self.pool,
            "nativeBefore": str(self.start_native),
            "quoteBefore": str(self.start_quote),
        }

    def rpc(self, m, params):
        return json.loads(
            cast("rpc", m, json.dumps(params), "--raw", "--rpc-url", self.url)
        )

    def call(self, to, sig, *args):
        return self.rpc(
            "eth_call", [{"to": to, "data": cast("calldata", sig, *args)}, "latest"]
        )

    def num(self, to, sig, *args):
        return int(self.call(to, sig, *args), 16)

    def send(self, label, to, sig, *args, cleanup=False):
        if not cleanup:
            monitor_ok()
        assert not self.uncertain and self.n < 52
        assert int(self.rpc("eth_gasPrice", []), 16) <= MAX_FEE, "Gas above cap"
        data = cast("calldata", sig, *args)
        self.rpc(
            "eth_call",
            [
                {"from": OWNER, "to": to, "data": data, "maxPriorityFeePerGas": "0x0"},
                "latest",
            ],
        )
        row = {
            "chainId": self.c,
            "action": label,
            "nonce": self.nonce,
            "attemptedAt": time.time(),
            "to": to,
        }
        evidence["transactions"].append(row)
        save()
        # Sign first so even a lost submission response has a known reconciliation hash.
        raw = cast(
            "mktx",
            to,
            sig,
            *args,
            "--rpc-url",
            self.url,
            "--account",
            "new-deployer",
            "--priority-gas-price",
            "0",
            "--gas-price",
            MAX_FEE,
            "--gas-limit",
            GAS,
            "--nonce",
            self.nonce,
            "--chain",
            self.c,
        )
        tx = cast("keccak", raw)
        assert tx.startswith("0x") and len(tx) == 66
        row["hash"] = tx
        save()
        self.uncertain = True
        # Submit once. Never generate a replacement automatically after an RPC error.
        returned = cast("publish", raw, "--rpc-url", self.url, "--async")
        assert returned == tx
        self.nonce += 1
        self.n += 1
        for _ in range(120):
            receipt = self.rpc("eth_getTransactionReceipt", [tx])
            if receipt:
                row.update(
                    receiptAt=time.time(),
                    blockNumber=int(receipt["blockNumber"], 16),
                    status=int(receipt["status"], 16),
                    gasUsed=int(receipt["gasUsed"], 16),
                    effectiveGasPrice=int(receipt["effectiveGasPrice"], 16),
                    logs=receipt["logs"],
                )
                save()
                # A returned hash is not confirmation. Keep cleanup blocked if receipt RPC fails.
                self.uncertain = False
                assert row["status"] == 1, (label, tx)
                # Wait for the load-balanced read node to catch up before state assertions.
                time.sleep(3)
                return receipt, row
            time.sleep(1)
        self.uncertain = True
        raise RuntimeError("Pending hash; reconcile before further submissions: " + tx)

    def order(self, amount, minimum, salt):
        return f"({self.key},{OWNER},false,{amount},{minimum},0,{2**96},{salt})"

    def setup(self):
        if not self.num(
            self.h, "isExecutor(bytes32,address,address)", self.pool, OWNER, self.r
        ):
            self.send(
                "authorize",
                self.h,
                "setExecutor(bytes32,address,bool)",
                self.pool,
                self.r,
                "true",
            )
        self.send(
            "approve",
            self.token,
            "approve(address,uint256)",
            self.r,
            sum(1000000 + i + DELTA for i in range(CYCLES)),
        )

    def cycle(self, i):
        amount = 1000000 + i
        minimum = 10**18
        rec, row = self.send(
            "create",
            self.r,
            f"swap({ORDER},bytes)",
            self.order(amount, minimum, ZERO),
            cast(
                "abi-encode",
                "f(address,address,uint256,uint256)",
                OWNER,
                self.r,
                minimum,
                0,
            ),
        )
        topic = cast(
            "keccak",
            "AsyncOrderCreated(bytes32,bytes32,address,bool,uint256,uint256,bytes32)",
        )
        logs = [
            log
            for log in rec["logs"]
            if log["address"].lower() == self.h.lower() and log["topics"][0] == topic
        ]
        assert len(logs) == 1
        oid = logs[0]["topics"][2]
        salt = "0x" + logs[0]["data"][-64:]
        self.active = (amount, minimum, salt, oid)
        entry = {
            "chainId": self.c,
            "cycle": i,
            "orderId": oid,
            "poolId": self.pool,
            "salt": salt,
        }
        evidence["orders"].append(entry)
        row.update(orderId=oid, kind="create")
        save()
        state = self.call(self.h, "asyncOrderInfo(bytes32,bytes32)", self.pool, oid)
        assert int(state[2:66], 16) == amount and int(state[66:], 16) == minimum, (
            "Order unexpectedly filled; stop and reconcile"
        )
        age = self.num(self.h, "orderCreatedSequence(bytes32,bytes32)", self.pool, oid)
        _, row = self.send(
            "top_up",
            self.r,
            f"topUpPriorityFee({ORDER},uint256)",
            self.order(amount, minimum, salt),
            DELTA,
        )
        row.update(orderId=oid, kind="priority_fee_update")
        save()
        assert (
            self.num(self.h, "asyncOrderPriorityFee(bytes32,bytes32)", self.pool, oid)
            == DELTA
        )
        assert (
            self.call(self.h, "asyncOrderInfo(bytes32,bytes32)", self.pool, oid)
            == state
        )
        assert (
            self.num(self.h, "orderCreatedSequence(bytes32,bytes32)", self.pool, oid)
            == age
        )
        _, row = self.send(
            "reprice",
            self.h,
            f"updatePrice({ORDER},uint256)",
            self.order(amount, minimum, salt),
            minimum * 2,
        )
        row.update(orderId=oid, kind="price_update")
        save()
        state = self.call(self.h, "asyncOrderInfo(bytes32,bytes32)", self.pool, oid)
        assert int(state[2:66], 16) == amount and int(state[66:], 16) == minimum * 2
        self.cancel()
        entry["complete"] = True
        save()
        print(self.c, "cycle", i + 1, "complete", flush=True)

    def cancel(self):
        if not self.active:
            return
        amount, minimum, salt, oid = self.active
        if self.num(self.h, "asyncOrder(bytes32,bytes32)", self.pool, oid) > 0:
            _, row = self.send(
                "cancel",
                self.r,
                f"cancelOrder({ORDER})",
                self.order(amount, minimum, salt),
                cleanup=True,
            )
            row.update(orderId=oid, kind="cancel")
            save()
        assert self.num(self.h, "asyncOrder(bytes32,bytes32)", self.pool, oid) == 0
        self.active = None

    def finish(self):
        if self.uncertain:
            raise RuntimeError(
                "Uncertain submission; manual receipt reconciliation required"
            )
        self.cancel()
        if self.num(self.token, "allowance(address,address)", OWNER, self.r):
            self.send(
                "revoke",
                self.token,
                "approve(address,uint256)",
                self.r,
                0,
                cleanup=True,
            )
        after = self.num(self.token, "balanceOf(address)", OWNER)
        evidence["chains"][str(self.c)].update(
            quoteAfter=str(after),
            quoteSpent=str(self.start_quote - after),
            nativeAfter=str(int(self.rpc("eth_getBalance", [OWNER, "latest"]), 16)),
            allowance=self.num(self.token, "allowance(address,address)", OWNER, self.r),
            feeVaultIncrease=str(
                self.num(
                    self.pm,
                    "balanceOf(address,uint256)",
                    self.d["FeeVault"]["address"],
                    int(self.token, 16),
                )
                - self.vault
            ),
        )
        save()


chains = []
try:
    save()
    monitor_ok()
    chains = [Chain(c, u) for c, u in NETWORKS.items()]
    for c in chains:
        c.setup()
    start = time.monotonic()
    for i in range(CYCLES):
        for c in chains:
            c.cycle(i)
        while time.monotonic() < start + (i + 1) * 50:
            monitor_ok()
            time.sleep(2)
    for c in chains:
        c.finish()
        v = evidence["chains"][str(c.c)]
        assert v["quoteSpent"] == str(CYCLES * DELTA) and v["allowance"] == 0
    evidence.update(complete=True, finishedAt=time.time())
    save()
except BaseException as e:
    evidence["error"] = str(e)
    save()
    for c in chains:
        try:
            c.finish()
        except Exception as cleanup:
            evidence.setdefault("cleanupErrors", []).append(
                {"chainId": c.c, "error": str(cleanup)}
            )
            save()
    raise
