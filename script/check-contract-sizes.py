#!/usr/bin/env python3
"""Enforce deployment limits for every production artifact compiled from this repository's src/."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
required = {'AsyncSwap', 'AsyncMatching', 'Router', 'FeeVault', 'NativeClaims', 'TokenClaims',
            'MatchingEngine', 'TickPrice'}
rows = []
for path in sorted((root / 'out').glob('*/*.json')):
    artifact = json.loads(path.read_text())
    metadata = artifact.get('metadata', {})
    if isinstance(metadata, str):
        metadata = json.loads(metadata)
    for source, name in metadata.get('settings', {}).get('compilationTarget', {}).items():
        if not source.startswith('src/') or not (root / source).is_file():
            continue
        runtime = len(artifact.get('deployedBytecode', {}).get('object', '').removeprefix('0x')) // 2
        creation = len(artifact.get('bytecode', {}).get('object', '').removeprefix('0x')) // 2
        rows.append(dict(contract=name, source=source, runtime=runtime, creation=creation))
assert required <= {r['contract'] for r in rows}, 'Missing core artifacts: run forge build first'
print(json.dumps(rows, indent=2))
failed = [r for r in rows if r['runtime'] > 24_576 or r['creation'] > 49_152]
assert not failed, f'Production contracts exceed EIP-170/EIP-3860 limits: {failed}'
