#!/usr/bin/env python3
"""Measure independent transactions against exported public-API fixtures on local Anvil."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import socket
import subprocess
import time
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument('workspace', type=Path)
args = parser.parse_args()
workspace = args.workspace.resolve()

def measure(variant):
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    url = f'http://127.0.0.1:{port}'
    process = subprocess.Popen(['anvil', '--host', '127.0.0.1', '--port', str(port),
        '--chain-id', '31337', '--gas-limit', '30000000', '--hardfork', 'cancun',
        '--base-fee', '0', '--timestamp', '1', '--silent'], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    def rpc(method, params):
        req = urllib.request.Request(url, data=json.dumps({'jsonrpc':'2.0','id':1,'method':method,'params':params}).encode(), headers={'Content-Type':'application/json'})
        response = json.load(urllib.request.urlopen(req, timeout=30))
        if 'error' in response:
            raise RuntimeError((method, response['error']))
        return response['result']
    try:
        for _ in range(100):
            if process.poll() is not None:
                raise RuntimeError(process.stderr.read().decode())
            try:
                assert rpc('eth_chainId', []) == '0x7a69'
                break
            except OSError:
                time.sleep(0.05)
        else:
            raise RuntimeError('Anvil did not start')
        state = json.loads((workspace / variant / 'deployments/research-fixture.json').read_text())
        updates = []
        for address, account in state.items():
            if account['code'] != '0x': updates.append(('anvil_setCode', [address, account['code']]))
            if int(account['balance'],16): updates.append(('anvil_setBalance', [address, account['balance']]))
            if int(account['nonce'],16): updates.append(('anvil_setNonce', [address, account['nonce']]))
            for slot, value in account['storage'].items():
                if int(value,16): updates.append(('anvil_setStorageAt', [address, slot, value]))
        for start in range(0, len(updates), 200):
            batch = [{'jsonrpc':'2.0','id':i,'method':m,'params':p} for i,(m,p) in enumerate(updates[start:start+200])]
            req = urllib.request.Request(url, data=json.dumps(batch).encode(), headers={'Content-Type':'application/json'})
            response = json.load(urllib.request.urlopen(req, timeout=30))
            assert all('error' not in x for x in response), response
        commands = re.findall(r'TX\|([^|]+)\|(0x[0-9a-fA-F]+)\|(0x[0-9a-fA-F]+)\|(0x[0-9a-fA-F]+)',
            (workspace / f'{variant}-export.log').read_text())
        assert len(commands) == 4
        results = []
        for name, target, actor, data in commands:
            snapshot = rpc('evm_snapshot', [])
            rpc('anvil_impersonateAccount', [actor])
            rpc('anvil_setBalance', [actor, hex(10**20)])
            rpc('evm_setNextBlockTimestamp', [1000])
            rpc('anvil_setNextBlockBaseFeePerGas', ['0x0'])
            tx = rpc('eth_sendTransaction', [{'from':actor,'to':target,'data':data,'gas':hex(30_000_000),'gasPrice':'0x0'}])
            receipt = None
            for _ in range(100):
                receipt = rpc('eth_getTransactionReceipt', [tx])
                if receipt is not None:
                    break
                time.sleep(0.05)
            assert receipt is not None, ('receipt timeout', name, tx)
            assert receipt['status'] == '0x1', (name, receipt)
            logs = [{'address':x['address'], 'topics':x['topics'], 'data':x['data']} for x in receipt['logs']]
            results.append({'workload': name, 'gas_used': int(receipt['gasUsed'],16),
                'logs_sha256': hashlib.sha256(json.dumps(logs,sort_keys=True).encode()).hexdigest(),
                'transaction_hash': tx, 'status': 1})
            assert rpc('evm_revert', [snapshot])
        return results
    finally:
        process.terminate()
        process.wait(timeout=10)

results = {'chain_id':31337, 'hardfork':'cancun', 'block_gas_limit':30_000_000,
    'shape':'256 distinct resting ask prices, distinct owners', 'intrinsic_gas_included':True,
    'refunds_applied':True, 'setup_and_approvals_excluded':True,
    'variants':{v:measure(v) for v in ('baseline','bitmap')}}
for a,b in zip(results['variants']['baseline'], results['variants']['bitmap']):
    assert a['workload'] == b['workload'] and a['logs_sha256'] == b['logs_sha256'], ('event mismatch', a,b)
    print(a['workload'], a['gas_used'], b['gas_used'], round(100*(a['gas_used']-b['gas_used'])/a['gas_used'],2))
(workspace/'receipts.json').write_text(json.dumps(results,indent=2)+'\n')
