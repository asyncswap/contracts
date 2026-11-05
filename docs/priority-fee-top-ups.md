# Priority fee top-ups

Implemented in source; requires a new hook and Router deployment. The existing immutable deployments
and the frozen audit scope do not include this endpoint.

## API

```solidity
router.topUpPriorityFee(order, addedFee);
```

The caller must be `order.owner`, with sufficient USDC balance and ERC-20 allowance to the Router.
A registered filling executor cannot top up another maker's order. Agents can submit from the maker's
wallet or through that wallet's own authorized execution mechanism. There is no new relayed signature
or Permit2 top-up endpoint in this version.

`addedFee` is a positive delta in the numeraire's base units. With six-decimal USDC, `25_000` adds
$0.025. The function identifies the order by chain, pool, owner, direction and salt; the amount,
minimum output and fee supplied in the order struct may be stale. It adds to the bid currently stored
on the order. For example, a $0.10 bid reduced to $0.075 by a partial fill becomes $0.10 after adding
$0.025.

The resulting bid must be at least `min(remaining USDC notional / 1000, pool priorityFeeCap)`, rounded
down. The default cap is $0.10 and limits the required minimum, not the user's maximum bid. A partially
consumed bid may sit below this minimum until amended, but a top-up must bring it back to the current
minimum. The resulting bid cannot exceed `uint64.max` base units. Missing and closed orders revert.

## Priority and settlement

- The limit price and remaining input budget do not change.
- Exact price remains the first ranking rule. A higher bid breaks equal-price ties.
- The order receives a fresh queue sequence and joins behind existing equal-price, equal-fee orders.
- The original maker age and signed reprice version stay unchanged. A pending signed reprice or
  cancellation is not invalidated by a top-up; nonce invalidation remains the way to revoke it.
- Added fees follow the existing non-refundable settlement rule: proportional consumption on fills,
  with the remainder going to the FeeVault on closure or cancellation. They are not keeper rewards.

The Router transfers USDC to PoolManager and credits the hook before the library rekeys the fee
queue and mints the added escrow claims. The price-level bitmap and order counts stay unchanged.
PoolManager requires balanced currency deltas at unlock completion; a payment failure, short payment
or invalid amendment reverts funding and queue changes together. The hook emits:

```solidity
event AsyncOrderPriorityFeeUpdated(
    PoolId indexed poolId, bytes32 indexed orderId, uint256 addedFee, uint256 newPriorityFee
);
```

The update uses the live order after payment. If a token callback partially fills it, the delta is
added to that remainder; if the order closes during payment, the transaction reverts. Supported USDC
transfers do not normally make such callbacks, but this behavior is tested.

## Agent choice: top up, or top up and match

A top-up does not attempt matching and does not pay the Router's native MEV tax. It still costs
transaction gas. Use it when raising priority for future liquidity. When compatible liquidity is
already visible, combine it with a bounded matching call:

```solidity
bytes[] memory calls = new bytes[](2);
calls[0] = abi.encodeCall(router.topUpPriorityFee, (order, addedFee));
calls[1] = abi.encodeCall(router.matchBook, (order.key, uint8(8)));
router.multicall(calls);
```

`maxMatches` must be 1–8. The matcher processes the book's best executable pairs, so the targeted
order is not guaranteed a fill within that bound. If no crossing pair exists, matching may succeed
without a fill and the top-up remains committed. If either call reverts, the entire batch reverts.
This is book matching; LP retries remain the separate `fillFromPoolLiquidity` path.

Read the live remaining bid and order state, choose a spending limit, then simulate the exact call
or multicall before submission. Simulation does not reserve liquidity. Retrying the same successful
top-up in a new transaction adds the delta again; check the receipt and current bid before retrying.

For transaction-cost measurements and reproduction instructions, see [the top-up benchmark](../benchmarks/topups/README.md).

Sources: [Router](../src/Router.sol), [hook](../src/AsyncSwap.sol),
[fee amendments](../src/libraries/PriorityFeeUpdates.sol), and
[tests](../test/PriorityFeeTopUp.t.sol).
