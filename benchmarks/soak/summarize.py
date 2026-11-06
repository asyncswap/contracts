#!/usr/bin/env python3
"""Reconcile the completed public run; raw journals remain the evidence."""

import json
from pathlib import Path

root = Path(__file__).resolve().parent / "results"
if not (root / "public-transactions.json").exists():
    raise SystemExit(
        "No completed final run: see results/status.json and the interrupted journals."
    )
s = json.loads((root / "public-transactions.json").read_text())
m = json.loads((root / "ingestion-load.json").read_text())
interrupted = json.loads((root / "interrupted/public-transactions.json").read_text())
recovery = json.loads((root / "interrupted/reconciliation.json").read_text())
assert recovery["complete"] and recovery["allowance"] == 0
assert int(recovery["receipt"]["status"], 16) == 1
assert s["complete"] and m["final"] and m["writerComplete"] and not m["abort"]
assert (
    m["failedReads"] == 0
    and m["expectedEvents"] == m["indexedEvents"] == m["websocketEvents"] == 96
)
assert m["elapsedSeconds"] >= 600
assert not s.get("error") and not s.get("cleanupErrors") and m["disconnects"] == 0
assert set(s["chains"]) == {"1301", "46630"}
assert len({(e["chainId"], e["hash"]) for e in m["events"]}) == 96
# Join by chain and transaction hash so equal counts cannot hide a missing receipt.
observed = {(e["chainId"], e["hash"]): e for e in m["events"]}
lifecycle = [t for t in s["transactions"] if t.get("kind")]
assert len(lifecycle) == len(observed) == 96
for receipt in lifecycle:
    event = observed[(receipt["chainId"], receipt["hash"])]
    assert all(
        event[k] == receipt[k] for k in ("orderId", "kind", "blockNumber", "receiptAt")
    )
    assert event["indexedAt"] and event["websocketAt"]
chains = {}
for chain, v in s["chains"].items():
    rows = [t for t in s["transactions"] if str(t["chainId"]) == chain]
    orders = [o for o in s["orders"] if str(o["chainId"]) == chain]
    assert len(orders) == 12 and all(o["complete"] for o in orders)
    assert len({o["orderId"] for o in orders}) == 12
    for order in orders:
        assert [t["kind"] for t in rows if t.get("orderId") == order["orderId"]] == [
            "create",
            "priority_fee_update",
            "price_update",
            "cancel",
        ]
    assert all(
        t["status"] == 1
        and t["gasUsed"] <= s["gasLimit"]
        and t["effectiveGasPrice"] <= s["maxFeePerGas"]
        for t in rows
    )
    assert len(rows) <= 52 and int(v["quoteSpent"]) == 12000 and v["allowance"] == 0
    native = int(v["nativeBefore"]) - int(v["nativeAfter"])
    assert 0 <= native <= 1200000000000000
    original = interrupted["chains"][chain]
    total_quote_spent = int(original["quoteBefore"]) - int(v["quoteAfter"])
    assert total_quote_spent == 29000
    chains[chain] = {
        "confirmedTransactions": len(rows),
        "completedCycles": len(orders),
        "quoteFeeSpentBaseUnits": v["quoteSpent"],
        "numeraire": "USDC" if chain == "1301" else "USDG",
        "nativeSpentWei": str(native),
        "receiptExecutionFeeWei": str(
            sum(t["gasUsed"] * t["effectiveGasPrice"] for t in rows)
        ),
        "gasUsed": sum(t["gasUsed"] for t in rows),
        "remainingAllowance": v["allowance"],
        "feeVaultIncrease": v["feeVaultIncrease"],
        "includingInterruptedAttempts": {
            "quoteFeeSpentBaseUnits": str(total_quote_spent),
            "nativeSpentWei": str(
                int(original["nativeBefore"]) - int(v["nativeAfter"])
            ),
        },
    }


def latency(field):
    raw = [e[field] - e["receiptAt"] for e in m["events"]]
    ordered = sorted(max(0, x) for x in raw)
    return {
        "p50Seconds": ordered[int((len(ordered) - 1) * 0.5)],
        "p95Seconds": ordered[int((len(ordered) - 1) * 0.95)],
        "maxSeconds": max(ordered),
        "observedBeforeReceiptPoll": sum(x < 0 for x in raw),
    }


summary = {
    "complete": True,
    "durationSeconds": m["elapsedSeconds"],
    "chains": chains,
    "readLoad": {
        "clients": 8,
        "targetRequestsPerSecond": 16,
        "successful": m["successfulReads"],
        "failed": m["failedReads"],
        "p50Ms": m["p50Ms"],
        "p95Ms": m["p95Ms"],
        "p99Ms": m["p99Ms"],
    },
    "ingestion": {
        "confirmedLifecycleEvents": 96,
        "restEvents": 96,
        "websocketEvents": 96,
        "disconnects": m["disconnects"],
        "restDelayAfterReceiptObservation": latency("indexedAt"),
        "websocketDelayAfterReceiptObservation": latency("websocketAt"),
    },
    "scope": "Bounded live testnet lifecycle soak with concurrent public API reads. Read-client rate excludes history reconciliation checks. Delay starts when the runner observes a receipt, not block inclusion; earlier observations are counted separately and clipped to zero for percentiles. Not maximum capacity, a multi-hour soak, or crossing-heavy block packing.",
}
(root / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps(summary, indent=2))
