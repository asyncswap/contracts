#!/usr/bin/env python3
"""Measure independent transactions against exported public-API fixtures on local Anvil."""
import os
import hashlib
import json
from pathlib import Path
import re
import socket
import subprocess
import time
import urllib.request

root = Path(__file__).resolve().parents[2]
env = dict(os.environ, FOUNDRY_TEST='benchmarks/topups/fixtures',
    FOUNDRY_OUT='.local/topup-benchmark/out', FOUNDRY_CACHE_PATH='.local/topup-benchmark/cache')
run = subprocess.run(['forge', 'test', '--match-contract', 'PriorityFeeTopUpGasTest',
    '--match-test', 'test_export', '--no-dynamic-test-linking', '-vv'], cwd=root, env=env,
    text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
if run.returncode:
    raise RuntimeError(run.stdout)
commands = re.findall(r'TX\|([^|]+)\|(0x[0-9a-fA-F]+)\|(0x[0-9a-fA-F]+)\|(0x[0-9a-fA-F]+)', run.stdout)
assert len(commands) == 4, run.stdout
event_topic = subprocess.check_output(['cast', 'keccak',
    'AsyncOrderPriorityFeeUpdated(bytes32,bytes32,uint256,uint256)'], text=True).strip()

def measure(command):
    name, target, actor, data = command
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
        state = json.loads((root / f'deployments/topup-{name}.json').read_text())
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
        rpc('anvil_impersonateAccount', [actor])
        rpc('anvil_setBalance', [actor, hex(10**20)])
        rpc('evm_setNextBlockTimestamp', [1000])
        rpc('anvil_setNonce', [actor, '0x0'])
        rpc('anvil_setNextBlockBaseFeePerGas', ['0x0'])
        tx = rpc('eth_sendTransaction', [{'from':actor,'to':target,'data':data,'gas':hex(30_000_000),'gasPrice':'0x0'}])
        receipt = None
        for _ in range(100):
            receipt = rpc('eth_getTransactionReceipt', [tx])
            if receipt is not None:
                break
            time.sleep(0.05)
        assert receipt is not None, ('receipt timeout', name, tx)
        assert receipt['status'] == '0x1', (name, receipt, rpc('debug_traceTransaction', [tx, {'tracer':'callTracer'}]))
        logs = [{'address':x['address'], 'topics':x['topics'], 'data':x['data']} for x in receipt['logs']]
        topups = [log for log in logs if log['topics'][0] == event_topic]
        assert len(topups) == 1, (name, logs)
        assert int(topups[0]['data'][2:66], 16) == 100_000
        assert int(topups[0]['data'][66:], 16) == (100_000 if name == 'single_zero' else 200_000)
        return {'workload': name, 'gas_used': int(receipt['gasUsed'],16),
            'logs_sha256': hashlib.sha256(json.dumps(logs,sort_keys=True).encode()).hexdigest(),
            'transaction_hash': tx, 'status': 1}
    finally:
        process.terminate()
        process.wait(timeout=10)

source_hashes = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
    for p in sorted((root / 'src').rglob('*.sol'))}
results = {'chain_id': 31337, 'hardfork': 'cancun', 'block_gas_limit': 30_000_000,
    'compiler': 'solc 0.8.26', 'optimizer_runs': 10_000,
    'forge_version': subprocess.check_output(['forge', '--version'], text=True).splitlines()[0],
    'added_fee_usdc_units': 100_000, 'intrinsic_gas_included': True,
    'refunds_applied': True, 'setup_and_approvals_excluded': True,
    'source_sha256': source_hashes,
    'measurements': [measure(command) for command in sorted(commands)]}
for row in results['measurements']:
    print(row['workload'], row['gas_used'])
(root / 'benchmarks/topups/results.json').write_text(json.dumps(results, indent=2) + '\n')
