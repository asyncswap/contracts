# Deployments

Async Swap v1.3.0 is deployed on Unichain Sepolia and Robinhood Chain testnet, with the bounded tick bitmap and funded priority-fee top-ups. Elysium testnet runs a later build of the same protocol (source `3eccc848`). No mainnet deployment is included.
The current testnet addresses and hook start blocks below match the per-chain deployment registries.

## Contracts

|  | Unichain Sepolia (1301) | Robinhood Chain testnet (46630) | Elysium testnet (99801) |
| --- | --- | --- | --- |
| `AsyncSwap` (hook) | [`0x914B6D0B00f0897a1FdaE43329556F477cf86888`](https://sepolia.uniscan.xyz/address/0x914B6D0B00f0897a1FdaE43329556F477cf86888) | [`0x917943DEE316842D941FE188bE7f149Dc3D32888`](https://explorer.testnet.chain.robinhood.com/address/0x917943DEE316842D941FE188bE7f149Dc3D32888) | [`0x91bb44fDEfdec74aaCbe7EE92A51C2eA427E6888`](https://testnet.elysium.kinetiq.xyz/address/0x91bb44fDEfdec74aaCbe7EE92A51C2eA427E6888) |
| `Router` | [`0xd31b1B308090e461c9944510fECdA447f849Ca52`](https://sepolia.uniscan.xyz/address/0xd31b1B308090e461c9944510fECdA447f849Ca52) | [`0xA93F36580aBA92a85A8C75B0c6f52C213c0226A5`](https://explorer.testnet.chain.robinhood.com/address/0xA93F36580aBA92a85A8C75B0c6f52C213c0226A5) | [`0x4f3aBD7F7afe42BdF3c6E187323d9CbD1271b588`](https://testnet.elysium.kinetiq.xyz/address/0x4f3aBD7F7afe42BdF3c6E187323d9CbD1271b588) |
| `FeeVault` | [`0x8FD7A76C8E440B3807216fe59fC7d653607Cb19a`](https://sepolia.uniscan.xyz/address/0x8FD7A76C8E440B3807216fe59fC7d653607Cb19a) | [`0xbB3570634FB375c483046534b42e77B0599DF8f2`](https://explorer.testnet.chain.robinhood.com/address/0xbB3570634FB375c483046534b42e77B0599DF8f2) | [`0xDeEdAe80F60d1c0B0B4Ac28bdF1BBD219c91d079`](https://testnet.elysium.kinetiq.xyz/address/0xDeEdAe80F60d1c0B0B4Ac28bdF1BBD219c91d079) |
| `AsyncMatching` | [`0x25d47EC632B406D307e5d3803b13015452156521`](https://sepolia.uniscan.xyz/address/0x25d47EC632B406D307e5d3803b13015452156521) | [`0x25d47EC632B406D307e5d3803b13015452156521`](https://explorer.testnet.chain.robinhood.com/address/0x25d47EC632B406D307e5d3803b13015452156521) | [`0xA05Dd653264A724df5A4A9e54759c3CEbaFa14b7`](https://testnet.elysium.kinetiq.xyz/address/0xA05Dd653264A724df5A4A9e54759c3CEbaFa14b7) |
| `TickPrice` | [`0xDd2b08533dB75ED63AEe52D9b3e2c8DaA1C63b61`](https://sepolia.uniscan.xyz/address/0xDd2b08533dB75ED63AEe52D9b3e2c8DaA1C63b61) | [`0xDd2b08533dB75ED63AEe52D9b3e2c8DaA1C63b61`](https://explorer.testnet.chain.robinhood.com/address/0xDd2b08533dB75ED63AEe52D9b3e2c8DaA1C63b61) | [`0x9c5B3e4cB505412E7A0017695D00a4A7453f57cB`](https://testnet.elysium.kinetiq.xyz/address/0x9c5B3e4cB505412E7A0017695D00a4A7453f57cB) |
| `DynamicFeeOrdering` | [`0x4c5901d2d168106C2fC274eF9445e085e9164Ae3`](https://sepolia.uniscan.xyz/address/0x4c5901d2d168106C2fC274eF9445e085e9164Ae3) | [`0x4c5901d2d168106C2fC274eF9445e085e9164Ae3`](https://explorer.testnet.chain.robinhood.com/address/0x4c5901d2d168106C2fC274eF9445e085e9164Ae3) | [`0x2f43586f3b729d45dbCd07CA645e66Aef933C61D`](https://testnet.elysium.kinetiq.xyz/address/0x2f43586f3b729d45dbCd07CA645e66Aef933C61D) |
| `TickBitmap` | [`0x977Aee08690CB39A5dab41937eCdbD70e1Bf4a21`](https://sepolia.uniscan.xyz/address/0x977Aee08690CB39A5dab41937eCdbD70e1Bf4a21) | [`0x977Aee08690CB39A5dab41937eCdbD70e1Bf4a21`](https://explorer.testnet.chain.robinhood.com/address/0x977Aee08690CB39A5dab41937eCdbD70e1Bf4a21) | [`0x977Aee08690CB39A5dab41937eCdbD70e1Bf4a21`](https://testnet.elysium.kinetiq.xyz/address/0x977Aee08690CB39A5dab41937eCdbD70e1Bf4a21) |
| `EligiblePrice` | [`0x5C51B17E1b1D842C168aeDcF001014Fe55b60f8e`](https://sepolia.uniscan.xyz/address/0x5C51B17E1b1D842C168aeDcF001014Fe55b60f8e) | [`0x5C51B17E1b1D842C168aeDcF001014Fe55b60f8e`](https://explorer.testnet.chain.robinhood.com/address/0x5C51B17E1b1D842C168aeDcF001014Fe55b60f8e) | [`0x5C51B17E1b1D842C168aeDcF001014Fe55b60f8e`](https://testnet.elysium.kinetiq.xyz/address/0x5C51B17E1b1D842C168aeDcF001014Fe55b60f8e) |
| `PriorityFeeUpdates` | [`0xB4852dD48089D4ec47e8f622111FE305F70dDB6C`](https://sepolia.uniscan.xyz/address/0xB4852dD48089D4ec47e8f622111FE305F70dDB6C) | [`0xB4852dD48089D4ec47e8f622111FE305F70dDB6C`](https://explorer.testnet.chain.robinhood.com/address/0xB4852dD48089D4ec47e8f622111FE305F70dDB6C) | [`0xbBb97F9A1655814f1c6C62bDD1Fe26092a0a9D7B`](https://testnet.elysium.kinetiq.xyz/address/0xbBb97F9A1655814f1c6C62bDD1Fe26092a0a9D7B) |
| `IncomingMatching` | | | [`0x57510fc2402Ba4346f38085b963d3429FBdf6131`](https://testnet.elysium.kinetiq.xyz/address/0x57510fc2402Ba4346f38085b963d3429FBdf6131) |
| PoolManager | [`0x00B036B58a818B1BC34d502D3fE730Db729e62AC`](https://sepolia.uniscan.xyz/address/0x00B036B58a818B1BC34d502D3fE730Db729e62AC) | [`0x8366a39CC670B4001A1121B8F6A443A643e40951`](https://explorer.testnet.chain.robinhood.com/address/0x8366a39CC670B4001A1121B8F6A443A643e40951) | [`0x67E44b69D10737dF41f5a98078072B817016B871`](https://testnet.elysium.kinetiq.xyz/address/0x67E44b69D10737dF41f5a98078072B817016B871) |
| Numeraire | USDC [`0x31d0220469e10c4e71834a79b1f276d740d3768f`](https://sepolia.uniscan.xyz/address/0x31d0220469e10c4e71834a79b1f276d740d3768f) | Paxos USDG [`0x7E955252E15c84f5768B83c41a71F9eba181802F`](https://explorer.testnet.chain.robinhood.com/address/0x7E955252E15c84f5768B83c41a71F9eba181802F) | USDC [`0x7d29d8047b905000459c0e80c34a26ceedcb47b2`](https://testnet.elysium.kinetiq.xyz/address/0x7d29d8047b905000459c0e80c34a26ceedcb47b2) |
| Hook start block | 67,049,925 | 149,102,588 | 26,826,205 |

How to read the table:

* **`AsyncSwap`, `Router`, `FeeVault`** are the protocol. The hook address is mined per chain for
  its Uniswap v4 permission bits, so it differs by chain, and `FeeVault` is created by the hook's
  constructor. Router addresses depend on the deployer nonce on each chain.
* **`AsyncMatching`, `TickPrice`, `DynamicFeeOrdering`, `TickBitmap`, `EligiblePrice`, `PriorityFeeUpdates`** (and, on Elysium, `IncomingMatching`) are linked libraries, created through the
  deterministic CREATE2 deployer (`0x4e59b44847b379578588920cA78FbF26c0B4956C`) with fixed salts.
  Identical bytecode gets the same address on every chain. Elysium's later build changed four of them, so
  those addresses differ there.
* **Pool parameters are fixed at deployment.** No setter changes them and anyone can open a pool. On
  these hooks `minOrder` is 0 (no dollar minimum) and `assetPrecision` is 4: an order's asset side
  must be at least 0.0001 of a whole token, or 10^(decimals - 4) base units. The optional priority bid's
  minimum is capped at $0.10, derived from the numeraire's decimals. Routers batch calls with `multicall`.
* **`WithdrawalRouter` entries in the registries are not for these hooks.** They were deployed for
  earlier hooks and are kept as a record. Cancels and claims go through the `Router` above.
* **PoolManager** is the Uniswap v4 singleton the hook is attached to. Unichain Sepolia and
  Robinhood testnet use existing instances. Elysium testnet has no canonical Uniswap v4 instance, so
  its PoolManager was deployed with the protocol.
* **Numeraire** is the stablecoin every pool is priced in.
* **Hook start block** is where an indexer should start reading the hook's events.

The per-chain registries in [`deployments/`](https://github.com/asyncswap/contracts/blob/main/deployments) are the source of truth: each
`deployments/<chainId>/<chainId>.json` holds every address with its deployment transaction and start
block. The docs site serves all of them, with each chain's name, explorer and numeraire, as one file
at [`/deployments.json`](https://docs.asyncswap.org/deployments.json).

## v1.3.0 release and previous orders

The protocol source is frozen at `c9372ff9577ba3950fa321090a7bfb559fc964a4`.
The deployer and hook owner on both testnets is `0x33ce69DA05c3ad30A3b525625F950fAda8673205` (`new-deployer`).
The registries advertise `features.priorityFeeTopUps: true` only for these new hooks and Routers.

Orders and pools are tied to their hook address. Existing orders remain on the previous deployment and must
be cancelled, filled or claimed through its original Router. They are not migrated to the new book.
The complete previous records are preserved in
[Unichain Sepolia](https://github.com/asyncswap/contracts/blob/main/deployments/1301/1301-pre-v1.3.0.json) and
[Robinhood testnet](https://github.com/asyncswap/contracts/blob/main/deployments/46630/46630-pre-v1.3.0.json).
Clients and indexers must retain those addresses while adding the new deployment; publishing this registry
alone does not update a running frontend or indexer.

The live create → top-up → cancel sequence passed on both networks. All nine release modules per chain
have exact source matches on Sourcify. See [release validation](https://github.com/asyncswap/contracts/blob/main/benchmarks/releases/README.md) for
receipts, measured gas and verification links.

## Network notes

| Network | Chain ID | Gas token | Notes |
| --- | --- | --- | --- |
| Unichain Sepolia | 1301 | ETH | Uniswap's PoolManager. |
| Robinhood Chain testnet | 46630 | ETH | No Circle USDC; the numeraire is Paxos USDG (6 decimals) from [faucet.paxos.com](https://faucet.paxos.com). An Arbitrum chain: `block.number` inside contracts is the L1 block, so start blocks come from receipts. |
| Elysium testnet | 99801 | HYPE | Kinetiq's EVM chain on HyperEVM. The numeraire is bridged USDC (6 decimals). Explorer: [testnet.elysium.kinetiq.xyz](https://testnet.elysium.kinetiq.xyz). |

## Faucets

Testnet gas and numeraire for trying the protocol:

| Network | Faucet |
| --- | --- |
| Unichain Sepolia | ETH from the faucets in the [Unichain docs](https://docs.unichain.org/docs/tools/faucets); USDC from [Circle](https://faucet.circle.com/) |
| Robinhood Chain testnet | ETH from [faucet.testnet.chain.robinhood.com](https://faucet.testnet.chain.robinhood.com/); USDG from [faucet.paxos.com](https://faucet.paxos.com) |
| Elysium testnet | HYPE from [elysium.kinetiq.xyz/testnet-faucet](https://elysium.kinetiq.xyz/testnet-faucet) |

## Deploying

`script/deploy.sh <chain-key> [dry-run|broadcast|verify]` deploys the libraries (when missing), the
hook and the Router, then writes the registry. Each network has a wrapper:
`deploy-unichain-sepolia.sh` and `deploy-robinhood-testnet.sh`. Chain addresses come from
[`script/config/chains.json`](https://github.com/asyncswap/contracts/blob/main/script/config/chains.json); RPCs and the keystore account come from
`.env.deploy` (see [`.env.deploy.example`](https://github.com/asyncswap/contracts/blob/main/.env.deploy.example)).

Fund the deployer with the network's gas token first.

Set `DEPLOYER_ACCOUNT=new-deployer` and its public address as `DEPLOY_OWNER` in the local `.env.deploy`. With that keystore enrolled in Olive, one Touch ID authorization lets Foundry sign the commands in the wrapper:

```bash
olive exec new-deployer -- script/deploy-robinhood-testnet.sh broadcast
```

`verify` submits every registry
entry to Sourcify, then to the chain's Blockscout explorer when there is one, and writes standard
JSON inputs to `deployments/<chainId>/verify/` for manual upload.
