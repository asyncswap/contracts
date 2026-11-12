# AsyncSwapFlashFiller

[Git Source](https://github.com/asyncswap/contracts/blob/245c06bce0aea780bf783eff9b5e05cd627266fc/src/periphery/AsyncSwapFlashFiller.sol)

**Inherits:** [IAsyncSwapFlashFiller](/reference/src/interfaces/IAsyncSwapFlashFiller)

**Title:** AsyncSwapFlashFiller

Base for flash fillers. Write `_route`; this contract handles the rest:

* only the Router may call the callback, and only for a fill this contract started;
* it approves the Router for the output owed to the maker;
* it pays the exact MEV tax owed, from its ETH balance, so `fill` needs no `msg.value`.
  Keep enough ETH in the contract for the tax (send it with `fill`, or fund it beforehand).
  Surplus and refunds stay in the contract; `withdraw` sends them to the owner.

## Constants

### POOLMANAGER

```solidity
IPoolManager public immutable POOLMANAGER;
```

### ROUTER

```solidity
IAsyncSwapCallback public immutable ROUTER;
```

### OWNER

```solidity
address public immutable OWNER;
```

## Functions

<a id="constructor-ipoolmanager-iasyncswapcallback-address" />

### constructor

```solidity
constructor(IPoolManager poolManager, IAsyncSwapCallback router, address owner);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| poolManager | `IPoolManager` |  |
| router | `IAsyncSwapCallback` |  |
| owner | `address` |  |

<a id="fill-asyncorder-uint256-bytes" />

### fill

Starts a flash fill of `order`. Any ETH sent stays here to pay the MEV tax.

```solidity
function fill(AsyncOrder calldata order, uint256 maxPrice, bytes calldata data) external payable;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |
| maxPrice | `uint256` |  |
| data | `bytes` |  |

<a id="ethneeded-uint256" />

### ethNeeded

The ETH `fill` needs for the MEV tax of `fills` fills at this gas price, less what the contract holds.

```solidity
function ethNeeded(uint256 fills) external view returns (uint256);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| fills | `uint256` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `uint256` |  |

<a id="asyncswapflashfill-asyncorder-uint256-uint256-bytes" />

### asyncSwapFlashFill

Called by the Router inside its PoolManager unlock, after the order was closed and its input,
less the 0.02% trade fee, credited to the filler as ERC-6909 claims (`amountIn` of the input
currency, id 0 for native ETH).

<i>
  Before returning, the filler must hold `amountOwed` claims of the order's output currency and allow
  the Router to transfer them (`PoolManager.approve(router, id, amountOwed)` or an operator grant). Inside
  the callback it may swap on any v4 pool, `burn`/`mint`/`take`/`settle`, and fill other Async Swap orders
  through `IAsyncSwapCallback.fillOrderInCallback` and `matchBookInCallback`. Every delta it opens must be zero
  when the Router's unlock ends.
</i>

```solidity
function asyncSwapFlashFill(AsyncOrder calldata order, uint256 amountIn, uint256 amountOwed, bytes calldata data)
        external;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |
| amountIn | `uint256` |  |
| amountOwed | `uint256` |  |
| data | `bytes` |  |

<a id="withdraw-uint256-uint256-uint256" />

### withdraw

Sends `amount` ETH and ERC-6909 claims of `ids` held here to the owner.

```solidity
function withdraw(uint256 amount, uint256[] calldata ids, uint256[] calldata amounts) external;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount | `uint256` |  |
| ids | `uint256[]` |  |
| amounts | `uint256[]` |  |

<a id="_route-asyncorder-uint256-uint256-bytes" />

### \_route

<i>
  Turn `amountIn` input claims into at least `amountOwed` output claims held by this contract. Runs inside
  the PoolManager unlock: swap on v4 pools, call `ROUTER.fillOrderInCallback` or `matchBookInCallback`.
  Every delta this contract opens must be zero when it returns.
</i>

```solidity
function _route(AsyncOrder calldata order, uint256 amountIn, uint256 amountOwed, bytes calldata data)
        internal
        virtual;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |
| amountIn | `uint256` |  |
| amountOwed | `uint256` |  |
| data | `bytes` |  |

<a id="_paymevtax" />

### \_payMevTax

```solidity
function _payMevTax() private;
```

<a id="receive" />

### receive

```solidity
receive() external payable;
```

## Errors

### MevTaxBalanceTooLow

The contract holds less ETH than the MEV tax it owes.

```solidity
error MevTaxBalanceTooLow(uint256 owed, uint256 balance);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| owed | `uint256` |  |
| balance | `uint256` |  |

### NotRouter

```solidity
error NotRouter();
```

### NotOwner

```solidity
error NotOwner();
```
