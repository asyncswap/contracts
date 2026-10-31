# TickPrice

[Git Source](https://github.com/asyncswap/contracts/blob/fe373151eb2cd6cdbd7a60b534a479a0dde5d75e/src/libraries/TickPrice.sol)

Book levels on Uniswap v4 ticks: an order sits at the floor tick (spacing 1, 0.01% steps)
of its exact currency1/currency0 limit. Levels are a fixed relative width at any price and
for any token decimals; the exact limit still decides crossing within a level.

## Functions

<a id="key-bool-bool-uint256-uint256" />

### key

Radix key of an order's level, ordered by numeraire per asset. Monotone in the exact
price, so distinct keys order prices strictly. Keys run from 1 to 2 \* MAX_TICK + 1;
ratios beyond the v4 price range share the end keys.

```solidity
function key(bool isBuy, bool zeroForOne, uint256 amountIn, uint256 amountOut) public pure returns (uint128);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| isBuy | `bool` |  |
| zeroForOne | `bool` |  |
| amountIn | `uint256` |  |
| amountOut | `uint256` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `uint128` |  |

<a id="poolbeatslevel-ipoolmanager-poolid-bool-bool-uint128" />

### poolBeatsLevel

Whether the pool has active liquidity and its current price is strictly better for an
incoming order than the best opposite level `levelKey` (below the best ask for a buy,
above the best bid for a sell), compared as keys; if so, also that level's sqrt price,
the limit a pool-first swap may not cross. `quote1`: the numeraire is currency1, so the
tick's price is already numeraire per asset; otherwise it is flipped.

```solidity
function poolBeatsLevel(IPoolManager manager, PoolId poolId, bool quote1, bool isBuy, uint128 levelKey)
        public
        view
        returns (bool, uint160);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| manager | `IPoolManager` |  |
| poolId | `PoolId` |  |
| quote1 | `bool` |  |
| isBuy | `bool` |  |
| levelKey | `uint128` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `bool` |  |
| \<none> | `uint160` |  |

<a id="floortick-uint256-uint256" />

### floorTick

Largest tick whose price is at most num/den, clamped to the v4 tick range. Monotone in
num/den. Two regimes keep sqrt(num/den) \* 2^96 well inside one tick of exact.

```solidity
function floorTick(uint256 num, uint256 den) internal pure returns (int24);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| num | `uint256` |  |
| den | `uint256` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `int24` |  |
