# IIncomingLiquidity

[Git Source](https://github.com/asyncswap/contracts/blob/19de7b313503f14cf5931e5bc16bd42698ddb96a/src/libraries/IncomingMatching.sol)

<i>
  The hook's existing self-call boundary rolls back a failed LP attempt atomically.
</i>

## Functions

<a id="fillorderfrompoolliquidity-asyncorder-bytes32-uint160" />

### fillOrderFromPoolLiquidity

```solidity
function fillOrderFromPoolLiquidity(AsyncOrder calldata order, bytes32 id, uint160 sqrtPriceLimitX96) external;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |
| id | `bytes32` |  |
| sqrtPriceLimitX96 | `uint160` |  |
