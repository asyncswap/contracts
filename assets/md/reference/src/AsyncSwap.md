# AsyncSwap

[Git Source](https://github.com/asyncswap/contracts/blob/fe373151eb2cd6cdbd7a60b534a479a0dde5d75e/src/AsyncSwap.sol)

**Inherits:** [BaseHook](/reference/src/BaseHook), EIP712

**Title:** AsyncSwap

**Author:** @msakiart

Uniswap v4 hook that converts an exact-input swap into an open async order: the maker
deposits their input via `_beforeSwap`. Crossing orders settle directly at the resting
limit; fillers settle unmatched orders.

Makers can also act by EIP-712 signature (`setExecutorWithSig`, `updatePriceWithSig`) so a
relayer pays gas and the wallet shows a readable message. See `OrderSignatures` for types.

## Constants

### feeVault

Holds fee claims separately from open-order escrow.

```solidity
FeeVault public immutable feeVault;
```

### numeraire

Chain-specific USDC address. Every pool must include this exact currency.

```solidity
Currency public immutable numeraire;
```

### router

The only swap caller the hook accepts, fixed at deployment. Only the Router settles a new order's input
and hands it to `matchNewOrder`, so an order opened through any other caller would leave the
transient pending-match id set for the rest of the transaction, and `matchBook` would skip that pool.

```solidity
address public immutable router;
```

### PENDING_NATIVE_DEPOSIT_SLOT

<i>
  Transient slot — keccak256("asyncswap.hook.pendingNativeDeposit") - 1.
  Tracks ETH deposited to this contract within the current tx via
  `receive()`, so `executeOrder` can settle native output only out of
  the filler's just-received deposit rather than the contract's
  accumulated balance (which may include donations, stranded ETH,
  or in-flight native-input escrow). Cleared after each settle.
</i>

```solidity
bytes32 constant PENDING_NATIVE_DEPOSIT_SLOT = 0x9c2a7e4f3b1d8a5c6e0f2d4b7a9c1e3d5f8b6a0c2e4d7b9f1a3c5e7d9b1f3a50;
```

### PENDING_MATCH_ID_SLOT

<i>
  Transient hand-off from `_beforeSwap` to the Router after it settles the new input.
</i>

```solidity
bytes32 constant PENDING_MATCH_ID_SLOT = 0x247d5e35be7fbfd4d95fd66ea940bfb4ee942bef70db6afae46dc83ce0f89eb2;
```

### PENDING_MATCH_EXECUTOR_SLOT

```solidity
bytes32 constant PENDING_MATCH_EXECUTOR_SLOT = 0x9583e36f799bab8c4d06dc676d85ba05b4dfbde5934d5684d8e431d0fd3948da;
```

## State Variables

### asyncOrders

Per-pool order book.

```solidity
mapping(PoolId poolId => AsyncFiller.State) public asyncOrders;
```

### priceBooks

```solidity
mapping(PoolId poolId => AsyncFiller.Book) private priceBooks;
```

### owner

Protocol owner authorized to collect vault fees and sweep stranded balances.

```solidity
address public owner;
```

### pendingOwner

Address nominated by `transferOwnership`; becomes owner on `acceptOwnership`.

```solidity
address public pendingOwner;
```

### nonceUsed

Unordered nonces consumed by signed maker actions (`setExecutorWithSig`, `updatePriceWithSig`).

```solidity
mapping(address maker => mapping(uint256 nonce => bool)) public nonceUsed;
```

### defaultMinOrder

Minimum order, in numeraire base units, that pools initialized from now on start with.

```solidity
uint256 public defaultMinOrder;
```

## Functions

<a id="onlyowner" />

### onlyOwner

Restricts a call to the protocol owner.

```solidity
modifier onlyOwner();
```

<a id="constructor-ipoolmanager-currency-address-address" />

### constructor

```solidity
constructor(IPoolManager _poolManager, Currency _numeraire, address _owner, address _router)
        BaseHook(_poolManager)
        EIP712("AsyncSwap", "1");
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \_poolManager | `IPoolManager` |  |
| \_numeraire | `Currency` |  |
| \_owner | `address` | Explicit protocol owner. Not `msg.sender`: CREATE2 deployments run the<br />constructor from the deterministic deployer, which could never act as owner. |
| \_router | `address` | The Router, deployed after the hook (it takes the hook in its constructor): pass its<br />predicted address. |

<a id="transferownership-address" />

### transferOwnership

Start a two-step ownership transfer. The deployer (or a factory) should call this after
deployment to hand control to the intended fee recipient / governance address, which
then calls `acceptOwnership`.

```solidity
function transferOwnership(address newOwner) external onlyOwner;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| newOwner | `address` |  |

<a id="acceptownership" />

### acceptOwnership

Complete a two-step ownership transfer. Only the nominated `pendingOwner` may call.

```solidity
function acceptOwnership() external;
```

<a id="sweep-currency-address" />

### sweep

Sweep an accumulated balance of `currency` held by this hook to `to`.

<i>
  Between transactions the hook's raw balance holds only stranded funds or donations;
  fees belong to feeVault. Maker input is escrowed as ERC-6909
  claims in the PoolManager, and the transient native-deposit ledger is cleared at the
  end of every tx, so no per-order escrow lives in the hook's balance across calls.
</i>

```solidity
function sweep(Currency currency, address to) external onlyOwner;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| currency | `Currency` |  |
| to | `address` |  |

<a id="_beforeinitialize-address-poolkey-uint160" />

### \_beforeInitialize

<i>
  Only the owner opens pools: the initial price feeds the sell-side minimum check, so an
  extreme price set by anyone else could block every sell on the pool.
</i>

```solidity
function _beforeInitialize(address sender, PoolKey calldata key, uint160)
        internal
        virtual
        override
        returns (bytes4);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| sender | `address` |  |
| key | `PoolKey` |  |
| \_ | `uint160` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `bytes4` |  |

<a id="gethookpermissions" />

### getHookPermissions

Returns a struct of permissions to signal which hook functions are to be implemented

<i>
  Used at deployment to validate the address correctly represents the expected permissions
</i>

```solidity
function getHookPermissions() public pure override returns (Hooks.Permissions memory);
```

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `Hooks.Permissions` |  |

<a id="_beforeaddliquidity-address-poolkey-modifyliquidityparams-bytes" />

### \_beforeAddLiquidity

```solidity
function _beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        internal
        pure
        override
        returns (bytes4);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \_ | `address` |  |
| \_ | `PoolKey` |  |
| \_ | `ModifyLiquidityParams` |  |
| \_ | `bytes` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `bytes4` |  |

<a id="asyncorder-poolid-bytes32" />

### asyncOrder

Read an order's currently-open input amount. Returns 0 if the order does not exist.

```solidity
function asyncOrder(PoolId poolId, bytes32 orderId) external view returns (uint256 amountIn);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| poolId | `PoolId` |  |
| orderId | `bytes32` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| amountIn | `uint256` |  |

<a id="asyncorderinfo-poolid-bytes32" />

### asyncOrderInfo

Read both legs of an open order. Returns (0, 0) if the order does not exist.

```solidity
function asyncOrderInfo(PoolId poolId, bytes32 orderId)
        external
        view
        returns (uint256 amountIn, uint256 amountOutMin);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| poolId | `PoolId` |  |
| orderId | `bytes32` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| amountIn | `uint256` |  |
| amountOutMin | `uint256` |  |

<a id="asyncorderpriorityfee-poolid-bytes32" />

### asyncOrderPriorityFee

The priority bid an order escrowed when it was created.

```solidity
function asyncOrderPriorityFee(PoolId poolId, bytes32 orderId) external view returns (uint256);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| poolId | `PoolId` |  |
| orderId | `bytes32` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `uint256` |  |

<a id="setminorder-poolkey-uint256" />

### setMinOrder

Set a pool's minimum order, in numeraire base units (0: none).

```solidity
function setMinOrder(PoolKey calldata key, uint256 minimum) external onlyOwner;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| key | `PoolKey` |  |
| minimum | `uint256` |  |

<a id="setdefaultminorder-uint256" />

### setDefaultMinOrder

Set the minimum order new pools start with.

```solidity
function setDefaultMinOrder(uint256 minimum) external onlyOwner;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| minimum | `uint256` |  |

<a id="bestorder-poolid-bool" />

### bestOrder

Return the best live limit order for a pool side. `isBuy` is true
when the maker escrows the pool numeraire to buy the other asset.
`priceKey` is a WAD-scaled raw-amount ratio for sorting within this pool,
not a human-readable price. Equal-price orders queue by bid, then submission order.

```solidity
function bestOrder(PoolId poolId, bool isBuy)
        external
        view
        returns (bool found, uint128 priceKey, bytes32 orderId, address maker);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| poolId | `PoolId` |  |
| isBuy | `bool` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| found | `bool` |  |
| priceKey | `uint128` |  |
| orderId | `bytes32` |  |
| maker | `address` |  |

<a id="orderbooklevel-poolid-bool-uint128" />

### orderBookLevel

Return the first and last order under the pool's configured ordering mode, plus count.

```solidity
function orderBookLevel(PoolId poolId, bool isBuy, uint128 priceKey)
        external
        view
        returns (bytes32 head, bytes32 tail, uint32 count);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| poolId | `PoolId` |  |
| isBuy | `bool` |  |
| priceKey | `uint128` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| head | `bytes32` |  |
| tail | `bytes32` |  |
| count | `uint32` |  |

<a id="orderbookorder-poolid-bytes32" />

### orderBookOrder

Read one live order: its terms, price key, queue position (`sequence`) and bid.

```solidity
function orderBookOrder(PoolId poolId, bytes32 orderId)
        external
        view
        returns (
            address maker,
            uint256 amountIn,
            uint256 amountOutMin,
            uint128 priceKey,
            bool isBuy,
            uint64 sequence,
            uint64 priorityFee
        );
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| poolId | `PoolId` |  |
| orderId | `bytes32` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| maker | `address` |  |
| amountIn | `uint256` |  |
| amountOutMin | `uint256` |  |
| priceKey | `uint128` |  |
| isBuy | `bool` |  |
| sequence | `uint64` |  |
| priorityFee | `uint64` |  |

<a id="ordercreatedsequence-poolid-bytes32" />

### orderCreatedSequence

Immutable incarnation of a live order, used to bind cancellation signatures.

```solidity
function orderCreatedSequence(PoolId poolId, bytes32 id) external view returns (uint64);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| poolId | `PoolId` |  |
| id | `bytes32` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `uint64` |  |

<a id="isexecutor-poolid-address-address" />

### isExecutor

```solidity
function isExecutor(PoolId poolId, address maker, address executor) external view returns (bool);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| poolId | `PoolId` |  |
| maker | `address` |  |
| executor | `address` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `bool` |  |

<a id="calculatehookfee-uint256" />

### calculateHookFee

```solidity
function calculateHookFee(uint256) public pure returns (uint256);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \_ | `uint256` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `uint256` |  |

<a id="calculatepoolfee-uint24-uint256" />

### calculatePoolFee

Surcharge a filler pays on top of the maker's minimum: none. The 0.02% trade fee comes
out of what each side receives instead (`AsyncFiller.tradeFee`).

```solidity
function calculatePoolFee(uint24, uint256) public pure virtual returns (uint256);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \_ | `uint24` |  |
| \_ | `uint256` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `uint256` |  |

<a id="executeorder-asyncorder-bytes" />

### executeOrder

Fill `order` in full. Must be called from an authorized executor (router) that has
already paid the filler's gross output within the same unlock: for ERC20 output via
`PoolManager.settleFor(hook)`, for native output by sending ETH to this hook.

```solidity
function executeOrder(AsyncOrder calldata order, bytes calldata data) external;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |
| data | `bytes` | abi.encode(filler) — the address that should receive the maker's input. |

<a id="matchneworder-asyncorder" />

### matchNewOrder

Match the order just created by the current Router unlock callback.

<i>
  The Router calls this only after settling the maker's input. The transient hand-off
  prevents stale order ids or a different executor from triggering a match.
</i>

```solidity
function matchNewOrder(AsyncOrder calldata order) external returns (uint8 matched);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| matched | `uint8` |  |

<a id="_poolbeatsbook-poolkey-bool" />

### \_poolBeatsBook

<i>
  True when the pool has active liquidity and its current price is strictly better for an
  incoming order than the best resting order on the other side: below the best ask for a
  buy, above the best bid for a sell (`TickPrice.poolBeatsLevel`). An empty opposite side or an equal level leaves the book first.
  The spot price excludes the pool fill's fees and price impact, so this is a heuristic.
  With it, the best level as a sqrt price: the limit a pool-first swap may not cross.
</i>

```solidity
function _poolBeatsBook(PoolKey calldata key, bool isBuy) private view returns (bool, uint160);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| key | `PoolKey` |  |
| isBuy | `bool` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `bool` |  |
| \<none> | `uint160` |  |

<a id="tryfillorderfrompoolliquidity-asyncorder" />

### tryFillOrderFromPoolLiquidity

Permissionless executor entry for retrying a resting order against current pool LPs.

<i>
  Must run inside PoolManager.unlock. Router calls this after validating the request path.
</i>

```solidity
function tryFillOrderFromPoolLiquidity(AsyncOrder calldata order) external returns (bool filled);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| filled | `bool` |  |

<a id="fillorderfrompoolliquidity-asyncorder-bytes32-uint160" />

### fillOrderFromPoolLiquidity

<i>
  The self-call boundary makes a failed AMM attempt atomic while preserving the resting
  order. PoolManager skips hook callbacks when the hook itself is the swap caller, so this
  swap does not create an order.
  `sqrtPriceLimitX96` is a price the swap may not cross (0 for none): the whole order fills
  before it, or the call reverts.
</i>

```solidity
function fillOrderFromPoolLiquidity(AsyncOrder calldata order, bytes32 id, uint160 sqrtPriceLimitX96) external;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |
| id | `bytes32` |  |
| sqrtPriceLimitX96 | `uint160` |  |

<a id="matchbook-poolkey-uint8" />

### matchBook

Permissionlessly continue a crossed book inside a PoolManager unlock.

<i>
  The Router exposes the unlock wrapper; each call processes at most eight pairs.
</i>

```solidity
function matchBook(PoolKey calldata key, uint8 maxMatches) external returns (uint8 matched);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| key | `PoolKey` |  |
| maxMatches | `uint8` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| matched | `uint8` |  |

<a id="updateprice-asyncorder-uint256" />

### updatePrice

Maker updates the limit price of an unfilled order. Direct call from the maker —
pure state mutation, no PM interaction, so no unlock or router needed.

```solidity
function updatePrice(AsyncOrder calldata order, uint256 newAmountOutMin) external;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |
| newAmountOutMin | `uint256` |  |

<a id="cancelorder-asyncorder" />

### cancelOrder

Maker cancels an unfilled order. Must be called via an authorized executor inside
an `IPoolManager.unlock` context. The executor must have asserted maker identity.

```solidity
function cancelOrder(AsyncOrder calldata order) external;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |

<a id="_beforeswap-address-poolkey-swapparams-bytes" />

### \_beforeSwap

```solidity
function _beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata hookParams)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| sender | `address` |  |
| key | `PoolKey` |  |
| params | `SwapParams` |  |
| hookParams | `bytes` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `bytes4` |  |
| \<none> | `BeforeSwapDelta` |  |
| \<none> | `uint24` |  |

