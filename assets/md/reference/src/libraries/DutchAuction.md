# DutchAuction

[Git Source](https://github.com/asyncswap/contracts/blob/8366a12e8620be597061ae730a5196e800c3049d/src/libraries/DutchAuction.sol)

**Title:** DutchAuction

**Author:** @msakiart

Linked module for Dutch auction orders. The maker of a resting order sets a floor and a duration in blocks,
and the order's minimum output then falls in a straight line from its price at start to the floor. Anyone
may call `step` to write the scheduled minimum into the order, by the same reprice path a maker uses, so
the book always holds a real price. The Router steps the order before every filler fill.

<i>
  Between steps the stored minimum is at or above the schedule, so the maker never receives less than the
  schedule gives. A maker reprice stops the auction: `step` sees a reprice count it did not write.
  Public library calls use DELEGATECALL, so the auctions and books stay in the hook.
</i>

## Constants

### MAX_DURATION

Longest auction, in blocks.

```solidity
uint32 internal constant MAX_DURATION = 50_000;
```

## Functions

<a id="start-asyncfiller-state-asyncfiller-book-mapping-bytes32-auction-asyncorder-bytes32-uint256-uint32-address" />

### start

Start an auction on a resting order. Maker only. The order's current minimum is the start price.

```solidity
function start(
        AsyncFiller.State storage self,
        AsyncFiller.Book storage book,
        mapping(bytes32 => Auction) storage auctions,
        AsyncOrder calldata order,
        bytes32 id,
        uint256 floorAmountOutMin,
        uint32 duration,
        address caller
    ) public;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| book | `AsyncFiller.Book` |  |
| auctions | `mapping(bytes32 => Auction)` |  |
| order | `AsyncOrder` |  |
| id | `bytes32` |  |
| floorAmountOutMin | `uint256` |  |
| duration | `uint32` |  |
| caller | `address` |  |

<a id="step-asyncfiller-state-asyncfiller-book-mapping-bytes32-auction-asyncorder-bytes32" />

### step

Write the scheduled minimum into the order when it is below the stored one. Anyone may call it.
Does nothing for an order with no running auction. Returns the order's minimum output after the step.

```solidity
function step(
        AsyncFiller.State storage self,
        AsyncFiller.Book storage book,
        mapping(bytes32 => Auction) storage auctions,
        AsyncOrder calldata order,
        bytes32 id
    ) public returns (uint256);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| book | `AsyncFiller.Book` |  |
| auctions | `mapping(bytes32 => Auction)` |  |
| order | `AsyncOrder` |  |
| id | `bytes32` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `uint256` |  |

<a id="amountoutminat-auction-uint256" />

### amountOutMinAt

The scheduled minimum output at `blockNumber`, rounded up for the maker.

```solidity
function amountOutMinAt(Auction memory auction, uint256 blockNumber) internal pure returns (uint256);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| auction | `Auction` |  |
| blockNumber | `uint256` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `uint256` |  |

## Events

### AuctionStarted

```solidity
event AuctionStarted(
        bytes32 indexed orderId, uint256 startAmountOutMin, uint256 floorAmountOutMin, uint64 startBlock, uint32 duration
    );
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| orderId | `bytes32` |  |
| startAmountOutMin | `uint256` |  |
| floorAmountOutMin | `uint256` |  |
| startBlock | `uint64` |  |
| duration | `uint32` |  |

## Errors

### InvalidAuction

```solidity
error InvalidAuction();
```

## Structs

### Auction

```solidity
struct Auction {
        uint256 startAmountOutMin;
        uint256 floorAmountOutMin;
        uint64 startBlock;
        uint32 duration;
        /// @dev The order's reprice count after the last write by this auction.
        uint32 reprices;
    }
```

**Properties**

| Name | Type | Description |
| ---- | ---- | ----------- |
| startAmountOutMin | `uint256` |  |
| floorAmountOutMin | `uint256` |  |
| startBlock | `uint64` |  |
| duration | `uint32` |  |
| reprices | `uint32` |  |
