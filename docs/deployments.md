# Deployments

Async Swap is live on four testnets. There is no mainnet deployment yet. Every contract below is
source-verified on [Sourcify](https://sourcify.dev) (full match), and every hook is owned by
`0x33ce69DA05c3ad30A3b525625F950fAda8673205`.

The per-chain registries in [`deployments/`](../deployments) are the source of truth: each
`deployments/<chainId>/<chainId>.json` holds every address with its deployment transaction and start
block, for indexers and the app.

The docs site serves all of them, with each chain's name, explorer and numeraire, as one file at
[`/deployments.json`](https://docs.asyncswap.org/deployments.json).

## Shared libraries

The libraries are created through the deterministic CREATE2 deployer
(`0x4e59b44847b379578588920cA78FbF26c0B4956C`) with fixed salts, so they have the same address on
every chain.

| Library | Address |
| --- | --- |
| `TickPrice` | `0xd74BD0774EE57bb9939B9bA2127C2911039C27F6` |
| `DynamicFeeOrdering` | `0xa6bc8acdF560D6C6169C442AF441e7fF53fC1A33` |
| `AsyncMatching` | `0xAc9c2C38534f3d984d49f4830a5e07edA6F1e1F5` |

## Testnets

The hook address is mined per chain for its Uniswap v4 permission bits, so it differs by chain.
`FeeVault` is created by the hook's constructor.

### Unichain Sepolia (1301)

| Contract | Address |
| --- | --- |
| `AsyncSwap` (hook) | [`0x91FD5f707b384D61260b3EfD317d4B67375C2888`](https://sepolia.uniscan.xyz/address/0x91FD5f707b384D61260b3EfD317d4B67375C2888) |
| `Router` | [`0x1cd2C2d1a82035bCf90D2bd79FBF043d99e1083b`](https://sepolia.uniscan.xyz/address/0x1cd2C2d1a82035bCf90D2bd79FBF043d99e1083b) |
| `FeeVault` | [`0x7d8c6a8495c776522b83E9Ccb2752ffEA4ef2F3e`](https://sepolia.uniscan.xyz/address/0x7d8c6a8495c776522b83E9Ccb2752ffEA4ef2F3e) |
| PoolManager (Uniswap) | `0x00B036B58a818B1BC34d502D3fE730Db729e62AC` |
| Numeraire (USDC) | `0x31d0220469e10c4e71834a79b1f276d740d3768f` |

Hook deployed at block 66,537,473.

### Ethereum Sepolia (11155111)

| Contract | Address |
| --- | --- |
| `AsyncSwap` (hook) | [`0x91720308BB0b6018e5F2480C10DB52dEd100e888`](https://sepolia.etherscan.io/address/0x91720308BB0b6018e5F2480C10DB52dEd100e888) |
| `Router` | [`0xd25159473B1ba2979E92454620dDB86Fa2Af46EB`](https://sepolia.etherscan.io/address/0xd25159473B1ba2979E92454620dDB86Fa2Af46EB) |
| `FeeVault` | [`0x4125560F702993F0f26E2d1B7E1793DAEaB2bE1a`](https://sepolia.etherscan.io/address/0x4125560F702993F0f26E2d1B7E1793DAEaB2bE1a) |
| PoolManager (Uniswap) | `0xE03A1074c86CFeDd5C142C4F04F1a1536e203543` |
| Numeraire (Circle test USDC) | `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238` |

Hook deployed at block 12,028,907.

Sepolia charges roughly 7× what Foundry's local EVM estimates for storing new contract code, so
deploys there need `DEPLOY_GAS_MULTIPLIER=800` (see [Deploying](#deploying)).

### Robinhood Chain testnet (46630)

| Contract | Address |
| --- | --- |
| `AsyncSwap` (hook) | [`0x913142f9CFA32cc21bb9DE9E24e4cDc8f005A888`](https://explorer.testnet.chain.robinhood.com/address/0x913142f9CFA32cc21bb9DE9E24e4cDc8f005A888) |
| `Router` | [`0x1cd2C2d1a82035bCf90D2bd79FBF043d99e1083b`](https://explorer.testnet.chain.robinhood.com/address/0x1cd2C2d1a82035bCf90D2bd79FBF043d99e1083b) |
| `FeeVault` | [`0x4C74C36691f1EA50238945e74Da11bA4C7DD624D`](https://explorer.testnet.chain.robinhood.com/address/0x4C74C36691f1EA50238945e74Da11bA4C7DD624D) |
| PoolManager (Uniswap) | `0x8366a39CC670B4001A1121B8F6A443A643e40951` |
| Numeraire (Paxos USDG) | `0x7E955252E15c84f5768B83c41a71F9eba181802F` |

Hook deployed at block 145,542,537. There is no Circle USDC on this chain; the numeraire is Paxos's
USDG test token (6 decimals) from [faucet.paxos.com](https://faucet.paxos.com).

### Arc testnet (5042002)

| Contract | Address |
| --- | --- |
| `AsyncSwap` (hook) | [`0x91BbbC18C7F2215d1205083578a941F1b5766888`](https://explorer.testnet.arc.io/address/0x91BbbC18C7F2215d1205083578a941F1b5766888) |
| `Router` | [`0x1cd2C2d1a82035bCf90D2bd79FBF043d99e1083b`](https://explorer.testnet.arc.io/address/0x1cd2C2d1a82035bCf90D2bd79FBF043d99e1083b) |
| `FeeVault` | [`0xD9EBe2446c3CB80809C7769bb45A9F0fb20f68e0`](https://explorer.testnet.arc.io/address/0xD9EBe2446c3CB80809C7769bb45A9F0fb20f68e0) |
| PoolManager | `0x8366a39CC670B4001A1121B8F6A443A643e40951` |
| Numeraire (USDC) | `0x3600000000000000000000000000000000000000` |

Hook deployed at block 69,894,548. Gas on Arc is paid in USDC
([faucet.circle.com](https://faucet.circle.com)), and the numeraire is the ERC-20 interface to that
same balance. **Never initialize a pool with the native currency on Arc**: native and ERC-20 USDC
are one balance.

Uniswap does not list Arc testnet in its deployments. The PoolManager above has runtime bytecode
identical to the official Arc mainnet PoolManager at the same address.

## Deploying

`script/deploy.sh <chain-key> [dry-run|broadcast|verify]` deploys the libraries (when missing), the
hook and the Router, then writes the registry. Each chain has a wrapper: `deploy-unichain-sepolia.sh`,
`deploy-sepolia.sh`, `deploy-robinhood-testnet.sh` and `deploy-arc-testnet.sh`. Chain addresses come
from [`script/config/chains.json`](../script/config/chains.json); RPCs and the keystore account come
from `.env.deploy` (see [`.env.deploy.example`](../.env.deploy.example)).

With the keystore enrolled in Olive, Touch ID signs each step:

```bash
olive exec new-deployer -- script/deploy-arc-testnet.sh broadcast
```

On Sepolia, add `DEPLOY_GAS_MULTIPLIER=800` in front. `verify` submits every registry entry to
Sourcify, then to the chain's Blockscout explorer when there is one, and writes standard JSON
inputs to `deployments/<chainId>/verify/` for manual upload.
