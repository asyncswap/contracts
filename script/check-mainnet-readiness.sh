#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
forge test --match-test test_rejectingBestBuyerReceivesClaimsWithoutBlocking -vv
printf '%s\n' 'MAINNET BLOCKED: waiting for audit. Native regression passes; the audit, integrated stress tests and deployment rehearsal remain. See MAINNET_READINESS.md.' >&2
exit 1
