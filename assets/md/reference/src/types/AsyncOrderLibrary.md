# AsyncOrderLibrary

[Git Source](https://github.com/asyncswap/contracts/blob/db503f7f95d5ccf59d6e7fcbb0e4507dab24c838/src/types/AsyncOrder.sol)

**Title:** AsyncOrderLibrary

Helpers attached to AsyncOrder for identity and pricing.

## Functions

<a id="orderid-asyncorder" />

### orderId

Stable identifier for an order, derived from its addressing fields.

<i>
  (chainId, poolId, owner, zeroForOne, salt) uniquely identifies one open order.

  * `block.chainid` keeps ids unique across chains where the same PoolKey can be
    deployed (for example Unichain mainnet and Sepolia).
  * `salt` is contract-assigned at create time and stored off-chain (in the event
    log) so the maker can pass it back when calling cancel / updatePrice / fill.
    `view` (not `pure`) because `block.chainid` reads EVM context.
</i>

```solidity
function orderId(AsyncOrder calldata order) internal view returns (bytes32);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `bytes32` |  |