<a id="_createorder-poolid-bool-uint256-userparams-bool" />

### \_createOrder

<i>
  Extracted to keep `_beforeSwap` stack-shallow.
</i>

```solidity
function _createOrder(PoolId poolId, bool zeroForOne, uint256 amountIn, UserParams memory hookData, bool isBuy)
        private;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| poolId | `PoolId` |  |
| zeroForOne | `bool` |  |
| amountIn | `uint256` |  |
| hookData | `UserParams` |  |
| isBuy | `bool` |  |

<a id="setexecutor-poolid-address-bool" />

### setExecutor

Maker explicitly authorises an executor (typically the Router) to submit
and fill orders on their behalf. Without this grant, `_createOrder` reverts
on the maker's first swap. Pass `allow = false` to revoke an executor.

```solidity
function setExecutor(PoolId poolId, address executor, bool allow) external;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| poolId | `PoolId` |  |
| executor | `address` |  |
| allow | `bool` |  |

<a id="setexecutorwithsig-poolkey-address-address-bool-uint256-uint256-bytes" />

### setExecutorWithSig

Signed `setExecutor`: anyone may submit the maker's EIP-712 `SetExecutor` grant.
Lets a relayer authorize the Router before the maker's first gasless order on a pool.

```solidity
function setExecutorWithSig(
        PoolKey calldata key,
        address maker,
        address executor,
        bool allow,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| key | `PoolKey` |  |
| maker | `address` |  |
| executor | `address` |  |
| allow | `bool` |  |
| nonce | `uint256` |  |
| deadline | `uint256` |  |
| signature | `bytes` |  |

<a id="updatepricewithsig-asyncorder-uint256-uint256-uint256-bytes" />

### updatePriceWithSig

Signed `updatePrice`: anyone may submit the maker's EIP-712 `UpdatePrice` message.

```solidity
function updatePriceWithSig(
        AsyncOrder calldata order,
        uint256 newAmountOutMin,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |
| newAmountOutMin | `uint256` |  |
| nonce | `uint256` |  |
| deadline | `uint256` |  |
| signature | `bytes` |  |

<a id="invalidatenonce-uint256" />

### invalidateNonce

Revoke a signed action before a relayer submits it.

```solidity
function invalidateNonce(uint256 nonce) external;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| nonce | `uint256` |  |

<a id="usenonce-poolid-address-uint256" />

### useNonce

Burns `maker`'s nonce for a signature the Router verified itself (`cancelWithSig`).
Every maker signature shares this one nonce space, so `invalidateNonce` revokes those
signatures too, and only the trusted Router may burn one: any other executor could
void the maker's signed actions on every pool.

```solidity
function useNonce(PoolId poolId, address maker, uint256 nonce) external;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| poolId | `PoolId` |  |
| maker | `address` |  |
| nonce | `uint256` |  |

<a id="domain_separator" />

### DOMAIN_SEPARATOR

EIP-712 domain separator for this hook's signed actions.

```solidity
function DOMAIN_SEPARATOR() external view returns (bytes32);
```

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `bytes32` |  |

<a id="_verify-address-bytes32-uint256-uint256-bytes" />

### \_verify

<i>
  Checks deadline, burns the nonce, then validates an EOA or ERC-1271 signature.
</i>

```solidity
function _verify(address maker, bytes32 structHash, uint256 nonce, uint256 deadline, bytes calldata signature)
        private;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| maker | `address` |  |
| structHash | `bytes32` |  |
| nonce | `uint256` |  |
| deadline | `uint256` |  |
| signature | `bytes` |  |

<a id="_usenonce-address-uint256" />

### \_useNonce

```solidity
function _useNonce(address maker, uint256 nonce) private;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| maker | `address` |  |
| nonce | `uint256` |  |

<a id="receive" />

### receive

Accept ETH transfers. The Router (or any caller paying for a native-output
fill) forwards `msg.value` to the hook before triggering `executeOrder`. The hook
records the deposit on a transient slot so `executeOrder` settles only against the
filler's same-transaction deposit. ETH sent without a follow-up `executeOrder` stays
in the hook balance and is recoverable only through `sweep`.

```solidity
receive() external payable;
```

## Events

### HookSwap

Pool-level swap-event mirror; bytes32 poolId for indexer compatibility.

<i>
  See https://github.com/OpenZeppelin/uniswap-hooks BaseAsyncSwap for the source pattern.
</i>

```solidity
event HookSwap(
        bytes32 indexed id,
        address indexed sender,
        int128 amount0,
        int128 amount1,
        uint128 hookLPfeeAmount0,
        uint128 hookLPfeeAmount1
    );
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| id | `bytes32` |  |
| sender | `address` |  |
| amount0 | `int128` |  |
| amount1 | `int128` |  |
| hookLPfeeAmount0 | `uint128` |  |
| hookLPfeeAmount1 | `uint128` |  |

### OwnershipTransferred

Emitted when ownership is transferred.

```solidity
event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| previousOwner | `address` |  |
| newOwner | `address` |  |

### OwnershipTransferStarted

Emitted when the owner nominates a new owner.

```solidity
event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| previousOwner | `address` |  |
| newOwner | `address` |  |

### Swept

Emitted when the owner sweeps an accumulated balance.

```solidity
event Swept(Currency indexed currency, address indexed to, uint256 amount);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| currency | `Currency` |  |
| to | `address` |  |
| amount | `uint256` |  |

### NonceInvalidated

Emitted when a maker burns a nonce, consumed or revoked.

```solidity
event NonceInvalidated(address indexed maker, uint256 nonce);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| maker | `address` |  |
| nonce | `uint256` |  |

### ExecutorSet

Emitted after each successful direct or signed executor authorization update.

<i>
  `allow` is the resulting permission, including when the value is unchanged.
</i>

```solidity
event ExecutorSet(PoolId indexed poolId, address indexed maker, address indexed executor, bool allow);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| poolId | `PoolId` |  |
| maker | `address` |  |
| executor | `address` |  |
| allow | `bool` |  |

### AsyncOrdersMatched

Pairwise direct escrow match; emitted by the linked matcher at the hook address.

```solidity
event AsyncOrdersMatched(
        PoolId indexed poolId,
        bytes32 indexed sellOrderId,
        bytes32 indexed buyOrderId,
        uint256 assetAmount,
        uint256 numeraireAmount
    );
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| poolId | `PoolId` |  |
| sellOrderId | `bytes32` |  |
| buyOrderId | `bytes32` |  |
| assetAmount | `uint256` |  |
| numeraireAmount | `uint256` |  |

### AsyncOrderLiquidityFilled

An open order was fully executed against active Uniswap v4 pool liquidity.

```solidity
event AsyncOrderLiquidityFilled(
        PoolId indexed poolId, bytes32 indexed orderId, address indexed maker, uint256 amountIn, uint256 amountOut
    );
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| poolId | `PoolId` |  |
| orderId | `bytes32` |  |
| maker | `address` |  |
| amountIn | `uint256` |  |
| amountOut | `uint256` |  |

### DynamicFeeCharged

Mirror of `DynamicFeeOrdering.DynamicFeeCharged`, emitted by the linked library in this
contract's context, so the hook's ABI decodes it.

```solidity
event DynamicFeeCharged(
        PoolId indexed poolId,
        bytes32 indexed orderId,
        Currency indexed currency,
        uint256 toLps,
        uint256 toFeeVault,
        int24 refTick
    );
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| poolId | `PoolId` |  |
| orderId | `bytes32` |  |
| currency | `Currency` |  |
| toLps | `uint256` |  |
| toFeeVault | `uint256` |  |
| refTick | `int24` |  |

### PoolPriceObserved

Mirror of `DynamicFeeOrdering.PoolPriceObserved`, emitted by the linked library in this
contract's context so indexers can reconstruct completed pool-fill price movements.

```solidity
event PoolPriceObserved(
        PoolId indexed poolId,
        bytes32 indexed orderId,
        int24 tickBefore,
        int24 tickAfter,
        int24 refTick,
        uint64 observedBlock
    );
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| poolId | `PoolId` |  |
| orderId | `bytes32` |  |
| tickBefore | `int24` |  |
| tickAfter | `int24` |  |
| refTick | `int24` |  |
| observedBlock | `uint64` |  |

## Errors

### ExactInputOnly

```solidity
error ExactInputOnly();
```

### UnaccountedNativeOutput

```solidity
error UnaccountedNativeOutput();
```

### NotOwner

```solidity
error NotOwner();
```

### ZeroAddress

```solidity
error ZeroAddress();
```

### SignatureExpired

```solidity
error SignatureExpired();
```

### InvalidSignature

```solidity
error InvalidSignature();
```

### NonceAlreadyUsed

```solidity
error NonceAlreadyUsed();
```

### InvalidNumeraire

```solidity
error InvalidNumeraire();
```

### NumeraireRequired

```solidity
error NumeraireRequired();
```

### DynamicFeeRequired

```solidity
error DynamicFeeRequired();
```

### NotSelf

```solidity
error NotSelf();
```

### NotTrustedRouter

```solidity
error NotTrustedRouter();
```

## Structs

### UserParams

Hook params decoded from the `hookData` of `IPoolManager.swap`. The maker sets
`amountOutMin` (their limit price); `executor` is the address authorized to call fill.
Salt is contract-assigned at create time (see `_createOrder`) and emitted in
`AsyncOrderCreated` — the maker fetches it from the event log to reference the
order in cancel / updatePrice later.

```solidity
struct UserParams {
        address user;
        address executor;
        uint256 amountOutMin;
        uint256 priorityFee;
    }
```

**Properties**

| Name | Type | Description |
| ---- | ---- | ----------- |
| user | `address` |  |
| executor | `address` |  |
| amountOutMin | `uint256` |  |
| priorityFee | `uint256` |  |
