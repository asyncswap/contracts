#!/usr/bin/env python3
"""Record the confirmed standalone PoolManager deployment in its registry."""

import argparse
import json
import os
import tempfile
from pathlib import Path


def quantity(value):
    return int(value, 16) if isinstance(value, str) and value.startswith("0x") else int(value)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chain-id", type=int, required=True)
    parser.add_argument("--registry", type=Path, required=True)
    parser.add_argument("--broadcast", type=Path, required=True)
    args = parser.parse_args()
    registry = json.loads(args.registry.read_text())
    run = json.loads(args.broadcast.read_text())
    if quantity(registry["chainId"]) != args.chain_id or quantity(run.get("chain", run.get("chainId"))) != args.chain_id:
        raise SystemExit("PoolManager registry/broadcast chain mismatch")
    manager = registry["contracts"]["PoolManager"]["address"].lower()
    receipt = next((r for r in run.get("receipts", [])
                    if (r.get("contractAddress") or "").lower() == manager
                    and quantity(r.get("status", 0)) == 1), None)
    if receipt is None:
        raise SystemExit("No confirmed PoolManager CREATE receipt for the registry address")
    registry["contracts"]["PoolManager"].update({
        "startBlock": quantity(receipt["blockNumber"]),
        "txHash": receipt["transactionHash"],
    })
    fd, tmp = tempfile.mkstemp(prefix=".poolmanager-", dir=args.registry.parent)
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(registry, f, indent=2)
            f.write("\n")
        os.replace(tmp, args.registry)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


if __name__ == "__main__":
    main()
