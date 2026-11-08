#!/usr/bin/env python3
"""Compile the isolated v2-raff arithmetic kernel for direct production parity tests."""

import argparse
import json
import hashlib
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument(
    "repository", type=Path, help="Local v2-raff checkout containing the experiment"
)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
repo = args.repository.resolve()
source = repo / "src/experimental/IncomingMath.huff"
bytecode = subprocess.check_output(
    ["hnc", str(source.relative_to(repo)), "--bytecode"], cwd=repo, text=True
).strip()
bytes.fromhex(bytecode.removeprefix("0x"))
(root / "deployments").mkdir(exist_ok=True)
(root / "deployments/incoming-math-huff.hex").write_text(
    "0x" + bytecode.removeprefix("0x")
)
metadata = {
    "huffBaseCommit": subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=repo, text=True
    ).strip(),
    "compiler": subprocess.check_output(["hnc", "--version"], text=True).strip(),
    "creationBytecodeSha256": hashlib.sha256(
        bytes.fromhex(bytecode.removeprefix("0x"))
    ).hexdigest(),
    "sourceSha256": {
        str(p.relative_to(repo)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in [source, repo / "src/lib/Common.huff", repo / "src/lib/Math.huff"]
    },
}
out = root / "benchmarks/incoming-memory/results/huff-build.json"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(metadata, indent=2) + "\n")
print("Prepared isolated Huff kernel for production-helper parity tests.")
