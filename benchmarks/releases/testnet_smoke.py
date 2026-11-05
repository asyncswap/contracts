#!/usr/bin/env python3
"""Explicit testnet smoke: initialize ETH/numeraire, create, top up and cancel.

Run through Olive: olive exec new-deployer -- python3 benchmarks/releases/testnet_smoke.py --broadcast
Spends 0.001 test USDC/USDG per chain plus test ETH gas. Never retries a submission.
"""
import argparse
import json
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OWNER = '0x33ce69DA05c3ad30A3b525625F950fAda8673205'
NETWORKS = {1301: 'https://sepolia.unichain.org', 46630: 'https://rpc.testnet.chain.robinhood.com'}
ORDER_TYPE = '((address,address,uint24,int24,address),address,bool,uint256,uint256,uint256,uint160,bytes32)'
ZERO = '0x' + '00' * 32


def cast(*args):
    return subprocess.check_output(['cast', *map(str, args)], text=True).strip()


def run(chain, url):
    def rpc(method, params):
        return json.loads(cast('rpc', method, json.dumps(params), '--raw', '--rpc-url', url))

    assert int(rpc('eth_chainId', []), 16) == chain
    registry = json.loads((ROOT / f'deployments/{chain}/{chain}.json').read_text())
    c = registry['contracts']
    hook, router, pm = (c[n]['address'] for n in ['AsyncSwap', 'Router', 'PoolManager'])
    assert registry['features']['priorityFeeTopUps']
    key = json.loads((ROOT / f'deployments/{chain}/{chain}-pool.json').read_text())
    old_hook = key['hooks']
    assert old_hook.lower() != hook.lower(), 'Run once against the new deployment; existing pools need a separate test.'
    token = key['currency1']
    assert int(key['currency0'], 16) == 0
    evidence_path = ROOT / f'deployments/{chain}/{chain}-v1.3.0-smoke.json'
    existing = json.loads(evidence_path.read_text()) if evidence_path.exists() else None
    assert existing is None or ([x['action'] for x in existing['transactions']] in [['initialize'], ['initialize', 'approve_exact_input_and_topup']] and not existing['complete']), 'Only a setup-only run can resume; inspect all other existing evidence manually.'
    evidence = {'chainId': chain, 'owner': OWNER, 'hook': hook, 'router': router, 'transactions': [], 'complete': False}

    if existing:
        assert existing['hook'] == hook and existing['owner'] == OWNER
        evidence = existing
    next_nonce = int(rpc('eth_getTransactionCount', [OWNER, 'pending']), 16)

    def save():
        evidence_path.write_text(json.dumps(evidence, indent=2) + '\n')

    def call(to, sig, *args):
        return rpc('eth_call', [{'to': to, 'data': cast('calldata', sig, *args)}, 'latest'])

    def number(to, sig, *args):
        return int(call(to, sig, *args), 16)

    def send(label, to, sig, *args):
        nonlocal next_nonce
        if existing and any(x['action'] == label for x in existing['transactions']):
            previous = next(x for x in existing['transactions'] if x['action'] == label)
            receipt = rpc('eth_getTransactionReceipt', [previous['hash']])
            assert receipt and int(receipt['status'], 16) == 1
            return receipt
        data = cast('calldata', sig, *args)
        # Simulate from the actual maker with zero priority, matching the transaction below.
        rpc('eth_call', [{'from': OWNER, 'to': to, 'data': data, 'maxPriorityFeePerGas': '0x0'}, 'latest'])
        tx = cast('send', to, '--data', data, '--rpc-url', url, '--account', 'new-deployer', '--priority-gas-price', '0', '--gas-limit', '1500000', '--nonce', next_nonce, '--async')
        assert tx.startswith('0x') and len(tx) == 66, tx
        next_nonce += 1
        row = {'action': label, 'hash': tx}
        evidence['transactions'].append(row)
        save()  # Persist before waiting: a timeout must never cause an additive top-up to be sent twice.
        print(chain, label, tx, flush=True)
        for _ in range(120):
            receipt = rpc('eth_getTransactionReceipt', [tx])
            if receipt:
                row.update(blockNumber=int(receipt['blockNumber'], 16), gasUsed=int(receipt['gasUsed'], 16), status=int(receipt['status'], 16))
                save()
                assert row['status'] == 1, (label, tx)
                # Public RPC backends can lag the node that returned the receipt.
                time.sleep(3)
                return receipt
            time.sleep(1)
        raise RuntimeError(f'Transaction pending: {tx}; check its receipt, do not resubmit.')

    def pool_tuple(address):
        return f'({key["currency0"]},{token},{key["fee"]},{key["tickSpacing"]},{address})'

    def pool_id(address):
        return cast('keccak', cast('abi-encode', 'f(address,address,uint24,int24,address)', key['currency0'], token, key['fee'], key['tickSpacing'], address))

    old_pool, pool = pool_id(old_hook), pool_id(hook)
    # Uniswap v4 StateLibrary stores pools at mapping slot 6; slot zero packs sqrtPriceX96 in its low 160 bits.
    old_slot = cast('keccak', cast('abi-encode', 'f(bytes32,uint256)', old_pool, 6))
    sqrt_price = number(pm, 'extsload(bytes32)', old_slot) & ((1 << 160) - 1)
    assert sqrt_price > 0, 'Previous pool is not initialized.'
    balance_before = number(token, 'balanceOf(address)', OWNER)
    vault_before = number(pm, 'balanceOf(address,uint256)', c['FeeVault']['address'], int(token, 16))
    assert balance_before >= 1001000
    assert number(token, 'allowance(address,address)', OWNER, router) == (1001000 if existing and len(existing['transactions']) == 2 else 0)
    send('initialize', pm, 'initialize((address,address,uint24,int24,address),uint160)', pool_tuple(hook), sqrt_price)
    send('approve_exact_input_and_topup', token, 'approve(address,uint256)', router, 1001000)
    send('authorize_router', hook, 'setExecutor(bytes32,address,bool)', pool, router, 'true')
    user_data = cast('abi-encode', 'f(address,address,uint256,uint256)', OWNER, router, 10**14, 0)

    def order(salt):
        return f'({pool_tuple(hook)},{OWNER},false,1000000,100000000000000,0,{sqrt_price},{salt})'

    receipt = send('create', router, f'swap({ORDER_TYPE},bytes)', order(ZERO), user_data)
    topic = cast('keccak', 'AsyncOrderCreated(bytes32,bytes32,address,bool,uint256,uint256,bytes32)')
    logs = [x for x in receipt['logs'] if x['address'].lower() == hook.lower() and x['topics'][0].lower() == topic.lower()]
    assert len(logs) == 1
    order_id = logs[0]['topics'][2]
    salt = '0x' + logs[0]['data'][-64:]
    state_before = call(hook, 'asyncOrderInfo(bytes32,bytes32)', pool, order_id)
    assert int(state_before[2:66], 16) == 1000000
    assert int(state_before[66:], 16) == 10**14
    assert number(hook, 'asyncOrderPriorityFee(bytes32,bytes32)', pool, order_id) == 0
    age_before = number(hook, 'orderCreatedSequence(bytes32,bytes32)', pool, order_id)
    receipt = send('top_up', router, f'topUpPriorityFee({ORDER_TYPE},uint256)', order(salt), 1000)
    fee_topic = cast('keccak', 'AsyncOrderPriorityFeeUpdated(bytes32,bytes32,uint256,uint256)')
    updates = [x for x in receipt['logs'] if x['address'].lower() == hook.lower() and x['topics'][0].lower() == fee_topic.lower()]
    assert len(updates) == 1 and updates[0]['topics'][2].lower() == order_id.lower()
    assert int(updates[0]['data'][2:66], 16) == 1000 and int(updates[0]['data'][66:], 16) == 1000
    assert number(hook, 'asyncOrderPriorityFee(bytes32,bytes32)', pool, order_id) == 1000
    assert call(hook, 'asyncOrderInfo(bytes32,bytes32)', pool, order_id) == state_before
    assert number(hook, 'orderCreatedSequence(bytes32,bytes32)', pool, order_id) == age_before
    send('cancel', router, f'cancelOrder({ORDER_TYPE})', order(salt))
    assert number(hook, 'asyncOrder(bytes32,bytes32)', pool, order_id) == 0
    assert number(token, 'balanceOf(address)', OWNER) == balance_before - 1000
    assert number(pm, 'balanceOf(address,uint256)', c['FeeVault']['address'], int(token, 16)) == vault_before + 1000
    assert number(token, 'allowance(address,address)', OWNER, router) == 0
    key['hooks'] = hook
    (ROOT / f'deployments/{chain}/{chain}-pool.json').write_text(json.dumps(key, indent=2) + '\n')
    evidence.update(complete=True, poolId=pool, orderId=order_id, addedFee=1000, inputReturned=1000000, makerAgePreserved=True, orderTermsPreserved=True, topupEventVerified=True, feeVaultCredited=True, remainingTokenAllowance=0)
    save()
    print(chain, 'smoke passed', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--broadcast', action='store_true', required=True)
    args = parser.parse_args()
    checked_account = False
    for chain_id, rpc_url in NETWORKS.items():
        evidence = ROOT / f'deployments/{chain_id}/{chain_id}-v1.3.0-smoke.json'
        if evidence.exists() and json.loads(evidence.read_text()).get('complete'):
            print(chain_id, 'already completed; no transactions submitted', flush=True)
            continue
        if not checked_account:
            assert cast('wallet', 'address', '--account', 'new-deployer').lower() == OWNER.lower()
            checked_account = True
        run(chain_id, rpc_url)
