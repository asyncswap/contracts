# DynamicFeeOrdering

[Git Source](https://github.com/asyncswap/contracts/blob/e578e5b3753d37bfd6053629c8aed4ad3d31df45/src/libraries/DynamicFeeOrdering.sol)

**Title:** Dynamic fee ordering on pool-liquidity fills

Linked library called by `AsyncMatching` in the hook's context.

## Constants

### ORDERING_WINDOW

<i>
  Blocks a pool fill's starting tick stays the reference that later fills are measured against.
</i>

```solidity
uint256 internal constant ORDERING_WINDOW = 2;
```

## Functions

<a id="charge-asyncfiller-state-poolkey-currency-int24-uint256" />

### charge

<i>
  Dynamic fee on a pool fill that backruns a price move, taken from its output. The first pool fill in a window of
  `ORDERING_WINDOW` blocks records its starting tick as the reference. A later fill in the
  window that moves the price back toward the reference pays half the price gap it closes:
  `amountOut * avgGap / 2`, with the gap averaged over the fill's start and end ticks (one
  tick is about 0.01%), so splitting a backrun does not lower its total. Half of the fee
  is donated to in-range LPs and half credited to the FeeVault as claims.
</i>

```solidity
function charge(
        AsyncFiller.State storage self,
        PoolKey calldata key,
        Currency output,
        int24 tickBefore,
        uint256 amountOut
    ) public returns (uint256 fee);
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
| fee | `uint256` |  |
