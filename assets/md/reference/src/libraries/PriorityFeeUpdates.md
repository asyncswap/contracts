# PriorityFeeUpdates

[Git Source](https://github.com/asyncswap/contracts/blob/94ab5ab1b86b7d89fc1803d06c20603b98838422/src/libraries/PriorityFeeUpdates.sol)

Funded priority amendments, linked separately to keep the hook within EIP-170.

## Functions

<a id="topup-asyncfiller-state-asyncfiller-book-poolid-bytes32-uint256" />

### topUp

<i>
  The hook admits only its trusted Router, which authenticates the maker and pays the delta.
</i>

```solidity
function topUp(
        AsyncFiller.State storage self,
        AsyncFiller.Book storage book,
        PoolId poolId,
        bytes32 id,
        uint256 addedFee
    ) public;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| book | `AsyncFiller.Book` |  |
| poolId | `PoolId` |  |
| id | `bytes32` |  |
| addedFee | `uint256` |  |

## Events

### AsyncOrderPriorityFeeUpdated

```solidity
event AsyncOrderPriorityFeeUpdated(
        PoolId indexed poolId, bytes32 indexed orderId, uint256 addedFee, uint256 newPriorityFee
    );
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| poolId | `PoolId` |  |
| orderId | `bytes32` |  |
| addedFee | `uint256` |  |
| newPriorityFee | `uint256` |  |
