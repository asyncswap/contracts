# IIncomingLiquidity

[Git Source](https://github.com/asyncswap/contracts/blob/cc20ad373bc4ca8ed8dd664a6393434575cb1bd8/src/libraries/IncomingMatching.sol)

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
