# Public-testnet soak with concurrent ingestion and reads

This run exercises the deployed v1.3.0 hooks on Unichain Sepolia (1301) and
Robinhood testnet (46630), the public indexer/API, and its WebSocket stream.
It follows the local matching, liquidity-fill and withdrawal campaign in
[`../stress/README.md`](../stress/README.md).

**Status: incomplete.** Two public attempts exercised ingestion and reads, but
neither completed the full planned duration and cycle count. All confirmed
events reconciled, orders closed, and allowances were cleared. The final rerun
is waiting for Olive authentication after Touch ID was canceled. The observer
has been stopped. Current evidence is summarized in `results/status.json`.

## Workload and budget

- Twelve create → top-up → reprice → cancel cycles per chain, paced across at
  least ten minutes. One maker, ETH/numeraire pools; the buy limit is deliberately
  non-marketable. Unexpected execution stops the run for reconciliation.
- Each order escrows about one test quote token, adds 1,000 base units to its
  priority bid, doubles its output minimum, and cancels. Expected non-refundable
  spend is 0.012 USDC and 0.012 USDG. Quote input is returned on cancellation.
- At most 52 transactions per chain, each capped at 1,000,000 gas and 0.02 gwei,
  with zero priority gas price. Execution-fee maximum is 0.00104 test ETH per
  chain; the total native-balance budget includes a margin up to 0.0012 ETH.
- Eight read clients issue up to two requests/second each while orders are
  being indexed. Separate history checks reconcile new receipts. One WebSocket
  connection observes the same lifecycle events.
- The run stops on a transaction failure, a disconnected observer, rate limiting,
  more than 10% failures in the latest 50 reads, or indexer delay above 120 seconds.
  The observer also has a 30-minute ceiling.

The writer checks remaining amounts, bid, maker age, repriced minimum, final
closure, refunded inputs, and zero remaining token allowance. Every lifecycle
receipt must appear in REST and WebSocket with the matching chain, order,
transaction and block. Indexed top-up amounts must match the funded delta.

## Reproduce deliberately

The scripts require Foundry `cast`, Python 3, Bun, and Olive's enrolled
`new-deployer` account. This spends test tokens and broadcasts publicly. Review
balances and budgets first. The writer rejects existing output files and never
retries a submission; a pending or uncertain hash must be reconciled manually.

```sh
bun benchmarks/soak/monitor.ts /tmp/new-soak-transactions.json /tmp/new-soak-monitor.json
# In another terminal, after the observer reports connected:
olive exec new-deployer -- python3 benchmarks/soak/public_soak.py --broadcast \
  --output /tmp/new-soak-transactions.json --monitor /tmp/new-soak-monitor.json
```

Olive uses Touch ID; the scripts never read or print a password or private key.
On a confirmed failure, cleanup attempts to cancel the active order and revoke
unused allowance. An uncertain submission blocks further sends and is recorded
for manual receipt reconciliation.

## Evidence and limits

On a completed run, `results/public-transactions.json` contains transaction hashes, receipts and
on-chain assertions. `results/ingestion-load.json` contains read metrics and
per-event observation times. `summarize.py` checks completeness and writes
`results/summary.json` after both processes finish.

`python3 benchmarks/soak/test_runner.py` runs three offline failure-handling
checks without loading the broadcasting CLI: a lost submission response,
a failed receipt lookup, and successful confirmation. The first two retain
the known hash, block cleanup, and never resubmit.

### Interrupted attempt

The first attempt stopped after seven cycles per chain when the Unichain public
RPC timed out during submission. All 56 confirmed lifecycle events reached REST
and WebSocket, and all 6,792 load reads succeeded. This attempt did **not** pass
the full soak. Its journals are retained under `results/interrupted/`.

The uncertain create had no returned hash. Latest and pending account nonces
were both 101; a confirmed allowance revocation consumed that nonce, preventing
the uncertain create from executing later. The replacement receipt and zero
allowance are in `results/interrupted/reconciliation.json`. Robinhood cleanup
also revoked its unused allowance. The restarted run begins from zero allowances.

The runner now signs first and records the hash before publishing once. An RPC
failure while waiting for a receipt keeps cleanup blocked until reconciliation.
The observer's ingestion deadline also applies when history still returns 404.
These changes improve failure handling; they do not change the successful order
lifecycle or the test's load and spending limits.

A subsequent construction-only attempt rejected an unsupported `cast mktx`
argument before broadcast; its journals are in `results/preflight-failure/`.
No transaction was submitted and both balances and allowances were unchanged.
The corrected signature-based construction passed an unsigned offline check
before the final restart.

This is a bounded lifecycle soak with simultaneous ingestion and reads, not
maximum capacity or a multi-hour production soak. Matching, LP fills and claim
withdrawals were stressed locally in the preceding campaign; this live run does
not repeat those operations. Delay is measured from receipt observation rather
than block inclusion, so a WebSocket event can legitimately arrive first.
The audit and crossing-heavy 100-transaction block-packing gates remain open.

The next attempt completed ten cycles per chain (80 reconciled events) before
all eight local read clients timed out during Mac clamshell sleep. It recorded
8,093 successful reads and eight failures, then closed orders and revoked both
allowances. The journals and matching macOS power events are retained under
`results/client-sleep/`; this interrupted attempt is not a passing soak.
Subsequent read-only host checks found the live API/indexer healthy, with no
container restarts or OOM kills. The planned rerun uses `caffeinate -i` against
idle sleep; clamshell sleep still requires keeping the lid open.
