# Deployments

Async Swap is deployed on three testnets and has no mainnet deployment. The earlier deployments on
Unichain and Arc mainnet were tests, had bugs, and are archived: do not send orders to them. The current testnet addresses and hook start blocks below match the per-chain deployment registries.

## Contracts

| | Unichain Sepolia (1301) | Robinhood Chain testnet (46630) | Arc testnet (5042002) |
| --- | --- | --- | --- |
| `AsyncSwap` (hook) | [`0x91B1e6C36Af74737FF82A654Fa7a1747fE186888`](https://sepolia.uniscan.xyz/address/0x91B1e6C36Af74737FF82A654Fa7a1747fE186888) | [`0x91E143120F9758b875713aA5E476E8e853C86888`](https://explorer.testnet.chain.robinhood.com/address/0x91E143120F9758b875713aA5E476E8e853C86888) | [`0x915bb9927D0860519a804345b27204E2C94a2888`](https://explorer.testnet.arc.io/address/0x915bb9927D0860519a804345b27204E2C94a2888) |
| `Router` | [`0x9FecF58D791d7167826EA18e2f653A8CDED79C1c`](https://sepolia.uniscan.xyz/address/0x9FecF58D791d7167826EA18e2f653A8CDED79C1c) | [`0xF1B572ADE26987F44Bf01A9f962B460e6Eeb8f89`](https://explorer.testnet.chain.robinhood.com/address/0xF1B572ADE26987F44Bf01A9f962B460e6Eeb8f89) | [`0x8FbeA6a4C4DD44616fc2eDf9fcb9Fd36da6d886F`](https://explorer.testnet.arc.io/address/0x8FbeA6a4C4DD44616fc2eDf9fcb9Fd36da6d886F) |
| `FeeVault` | [`0xbB4FEEBf05D6F4f6eE76f951ce6964e48E5ce9A4`](https://sepolia.uniscan.xyz/address/0xbB4FEEBf05D6F4f6eE76f951ce6964e48E5ce9A4) | [`0x24FBfcf78f844CBbA196D85c2F3F48d99B73267c`](https://explorer.testnet.chain.robinhood.com/address/0x24FBfcf78f844CBbA196D85c2F3F48d99B73267c) | [`0xE612f4cfBAAC021030707cCfEC1d9BC49B49442B`](https://explorer.testnet.arc.io/address/0xE612f4cfBAAC021030707cCfEC1d9BC49B49442B) |
| `AsyncMatching` | [`0xac90214FF07101Ec1cB4D52503A3bbb0c7F544b7`](https://sepolia.uniscan.xyz/address/0xac90214FF07101Ec1cB4D52503A3bbb0c7F544b7) | [`0xac90214FF07101Ec1cB4D52503A3bbb0c7F544b7`](https://explorer.testnet.chain.robinhood.com/address/0xac90214FF07101Ec1cB4D52503A3bbb0c7F544b7) | [`0xac90214FF07101Ec1cB4D52503A3bbb0c7F544b7`](https://explorer.testnet.arc.io/address/0xac90214FF07101Ec1cB4D52503A3bbb0c7F544b7) |
| `TickPrice` | [`0x4FFE1e1C663A8f4D09ddBD52902fcd1ba9F4ff5F`](https://sepolia.uniscan.xyz/address/0x4FFE1e1C663A8f4D09ddBD52902fcd1ba9F4ff5F) | [`0x4FFE1e1C663A8f4D09ddBD52902fcd1ba9F4ff5F`](https://explorer.testnet.chain.robinhood.com/address/0x4FFE1e1C663A8f4D09ddBD52902fcd1ba9F4ff5F) | [`0x4FFE1e1C663A8f4D09ddBD52902fcd1ba9F4ff5F`](https://explorer.testnet.arc.io/address/0x4FFE1e1C663A8f4D09ddBD52902fcd1ba9F4ff5F) |
| `DynamicFeeOrdering` | [`0xCfEe50D16C2Aea951Bc2302De14d875Cb51a938c`](https://sepolia.uniscan.xyz/address/0xCfEe50D16C2Aea951Bc2302De14d875Cb51a938c) | [`0xCfEe50D16C2Aea951Bc2302De14d875Cb51a938c`](https://explorer.testnet.chain.robinhood.com/address/0xCfEe50D16C2Aea951Bc2302De14d875Cb51a938c) | [`0xCfEe50D16C2Aea951Bc2302De14d875Cb51a938c`](https://explorer.testnet.arc.io/address/0xCfEe50D16C2Aea951Bc2302De14d875Cb51a938c) |
| PoolManager | [`0x00B036B58a818B1BC34d502D3fE730Db729e62AC`](https://sepolia.uniscan.xyz/address/0x00B036B58a818B1BC34d502D3fE730Db729e62AC) | [`0x8366a39CC670B4001A1121B8F6A443A643e40951`](https://explorer.testnet.chain.robinhood.com/address/0x8366a39CC670B4001A1121B8F6A443A643e40951) | [`0x8366a39CC670B4001A1121B8F6A443A643e40951`](https://explorer.testnet.arc.io/address/0x8366a39CC670B4001A1121B8F6A443A643e40951) |
| Numeraire | USDC [`0x31d0220469e10c4e71834a79b1f276d740d3768f`](https://sepolia.uniscan.xyz/address/0x31d0220469e10c4e71834a79b1f276d740d3768f) | Paxos USDG [`0x7E955252E15c84f5768B83c41a71F9eba181802F`](https://explorer.testnet.chain.robinhood.com/address/0x7E955252E15c84f5768B83c41a71F9eba181802F) | USDC [`0x3600000000000000000000000000000000000000`](https://explorer.testnet.arc.io/address/0x3600000000000000000000000000000000000000) |
| Hook start block | 66,737,245 | 146,837,556 | 70,285,011 |

How to read the table:

- **`AsyncSwap`, `Router`, `FeeVault`** are the protocol. The hook address is mined per chain for
  its Uniswap v4 permission bits, so it differs by chain, and `FeeVault` is created by the hook's
  constructor. Router addresses depend on the deployer nonce on each chain.
- **`AsyncMatching`, `TickPrice`, `DynamicFeeOrdering`** are linked libraries, created through the
  deterministic CREATE2 deployer (`0x4e59b44847b379578588920cA78FbF26c0B4956C`) with fixed salts.
  Identical bytecode gets the same address on every chain.
- **Pool parameters are fixed at deployment.** No setter changes them and anyone can open a pool. On
  these hooks `minOrder` is 0 (no dollar minimum) and `assetPrecision` is 4: an order's asset side
  must be at least 0.0001 of a whole token, or 10^(decimals - 4) base units. The optional priority bid's
  minimum is capped at $0.10, derived from the numeraire's decimals. Routers batch calls with `multicall`.
- **`WithdrawalRouter` entries in the registries are not for these hooks.** They were deployed for
  earlier hooks and are kept as a record. Cancels and claims go through the `Router` above.
- **PoolManager** is the Uniswap v4 singleton the hook is attached to. All three testnets
  use existing instances.
- **Numeraire** is the stablecoin every pool is priced in.
- **Hook start block** is where an indexer should start reading the hook's events.

The per-chain registries in [`deployments/`](../deployments) are the source of truth: each
`deployments/<chainId>/<chainId>.json` holds every address with its deployment transaction and start
block. The docs site serves all of them, with each chain's name, explorer and numeraire, as one file
at [`/deployments.json`](https://docs.asyncswap.org/deployments.json).

## Network notes

| Network | Chain ID | Gas token | Notes |
| --- | --- | --- | --- |
| Unichain Sepolia | 1301 | ETH | Uniswap's PoolManager. |
| Robinhood Chain testnet | 46630 | ETH | No Circle USDC; the numeraire is Paxos USDG (6 decimals) from [faucet.paxos.com](https://faucet.paxos.com). An Arbitrum chain: `block.number` inside contracts is the L1 block, so start blocks come from receipts. |
| Arc testnet | 5042002 | USDC | Gas is paid in USDC ([faucet.circle.com](https://faucet.circle.com)), and the numeraire is the ERC-20 interface to that same balance. **Never initialize a pool with the native currency.** Uniswap does not list Arc testnet; this PoolManager's runtime bytecode is identical to the official Arc mainnet PoolManager at the same address. |

## Deploying

`script/deploy.sh <chain-key> [dry-run|broadcast|verify]` deploys the libraries (when missing), the
hook and the Router, then writes the registry. Each network has a wrapper:
`deploy-unichain-sepolia.sh`, `deploy-robinhood-testnet.sh` and
`deploy-arc-testnet.sh`. Chain addresses come from
[`script/config/chains.json`](../script/config/chains.json); RPCs and the keystore account come from
`.env.deploy` (see [`.env.deploy.example`](../.env.deploy.example)).

With the keystore enrolled in Olive, Touch ID signs each step:

```bash
olive exec new-deployer -- script/deploy-arc-testnet.sh broadcast
```

`verify` submits every registry
entry to Sourcify, then to the chain's Blockscout explorer when there is one, and writes standard
JSON inputs to `deployments/<chainId>/verify/` for manual upload.
