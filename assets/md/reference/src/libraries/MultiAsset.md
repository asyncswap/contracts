# MultiAsset

[Git Source](https://github.com/asyncswap/contracts/blob/dcdaa4149b4a204d108b783b34566c480885aabc/src/libraries/MultiAsset.sol)

**Title:** MultiAsset

**Author:** @msakiart

Linked module for multi-asset trading: pool setup (including pools without the numeraire) and the hook's
side of flash fills and of fills paid in ERC-6909 claims. Public library calls use DELEGATECALL, so escrow,
books and the transient flash record stay in the hook.

## Constants

### BEGIN

Close the order and credit its input, less the trade fee, to the filler as claims; record it as the
open flash fill. Returns the input credited and the output owed.

```solidity
uint8 internal constant BEGIN = 0;
```

### SETTLE

Pay the maker of the open flash fill out of the output claims the Router has transferred to the hook.

```solidity
uint8 internal constant SETTLE = 1;
```

### FILL

A full fill paid in claims (inside a flash fill): the hook already holds the output as claims.

```solidity
uint8 internal constant FILL = 2;
```

### FLASH_ORDER_SLOT

<i>
  Transient record of the open flash fill, in the hook's context: its id, then the input and minimum output
  it was opened at. Each slot is keccak256("asyncswap.flashFill.\<name>") - 1.
</i>

```solidity
bytes32 private constant FLASH_ORDER_SLOT = 0xadcc9340e9b9520481a90c5e1cb2c7bb827085ef7c7b209a028db0fe766510cd;
```

### FLASH_AMOUNT_IN_SLOT

```solidity
bytes32 private constant FLASH_AMOUNT_IN_SLOT = 0xa948fdbbf716a51dd3ab76f9643ccf5ff5ac531fed11e84d483629e540b40220;
```

### FLASH_AMOUNT_OUT_SLOT

```solidity
bytes32 private constant FLASH_AMOUNT_OUT_SLOT = 0x4af24310f6994917e24875d474455b553ed83a7345f90cd7dd124597d7de6b85;
```

## Functions

<a id="initialize-mapping-poolid-asyncfiller-state-asyncfiller-book-poolkey-poolconfig" />

### initialize

Set up a new pool's state and book. Anyone may open a pool that pairs the numeraire with a dynamic fee. A
pool without the numeraire (for example ETH/TOKEN) may be opened only once both of its tokens have a
numeraire pool on this hook with the same tick spacing, so every such order has a numeraire route for
fillers. On it `currency1` is the quote side, each side's minimum is its token's decimal floor (no dollar
minimum), and priority bids are refused (`AsyncFiller.NO_PRIORITY_BIDS`). No check reads a price.

```solidity
function initialize(
        mapping(PoolId => AsyncFiller.State) storage states,
        AsyncFiller.Book storage book,
        PoolKey calldata key,
        PoolConfig calldata config
    ) public;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| states | `mapping(PoolId => AsyncFiller.State)` |  |
| book | `AsyncFiller.Book` |  |
| key | `PoolKey` |  |
| config | `PoolConfig` |  |

<a id="_requirenumerairepool-mapping-poolid-asyncfiller-state-currency-currency-int24" />

### \_requireNumerairePool

<i>
  Reverts `NumeraireRequired` unless `currency` already has a numeraire pool on this hook with `tickSpacing`.
</i>

```solidity
function _requireNumerairePool(
        mapping(PoolId => AsyncFiller.State) storage states,
        Currency numeraire,
        Currency currency,
        int24 tickSpacing
    ) private view;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| states | `mapping(PoolId => AsyncFiller.State)` |  |
| numeraire | `Currency` |  |
| currency | `Currency` |  |
| tickSpacing | `int24` |  |

<a id="_minassetamount-currency-uint8" />

### \_minAssetAmount

<i>
  10^(decimals - assetPrecision) base units of `asset`, at least 1. Native ETH has 18 decimals. A token
  without a readable `decimals()` gets the 1-unit floor, and reported decimals are capped at 36. An asset
  with no code reverts: a pool opened before its token is deployed would otherwise keep a 1-unit floor.
</i>

```solidity
function _minAssetAmount(Currency asset, uint8 assetPrecision) private view returns (uint256);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| asset | `Currency` |  |
| assetPrecision | `uint8` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `uint256` |  |

<a id="run-asyncfiller-state-asyncfiller-book-bytes-address" />

### run

<i>
  The flash path charges no pool fee: `AsyncSwap.calculatePoolFee` is zero, and the 0.02% trade fee comes
  out of what each side receives, as in a plain fill. `executor` is the hook's caller (the Router).
</i>

```solidity
function run(AsyncFiller.State storage self, AsyncFiller.Book storage book, bytes calldata args, address executor)
        public
        returns (uint256, uint256);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| book | `AsyncFiller.Book` |  |
| args | `bytes` |  |
| executor | `address` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `uint256` |  |
| \<none> | `uint256` |  |

<a id="_begin-asyncfiller-state-asyncfiller-book-asyncorder-bytes32-address-address" />

### \_begin

```solidity
function _begin(
        AsyncFiller.State storage self,
        AsyncFiller.Book storage book,
        AsyncOrder memory order,
        bytes32 id,
        address executor,
        address filler
    ) private returns (uint256, uint256);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| book | `AsyncFiller.Book` |  |
| order | `AsyncOrder` |  |
| id | `bytes32` |  |
| executor | `address` |  |
| filler | `address` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `uint256` |  |
| \<none> | `uint256` |  |

<a id="_settle-asyncfiller-state-asyncorder-bytes32-address" />

### \_settle

```solidity
function _settle(AsyncFiller.State storage self, AsyncOrder memory order, bytes32 id, address filler) private;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| order | `AsyncOrder` |  |
| id | `bytes32` |  |
| filler | `address` |  |

<a id="_fill-asyncfiller-state-asyncfiller-book-asyncorder-bytes32-address-address" />

### \_fill

```solidity
function _fill(
        AsyncFiller.State storage self,
        AsyncFiller.Book storage book,
        AsyncOrder memory order,
        bytes32 id,
        address executor,
        address filler
    ) private;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| self | `AsyncFiller.State` |  |
| book | `AsyncFiller.Book` |  |
| order | `AsyncOrder` |  |
| id | `bytes32` |  |
| executor | `address` |  |
| filler | `address` |  |

<a id="_openflashfill-bytes32" />

### \_openFlashFill

```solidity
function _openFlashFill(bytes32 id) private;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| id | `bytes32` |  |

<a id="_closeflashfill-bytes32" />

### \_closeFlashFill

```solidity
function _closeFlashFill(bytes32 id) private returns (uint256 amountIn, uint256 amountOut);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| id | `bytes32` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| amountIn | `uint256` |  |
| amountOut | `uint256` |  |

## Errors

### FlashFillActive

```solidity
error FlashFillActive();
```

### NumeraireRequired

```solidity
error NumeraireRequired();
```

### DynamicFeeRequired

```solidity
error DynamicFeeRequired();
```

### AssetHasNoCode

```solidity
error AssetHasNoCode();
```

### NoFlashFill

```solidity
error NoFlashFill();
```

## Structs

### PoolConfig

Immutable hook settings `initialize` copies into each new pool.

```solidity
struct PoolConfig {
        IPoolManager poolManager;
        Currency numeraire;
        address feeVault;
        uint256 minOrder;
        uint64 priorityFeeCap;
        uint8 assetPrecision;
    }
```

**Properties**

| Name | Type | Description |
| ---- | ---- | ----------- |
| poolManager | `IPoolManager` |  |
| numeraire | `Currency` |  |
| feeVault | `address` |  |
| minOrder | `uint256` |  |
| priorityFeeCap | `uint64` |  |
| assetPrecision | `uint8` |  |
