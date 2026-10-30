# Deployments

Async Swap is deployed on four testnets and has no mainnet deployment. The earlier deployments on
Unichain and Arc mainnet were tests, had bugs, and are archived: do not send orders to them. Every
contract in the table is source-verified on [Sourcify](https://sourcify.dev) (full match), and every
hook is owned by `0x33ce69DA05c3ad30A3b525625F950fAda8673205`.

## Contracts

| | Unichain Sepolia (1301) | Ethereum Sepolia (11155111) | Robinhood Chain testnet (46630) | Arc testnet (5042002) |
| --- | --- | --- | --- | --- |
| `AsyncSwap` (hook) | [`0x91FD5f707b384D61260b3EfD317d4B67375C2888`](https://sepolia.uniscan.xyz/address/0x91FD5f707b384D61260b3EfD317d4B67375C2888) | [`0x91720308BB0b6018e5F2480C10DB52dEd100e888`](https://sepolia.etherscan.io/address/0x91720308BB0b6018e5F2480C10DB52dEd100e888) | [`0x913142f9CFA32cc21bb9DE9E24e4cDc8f005A888`](https://explorer.testnet.chain.robinhood.com/address/0x913142f9CFA32cc21bb9DE9E24e4cDc8f005A888) | [`0x91BbbC18C7F2215d1205083578a941F1b5766888`](https://explorer.testnet.arc.io/address/0x91BbbC18C7F2215d1205083578a941F1b5766888) |
| `Router` | [`0x1cd2C2d1a82035bCf90D2bd79FBF043d99e1083b`](https://sepolia.uniscan.xyz/address/0x1cd2C2d1a82035bCf90D2bd79FBF043d99e1083b) | [`0xd25159473B1ba2979E92454620dDB86Fa2Af46EB`](https://sepolia.etherscan.io/address/0xd25159473B1ba2979E92454620dDB86Fa2Af46EB) | [`0x1cd2C2d1a82035bCf90D2bd79FBF043d99e1083b`](https://explorer.testnet.chain.robinhood.com/address/0x1cd2C2d1a82035bCf90D2bd79FBF043d99e1083b) | [`0x1cd2C2d1a82035bCf90D2bd79FBF043d99e1083b`](https://explorer.testnet.arc.io/address/0x1cd2C2d1a82035bCf90D2bd79FBF043d99e1083b) |
| `FeeVault` | [`0x7d8c6a8495c776522b83E9Ccb2752ffEA4ef2F3e`](https://sepolia.uniscan.xyz/address/0x7d8c6a8495c776522b83E9Ccb2752ffEA4ef2F3e) | [`0x4125560F702993F0f26E2d1B7E1793DAEaB2bE1a`](https://sepolia.etherscan.io/address/0x4125560F702993F0f26E2d1B7E1793DAEaB2bE1a) | [`0x4C74C36691f1EA50238945e74Da11bA4C7DD624D`](https://explorer.testnet.chain.robinhood.com/address/0x4C74C36691f1EA50238945e74Da11bA4C7DD624D) | [`0xD9EBe2446c3CB80809C7769bb45A9F0fb20f68e0`](https://explorer.testnet.arc.io/address/0xD9EBe2446c3CB80809C7769bb45A9F0fb20f68e0) |
| `AsyncMatching` | [`0xAc9c2C38534f3d984d49f4830a5e07edA6F1e1F5`](https://sepolia.uniscan.xyz/address/0xAc9c2C38534f3d984d49f4830a5e07edA6F1e1F5) | [`0xAc9c2C38534f3d984d49f4830a5e07edA6F1e1F5`](https://sepolia.etherscan.io/address/0xAc9c2C38534f3d984d49f4830a5e07edA6F1e1F5) | [`0xAc9c2C38534f3d984d49f4830a5e07edA6F1e1F5`](https://explorer.testnet.chain.robinhood.com/address/0xAc9c2C38534f3d984d49f4830a5e07edA6F1e1F5) | [`0xAc9c2C38534f3d984d49f4830a5e07edA6F1e1F5`](https://explorer.testnet.arc.io/address/0xAc9c2C38534f3d984d49f4830a5e07edA6F1e1F5) |
| `TickPrice` | [`0xd74BD0774EE57bb9939B9bA2127C2911039C27F6`](https://sepolia.uniscan.xyz/address/0xd74BD0774EE57bb9939B9bA2127C2911039C27F6) | [`0xd74BD0774EE57bb9939B9bA2127C2911039C27F6`](https://sepolia.etherscan.io/address/0xd74BD0774EE57bb9939B9bA2127C2911039C27F6) | [`0xd74BD0774EE57bb9939B9bA2127C2911039C27F6`](https://explorer.testnet.chain.robinhood.com/address/0xd74BD0774EE57bb9939B9bA2127C2911039C27F6) | [`0xd74BD0774EE57bb9939B9bA2127C2911039C27F6`](https://explorer.testnet.arc.io/address/0xd74BD0774EE57bb9939B9bA2127C2911039C27F6) |
| `DynamicFeeOrdering` | [`0xa6bc8acdF560D6C6169C442AF441e7fF53fC1A33`](https://sepolia.uniscan.xyz/address/0xa6bc8acdF560D6C6169C442AF441e7fF53fC1A33) | [`0xa6bc8acdF560D6C6169C442AF441e7fF53fC1A33`](https://sepolia.etherscan.io/address/0xa6bc8acdF560D6C6169C442AF441e7fF53fC1A33) | [`0xa6bc8acdF560D6C6169C442AF441e7fF53fC1A33`](https://explorer.testnet.chain.robinhood.com/address/0xa6bc8acdF560D6C6169C442AF441e7fF53fC1A33) | [`0xa6bc8acdF560D6C6169C442AF441e7fF53fC1A33`](https://explorer.testnet.arc.io/address/0xa6bc8acdF560D6C6169C442AF441e7fF53fC1A33) |
| PoolManager | [`0x00B036B58a818B1BC34d502D3fE730Db729e62AC`](https://sepolia.uniscan.xyz/address/0x00B036B58a818B1BC34d502D3fE730Db729e62AC) | [`0xE03A1074c86CFeDd5C142C4F04F1a1536e203543`](https://sepolia.etherscan.io/address/0xE03A1074c86CFeDd5C142C4F04F1a1536e203543) | [`0x8366a39CC670B4001A1121B8F6A443A643e40951`](https://explorer.testnet.chain.robinhood.com/address/0x8366a39CC670B4001A1121B8F6A443A643e40951) | [`0x8366a39CC670B4001A1121B8F6A443A643e40951`](https://explorer.testnet.arc.io/address/0x8366a39CC670B4001A1121B8F6A443A643e40951) |
| Numeraire | USDC [`0x31d0220469e10c4e71834a79b1f276d740d3768f`](https://sepolia.uniscan.xyz/address/0x31d0220469e10c4e71834a79b1f276d740d3768f) | Circle test USDC [`0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238`](https://sepolia.etherscan.io/address/0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238) | Paxos USDG [`0x7E955252E15c84f5768B83c41a71F9eba181802F`](https://explorer.testnet.chain.robinhood.com/address/0x7E955252E15c84f5768B83c41a71F9eba181802F) | USDC [`0x3600000000000000000000000000000000000000`](https://explorer.testnet.arc.io/address/0x3600000000000000000000000000000000000000) |
| Hook start block | 66,537,473 | 12,028,907 | 145,542,537 | 69,894,548 |

How to read the table:

* **`AsyncSwap`, `Router`, `FeeVault`** are the protocol. The hook address is mined per chain for
  its Uniswap v4 permission bits, so it differs by chain, and `FeeVault` is created by the hook's
  constructor. The Router is the same on every chain except Ethereum Sepolia.
* **`AsyncMatching`, `TickPrice`, `DynamicFeeOrdering`** are linked libraries, created through the
  deterministic CREATE2 deployer (`0x4e59b44847b379578588920cA78FbF26c0B4956C`) with fixed salts,
  so they have the same address on every chain.
* **PoolManager** is the Uniswap v4 singleton the hook is attached to; Async Swap does not deploy
  it.
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

## Deploying

`script/deploy.sh <chain-key> [dry-run|broadcast|verify]` deploys the libraries (when missing), the
hook and the Router, then writes the registry. Each network has a wrapper:
`deploy-unichain-sepolia.sh`, `deploy-sepolia.sh`, `deploy-robinhood-testnet.sh` and
`deploy-arc-testnet.sh`. Chain addresses come from
[`script/config/chains.json`](https://github.com/asyncswap/contracts/blob/main/script/config/chains.json); RPCs and the keystore account come from
`.env.deploy` (see [`.env.deploy.example`](https://github.com/asyncswap/contracts/blob/main/.env.deploy.example)).

With the keystore enrolled in Olive, Touch ID signs each step:

```bash
olive exec new-deployer -- script/deploy-arc-testnet.sh broadcast
```

On Ethereum Sepolia, put `DEPLOY_GAS_MULTIPLIER=800` in front. `verify` submits every registry
entry to Sourcify, then to the chain's Blockscout explorer when there is one, and writes standard
JSON inputs to `deployments/<chainId>/verify/` for manual upload.
