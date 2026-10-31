# DynamicFeeOrdering

[Git Source](https://github.com/asyncswap/contracts/blob/fe373151eb2cd6cdbd7a60b534a479a0dde5d75e/src/libraries/DynamicFeeOrdering.sol)

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

<a id="charge-asyncfiller-state-poolkey-bytes32-currency-int24-uint256" />

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
        bytes32 id,
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
| id | `bytes32` |  |
| output | `Currency` |  |
| tickBefore | `int24` |  |
| amountOut | `uint256` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| fee | `uint256` |  |

<a id="_pay-asyncfiller-state-poolkey-bytes32-currency-uint256" />

### \_pay

<i>
  Half of `fee` to in-range LPs (all of it to the FeeVault if none are in range), the rest
  to the FeeVault as claims.
</i>

```solidity
function _pay(AsyncFiller.State storage self, PoolKey calldata key, bytes32 id, Currency output, uint256 fee)
        private;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| key | `PoolKey` |  |
| id | `bytes32` |  |
| output | `Currency` |  |
| fee | `uint256` |  |

## Events

### DynamicFeeCharged

A pool fill paid the dynamic fee, in `currency` (the fill's output): `toLps` donated to
in-range LPs and `toFeeVault` credited to the FeeVault, measured against `refTick`.

```solidity
event DynamicFeeCharged(
        PoolId indexed poolId,
        bytes32 indexed orderId,
        Currency indexed currency,
        uint256 toLps,
        uint256 toFeeVault,
        int24 refTick
    );
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| poolId | `PoolId` |  |
| orderId | `bytes32` |  |
| currency | `Currency` |  |
| toLps | `uint256` |  |
| toFeeVault | `uint256` |  |
| refTick | `int24` |  |

### PoolPriceObserved

The pool tick before and after a completed pool fill, with the reference used for fee ordering.

<i>
  Indexers can use these events as the price-movement log; fee calculation uses compact on-chain state.
</i>

```solidity
event PoolPriceObserved(
        PoolId indexed poolId,
        bytes32 indexed orderId,
        int24 tickBefore,
        int24 tickAfter,
        int24 refTick,
        uint64 observedBlock
    );
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| poolId | `PoolId` |  |
| orderId | `bytes32` |  |
| tickBefore | `int24` |  |
| tickAfter | `int24` |  |
| refTick | `int24` |  |
| observedBlock | `uint64` |  |
