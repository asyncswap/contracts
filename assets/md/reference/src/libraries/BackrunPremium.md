# BackrunPremium

[Git Source](https://github.com/asyncswap/contracts/blob/eff0e7ca5ad2433bf20dd7668ba6175717256ba1/src/libraries/BackrunPremium.sol)

**Title:** Backrun premium on pool-liquidity fills

Linked library called by `AsyncMatching` in the hook's context.

## Constants

### BACKRUN_WINDOW

<i>
  Blocks a pool fill's starting tick stays the reference that later fills are measured against.
</i>

```solidity
uint256 internal constant BACKRUN_WINDOW = 2;
```

## Functions

<a id="charge-asyncfiller-state-poolkey-currency-int24-uint256" />

### charge

<i>
  Backrun premium on a pool fill, taken from its output. The first pool fill in a window of
  `BACKRUN_WINDOW` blocks records its starting tick as the reference. A later fill in the
  window that moves the price back toward the reference pays half the price gap it closes:
  `amountOut * avgGap / 2`, with the gap averaged over the fill's start and end ticks (one
  tick is about 0.01%), so splitting a backrun does not lower its total. Half of the premium
  is donated to in-range LPs and half credited to the FeeVault as claims.
</i>

```solidity
function charge(
        AsyncFiller.State storage self,
        PoolKey calldata key,
        Currency output,
        int24 tickBefore,
        uint256 amountOut
    ) public returns (uint256 premium);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| key | `PoolKey` |  |
| output | `Currency` |  |
| tickBefore | `int24` |  |
| amountOut | `uint256` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| premium | `uint256` |  |
