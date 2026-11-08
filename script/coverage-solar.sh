#!/usr/bin/env bash
# Coverage compiles in memory. Prebuild matching disk metadata for immutable-layout assertions.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
forge_bin="${FORGE_BIN:-forge}"
common=(--use solar --offline --out out-solar-coverage --cache-path cache-solar-coverage)
raw_report="$(mktemp "${TMPDIR:-/tmp}/asyncswap-solar-coverage.XXXXXX")"
trap 'rm -f "$raw_report"' EXIT
"$forge_bin" build "${common[@]}" --optimize false --ast
# Run the requested tests, then filter the report rather than excluding code from execution.
"$forge_bin" coverage "${common[@]}" "$@" --report lcov --report-file "$raw_report"
python3 script/coverage-src.py "$raw_report" --output coverage/solar-src.lcov
