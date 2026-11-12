# Locked-liquidity launches

`Launchpad` creates a fixed-supply 18-decimal token and initializes its market on the configured Async Swap hook. One transaction deposits the entire supply into a permanently locked Uniswap v4 position, except unavoidable rounding dust which remains permanently locked in the launcher. It does **not** create an initial sell order.

## Creator inputs

- Name and symbol (1–64 and 1–10 bytes).
- Total supply, in 18-decimal token units, up to `uint128.max`.
- Starting price: whole numeraire per whole token, scaled by `1e18`. For example `0.001 USDG/token` is `1e15`, regardless of the quote token's decimals. The smallest representable price input is `priceX18 = 1`, or `0.000000000000000001` quote per token. This is a precision limit, not the hook’s minimum order size. The actual starting price rounds upward to a valid tick. Very small supplies can still produce zero liquidity and revert.
- Public metadata URI (up to 2,048 bytes) for the image and social links. Upload and host the metadata before launching; browser blob URLs are not persistent metadata. The URI is immutable; content immutability depends on the hosting scheme. UI clients must sanitize content.

The quote token is fixed by `hook.numeraire()`, not caller-selected: USDG on the existing Robinhood testnet deployment, USDC on Unichain Sepolia. The creator funds only deployment gas, not quote-token liquidity.

The hook enforces `minOrder` on the order’s quote leg and an asset floor derived from `assetPrecision` on its asset leg. These do not set a minimum initialization price or liquidity deposit. At verification, both configured testnet hooks returned `minOrder = 0` and `assetPrecision = 4` (0.0001 token). Clients should read the deployed configuration rather than infer a price floor from it.

## Price and inventory

Price rounds upward to a tick with spacing 1. Liquidity spans from that initial price to the highest pool tick: the first buys increase the price rather than filling the entire supply at a fixed ask. The actual initialized sqrt price is in `MarketLaunched`. Ratios that overflow the checked Q192 math or liquidity outside positive `int128` bounds revert atomically.

The deployed hook requires active liquidity before attempting a pool fill. A token1-only position at its upper tick would be inactive. The launcher searches up to 128 CREATE2 salts to ensure the new token sorts before the numeraire, then initializes at the inclusive lower boundary. Salts bind the creator and a monotonically increasing nonce. No hook or Router upgrade is required. Numeraires near address zero may exhaust the search; the whole transaction then reverts.

## Permanent lock and fees

- The launcher is the v4 position owner. It has no withdrawal, liquidity reduction, transfer, upgrade, admin or sweep entry point.
- The creator gets zero tokens and cannot recover liquidity principal, including quote proceeds accumulated through swaps. Rounding dust and unsolicited transfers have no recovery path.
- `claimFees(token)` performs a zero-liquidity-delta update and pays only accrued fees to the original creator. Anyone may trigger it, but cannot redirect proceeds.
- Fees are earned only when trades use the position. Direct order-book matches do not generate LP fees for it. Earnings and fills are not guaranteed.
- The factory never authorizes itself to spend creator funds. Only the configured PoolManager can invoke its unlock callback. Launch and claim entry points are reentrancy guarded.
- The permanent lock makes code defects consequential. This PR is a testnet prototype, not an audit or production certification.

## Testnet check

```sh
forge test --match-contract '^LaunchpadTest$' -vv
bash script/check-launchpad-testnets.sh
```

The latter runs against **live-state forks** of Robinhood testnet and Unichain Sepolia: creates a launcher and token locally, buys via the deployed Router, claims fees, checks the actual PoolManager position liquidity is unchanged, and checks no mint/withdraw entry points exist. No private key or public transaction is used. RPC overrides: `RPC_URL_ROBINHOOD_TESTNET` and `RPC_URL_UNICHAIN_SEPOLIA`.

For an explicit public-testnet deployment, simulate first:

```sh
forge script script/DeployLaunchpad.s.sol --rpc-url "$RPC_URL_UNICHAIN_SEPOLIA"
# Add --account <funded-keystore> --broadcast only when actually deploying.
```

The script permits only chain IDs 1301 and 46630 and uses the hook addresses in `docs/deployments.md`. Record the resulting address and transaction before enabling the frontend launch button. UI integration must upload metadata, show the irreversible lock and tick-rounded starting price, request wallet confirmation for `launch`, decode `MarketLaunched`, register the new token in search, and navigate to its market. Fee management uses `claimFees(token)`; there is no LP withdrawal action.
