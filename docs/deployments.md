# Deployments

Async Swap is deployed on four testnets and has no mainnet deployment. The earlier deployments on
Unichain and Arc mainnet were tests, had bugs, and are archived: do not send orders to them. The current testnet addresses and hook start blocks below match the per-chain deployment registries.

## Contracts

| | Unichain Sepolia (1301) | Ethereum Sepolia (11155111) | Robinhood Chain testnet (46630) | Arc testnet (5042002) |
| --- | --- | --- | --- | --- |
| `AsyncSwap` (hook) | [`0x915a5d12A5985592D06C2a3e82d74da534dD2888`](https://sepolia.uniscan.xyz/address/0x915a5d12A5985592D06C2a3e82d74da534dD2888) | [`0x91fDcbe3aef56f988104c1BBC5AD90cCDe016888`](https://sepolia.etherscan.io/address/0x91fDcbe3aef56f988104c1BBC5AD90cCDe016888) | [`0x91958BEE3ef8E0b69a325ADc8771A67F84252888`](https://explorer.testnet.chain.robinhood.com/address/0x91958BEE3ef8E0b69a325ADc8771A67F84252888) | [`0x91e695092f2C193B45B1917d06527dBfD1e42888`](https://explorer.testnet.arc.io/address/0x91e695092f2C193B45B1917d06527dBfD1e42888) |
| `Router` | [`0x9C6D7Ad197B01dbb5F7dA3b33A1358f926A01479`](https://sepolia.uniscan.xyz/address/0x9C6D7Ad197B01dbb5F7dA3b33A1358f926A01479) | [`0x42369Df244d88D88f2a21b1089Ed52d7F56aF4f6`](https://sepolia.etherscan.io/address/0x42369Df244d88D88f2a21b1089Ed52d7F56aF4f6) | [`0x3BD71f850D59273d8Efe9e63B1EDcdE53cdB520F`](https://explorer.testnet.chain.robinhood.com/address/0x3BD71f850D59273d8Efe9e63B1EDcdE53cdB520F) | [`0x3BD71f850D59273d8Efe9e63B1EDcdE53cdB520F`](https://explorer.testnet.arc.io/address/0x3BD71f850D59273d8Efe9e63B1EDcdE53cdB520F) |
| `FeeVault` | [`0x09083601c1EFFf8A21750D63C53a5A8219f5D7F4`](https://sepolia.uniscan.xyz/address/0x09083601c1EFFf8A21750D63C53a5A8219f5D7F4) | [`0x3Cbc3b7B0429E53986132283DD4C381935b05c07`](https://sepolia.etherscan.io/address/0x3Cbc3b7B0429E53986132283DD4C381935b05c07) | [`0xcf1944E552bfC1a3361B83Db309c994536392675`](https://explorer.testnet.chain.robinhood.com/address/0xcf1944E552bfC1a3361B83Db309c994536392675) | [`0x451Cf49884c48727469D5A8bf9Bf19385cbA9282`](https://explorer.testnet.arc.io/address/0x451Cf49884c48727469D5A8bf9Bf19385cbA9282) |
| `AsyncMatching` | [`0xBb48d6a1597E9ABA42a2832E779E1A435E02e5f4`](https://sepolia.uniscan.xyz/address/0xBb48d6a1597E9ABA42a2832E779E1A435E02e5f4) | [`0xBb48d6a1597E9ABA42a2832E779E1A435E02e5f4`](https://sepolia.etherscan.io/address/0xBb48d6a1597E9ABA42a2832E779E1A435E02e5f4) | [`0xBb48d6a1597E9ABA42a2832E779E1A435E02e5f4`](https://explorer.testnet.chain.robinhood.com/address/0xBb48d6a1597E9ABA42a2832E779E1A435E02e5f4) | [`0xBb48d6a1597E9ABA42a2832E779E1A435E02e5f4`](https://explorer.testnet.arc.io/address/0xBb48d6a1597E9ABA42a2832E779E1A435E02e5f4) |
| `TickPrice` | [`0x5Be5a3101085c53Ddd96d8Cb627b7189db11bBc8`](https://sepolia.uniscan.xyz/address/0x5Be5a3101085c53Ddd96d8Cb627b7189db11bBc8) | [`0x5Be5a3101085c53Ddd96d8Cb627b7189db11bBc8`](https://sepolia.etherscan.io/address/0x5Be5a3101085c53Ddd96d8Cb627b7189db11bBc8) | [`0x5Be5a3101085c53Ddd96d8Cb627b7189db11bBc8`](https://explorer.testnet.chain.robinhood.com/address/0x5Be5a3101085c53Ddd96d8Cb627b7189db11bBc8) | [`0x5Be5a3101085c53Ddd96d8Cb627b7189db11bBc8`](https://explorer.testnet.arc.io/address/0x5Be5a3101085c53Ddd96d8Cb627b7189db11bBc8) |
| `DynamicFeeOrdering` | [`0x5Ad5872419407eF4fa9492a71C465F599Cd2EcA4`](https://sepolia.uniscan.xyz/address/0x5Ad5872419407eF4fa9492a71C465F599Cd2EcA4) | [`0x5Ad5872419407eF4fa9492a71C465F599Cd2EcA4`](https://sepolia.etherscan.io/address/0x5Ad5872419407eF4fa9492a71C465F599Cd2EcA4) | [`0x5Ad5872419407eF4fa9492a71C465F599Cd2EcA4`](https://explorer.testnet.chain.robinhood.com/address/0x5Ad5872419407eF4fa9492a71C465F599Cd2EcA4) | [`0x5Ad5872419407eF4fa9492a71C465F599Cd2EcA4`](https://explorer.testnet.arc.io/address/0x5Ad5872419407eF4fa9492a71C465F599Cd2EcA4) |
| PoolManager | [`0x00B036B58a818B1BC34d502D3fE730Db729e62AC`](https://sepolia.uniscan.xyz/address/0x00B036B58a818B1BC34d502D3fE730Db729e62AC) | [`0xE03A1074c86CFeDd5C142C4F04F1a1536e203543`](https://sepolia.etherscan.io/address/0xE03A1074c86CFeDd5C142C4F04F1a1536e203543) | [`0x8366a39CC670B4001A1121B8F6A443A643e40951`](https://explorer.testnet.chain.robinhood.com/address/0x8366a39CC670B4001A1121B8F6A443A643e40951) | [`0x8366a39CC670B4001A1121B8F6A443A643e40951`](https://explorer.testnet.arc.io/address/0x8366a39CC670B4001A1121B8F6A443A643e40951) |
| Numeraire | USDC [`0x31d0220469e10c4e71834a79b1f276d740d3768f`](https://sepolia.uniscan.xyz/address/0x31d0220469e10c4e71834a79b1f276d740d3768f) | Circle test USDC [`0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238`](https://sepolia.etherscan.io/address/0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238) | Paxos USDG [`0x7E955252E15c84f5768B83c41a71F9eba181802F`](https://explorer.testnet.chain.robinhood.com/address/0x7E955252E15c84f5768B83c41a71F9eba181802F) | USDC [`0x3600000000000000000000000000000000000000`](https://explorer.testnet.arc.io/address/0x3600000000000000000000000000000000000000) |
| Hook start block | 66,556,662 | 12,030,514 | 145,660,411 | 69,930,370 |

How to read the table:

- **`AsyncSwap`, `Router`, `FeeVault`** are the protocol. The hook address is mined per chain for
  its Uniswap v4 permission bits, so it differs by chain, and `FeeVault` is created by the hook's
  constructor. The Router is the same on every chain except Ethereum Sepolia.
- **`AsyncMatching`, `TickPrice`, `DynamicFeeOrdering`** are linked libraries, created through the
  deterministic CREATE2 deployer (`0x4e59b44847b379578588920cA78FbF26c0B4956C`) with fixed salts,
  so they have the same address on every chain.
- **PoolManager** is the Uniswap v4 singleton the hook is attached to; Async Swap does not deploy
  it.
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
| Ethereum Sepolia | 11155111 | ETH | Storing contract code costs about 7× Foundry's local estimate: deploy with `DEPLOY_GAS_MULTIPLIER=800`. |
| Robinhood Chain testnet | 46630 | ETH | No Circle USDC; the numeraire is Paxos USDG (6 decimals) from [faucet.paxos.com](https://faucet.paxos.com). An Arbitrum chain: `block.number` inside contracts is the L1 block, so start blocks come from receipts. |
| Arc testnet | 5042002 | USDC | Gas is paid in USDC ([faucet.circle.com](https://faucet.circle.com)), and the numeraire is the ERC-20 interface to that same balance. **Never initialize a pool with the native currency.** Uniswap does not list Arc testnet; this PoolManager's runtime bytecode is identical to the official Arc mainnet PoolManager at the same address. |

## Deploying

`script/deploy.sh <chain-key> [dry-run|broadcast|verify]` deploys the libraries (when missing), the
hook and the Router, then writes the registry. Each network has a wrapper:
`deploy-unichain-sepolia.sh`, `deploy-sepolia.sh`, `deploy-robinhood-testnet.sh` and
`deploy-arc-testnet.sh`. Chain addresses come from
[`script/config/chains.json`](../script/config/chains.json); RPCs and the keystore account come from
`.env.deploy` (see [`.env.deploy.example`](../.env.deploy.example)).

With the keystore enrolled in Olive, Touch ID signs each step:

```bash
olive exec new-deployer -- script/deploy-arc-testnet.sh broadcast
```

On Ethereum Sepolia, put `DEPLOY_GAS_MULTIPLIER=800` in front. `verify` submits every registry
entry to Sourcify, then to the chain's Blockscout explorer when there is one, and writes standard
JSON inputs to `deployments/<chainId>/verify/` for manual upload.
