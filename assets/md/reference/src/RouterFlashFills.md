# RouterFlashFills

[Git Source](https://github.com/asyncswap/contracts/blob/db503f7f95d5ccf59d6e7fcbb0e4507dab24c838/src/RouterFlashFills.sol)

**Inherits:** [IAsyncSwapCallback](/reference/src/interfaces/IAsyncSwapCallback)

**Title:** RouterFlashFills

**Author:** @msakiart

The Router's flash-fill surface (`IAsyncSwapCallback`). The Router creates this module in its constructor
and runs it by DELEGATECALL from its `fallback`, so every call executes as the Router: the hook sees the
Router as caller, and the transient filler slot lives in the Router's context. Kept out of the Router so
its runtime stays under EIP-170.

<i>
  Called directly (not through the Router) every hook call reverts `NotTrustedRouter`.
</i>

## Constants

### POOLMANAGER

```solidity
IPoolManager immutable POOLMANAGER;
```

### HOOK

```solidity
AsyncSwap immutable HOOK;
```

### MEV_TAX_GAS

```solidity
uint256 immutable MEV_TAX_GAS;
```

### FLASH_FILLER_LOCATION

<i>
  Router transient slot this module shares (see Router).
  keccak256("Router.FlashFiller") - 1: the filler of the flash fill in progress, zero otherwise.
</i>

```solidity
bytes32 constant FLASH_FILLER_LOCATION = 0x8a32db0797977fc7694da75ada74debc8ae08fbf3557ccd5133e780e8ba11369;
```

### FLASH_FILL_ACTION

<i>
  First word of the Router's unlock data for a flash fill: `Router.ActionType.FlashFill`.
</i>

```solidity
uint8 constant FLASH_FILL_ACTION = 9;
```

### BEGIN

```solidity
uint8 constant BEGIN = 0;
```

### SETTLE

```solidity
uint8 constant SETTLE = 1;
```

### FILL

```solidity
uint8 constant FILL = 2;
```

## Functions

<a id="constructor-ipoolmanager-asyncswap-uint256" />

### constructor

```solidity
constructor(IPoolManager _poolManager, AsyncSwap _hook, uint256 _mevTaxGas);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \_poolManager | `IPoolManager` |  |
| \_hook | `AsyncSwap` |  |
| \_mevTaxGas | `uint256` |  |

<a id="fillorderwithcallback-asyncorder-uint256-bytes" />

### fillOrderWithCallback

Fill `order` with no inventory: input first as claims, callback, then the owed output as claims.
Every fill in the callback (this one and each `fillOrderInCallback`) owes the MEV tax, paid to the
FeeVault when the fill runs. `msg.value` prepays it, any amount; the filler may also pay inside its
callback with `PoolManager.settleFor(router)`. A surplus is returned to the filler in ETH and a
shortfall reverts `MevTaxUnpaid`.

```solidity
function fillOrderWithCallback(AsyncOrder calldata order, uint256 maxPrice, bytes calldata data) external payable;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |
| maxPrice | `uint256` |  |
| data | `bytes` |  |

<a id="unlockcallback-bytes" />

### unlockCallback

Body of a flash fill: the Router's `unlockCallback` forwards its calldata here (running as the Router)
when the action is a flash fill. Input first, callback, then the output check and payout.

```solidity
function unlockCallback(bytes calldata data) external returns (bytes memory);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| data | `bytes` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `bytes` |  |

<a id="fillorderincallback-asyncorder-uint256" />

### fillOrderInCallback

Inside the callback: fill another open order, paying its output and receiving its input as claims.

```solidity
function fillOrderInCallback(AsyncOrder calldata order, uint256 maxPrice) external;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |
| maxPrice | `uint256` |  |

<a id="matchbookincallback-poolkey-uint8" />

### matchBookInCallback

Inside the callback: continue a crossed book.

```solidity
function matchBookInCallback(PoolKey calldata key, uint8 maxMatches) external returns (uint8);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| key | `PoolKey` |  |
| maxMatches | `uint8` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `uint8` |  |

<a id="mevtaxfor-uint256" />

### mevTaxFor

MEV tax for `fills` fills at this transaction's priority fee. Off chain, simulate with the gas price
you will send (`eth_call` with `gasPrice`); on chain it is exact for the running transaction.

```solidity
function mevTaxFor(uint256 fills) external view returns (uint256);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| fills | `uint256` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `uint256` |  |

<a id="mevtaxowed" />

### mevTaxOwed

Inside the callback: the MEV tax the Router still owes for this flash fill, every fill charged so far
less what was paid. Settle exactly this with `PoolManager.settleFor(router)` before returning.

```solidity
function mevTaxOwed() external view returns (uint256);
```

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `uint256` |  |

<a id="_mevtax" />

### \_mevTax

```solidity
function _mevTax() private view returns (uint256);
```

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `uint256` |  |

<a id="_chargemevtax-address" />

### \_chargeMevTax

<i>
  Pays one fill's MEV tax to the FeeVault as native claims now; the Router owes it to the PoolManager
  until `_settleMevTax`.
</i>

```solidity
function _chargeMevTax(address filler) private;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| filler | `address` |  |

<a id="_settlemevtax-address-uint256" />

### \_settleMevTax

<i>
  Settles the prepayment, then requires the Router's native delta to be covered: the filler may have paid
  with `settleFor(router)` in its callback. A surplus goes back to the filler.
</i>

```solidity
function _settleMevTax(address filler, uint256 prepaid) private;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| filler | `address` |  |
| prepaid | `uint256` |  |

<a id="_hookcall-uint8-asyncorder-address" />

### \_hookCall

```solidity
function _hookCall(uint8 op, AsyncOrder memory order, address filler) private returns (uint256, uint256);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| op | `uint8` |  |
| order | `AsyncOrder` |  |
| filler | `address` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `uint256` |  |
| \<none> | `uint256` |  |

<a id="_onlyflashfiller" />

### \_onlyFlashFiller

```solidity
function _onlyFlashFiller() private view;
```

<a id="_flashfiller" />

### \_flashFiller

```solidity
function _flashFiller() private view returns (address filler);
```

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| filler | `address` |  |

<a id="_output-asyncorder" />

### \_output

```solidity
function _output(AsyncOrder memory order) private pure returns (Currency);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `Currency` |  |

<a id="_checkfill-asyncorder-uint256" />

### \_checkFill

<i>
  Checks the live order against the filler's bounds and returns the output owed: the live minimum, at most
  `maxPrice`, for a live input of at least `order.amountIn`. A missing order is left for the hook to reject.
  The flash path charges no pool fee, so the hook burns exactly the live minimum it returns.
  A Dutch auction order is stepped first, so the filler pays the scheduled price, not an older one.
</i>

```solidity
function _checkFill(AsyncOrder memory order, uint256 maxPrice) private returns (uint256 livePrice);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |
| maxPrice | `uint256` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| livePrice | `uint256` |  |

## Events

### MevTaxPaid

```solidity
event MevTaxPaid(address indexed payer, uint256 amount);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| payer | `address` |  |
| amount | `uint256` |  |

## Errors

### FlashFillActive

A flash fill is already running.

```solidity
error FlashFillActive();
```

### NotFlashFiller

An in-callback entry point was called by anyone but the filler of the running flash fill.

```solidity
error NotFlashFiller();
```

### MevTaxUnpaid

The filler left `owed` of the MEV tax of its fills unpaid.

```solidity
error MevTaxUnpaid(uint256 owed);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| owed | `uint256` |  |
