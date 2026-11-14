# DutchAuction

[Git Source](https://github.com/asyncswap/contracts/blob/84f3d45a9d5fd5044b514fe8372b641bb2c45527/src/libraries/DutchAuction.sol)

**Title:** DutchAuction

**Author:** @msakiart

Linked module for Dutch auction orders. The order rests in the book at the maker's minimum output (the
floor) the whole time. An auction adds a premium on top that only flash fillers pay: it starts at
`startAmountOutMin - floor` and falls in a straight line to zero over `duration` blocks. After that the order
is a plain good-till-cancelled order at the floor, with nothing to step and no keeper.

<i>
  Book matches and pool fills during an auction pay the floor, the maker's own limit. Plain filler fills are
  refused while a premium is live (`requireNoPremium`), so a filler cannot skip it. A maker reprice or a partial
  match ends the premium: `premium` sees a reprice count or a minimum it did not record.
  Public library calls use DELEGATECALL, so the auctions stay in the hook.
</i>

## Constants

### MAX_DURATION

Longest auction, in blocks.

```solidity
uint32 internal constant MAX_DURATION = 50_000;
```

## Functions

<a id="start-asyncfiller-state-mapping-bytes32-auction-asyncorder-bytes32-uint256-uint32-address" />

### start

Start an auction on a resting order. Maker only. The order's current minimum output is the floor, and
`startAmountOutMin` (above it) is what a flash filler pays at the start block.

```solidity
function start(
        AsyncFiller.State storage self,
        mapping(bytes32 => Auction) storage auctions,
        AsyncOrder calldata order,
        bytes32 id,
        uint256 startAmountOutMin,
        uint32 duration,
        address caller
    ) public;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| auctions | `mapping(bytes32 => Auction)` |  |
| order | `AsyncOrder` |  |
| id | `bytes32` |  |
| startAmountOutMin | `uint256` |  |
| duration | `uint32` |  |
| caller | `address` |  |

<a id="premium-asyncfiller-state-mapping-bytes32-auction-bytes32" />

### premium

The auction premium a flash filler pays on top of the order's minimum output now. Zero for an order with
no auction, after the duration, or once the maker repriced or the order was partly matched.

```solidity
function premium(AsyncFiller.State storage self, mapping(bytes32 => Auction) storage auctions, bytes32 id)
        public
        view
        returns (uint256);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| auctions | `mapping(bytes32 => Auction)` |  |
| id | `bytes32` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `uint256` |  |

<a id="requirenopremium-asyncfiller-state-mapping-bytes32-auction-bytes32" />

### requireNoPremium

Revert while the order's premium is live, so plain fills cannot skip it.

```solidity
function requireNoPremium(AsyncFiller.State storage self, mapping(bytes32 => Auction) storage auctions, bytes32 id)
        public
        view;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| auctions | `mapping(bytes32 => Auction)` |  |
| id | `bytes32` |  |

## Events

### AuctionStarted

```solidity
event AuctionStarted(
        bytes32 indexed orderId,
        uint256 startAmountOutMin,
        uint256 floorAmountOutMin,
        uint64 startBlock,
        uint32 duration
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

### AuctionRunning

A plain fill was tried while the order's auction premium is live. Fill it with a flash fill, which pays
the premium, or after the auction.

```solidity
error AuctionRunning(uint256 premium);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| premium | `uint256` |  |

## Structs

### Auction

```solidity
struct Auction {
        uint256 startAmountOutMin;
        /// @dev The order's minimum output when the auction started. The premium is measured above it.
        uint256 floorAmountOutMin;
        uint64 startBlock;
        uint32 duration;
        /// @dev The order's reprice count when the auction started.
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
