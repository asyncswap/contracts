# IIncomingLiquidity

[Git Source](https://github.com/asyncswap/contracts/blob/8366a12e8620be597061ae730a5196e800c3049d/src/libraries/IncomingMatching.sol)

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
