/** Public testnet read/ingestion observer: 8 readers at <=2 requests/s each. */
import { readFileSync, writeFileSync, renameSync } from "node:fs";
const [statePath, outputPath] = process.argv.slice(2);
if (!statePath || !outputPath)
  throw Error("Usage: bun monitor.ts writer.json monitor.json");
const api = "https://api.asyncswap.org";
const baseline = [
  {
    chainId: 1301,
    orderId:
      "0x32e0846b8016290872a504e105a106d65b03ed52fc6e998d304e112aba9ebfbc",
  },
  {
    chainId: 46630,
    orderId:
      "0x46b852272fcaac9c2ec9f035b790d8b4cbd6dbaae6474c693f94f22e7b55c3ed",
  },
];
const started = Date.now();
let stop = false,
  connected = false,
  abort = "",
  disconnects = 0;
const samples: number[] = [];
let failed = 0;
const errors: string[] = [];
const recent: boolean[] = [];
const wsEvents = new Map<string, { at: number; event: any }>();
const indexed = new Map<string, { at: number; event: any }>();
let expected: any[] = [];
let lastWriter: any = null;
const key = (r: any) =>
  `${r.chainId}:${String(r.hash ?? r.txHash).toLowerCase()}`;
const quantile = (q: number) => {
  const s = [...samples].sort((a, b) => a - b);
  return s.length ? s[Math.floor((s.length - 1) * q)] : null;
};
function state() {
  try {
    return JSON.parse(readFileSync(statePath, "utf8"));
  } catch {
    return null;
  }
}
function persist(final = false) {
  const rows = expected.map((r) => ({
    chainId: r.chainId,
    hash: r.hash,
    orderId: r.orderId,
    kind: r.kind,
    blockNumber: r.blockNumber,
    receiptAt: r.receiptAt,
    indexedAt: indexed.get(key(r))?.at,
    websocketAt: wsEvents.get(key(r))?.at,
  }));
  const data = {
    startedAt: started / 1000,
    updatedAt: Date.now() / 1000,
    elapsedSeconds: (Date.now() - started) / 1000,
    connected,
    abort,
    disconnects,
    final,
    writerComplete: lastWriter?.complete ?? false,
    successfulReads: samples.length,
    failedReads: failed,
    errors: errors.slice(0, 10),
    p50Ms: quantile(0.5),
    p95Ms: quantile(0.95),
    p99Ms: quantile(0.99),
    expectedEvents: rows.length,
    indexedEvents: rows.filter((r) => r.indexedAt !== undefined).length,
    websocketEvents: rows.filter((r) => r.websocketAt !== undefined).length,
    events: rows,
  };
  writeFileSync(outputPath + ".tmp", JSON.stringify(data, null, 2) + "\n");
  renameSync(outputPath + ".tmp", outputPath);
}
const ws = new WebSocket("wss://api.asyncswap.org/v1/filler/stream");
ws.onopen = () => {
  connected = true;
  persist();
};
ws.onclose = () => {
  connected = false;
  disconnects++;
  if (!stop) abort = "WebSocket disconnected";
};
ws.onerror = () => {
  abort = "WebSocket failed";
};
ws.onmessage = (message) => {
  try {
    const e = JSON.parse(String(message.data));
    if ([1301, 46630].includes(e.chainId) && typeof e.txHash === "string")
      wsEvents.set(key(e), { at: Date.now() / 1000, event: e });
  } catch {}
};
const timer = setInterval(() => persist(), 1000);
async function reader(i: number) {
  while (!stop) {
    const t = performance.now();
    const target = baseline[i % 2];
    let ok = false;
    try {
      const r = await fetch(
        `${api}/v1/filler/orders/${target.orderId}/events?chainId=${target.chainId}`,
        { signal: AbortSignal.timeout(5000) },
      );
      if (r.status === 429) abort = "API rate-limited the bounded load";
      if (!r.ok) throw Error(`HTTP ${r.status}`);
      const b: any = await r.json();
      if (
        !b.events?.length ||
        b.events.some(
          (e: any) =>
            e.chainId !== target.chainId || e.orderId !== target.orderId,
        )
      )
        throw Error("Invalid event response");
      samples.push(performance.now() - t);
      ok = true;
    } catch (e) {
      failed++;
      if (errors.length < 10) errors.push(String(e));
    }
    recent.push(ok);
    if (recent.length > 50) recent.shift();
    if (recent.length === 50 && recent.filter((x) => !x).length > 5)
      abort = "More than 10% failures in latest 50 reads";
    if (abort) break;
    await Bun.sleep(Math.max(0, 500 - (performance.now() - t)));
  }
}
const readers = Array.from({ length: 8 }, (_, i) => reader(i));
const typeFor: any = {
  create: "order.created",
  priority_fee_update: "order.priorityFeeUpdate",
  price_update: "order.priceUpdate",
  cancel: "order.cancelled",
};
let finishDeadline: number | undefined;
while (!stop) {
  lastWriter = state();
  expected = (lastWriter?.transactions ?? []).filter(
    (r: any) => r.kind && r.status === 1,
  );
  for (const row of expected) {
    const k = key(row);
    const observed = wsEvents.get(k);
    if (
      observed &&
      (observed.event.orderId.toLowerCase() !== row.orderId.toLowerCase() ||
        observed.event.type !== typeFor[row.kind] ||
        Number(observed.event.blockNumber) !== row.blockNumber)
    )
      abort = "WebSocket event disagrees with receipt";
    if (indexed.has(k)) continue;
    // Missing history (404) must still count toward the ingestion deadline.
    if (Date.now() / 1000 - row.receiptAt > 120)
      abort = "Indexer more than 120 seconds behind a confirmed receipt";
    try {
      const r = await fetch(
        `${api}/v1/filler/orders/${row.orderId}/events?chainId=${row.chainId}`,
        { signal: AbortSignal.timeout(5000) },
      );
      if (r.status === 404) continue;
      if (!r.ok) throw Error(`history HTTP ${r.status}`);
      const b: any = await r.json();
      const e = b.events.find(
        (e: any) =>
          e.txHash.toLowerCase() === row.hash.toLowerCase() &&
          e.kind === row.kind,
      );
      if (e) {
        if (
          Number(e.blockNumber) !== row.blockNumber ||
          e.chainId !== row.chainId ||
          e.orderId.toLowerCase() !== row.orderId.toLowerCase()
        )
          throw Error("History receipt mismatch");
        if (
          row.kind === "priority_fee_update" &&
          (e.addedFee !== "1000" || e.newPriorityFee !== "1000")
        )
          throw Error("Wrong indexed top-up amount");
        indexed.set(k, { at: Date.now() / 1000, event: e });
      }
    } catch (e) {
      if (errors.length < 10) errors.push(String(e));
    }
    if (Date.now() / 1000 - row.receiptAt > 120 && !indexed.has(k))
      abort = "Indexer more than 120 seconds behind a confirmed receipt";
  }
  if (lastWriter?.complete || lastWriter?.error) {
    finishDeadline ??= Date.now() + 120000;
    if (lastWriter.error) abort ||= "Writer stopped";
    if (
      expected.every((r) => indexed.has(key(r)) && wsEvents.has(key(r))) ||
      Date.now() > finishDeadline
    )
      stop = true;
  }
  if (Date.now() - started > 30 * 60 * 1000) {
    abort ||= "30-minute run ceiling";
    stop = true;
  }
  persist();
  if (!stop) await Bun.sleep(2000);
}
await Promise.all(readers);
clearInterval(timer);
persist(true);
ws.close();
if (
  abort ||
  !lastWriter?.complete ||
  failed ||
  expected.length !== 96 ||
  expected.some((r) => !indexed.has(key(r)) || !wsEvents.has(key(r)))
)
  process.exitCode = 1;
console.log(
  JSON.stringify({
    complete: lastWriter?.complete,
    reads: samples.length,
    failed,
    expected: expected.length,
    indexed: indexed.size,
    websocket: expected.filter((r) => wsEvents.has(key(r))).length,
    abort,
  }),
);
