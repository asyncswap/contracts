#!/usr/bin/env python3
"""Keep only repository src/ LCOV records and print a weighted, human-readable summary."""

import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def source_records(text, root=ROOT):
    root = root.resolve()
    records = []
    for block in text.split("end_of_record"):
        lines = block.strip().splitlines()
        sources = [line[3:] for line in lines if line.startswith("SF:")]
        if not sources:
            continue
        if len(sources) != 1:
            raise ValueError("LCOV record must identify exactly one source")
        source = (root / sources[0]).resolve()
        if not source.is_relative_to((root / "src").resolve()):
            continue
        name = source.relative_to(root).as_posix()
        counts = {}
        for line in lines:
            key, _, value = line.partition(":")
            if key in {"LF", "LH", "BRF", "BRH", "FNF", "FNH"}:
                counts[key] = int(value)
        pairs = [(counts.get(hit, 0), counts.get(found, 0))
                 for hit, found in [("LH", "LF"), ("BRH", "BRF"), ("FNH", "FNF")]]
        if any(hit < 0 or found < hit for hit, found in pairs):
            raise ValueError(f"Invalid coverage counts: {name}")
        normalized = ["SF:" + name if line.startswith("SF:") else line for line in lines]
        records.append((name, pairs, "\n".join(normalized) + "\nend_of_record\n"))
    if not records:
        raise ValueError("No src/ coverage records found")
    if len({name for name, _, _ in records}) != len(records):
        raise ValueError("Duplicate source records would double-count coverage")
    return sorted(records)


def metric(hit, found):
    return f"{100 * hit / found:.2f}% ({hit}/{found})" if found else "N/A (0/0)"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    records = source_records(args.input.read_text())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("".join(record for _, _, record in records))
    print("\nCoverage scope: src/ only (compiler-reported; no test or deployment-script files).")
    print("| Source | Lines | Branches | Functions |")
    print("| --- | ---: | ---: | ---: |")
    totals = [[0, 0] for _ in range(3)]
    for name, pairs, _ in records:
        print("| " + name + " | " + " | ".join(metric(*pair) for pair in pairs) + " |")
        for total, pair in zip(totals, pairs):
            total[0] += pair[0]
            total[1] += pair[1]
    print("| Total | " + " | ".join(metric(*pair) for pair in totals) + " |")
    print(f"\nLCOV report: {args.output}")


if __name__ == "__main__":
    main()
