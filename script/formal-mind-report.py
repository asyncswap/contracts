#!/usr/bin/env python3
"""Render audit/formal-mind.audit.json (Formal Mind's report) as audit/formal-mind.md. Both are local only now; the
last tracked audit/formal-mind.md is at 2739d6c.

The JSON was produced against the Lean model generated on Oct 28 (c49689f). Its finding statuses and some properties
have since changed in the code; FINDING_STATUS and OUTDATED below record that, and the rendered file says so.

    python3 script/formal-mind-report.py
"""
import json
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
src = root / "audit/formal-mind.audit.json"
out = root / "audit/formal-mind.md"
MODEL = "c49689f"
SNAPSHOT = "5901aca"  # last commit with formal/ tracked

FINDING_STATUS = {
    "FM-01": "✅ Fixed in `550b463`; see [FM-01-routing-pool-impact.md](FM-01-routing-pool-impact.md)",
}

OUTDATED = {
    "P-03": "`setExecutor` now reverts `CannotRevokeTrustedRouter` when a maker revokes the trusted Router.",
    "P-15": "Pool creation is open since #61 (`81ba6b8`): `beforeInitialize` no longer checks `sender` is the owner.",
    "P-19": "`setExecutorWithSig` now also reverts `CannotRevokeTrustedRouter` (after the signature checks) "
    "when the grant revokes the trusted Router.",
}


def cell(text):
    return text.replace("|", "\\|").replace("\n", " ")


def summary(description):
    """The description's first paragraph, which states the property."""
    return description.strip().split("\n\n")[0]


def loc(locations):
    return ", ".join(f"`{l['file']}:{l['line']}`" for l in locations or []) or "—"


def main():
    if not src.exists():
        sys.exit(f"{src.relative_to(root)} not found: it is kept local")
    d = json.loads(src.read_text())
    props = sorted(d["properties"], key=lambda p: int(p["id"].split("-")[1]))
    lines = [
        "# Formal Mind report",
        "",
        f"Generated from Formal Mind's `{d['schema']}` report by `python3 script/formal-mind-report.py`. Don't edit by hand.",
        "",
        f"> **Out of date.** Every property here was proved against the Lean model generated from the contracts at "
        f"`{MODEL}` (Oct 28), not the current code, and line numbers refer to that code. Properties the code has since "
        f"changed are marked ⚠️. Most of the Lean files named here were never committed; the last tracked copy of `formal/` is at `{SNAPSHOT}`. The "
        f"Solidity tests in [`test/formal/`](../test/formal/README.md) check the same kinds of properties against the "
        f"current bytecode.",
        "",
        "## Findings",
        "",
        "| ID | Severity | Finding | Location | PoC | Status |",
        "|----|----------|---------|----------|-----|--------|",
    ]
    for f in d["findings"]:
        status = FINDING_STATUS.get(f["id"], f["status"])
        lines.append(
            f"| {f['id']} | {f['severity'].capitalize()} | {cell(f['title'])} | {loc(f['locations'])} | "
            f"`{f['poc']}` | {status} |"
        )
    lines += [
        "",
        "Full write-ups: [formal-mind-swarm.md](formal-mind-swarm.md).",
        "",
        "## Properties",
        "",
        f"{len(props)} properties, all reported `verified` against the `{MODEL}` model; "
        f"{len(OUTDATED)} no longer match the code.",
        "",
        "| ID | Function | Location | Property | Status |",
        "|----|----------|----------|----------|--------|",
    ]
    for p in props:
        status = f"⚠️ Out of date: {OUTDATED[p['id']]}" if p["id"] in OUTDATED else p["status"].capitalize()
        lines.append(
            f"| [{p['id']}](#{p['id'].lower()}) | `{p['title']}` | {loc(p.get('locations'))} | "
            f"{cell(summary(p['description']))} | {cell(status)} |"
        )
    lines += ["", "## Property details", ""]
    for p in props:
        lines += [f"### {p['id']}", "", f"**`{p['title']}`** at {loc(p.get('locations'))}", ""]
        if p["id"] in OUTDATED:
            lines += [f"> ⚠️ **Out of date.** {OUTDATED[p['id']]}", ""]
        lines += [p["description"].strip(), ""]
        lines += ["Theorems:", ""] + [f"- `{t['name']}`" for t in p["theorems"]]
        if p["files"]:
            lines += ["", "Lean (local only): " + ", ".join(f"`{f}`" for f in p["files"])]
        lines.append("")
    out.write_text("\n".join(lines))
    print(f"wrote {out.relative_to(root)}: {len(d['findings'])} findings, {len(props)} properties")


if __name__ == "__main__":
    main()
