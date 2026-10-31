# Deployments

Async Swap is deployed on four testnets and has no mainnet deployment. The earlier deployments on
Unichain and Arc mainnet were tests, had bugs, and are archived: do not send orders to them. The current testnet addresses and hook start blocks below match the per-chain deployment registries.

## Contracts

| | Unichain Sepolia (1301) | Ethereum Sepolia (11155111) | Robinhood Chain testnet (46630) | Arc testnet (5042002) |
| --- | --- | --- | --- | --- |
| `AsyncSwap` (hook) | [`0x919F4c9F5eA50d04F72fe72F9ADdC2BaE42eA888`](https://sepolia.uniscan.xyz/address/0x919F4c9F5eA50d04F72fe72F9ADdC2BaE42eA888) | [`0x916373De182757f70048b6993519f9E681e86888`](https://sepolia.etherscan.io/address/0x916373De182757f70048b6993519f9E681e86888) | [`0x91bd732b4BEB3aF4b29Dd631aC83bE7ebbbFA888`](https://explorer.testnet.chain.robinhood.com/address/0x91bd732b4BEB3aF4b29Dd631aC83bE7ebbbFA888) | [`0x91502692bc33610F803DA85507A29DA1dC266888`](https://explorer.testnet.arc.io/address/0x91502692bc33610F803DA85507A29DA1dC266888) |
| `Router` | [`0x8FbeA6a4C4DD44616fc2eDf9fcb9Fd36da6d886F`](https://sepolia.uniscan.xyz/address/0x8FbeA6a4C4DD44616fc2eDf9fcb9Fd36da6d886F) | [`0x2CCdFB7085e6e42e814cA8E7055483d1ccE95c38`](https://sepolia.etherscan.io/address/0x2CCdFB7085e6e42e814cA8E7055483d1ccE95c38) | [`0xE35C5df17676809b25995bE17d3a59498C75BC59`](https://explorer.testnet.chain.robinhood.com/address/0xE35C5df17676809b25995bE17d3a59498C75BC59) | [`0xE35C5df17676809b25995bE17d3a59498C75BC59`](https://explorer.testnet.arc.io/address/0xE35C5df17676809b25995bE17d3a59498C75BC59) |
| `FeeVault` | [`0x5242ccbD1C03537Fe4BFc3Ae604493BFbAfc859c`](https://sepolia.uniscan.xyz/address/0x5242ccbD1C03537Fe4BFc3Ae604493BFbAfc859c) | [`0x6eb5f30a80b38CF9bB3B87C1A6972DC387853948`](https://sepolia.etherscan.io/address/0x6eb5f30a80b38CF9bB3B87C1A6972DC387853948) | [`0x7e4D8A2Aa6052FA76324085Cb60F30173453BDC8`](https://explorer.testnet.chain.robinhood.com/address/0x7e4D8A2Aa6052FA76324085Cb60F30173453BDC8) | [`0x533bf96ef69a2E9E94E8f42983439C25d7dDAbb1`](https://explorer.testnet.arc.io/address/0x533bf96ef69a2E9E94E8f42983439C25d7dDAbb1) |
| `AsyncMatching` | [`0x04ceEeeb17C3e75B0F6D1fBE6486Cf2Da8cC01d2`](https://sepolia.uniscan.xyz/address/0x04ceEeeb17C3e75B0F6D1fBE6486Cf2Da8cC01d2) | [`0x04ceEeeb17C3e75B0F6D1fBE6486Cf2Da8cC01d2`](https://sepolia.etherscan.io/address/0x04ceEeeb17C3e75B0F6D1fBE6486Cf2Da8cC01d2) | [`0x04ceEeeb17C3e75B0F6D1fBE6486Cf2Da8cC01d2`](https://explorer.testnet.chain.robinhood.com/address/0x04ceEeeb17C3e75B0F6D1fBE6486Cf2Da8cC01d2) | [`0x04ceEeeb17C3e75B0F6D1fBE6486Cf2Da8cC01d2`](https://explorer.testnet.arc.io/address/0x04ceEeeb17C3e75B0F6D1fBE6486Cf2Da8cC01d2) |
| `TickPrice` | [`0xb08191f43308E1759586236b140368E4351a6506`](https://sepolia.uniscan.xyz/address/0xb08191f43308E1759586236b140368E4351a6506) | [`0xb08191f43308E1759586236b140368E4351a6506`](https://sepolia.etherscan.io/address/0xb08191f43308E1759586236b140368E4351a6506) | [`0xb08191f43308E1759586236b140368E4351a6506`](https://explorer.testnet.chain.robinhood.com/address/0xb08191f43308E1759586236b140368E4351a6506) | [`0xb08191f43308E1759586236b140368E4351a6506`](https://explorer.testnet.arc.io/address/0xb08191f43308E1759586236b140368E4351a6506) |
| `DynamicFeeOrdering` | [`0xe7359f9c28Ea618D224847fc94614269458B99a3`](https://sepolia.uniscan.xyz/address/0xe7359f9c28Ea618D224847fc94614269458B99a3) | [`0xe7359f9c28Ea618D224847fc94614269458B99a3`](https://sepolia.etherscan.io/address/0xe7359f9c28Ea618D224847fc94614269458B99a3) | [`0xe7359f9c28Ea618D224847fc94614269458B99a3`](https://explorer.testnet.chain.robinhood.com/address/0xe7359f9c28Ea618D224847fc94614269458B99a3) | [`0xe7359f9c28Ea618D224847fc94614269458B99a3`](https://explorer.testnet.arc.io/address/0xe7359f9c28Ea618D224847fc94614269458B99a3) |
| PoolManager | [`0x00B036B58a818B1BC34d502D3fE730Db729e62AC`](https://sepolia.uniscan.xyz/address/0x00B036B58a818B1BC34d502D3fE730Db729e62AC) | [`0xE03A1074c86CFeDd5C142C4F04F1a1536e203543`](https://sepolia.etherscan.io/address/0xE03A1074c86CFeDd5C142C4F04F1a1536e203543) | [`0x8366a39CC670B4001A1121B8F6A443A643e40951`](https://explorer.testnet.chain.robinhood.com/address/0x8366a39CC670B4001A1121B8F6A443A643e40951) | [`0x8366a39CC670B4001A1121B8F6A443A643e40951`](https://explorer.testnet.arc.io/address/0x8366a39CC670B4001A1121B8F6A443A643e40951) |
| Numeraire | USDC [`0x31d0220469e10c4e71834a79b1f276d740d3768f`](https://sepolia.uniscan.xyz/address/0x31d0220469e10c4e71834a79b1f276d740d3768f) | Circle test USDC [`0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238`](https://sepolia.etherscan.io/address/0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238) | Paxos USDG [`0x7E955252E15c84f5768B83c41a71F9eba181802F`](https://explorer.testnet.chain.robinhood.com/address/0x7E955252E15c84f5768B83c41a71F9eba181802F) | USDC [`0x3600000000000000000000000000000000000000`](https://explorer.testnet.arc.io/address/0x3600000000000000000000000000000000000000) |
| Hook start block | 66,580,115 | 12,032,423 | 145,819,535 | 69,975,723 |

How to read the table:

* **`AsyncSwap`, `Router`, `FeeVault`** are the protocol. The hook address is mined per chain for
  its Uniswap v4 permission bits, so it differs by chain, and `FeeVault` is created by the hook's
  constructor. Router addresses depend on the deployer nonce on each chain.
* **`AsyncMatching`, `TickPrice`, `DynamicFeeOrdering`** are linked libraries, created through the
  deterministic CREATE2 deployer (`0x4e59b44847b379578588920cA78FbF26c0B4956C`) with fixed salts,
  so they have the same address on every chain.
* **PoolManager** is the Uniswap v4 singleton the hook is attached to. The four deployed testnets
  use existing instances; new testnets without one require a local PoolManager deployment.
* **Numeraire** is the stablecoin every pool is priced in.
* **Hook start block** is where an indexer should start reading the hook's events.

The per-chain registries in [`deployments/`](https://github.com/asyncswap/contracts/blob/main/deployments) are the source of truth: each
`deployments/<chainId>/<chainId>.json` holds every address with its deployment transaction and start
block. The docs site serves all of them, with each chain's name, explorer and numeraire, as one file
at [`/deployments.json`](https://docs.asyncswap.org/deployments.json).

## Network notes

| Network | Chain ID | Gas token | Notes |
| --- | --- | --- | --- |
| Unichain Sepolia | 1301 | ETH | Uniswap's PoolManager. |
| Ethereum Sepolia | 11155111 | ETH | Storing contract code costs about 7× Foundry's local estimate: deploy with `DEPLOY_GAS_MULTIPLIER=800`. |
| Robinhood Chain testnet | 46630 | ETH | No Circle USDC; the numeraire is Paxos USDG (6 decimals) from [faucet.paxos.com](https://faucet.paxos.com). An Arbitrum chain: `block.number` inside contracts is the L1 block, so start blocks come from receipts. |
| Arc testnet | 5042002 | USDC | Gas is paid in USDC ([faucet.circle.com](https://faucet.circle.com)), and the numeraire is the ERC-20 interface to that same balance. **Never initialize a pool with the native currency.** Uniswap does not list Arc testnet; this PoolManager's runtime bytecode is identical to the official Arc mainnet PoolManager at the same address. |

MegaETH testnet (6343) and HyperEVM testnet (998) are prepared but have **no Async Swap deployment
yet**. Their wrappers first deploy a PoolManager, then the hook and Router. MegaETH uses the
[official testnet USDM](https://github.com/megaeth-labs/mega-tokenlist) (18 decimals) as an explicit
testnet exception to the USDC numeraire plan. HyperEVM uses testnet USDC (6 decimals). The hook
sets the optional $0.10 priority-bid cap in each numeraire's base units before pools initialize.
HyperEVM requires the deployer to opt into [big blocks](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm/dual-block-architecture)
through the HyperCore `evmUserModify` action before broadcasting. Its fast blocks allow 3 million
gas, while PoolManager's runtime code deposit alone needs about 4.83 million. The deployment
wrapper checks `eth_usingBigBlocks` and stops if the deployer has not opted in.
After the deployer receives a HyperCore testnet asset and HYPE for EVM gas, enable routing
without exporting its private key:

```bash
olive exec new-deployer -- bun script/hyperevm-big-blocks.ts enable --broadcast
olive exec new-deployer -- script/deploy-hyperevm-testnet.sh broadcast
olive exec new-deployer -- bun script/hyperevm-big-blocks.ts disable --broadcast
```

The helper signs the HyperCore action through the Olive keystore and checks that the signature
recovers to `DEPLOY_OWNER` before submitting it. The final command restores fast-block routing
after contract deployment.

## Deploying

`script/deploy.sh <chain-key> [dry-run|broadcast|verify]` deploys the libraries (when missing), the
hook and the Router, then writes the registry. Each network has a wrapper:
`deploy-unichain-sepolia.sh`, `deploy-sepolia.sh`, `deploy-robinhood-testnet.sh` and
`deploy-arc-testnet.sh`. Chain addresses come from
[`script/config/chains.json`](https://github.com/asyncswap/contracts/blob/main/script/config/chains.json); RPCs and the keystore account come from
`.env.deploy` (see [`.env.deploy.example`](https://github.com/asyncswap/contracts/blob/main/.env.deploy.example)).

For a testnet without a PoolManager, use `deploy-megaeth-testnet.sh` or
`deploy-hyperevm-testnet.sh`. Each wrapper checks the chain, token decimals and dependencies,
deploys the PoolManager once, then runs `deploy.sh`. The signer in `DEPLOYER_ACCOUNT` must equal
`DEPLOY_OWNER` for these deployments. Fund that address with the network's gas token first.

With the keystore enrolled in Olive, Touch ID signs each step:

```bash
olive exec new-deployer -- script/deploy-arc-testnet.sh broadcast
```

On Ethereum Sepolia, put `DEPLOY_GAS_MULTIPLIER=800` in front. `verify` submits every registry
entry to Sourcify, then to the chain's Blockscout explorer when there is one, and writes standard
JSON inputs to `deployments/<chainId>/verify/` for manual upload.
