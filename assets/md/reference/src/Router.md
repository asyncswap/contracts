# Router

[Git Source](https://github.com/asyncswap/contracts/blob/2bbb7d0a129a3419408dd3151a91cb5ff19adf49/src/Router.sol)

**Inherits:** EIP712, Multicall

**Title:** Router

**Author:** @msakiart

Thin entrypoint for makers (`swap`, `cancelOrder`, `cancelAndWithdraw`, `withdrawClaims`), fillers
(`fillOrder`) and keepers (`matchBook`, `fillFromPoolLiquidity`), batched with `multicall`. Each action
goes through `IPoolManager.unlock` so the hook can operate on PM debts. Native payouts/refunds are
PoolManager claims (ID 0), redeemable through NativeClaims or `withdrawClaims`; ERC20 payouts remain
direct.

Gasless variants (`swapWithSig`, `cancelWithSig`) take the maker's EIP-712 signature so a
relayer can submit. Signed creates pull input through Permit2 with the order as witness,
so the wallet shows the full order (tokens, amounts, pool) in one readable message.

`multicall` runs several of these as one atomic transaction, each as the caller (for example,
cancel many orders and withdraw the claims). It is not payable, so native-value actions
(`swap` with native input, `fillOrder` with native output) cannot reuse one `msg.value`.
Each action keeps its own PoolManager unlock and sets the transient slots it reads.

Order creation and fills (`swap`, `swapWithSig`, `fillOrder`, `fillFromPoolLiquidity`) pay an MEV tax
("Priority Is All You Need", Robinson & White): `mevTax()`, the transaction's priority fee per gas times
`MEV_TAX_GAS`, in ETH on top of any native deposit, credited to the FeeVault as native claims. On a chain
that orders by priority fee, searchers racing for the same position bid it up, so most of what they race
for goes to the protocol; a transaction with no priority pays nothing. Inside `multicall`, which is not
payable, a taxed action needs a transaction with no priority.

## Constants

### POOLMANAGER

```solidity
IPoolManager immutable POOLMANAGER;
```

### HOOK

```solidity
AsyncSwap immutable HOOK;
```

### PERMIT2

```solidity
ISignatureTransfer public immutable PERMIT2;
```

### MEV_TAX_GAS

Gas units the MEV tax charges per unit of priority fee: the tax on a transaction is its priority fee
per gas times this. Fixed at deployment.

```solidity
uint256 public immutable MEV_TAX_GAS;
```

### ACTION_LOCATION

keccak256("Router.ActionType") - 1

```solidity
bytes32 constant ACTION_LOCATION = 0xf3b150ebf41dad0872df6788629edb438733cb4a5c9ea779b1b1f3614faffc69;
```

### USER_LOCATION

keccak256("Router.User") - 1

```solidity
bytes32 constant USER_LOCATION = 0x3dde20d9bf5cc25a9f487c6d6b54d3c19e3fa4738b91a7a509d4fc4180a72356;
```

### ASYNC_FILLER_LOCATION

keccak256("Router.AsyncFiller") - 1

```solidity
bytes32 constant ASYNC_FILLER_LOCATION = 0xd972a937b59dc5cb8c692dd9f211e85afa8def4caee6e05b31db0f53e16d02e0;
```

### MAX_PRICE_LOCATION

<i>
  keccak256("asyncswap.router.maxPrice") - 1
</i>

```solidity
bytes32 constant MAX_PRICE_LOCATION = 0x6b4f8e2c9d5a0b7e1f3c2a8d4e9f0b6c5a1d8e7f2b3c4d5e6a7f8b9c0d1e2f30;
```

### MEV_TAX_LOCATION

keccak256("Router.MevTax") - 1

```solidity
bytes32 constant MEV_TAX_LOCATION = 0xe6251c15e22bdb44d13d4efeec6855e57f2b38fe36310ce3c709991726ed21da;
```

## Functions

<a id="constructor-ipoolmanager-asyncswap-isignaturetransfer-uint256" />

### constructor

```solidity
constructor(IPoolManager _poolManager, AsyncSwap _hook, ISignatureTransfer _permit2, uint256 _mevTaxGas)
        EIP712("AsyncSwap Router", "1");
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \_poolManager | `IPoolManager` |  |
| \_hook | `AsyncSwap` |  |
| \_permit2 | `ISignatureTransfer` |  |
| \_mevTaxGas | `uint256` |  |

<a id="mevtax" />

### mevTax

The MEV tax this transaction pays per taxed action, in wei: its priority fee per gas times
`MEV_TAX_GAS`.

```solidity
function mevTax() public view returns (uint256);
```

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `uint256` |  |

<a id="_chargemevtax-uint256" />

### \_chargeMevTax

<i>
  Requires `msg.value` to be `deposit` plus the MEV tax, and records the tax for the unlock callback,
  which credits it to the FeeVault.
</i>

```solidity
function _chargeMevTax(uint256 deposit) private;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| deposit | `uint256` |  |

<a id="onlypoolmanager" />

### onlyPoolManager

```solidity
modifier onlyPoolManager();
```

<a id="swap-asyncorder-bytes" />

### swap

Maker submits a new async order. `userData` must encode `AsyncSwap.UserParams`
with `executor == address(this)` so the router is authorized to fill later.
`userData.amountOutMin` MUST equal `order.amountOutMin` — the router enforces
this so the limit price the maker signs in `order` is exactly what beforeSwap
stores via hookData.

The hook auto-assigns a salt on create and emits it in `AsyncOrderCreated`.
Submitters can pass `order.salt = bytes32(0)` on initial submission; the
field is only read on cancel / updatePrice / fill paths (where the maker
supplies the salt fetched from the indexer or event log).

Native input (currency0 = address(0) and zeroForOne = true, OR currency1 =
address(0) and zeroForOne = false) requires `msg.value == order.amountIn` —
the router holds the ETH and settles it to PM during unlock. For ERC20 input
the maker must approve the router for `amountIn` of the input token. Either way `msg.value`
also carries the MEV tax (`mevTax()`, zero without a priority fee).

```solidity
function swap(AsyncOrder calldata order, bytes memory userData) external payable;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |
| userData | `bytes` |  |

<a id="fillorder-asyncorder-uint256-bytes" />

### fillOrder

Filler completes an open order, paying exactly the maker's live minimum. The maker
receives it less the 0.02% trade fee, and the filler the input less 0.02%.
For ERC20 output, approve the router for that amount. For native output,
`msg.value` must equal the live minimum;
a stale or excessive deposit reverts rather than stranding the difference. `msg.value`
also carries the MEV tax (`mevTax()`, zero without a priority fee).
Native output is currency1 for zeroForOne, otherwise currency0.

`maxPrice` caps the output the filler pays —
it protects fillers from a maker who front-runs them with `updatePrice` to
bump the order's stored price. Pass `type(uint256).max` to disable the check.
`order.amountIn` is the least input the filler accepts: the fill reverts if the
order's live input has dropped below it (e.g. after a partial match).

```solidity
function fillOrder(AsyncOrder calldata order, uint256 maxPrice, bytes calldata) external payable;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |
| maxPrice | `uint256` |  |
| \_ | `bytes` |  |

<a id="swapwithsig-asyncorder-permitdata-executorgrant" />

### swapWithSig

Relayer submits a maker's signed order. The maker signs a Permit2
`PermitWitnessTransferFrom` for `amountIn` of the input token with `spender = Router`
and the `AsyncOrder` witness (see `OrderSignatures`), so one signature both approves
the transfer and commits to the order. Input then lands in the hook escrow exactly as
in `swap`. Requires a prior Permit2 approval of the input token; native input is not
supported (use `swap`). The relayer pays the MEV tax for its transaction's priority in `msg.value`.

```solidity
function swapWithSig(AsyncOrder calldata order, PermitData calldata permit, ExecutorGrant calldata grant)
        external
        payable;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |
| permit | `PermitData` |  |
| grant | `ExecutorGrant` |  |

<a id="cancelwithsig-asyncorder-uint256-uint256-bytes" />

### cancelWithSig

Relayer submits a maker's signed EIP-712 `CancelOrder`. Input returns to the maker.
The nonce is burnt in the hook's store, so `AsyncSwap.invalidateNonce` revokes it.

```solidity
function cancelWithSig(AsyncOrder calldata order, uint256 nonce, uint256 deadline, bytes calldata signature)
        external;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |
| nonce | `uint256` |  |
| deadline | `uint256` |  |
| signature | `bytes` |  |

<a id="domain_separator" />

### DOMAIN_SEPARATOR

EIP-712 domain separator for Router-verified signatures (`CancelOrder`).

```solidity
function DOMAIN_SEPARATOR() external view returns (bytes32);
```

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `bytes32` |  |

<a id="cancelorder-asyncorder" />

### cancelOrder

Maker cancels an unfilled order and reclaims their reserved input.

```solidity
function cancelOrder(AsyncOrder calldata order) external;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |

<a id="cancelandwithdraw-asyncorder" />

### cancelAndWithdraw

Cancel an owned order and return its remaining input to the owner's wallet.

<i>
  Native refunds are redeemed atomically. Approve this Router for claim ID 0 first.
  Existing claims are untouched; a failed redemption rolls back the cancellation.
</i>

```solidity
function cancelAndWithdraw(AsyncOrder calldata order) external;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |

<a id="withdrawclaims-currency-uint256" />

### withdrawClaims

Withdraw the caller's approved ERC-6909 claims directly to their wallet.

<i>
  Approve exact currency claim allowances on PoolManager first. No operator grant is needed.
</i>

```solidity
function withdrawClaims(Currency[] calldata currencies, uint256[] calldata amounts) external;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| currencies | `Currency[]` |  |
| amounts | `uint256[]` |  |

<a id="matchbook-poolkey-uint8" />

### matchBook

Anyone can continue a crossed book after a transaction hits the automatic match cap.

<i>
  Work is capped at eight matched pairs per unlock to keep gas predictable.
</i>

```solidity
function matchBook(PoolKey calldata key, uint8 maxMatches) external;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| key | `PoolKey` |  |
| maxMatches | `uint8` |  |

<a id="fillfrompoolliquidity-asyncorder" />

### fillFromPoolLiquidity

Retry a resting order against the pool's active Uniswap v4 LP positions.

<i>
  The order is left untouched when the pool cannot fully fill it at its minimum output. `msg.value` is
  the MEV tax.
</i>

```solidity
function fillFromPoolLiquidity(AsyncOrder calldata order) external payable;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |

<a id="unlockcallback-bytes" />

### unlockCallback

PM unlock-callback dispatcher. The action enum is read from transient storage, set
by the externally-callable entry above. Each branch must leave PM deltas net-zero.

```solidity
function unlockCallback(bytes calldata data) external onlyPoolManager returns (bytes memory);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| data | `bytes` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `bytes` |  |

<a id="_paymevtax" />

### \_payMevTax

<i>
  Credits a recorded MEV tax, held by the Router since the entry call, to the FeeVault as native claims.
</i>

```solidity
function _payMevTax() private;
```

<a id="_withdrawclaim-address-currency-uint256" />

### \_withdrawClaim

```solidity
function _withdrawClaim(address owner, Currency currency, uint256 amount) private;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| owner | `address` |  |
| currency | `Currency` |  |
| amount | `uint256` |  |

<a id="_requireunchanged-asyncorder-bytes32-uint256-uint256" />

### \_requireUnchanged

<i>
  Reverts unless the order still reads `(amountIn, amountOutMin)` in the hook.
</i>

```solidity
function _requireUnchanged(AsyncOrder memory order, bytes32 id, uint256 amountIn, uint256 amountOutMin)
        private
        view;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |
| id | `bytes32` |  |
| amountIn | `uint256` |  |
| amountOutMin | `uint256` |  |

<a id="_settlewithpermit-currency-asyncorder-permitdata" />

### \_settleWithPermit

<i>
  Pays the maker's input into the PoolManager via Permit2. Permit2 verifies the maker's
  signature over the transfer AND the order witness, so a relayer cannot alter the order.
</i>

```solidity
function _settleWithPermit(Currency input, AsyncOrder memory order, PermitData memory permit) private;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| input | `Currency` |  |
| order | `AsyncOrder` |  |
| permit | `PermitData` |  |

<a id="_settlepriorityfee-asyncorder" />

### \_settlePriorityFee

<i>
  Pays the order's bid, which the hook escrowed as claims when it created the order, in the
  pool's USDC numeraire. Signed orders also require an ERC-20 approval for the bid; the
  signed order commits to its amount.
</i>

```solidity
function _settlePriorityFee(AsyncOrder memory order) private;
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |

<a id="_orderid-asyncorder" />

### \_orderId

<i>
  MUST match AsyncOrderLibrary.orderId exactly: (chainId, poolId, owner, zeroForOne, salt).
</i>

```solidity
function _orderId(AsyncOrder memory order) private view returns (bytes32);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| order | `AsyncOrder` |  |

**Returns**

| Name | Type | Description |
| ---- | ---- | ----------- |
| \<none> | `bytes32` |  |

## Events

### MevTaxPaid

A taxed action paid `amount` wei of MEV tax, credited to the FeeVault as native claims.

```solidity
event MevTaxPaid(address indexed payer, uint256 amount);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| payer | `address` |  |
| amount | `uint256` |  |

### ClaimWithdrawn

```solidity
event ClaimWithdrawn(address indexed owner, Currency indexed currency, uint256 amount);
```

**Parameters**

| Name | Type | Description |
| ---- | ---- | ----------- |
| owner | `address` |  |
| currency | `Currency` |  |
| amount | `uint256` |  |

## Errors

### SignatureExpired

```solidity
error SignatureExpired();
```

### InvalidSignature

```solidity
error InvalidSignature();
```

## Structs

### SwapCallback

```solidity
struct SwapCallback {
        ActionType action;
        AsyncOrder order;
        uint8 maxMatches;
    }
```

**Properties**

| Name | Type | Description |
| ---- | ---- | ----------- |
| action | `ActionType` |  |
| order | `AsyncOrder` |  |
| maxMatches | `uint8` |  |

### PermitData

Permit2 signature + nonce/deadline for a signed create.

```solidity
struct PermitData {
        uint256 nonce;
        uint256 deadline;
        bytes signature;
    }
```

**Properties**

| Name | Type | Description |
| ---- | ---- | ----------- |
| nonce | `uint256` |  |
| deadline | `uint256` |  |
| signature | `bytes` |  |

### ExecutorGrant

Optional signed `SetExecutor` grant, submitted to the hook ahead of the maker's first
gasless order on a pool. A supplied grant is always applied and its nonce spent, so leave
`signature` empty when the Router is already authorized.

```solidity
struct ExecutorGrant {
        uint256 nonce;
        uint256 deadline;
        bytes signature;
    }
```

**Properties**

| Name | Type | Description |
| ---- | ---- | ----------- |
| nonce | `uint256` |  |
| deadline | `uint256` |  |
| signature | `bytes` |  |

## Enums

### ActionType

```solidity
enum ActionType {
        Swap,
        FillOrder,
        Cancel,
        SwapWithSig,
        MatchBook,
        PoolLiquidityFill,
        CancelAndWithdraw,
        WithdrawClaims
    }
```

**Variants**

| Name | Description |
| ---- | ----------- |
| Swap |  |
| FillOrder |  |
| Cancel |  |
| SwapWithSig |  |
| MatchBook |  |
| PoolLiquidityFill |  |
| CancelAndWithdraw |  |
| WithdrawClaims |  |
