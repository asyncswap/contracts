#!/usr/bin/env python3
"""Bounded read-only load against a disposable localhost API; never a public host."""
import argparse, concurrent.futures, json, time, urllib.request
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--receipts',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
a=p.parse_args();data=json.loads(a.receipts.read_text())
ids=[]
for receipt in data['receipts']:
 for log in receipt['logs']:
  if log['topics'][0]=='0xb90a2c2630a70bbe0480bebdb6b64c7043abd7c289ffeffcf94d4620e66d5286':ids.append(log['topics'][2])
assert ids
reports=[]
for concurrency,seconds in [(1,30),(8,60),(32,120)]:
 start=time.monotonic();deadline=start+seconds
 def worker(index):
  samples=[];errors=[];requests=0
  while time.monotonic()<deadline:
   order=ids[(index+requests)%len(ids)];t=time.monotonic()
   try:
    with urllib.request.urlopen(f'http://127.0.0.1:42079/v1/filler/orders/{order}/events?chainId=1301',timeout=5) as r:
     body=json.load(r)
     assert r.status==200 and body['events'] and all(e['orderId']==order and e['chainId']==1301 for e in body['events'])
    samples.append((time.monotonic()-t)*1000)
   except Exception as e:errors.append(type(e).__name__+': '+str(e))
   requests+=1
   # Cap each client at ten requests/second; this is offered load, not maximum capacity.
   time.sleep(max(0,0.1-(time.monotonic()-t)))
  return samples,errors
 with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency) as pool:rows=list(pool.map(worker,range(concurrency)))
 samples=sorted(x for row in rows for x in row[0]);errors=[e for row in rows for e in row[1]];elapsed=time.monotonic()-start
 result={'clients':concurrency,'seconds':round(elapsed,3),'successful':len(samples),'failed':len(errors),'requestsPerSecond':round((len(samples)+len(errors))/elapsed,2),'p50Ms':samples[int((len(samples)-1)*.5)] if samples else None,'p95Ms':samples[int((len(samples)-1)*.95)] if samples else None,'p99Ms':samples[int((len(samples)-1)*.99)] if samples else None,'errors':errors[:10]}
 reports.append(result);print(json.dumps(result),flush=True)
 a.output.write_text(json.dumps({'scope':'Local API reads over the previous indexed 100-transaction fork dataset; no concurrent chain writes. Not production capacity.','phases':reports},indent=2)+'\n')
assert all(r['failed']==0 for r in reports), 'API load had failures; inspect the report'
