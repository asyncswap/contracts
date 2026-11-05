#!/usr/bin/env python3
"""Compare this checkout with a pinned radix baseline in isolated workspaces."""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

assets = Path(__file__).resolve().parent
source = assets.parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, required=True, help='New directory outside this checkout')
parser.add_argument('--baseline-ref', default='abf374271c3378a4f461841fd7dac3867f3f5158')
args = parser.parse_args()
workspace = args.output.resolve()
if workspace == source or source in workspace.parents:
    parser.error('--output must be outside this checkout')
baseline = subprocess.check_output(['git','rev-parse',args.baseline_ref+'^{commit}'],cwd=source,text=True).strip()
workspace.mkdir(parents=True, exist_ok=False)
source_hashes = {str(p.relative_to(source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((source/'src').rglob('*.sol'))}
for variant in ('baseline','bitmap'):
    target=workspace/variant
    target.mkdir()
    if variant=='baseline':
        with tempfile.TemporaryFile() as archive:
            subprocess.run(['git','archive',baseline,'src','test','script','foundry.toml','remappings.txt'],cwd=source,stdout=archive,check=True)
            archive.seek(0)
            with tarfile.open(fileobj=archive) as tar: tar.extractall(target, filter='data')
        # The baseline keeps its original outer radix book. Only the comparison harness needs this library.
        shutil.copy2(source/'src/libraries/TickBitmap.sol',target/'src/libraries/TickBitmap.sol')
        for name in ('MatchingReference.t.sol','TickBitmap.t.sol','utils/TickIndexHarness.sol'):
            shutil.copy2(source/'test'/name,target/'test'/name)
    else:
        for folder in ('src','test','script'): shutil.copytree(source/folder,target/folder)
        for name in ('foundry.toml','remappings.txt'): shutil.copy2(source/name,target/name)
    (target/'dependencies').symlink_to(source/'dependencies',target_is_directory=True)
    (target/'deployments').mkdir()
    for p in (assets/'fixtures').glob('*.sol'): shutil.copy2(p,target/'test'/p.name)

checks=[]
def run(variant,label,flags,export=False):
    command=['forge','test','--fuzz-runs','128','--fuzz-seed','0x5eed','--gas-limit','10000000000']+flags
    env=dict(os.environ)
    env.pop('EXPORT_RESEARCH_FIXTURE',None)
    if export: env['EXPORT_RESEARCH_FIXTURE']='true'
    log=workspace/(variant+'-'+label+'.log')
    with log.open('w') as out:
        result=subprocess.run(command,cwd=workspace/variant,env=env,stdout=out,stderr=subprocess.STDOUT)
    if result.returncode:
        print('\n'.join(log.read_text().splitlines()[-20:]),file=sys.stderr)
        raise RuntimeError(f'{variant} {label} failed: {log}')
    summary=re.findall(r'Ran .*test suites? .*: (\d+) tests passed, (\d+) failed, (\d+) skipped',log.read_text())[-1]
    passed,failed,skipped=map(int,summary)
    assert failed==skipped==0
    checks.append(dict(variant=variant,label=label,passed=passed,command=command))
    print(variant,label,passed,'passed',flush=True)

for variant in ('baseline','bitmap'):
    run(variant,'oracle',['--match-contract','MatchingReferenceTest','-vv'])
    run(variant,'coverage',['--match-contract','ResearchCoverageTest','-vv'])
    run(variant,'export',['--match-contract','ResearchLiveTest','--match-test','test_distinct256','-vv'],True)
subprocess.run([sys.executable,str(assets/'receipts.py'),str(workspace)],check=True)

def live(variant):
    return {(w,int(n)):(int(g),h) for w,n,g,h in re.findall(r'LIVE\|([^|]+)\|(\d+)\|(\d+)\|(0x[0-9a-f]+)',(workspace/(variant+'-coverage.log')).read_text())}
a,b=live('baseline'),live('bitmap')
assert len(a)==38 and a.keys()==b.keys()
rows=[]
for k in sorted(a):
    assert a[k][1]==b[k][1],('state mismatch',k)
    rows.append(dict(workload=k[0],orders=k[1],baseline_gross_gas=a[k][0],candidate_gross_gas=b[k][0],
        saving_percent=round(100*(a[k][0]-b[k][0])/a[k][0],3),state_digest=a[k][1]))
with (workspace/'coverage.csv').open('w',newline='') as out:
    writer=csv.DictWriter(out,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)

# Follow all compiler link references: checking only the entry hook can miss an oversized library.
def sizes(variant):
    result={}
    pending=[('AsyncSwap.sol','AsyncSwap'),('Router.sol','Router'),('FeeVault.sol','FeeVault')]
    while pending:
        file,name=pending.pop()
        if name in result: continue
        a=json.loads((workspace/variant/'out'/Path(file).name/(name+'.json')).read_text())
        code=a['deployedBytecode']
        size=len(code['object'].removeprefix('0x'))//2
        assert 0<size<=24_576,(variant,name,size)
        result[name]=size
        for f,libs in code['linkReferences'].items(): pending.extend((f,n) for n in libs)
    return result
assert all(hashlib.sha256((source/f).read_bytes()).hexdigest()==h for f,h in source_hashes.items()),'source changed during run'
result=dict(baseline_commit=baseline,candidate_source_hashes=source_hashes,checks=checks,matched_public_api_states=38,
    forge=subprocess.check_output(['forge','--version'],text=True).strip(),
    anvil=subprocess.check_output(['anvil','--version'],text=True).strip(),
    runtime_bytes={v:sizes(v) for v in ('baseline','bitmap')},coverage=rows,
    receipts=json.loads((workspace/'receipts.json').read_text()))
(workspace/'results.json').write_text(json.dumps(result,indent=2)+'\n')
print('Complete:',workspace/'results.json')
