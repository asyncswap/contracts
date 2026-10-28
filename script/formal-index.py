#!/usr/bin/env python3
"""Rebuild test/formal/README.md's theorem → test map from formal/Proofs/ and test/formal/.

Every theorem and lemma under formal/Proofs/ gets a row: the test in test/formal/ that checks it on the
bytecode (a test function named after it: `test…_<theorem>`), or the reason it has none. Reasons and
Halmos notes already written in the README for a theorem are kept; a theorem with neither a test nor a
reason is listed as not tested yet. The prose above `## Theorem → test map` is kept as written.

    python3 script/formal-index.py           # rewrite the README
    python3 script/formal-index.py --check   # exit 1 if it is out of date
"""
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
readme = root / "test/formal/README.md"
proofs = root / "formal/Proofs"
MAP = "## Theorem → test map"

THEOREM = re.compile(r"^\s*(?:@\[[^\]]*\]\s*)?(?:private |protected )?(?:theorem|lemma)\s+(\S+)")
TEST = re.compile(r"function\s+(test\w*)\s*\(")


def old_rows(text):
    """What the README already says per theorem: (test cell, halmos) or a reason."""
    tested, reasons = {}, {}
    for line in text.splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 3 or not cells[0].startswith("`"):
            continue
        name = cells[0].strip("`")
        if len(cells) == 4:
            tested[name] = (cells[2], cells[3])
        elif len(cells) == 3 and cells[2] != "not tested yet":
            reasons[name] = cells[2]
    return tested, reasons


def tests_by_name():
    """Every test function in test/formal/, by the theorem it is named after (the part after its first `_`)."""
    out = {}
    for sol in sorted((root / "test/formal").glob("*.sol")):
        for fn in TEST.findall(sol.read_text()):
            out.setdefault(fn, []).append(sol.name)
    return out


def find_tests(name, tests):
    """Tests named `test…_<name>` (exactly that suffix), as `[File.t.sol](File.t.sol) fn, fn`."""
    by_file = {}
    for fn, files in tests.items():
        if fn.endswith("_" + name):
            for f in files:
                by_file.setdefault(f, []).append(fn)
    return [f"[`{f}`]({f}) " + ", ".join(f"`{fn}`" for fn in sorted(fns)) for f, fns in sorted(by_file.items())]


def build(text):
    head, _, _ = text.partition(MAP)
    tested, reasons = old_rows(text)
    tests = tests_by_name()
    sections, counts = [], {"theorems": 0, "tested": 0, "left": 0, "untested": 0}
    current = set()
    for lean in sorted(proofs.rglob("*.lean")):
        rel = lean.relative_to(root / "formal")
        rows = [(m.group(1), i + 1) for i, l in enumerate(lean.read_text().splitlines()) if (m := THEOREM.match(l))]
        if not rows:
            continue
        link = lambda line: f"[{lean.name}:{line}](../../formal/{rel}#L{line})"
        have, left, todo = [], [], []
        for name, line in rows:
            short = name.split(".")[-1]
            current.add(short)
            found = find_tests(short, tests)
            counts["theorems"] += 1
            if found:
                halmos = tested.get(name, tested.get(short, ("", "")))[1] or "—"
                have.append(f"| `{name}` | {link(line)} | {'; '.join(found)} | {halmos} |")
            elif name in reasons or short in reasons:
                left.append(f"| `{name}` | {link(line)} | {reasons.get(name, reasons.get(short))} |")
            else:
                todo.append(f"| `{name}` | {link(line)} | not tested yet |")
        counts["tested"] += len(have)
        counts["left"] += len(left)
        counts["untested"] += len(todo)
        out = [f"### `{rel}`", ""]
        if have:
            out += ["| Theorem | Lean | Test | Halmos |", "|---|---|---|---|", *have, ""]
        if left or todo:
            out += ["Left out:" if have else "No test:", "", "| Theorem | Lean | Reason |", "|---|---|---|", *left, *todo, ""]
        sections.append("\n".join(out))
    # Tests named after a theorem formal/Proofs/ no longer has (the proofs were retired and written again since).
    orphans = {}
    for fn, files in tests.items():
        if not any(fn.endswith("_" + t) for t in current):
            for f in files:
                orphans.setdefault(f, []).append(fn)
    counts["orphan_tests"] = sum(len(v) for v in orphans.values())
    if orphans:
        rows = [f"| [`{f}`]({f}) | {len(fns)} |" for f, fns in sorted(orphans.items())]
        sections.append("\n".join([
            "### Tests whose theorem is gone",
            "",
            "These tests still check the bytecode and pass, but the theorem each is named after was retired with the earlier proofs",
            "(contracts f243b0b) and isn't in `formal/Proofs/` now. They stay as bytecode checks; map them again as the swarm",
            "re-proves those properties.",
            "",
            "| Test file | Tests |",
            "|---|---|",
            *rows,
            "",
        ]))
    summary = (
        f"{counts['theorems']} theorems and lemmas in `formal/Proofs/`: {counts['tested']} have a test here, "
        f"{counts['left']} are left out for the reason given, and {counts['untested']} aren't tested yet. "
        f"{counts['orphan_tests']} tests are named after theorems that were retired (listed at the end). "
        "Generated by `python3 script/formal-index.py`; run it after the proofs or the tests change.\n"
    )
    return head + MAP + "\n\n" + summary + "\n" + "\n".join(sections), counts


if __name__ == "__main__":
    text = readme.read_text()
    new, counts = build(text)
    if "--check" in sys.argv:
        sys.exit(0 if new == text else 1)
    readme.write_text(new)
    print(counts)
