#!/usr/bin/env python3
"""Fetch pinned official sources and build their release artifacts in ignored local directories."""

import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
ROUTER = ROOT / ".local/universal-router"
PIN = "64027f3372aa235734207c4e05667204f6f927e1"


def run(args, cwd=ROOT):
    subprocess.run(args, cwd=cwd, check=True)


def sha(path):
    return subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=path, text=True
    ).strip()


if not ROUTER.exists():
    run(
        [
            "gh",
            "repo",
            "clone",
            "Uniswap/universal-router",
            str(ROUTER),
            "--",
            "--branch",
            "2.2.0",
            "--depth",
            "1",
            "--recurse-submodules",
            "--shallow-submodules",
        ]
    )
assert sha(ROUTER) == PIN, "Unexpected router revision; do not benchmark a moved tag"
assert sha(ROUTER / "lib/v4-periphery") == "a7af5b345b479b05fde9182d7e40913a73b3e18f"
assert sha(ROUTER / "lib/permit2") == "cc56ad0f3439c502c246fc5cfcc3db92bb8b7219"
packages = ROOT / ".local/universal-router-npm"
run(
    [
        "npm",
        "install",
        "--prefix",
        str(packages),
        "--ignore-scripts",
        "--no-package-lock",
        "--save-exact",
        "@uniswap/v2-core@1.0.1",
        "@uniswap/v3-core@1.0.0",
        "@openzeppelin/contracts@5.0.2",
    ]
)
if not (ROUTER / "node_modules").exists():
    (ROUTER / "node_modules").symlink_to(
        packages / "node_modules", target_is_directory=True
    )
run(["forge", "build", "contracts/UniversalRouter.sol"], ROUTER)
run(["forge", "build", "src/Permit2.sol"], ROUTER / "lib/permit2")
report = {
    "universalRouterTag": "2.2.0",
    "universalRouterCommit": PIN,
    "v4PeripheryCommit": sha(ROUTER / "lib/v4-periphery"),
    "permit2Commit": sha(ROUTER / "lib/permit2"),
    "npmDependencies": {
        "@uniswap/v2-core": "1.0.1",
        "@uniswap/v3-core": "1.0.0",
        "@openzeppelin/contracts": "5.0.2",
    },
    "artifacts": {},
}
for name, source, runs, version, size in [
    (
        "UniversalRouter",
        ROUTER / "out/UniversalRouter.sol/UniversalRouter.json",
        1,
        "0.8.26",
        23233,
    ),
    (
        "Permit2",
        ROUTER / "lib/permit2/out/Permit2.sol/Permit2.json",
        1000000,
        "0.8.17",
        9152,
    ),
]:
    artifact = json.loads(source.read_text())
    metadata = artifact["metadata"]
    metadata = json.loads(metadata) if isinstance(metadata, str) else metadata
    assert metadata["compiler"]["version"].startswith(version)
    assert (
        metadata["settings"]["optimizer"]["runs"] == runs
        and metadata["settings"]["viaIR"]
    )
    code = artifact["deployedBytecode"]["object"].removeprefix("0x")
    assert len(code) // 2 == size
    destination = ROOT / f"deployments/benchmark-{name}.json"
    shutil.copyfile(source, destination)
    report["artifacts"][name] = {
        "compiler": metadata["compiler"]["version"],
        "optimizerRuns": runs,
        "viaIR": True,
        "evmVersion": metadata["settings"]["evmVersion"],
        "runtimeBytes": size,
        "creationBytecodeSha256": hashlib.sha256(
            bytes.fromhex(artifact["bytecode"]["object"].removeprefix("0x"))
        ).hexdigest(),
    }
output = ROOT / "benchmarks/universal-router/results"
output.mkdir(parents=True, exist_ok=True)
(output / "build.json").write_text(json.dumps(report, indent=2) + "\n")
print("Pinned Universal Router and Permit2 artifacts ready")
