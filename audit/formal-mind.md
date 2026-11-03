# Formal Mind report

Generated from Formal Mind's `formalmind.audit/v1` report by `python3 script/formal-mind-report.py`. Don't edit by hand.

> **Out of date.** Every property here was proved against the Lean model generated from the contracts at `c49689f` (Oct 28), not the current code, and line numbers refer to that code. Properties the code has since changed are marked ⚠️. Most of the Lean files named here were never committed; the last tracked copy of `formal/` is at `5901aca`. The Solidity tests in [`test/formal/`](../test/formal/README.md) check the same kinds of properties against the current bytecode.

## Findings

| ID | Severity | Finding | Location | PoC | Status |
|----|----------|---------|----------|-----|--------|
| FM-01 | Medium | Best-price routing compares only the pool spot tick, then swaps the whole order through the pool, bypassing better book liquidity | `src/AsyncSwap.sol:396` | `test/formal/RoutingPoolImpact.t.sol` | ✅ Fixed in `550b463`; see [FM-01-routing-pool-impact.md](FM-01-routing-pool-impact.md) |

Full write-ups: [formal-mind-swarm.md](formal-mind-swarm.md).

## Properties

49 properties, all reported `verified` against the `c49689f` model; 3 no longer match the code.

| ID | Function | Location | Property | Status |
|----|----------|----------|----------|--------|
| [P-01](#p-01) | `AsyncSwap.asyncOrderInfo` | `src/AsyncSwap.sol:233` | `AsyncSwap.asyncOrderInfo` always succeeds, returns the selected `asyncOrders[poolId].orders[orderId]` `amountIn` and `amountOutMin` values in that order, and preserves storage. Its returned values depend only on the `asyncOrders` mapping, so equal mappings give equal returns regardless of the environment or other storage. | Verified |
| [P-02](#p-02) | `AsyncSwap.isExecutor` | `src/AsyncSwap.sol:296` | `AsyncSwap.isExecutor` returns exactly `asyncOrders[poolId].isExecutor[maker][executor]`, preserves the entire modeled state, and has no function-body revert condition. | Verified |
| [P-03](#p-03) | `AsyncSwap.setExecutor` | `src/AsyncSwap.sol:524` | `AsyncSwap.setExecutor` always succeeds in the generated model and returns unit. On success, assuming the external adapter satisfies `ext.get (ext.set w st) = st`, the projected storage updates only `asyncOrders[poolId].isExecutor[env.sender][executor]` to `allow`; every other pool/caller/executor permission entry remains unchanged. The model does not establish ABI, nonpayable, event, or gas-level properties. | ⚠️ Out of date: `setExecutor` now reverts `CannotRevokeTrustedRouter` when a maker revokes the trusted Router. |
| [P-04](#p-04) | `AsyncSwap.setDefaultMinOrder` | `src/AsyncSwap.sol:253` | `AsyncSwap.setDefaultMinOrder` reverts with `NotOwner` exactly when the caller differs from the stored owner. An owner call succeeds for every modeled minimum, returns `()`, and produces exactly `ext.set s { ext.get s with defaultMinOrder := minimum }`. Under the storage read-after-write law, the resulting contract state differs only in `defaultMinOrder`, which equals `minimum`; owner and every other contract-state field are preserved. The body makes no external calls. | Verified |
| [P-05](#p-05) | `Router.cancelOrder` | `src/Router.sol:220` | `Router.cancelOrder` rejects a non-owner with `Only owner can cancel`. For the owner, it writes the caller to transient `USER_LOCATION` and calls `POOLMANAGER.unlock` with ABI-encoded action 2 (Cancel), every supplied order field, and maxMatches 0. It succeeds exactly when that external call succeeds, returns unit, and retains the external call's resulting world; external errors propagate unchanged. The local pre-call write preserves both persistent storage fields and every other transient slot. | Verified |
| [P-06](#p-06) | `AsyncSwap.calculatePoolFee` | `src/AsyncSwap.sol:305` | `AsyncSwap.calculatePoolFee` (`src/AsyncSwap.sol:353`), as implemented in the base `AsyncSwap` contract, is total, returns zero and leaves state unchanged: | Verified |
| [P-07](#p-07) | `Router.swap` | `src/Router.sol:113` | `Router.swap` succeeds exactly when ABI decoding and all applicable local guards pass and the specified pool-manager `unlock` call succeeds. Successful decoding requires at least 128 bytes and two valid 160-bit address words. The caller must own the order; decoded user, executor, minimum output, and priority fee must match the owner, router, and order fields. Native input requires `msg.value = order.amountIn`; ERC20 input requires zero value. Local failures follow the modeled guard order, and unlock errors propagate. Before unlock, the Router storage projection changes only the two transient slots: `USER_LOCATION` receives the caller and `ASYNC_FILLER_LOCATION` receives the router address. Unlock receives the ABI-encoded Swap callback with the original order and zero maxMatches. The function discards unlock's return data, returns no value, and retains unlock's resulting state. | Verified |
| [P-09](#p-09) | `AsyncSwap.acceptOwnership` | `src/AsyncSwap.sol:166` | `AsyncSwap.acceptOwnership` reverts with `NotOwner` exactly when the sender differs from `pendingOwner`. Otherwise it returns unit, sets `owner` to the sender, and clears `pendingOwner`. The exact execution theorem describes both storage writes without accessor assumptions. Under the storage-accessor laws, the resulting contract storage equals the original record with only those two fields updated; every other field is preserved. The body invokes no external-call handler. | Verified |
| [P-10](#p-10) | `AsyncSwap.setMinOrder` | `src/AsyncSwap.sol:248` | In the generated function-body model, `AsyncSwap.setMinOrder` reverts exactly when the caller differs from the current owner, with `NotOwner`. For the owner it returns unit and sets `priceBooks[toId(key)].minOrder` to `minimum`. All other book fields, other pool IDs, and this contract's modeled storage fields outside `priceBooks` remain unchanged. The execution formula uses no external-call handlers. | Verified |
| [P-11](#p-11) | `AsyncSwap.invalidateNonce` | `src/AsyncSwap.sol:578` | `AsyncSwap.invalidateNonce` reverts with `NonceAlreadyUsed` exactly when `nonceUsed[msg.sender][nonce]` is true. Otherwise it returns unit and passes to the storage setter the original contract state with only that nonce entry set to true. With a lawful storage getter/setter, every other nonce entry and every other contract storage field remains unchanged. The exact execution equation uses no external-call handlers. | Verified |
| [P-12](#p-12) | `AsyncSwap.transferOwnership` | `src/AsyncSwap.sol:159` | `AsyncSwap.transferOwnership` reverts with `NotOwner` when the caller is not the current owner. For the current owner, it reverts with `ZeroAddress` exactly when `newOwner = 0`; otherwise it returns unit and updates only `pendingOwner` to the nominated nonzero value, preserving the rest of the storage record. | Verified |
| [P-14](#p-14) | `Router.fillFromPoolLiquidity` | `src/Router.sol:240` | `Router.fillFromPoolLiquidity` has no source-level guards. In the generated model, its outcome is determined by `POOLMANAGER.unlock`. | Verified |
| [P-15](#p-15) | `BaseHook.beforeInitialize` | `src/BaseHook.sol:35` | `BaseHook.beforeInitialize` reverts in order unless the caller is the pool manager, `sender` is the owner, the pool key contains the numeraire, and the fee equals `LPFeeLibrary.DYNAMIC_FEE_FLAG`. On success it returns selector `0xdc98354e` and updates only the selected pool's `asyncOrders.poolManager`, `asyncOrders.numeraire`, `asyncOrders.feeVault`, and `priceBooks.minOrder` fields, with `minOrder` set to `defaultMinOrder`; it performs no external calls. | ⚠️ Out of date: Pool creation is open since #61 (`81ba6b8`): `beforeInitialize` no longer checks `sender` is the owner. |
| [P-17](#p-17) | `NativeClaims.redeem` | `src/NativeClaims.sol:30` | `NativeClaims.redeem` reverts with `ReentrantRedemption` when `_redeeming` is true. Otherwise, it reverts with `InvalidRedemption` when `recipient` or `amount` is zero. For nonzero inputs, it sets `_redeeming` to true, calls `poolManager.unlock(abi.encode(msg.sender, recipient, amount))`, propagates that call's revert, and on a successful return clears `_redeeming` and returns `()`; the local execution performs no other storage writes. | Verified |
| [P-18](#p-18) | `TokenClaims.redeem` | `src/TokenClaims.sol:30` | `TokenClaims.redeem` reverts with `ReentrantRedemption` when `_redeeming` is true and with `InvalidRedemption` when the recipient or amount is zero. When both guards pass, it sets `_redeeming` to true, calls `poolManager.unlock` with `abi.encode(msg.sender, currency, recipient, amount)`, propagates the external call's result, and clears `_redeeming` after a successful call. | Verified |
| [P-19](#p-19) | `AsyncSwap.setExecutorWithSig` | `src/AsyncSwap.sol:531` | `AsyncSwap.setExecutorWithSig` checks its guards in source order: deadline, then nonce, then signature. | ⚠️ Out of date: `setExecutorWithSig` now also reverts `CannotRevokeTrustedRouter` (after the signature checks) when the grant revokes the trusted Router. |
| [P-22](#p-22) | `FeeVault.collect` | `src/FeeVault.sol:27` | `FeeVault.collect` propagates failure from `hook.owner()`, reverts with `Unauthorized` when `msg.sender` differs from the returned owner, and reverts with `ZeroAddress` when `recipient` is zero. When both guards pass, it calls `poolManager.unlock(abiEncode [currency, recipient])`, propagates that call's failure, returns `()`, and performs no local storage update; the resulting state is the state returned by `unlock`. | Verified |
| [P-23](#p-23) | `FeeVault.unlockCallback` | `src/FeeVault.sol:34` | `FeeVault.unlockCallback` reverts with `Unauthorized` unless the caller is the PoolManager. For an authorized call with calldata containing two ABI words whose decoded values fit in 160 bits, balance lookup errors propagate; a zero balance returns empty bytes without changing the world state; a nonzero balance calls `burn(address(this), id, amount)` and then `take(currency, recipient, amount)`, propagating either error and otherwise returning empty bytes with the final external-call state. | Verified |
| [P-24](#p-24) | `Router.swapWithSig` | `src/Router.sol:180` | `Router.swapWithSig` reverts with `Native input needs swap()` whenever the selected input currency (`currency0` when `order.zeroForOne` is true, otherwise `currency1`) is zero; this path performs no later external calls or transient writes. | Verified |
| [P-25](#p-25) | `AsyncSwap.sweep` | `src/AsyncSwap.sol:178` | `AsyncSwap.sweep` reverts with `NotOwner` when the caller is not the stored owner, and an owner call with a zero recipient reverts with `ZeroAddress`. For an owner call with a nonzero recipient, it invokes the modeled balance and transfer calls; if those calls return the stated successful results, the function returns unit with the transfer call’s post-world. The function body performs no contract-local storage write. | Verified |
| [P-27](#p-27) | `AsyncSwap.cancelOrder` | `src/AsyncSwap.sol:426` | `AsyncSwap.cancelOrder` propagates `NotAuthorizedExecutor` when the delegated executor condition is unauthorized and propagates `OrderNotFound` when the delegated order has zero `amountIn`, assuming successful generated `orderId` and pool-ID computations. When those computations succeed and the supplied `AsyncMatching.cancel` execution returns successfully with post-state `w'`, `AsyncSwap.cancelOrder` returns `Unit` with the same post-state. The success theorem covers wrapper delegation and propagation; the delegate's internal guards, external calls, and storage effects remain assumptions. | Verified |
| [P-28](#p-28) | `AsyncSwap.executeOrder` | `src/AsyncSwap.sol:315` | `AsyncSwap.executeOrder` reverts with `UnaccountedNativeOutput` when the generated execution reaches the native-output branch, `asyncOrderInfo` returns minimum output 1, `calculatePoolFee` returns 0 for that minimum output, and the pending native-deposit amount is less than 1. The theorem establishes this early revert before `AsyncMatching.fill` is called. | Verified |
| [P-32](#p-32) | `BaseHook.beforeSwap` | `src/BaseHook.sol:143` | `BaseHook.beforeSwap` reverts with `NotPoolManager` when `env.sender ≠ ext.poolManager`. When `env.sender = ext.poolManager`, it returns exactly the successful result and post-state produced by `AsyncSwap._beforeSwap`, including any effects represented by that delegated result and post-state. | Verified |
| [P-33](#p-33) | `Router.unlockCallback` | `src/Router.sol:253` | `Router.unlockCallback` reverts with `"Caller is not PoolManager"` whenever the call sender differs from the configured `PoolManager`. | Verified |
| [P-34](#p-34) | `AsyncSwap.matchBook` | `src/AsyncSwap.sol:402` | `AsyncSwap.matchBook` returns zero without invoking `AsyncMatching.matchBook` when the pending match ID is nonzero and the corresponding order has nonzero input. Otherwise, assuming all three pool-ID computations succeed with the same pool ID and `AsyncMatching.matchBook` succeeds with post-state `w'` and result `n`, it returns `n` with post-state `w'`. | Verified |
| [P-36](#p-36) | `AsyncSwap.getHookPermissions` | `src/AsyncSwap.sol:197` | `AsyncSwap.getHookPermissions` succeeds for every extension, environment, and storage state; returns the declared `Hooks.Permissions` record with `beforeInitialize`, `beforeAddLiquidity`, `beforeSwap`, and `beforeSwapReturnDelta` enabled and every other permission disabled; and leaves storage unchanged. | Verified |
| [P-37](#p-37) | `AsyncSwap.asyncOrder` | `src/AsyncSwap.sol:228` | `AsyncSwap.asyncOrder` never reverts; on every call it returns `asyncOrders[poolId].orders[orderId].amountIn` and preserves the complete modeled contract state. The generated function has no storage writes or external calls. | Verified |
| [P-38](#p-38) | `AsyncSwap.asyncOrderPriorityFee` | `src/AsyncSwap.sol:243` | `AsyncSwap.asyncOrderPriorityFee` always succeeds, returns the selected order's `priorityFee`, and leaves storage unchanged. Its result depends only on `asyncOrders`. | Verified |
| [P-39](#p-39) | `AsyncSwap.bestOrder` | `src/AsyncSwap.sol:261` | `AsyncSwap.bestOrder` propagates the successful result tuple returned by its delegated `AsyncMatching.bestOrder` call. If that delegated call returns the tuple without changing state, `AsyncSwap.bestOrder` also returns it without changing state. | Verified |
| [P-40](#p-40) | `AsyncSwap.orderBookLevel` | `src/AsyncSwap.sol:270` | `AsyncSwap.orderBookLevel` has no guards of its own: it reverts exactly when its delegated `AsyncFiller.level` computation reverts. On successful execution, it returns the delegated `(head, tail, count)` result and leaves the storage state unchanged. | Verified |
| [P-41](#p-41) | `AsyncSwap.orderBookOrder` | `src/AsyncSwap.sol:279` | `AsyncSwap.orderBookOrder` never reverts; it returns the owner, input amount, minimum output, price, buy flag, sequence, and priority fee stored in `asyncOrders[poolId].orders[orderId]`, and leaves storage unchanged. | Verified |
| [P-42](#p-42) | `AsyncSwap.calculateHookFee` | `src/AsyncSwap.sol:300` | `AsyncSwap.calculateHookFee` never reverts; on every call it returns fee `0` and preserves storage, so it has no storage writes or external-call effects. | Verified |
| [P-43](#p-43) | `AsyncSwap.DOMAIN_SEPARATOR` | `src/AsyncSwap.sol:586` | `AsyncSwap.DOMAIN_SEPARATOR` does not revert. It returns the cached EIP-712 domain separator when `address(this)` and `chainid` equal their cached values; otherwise it returns `keccak(TYPE_HASH, hashedName, hashedVersion, chainid, address(this))`. Both branches preserve the complete world state and perform no storage writes. | Verified |
| [P-45](#p-45) | `Router.DOMAIN_SEPARATOR` | `src/Router.sol:215` | `Router.DOMAIN_SEPARATOR` succeeds without a reverting guard and returns the cached EIP-712 domain separator when `address(this)` and `chainid` match the cached values; otherwise it returns the freshly built separator. Every successful call leaves the complete world state unchanged. | Verified |
| [P-46](#p-46) | `BaseHook.afterInitialize` | `src/BaseHook.sol:48` | `BaseHook.afterInitialize` reverts with `NotPoolManager` when the caller is not the configured pool manager; for the configured pool manager, it reverts with `HookNotImplemented` via the default `_afterInitialize` implementation. The modeled function therefore has no successful return and performs no storage writes. | Verified |
| [P-47](#p-47) | `BaseHook.beforeAddLiquidity` | `src/BaseHook.sol:61` | `BaseHook.beforeAddLiquidity` reverts with `NotPoolManager` unless the caller is the pool manager. When the guard holds, it returns selector `0x259982e5` and leaves storage unchanged. | Verified |
| [P-48](#p-48) | `BaseHook.beforeRemoveLiquidity` | `src/BaseHook.sol:79` | `BaseHook.beforeRemoveLiquidity` reverts with `NotPoolManager` when the caller is not the configured pool manager; for the configured pool manager, the generated base implementation reverts with `HookNotImplemented`. It has no successful execution, storage write, or return value. | Verified |
| [P-49](#p-49) | `BaseHook.afterAddLiquidity` | `src/BaseHook.sol:97` | `BaseHook.afterAddLiquidity` reverts with `NotPoolManager` when `env.sender ≠ ext.poolManager`; otherwise it reverts with `HookNotImplemented` from the generated default `_afterAddLiquidity` implementation. Neither path changes storage, and no successful return value is produced. | Verified |
| [P-50](#p-50) | `BaseHook.afterRemoveLiquidity` | `src/BaseHook.sol:120` | `BaseHook.afterRemoveLiquidity` reverts with `NotPoolManager` when the caller is not `ext.poolManager`; when the caller is `ext.poolManager`, it reverts with `HookNotImplemented`. It performs no storage writes and has no successful return. | Verified |
| [P-51](#p-51) | `BaseHook.afterSwap` | `src/BaseHook.sol:160` | `BaseHook.afterSwap` reverts with `NotPoolManager` when `env.sender ≠ ext.poolManager`; when the caller is authorized, it reverts with `HookNotImplemented` from the default hook body. Consequently, the modeled function has no successful return path and performs no storage writes or external calls. | Verified |
| [P-52](#p-52) | `BaseHook.beforeDonate` | `src/BaseHook.sol:179` | `BaseHook.beforeDonate` reverts with `NotPoolManager` when `env.sender ≠ ext.poolManager`; when `env.sender = ext.poolManager`, it reverts with `HookNotImplemented` via the generated `_beforeDonate` implementation. Consequently, every modeled call reverts and the function has no successful return or storage-write path. | Verified |
| [P-53](#p-53) | `BaseHook.afterDonate` | `src/BaseHook.sol:198` | `BaseHook.afterDonate` reverts with `NotPoolManager` when `env.sender` differs from `ext.poolManager`. When the caller is the configured pool manager, it reaches the generated default `_afterDonate`, which reverts with `HookNotImplemented`; consequently, no invocation returns a value, performs an external call, or writes storage. | Verified |
| [P-54](#p-54) | `AsyncSwap.onlyOwner` | — | `AsyncSwap.onlyOwner` reverts with `NotOwner` when `msg.sender` differs from the stored owner. When the caller is the stored owner, it runs the wrapped continuation unchanged and preserves its return value and resulting storage state; the modifier itself performs no storage writes or additional external calls. | Verified |
| [P-55](#p-55) | `CurrencyLibrary.isAddressZero` | — | `CurrencyLibrary.isAddressZero` always succeeds and returns whether `currency == CurrencyLibrary.ADDRESS_ZERO`; it preserves the complete storage state and performs no writes. | Verified |
| [P-56](#p-56) | `CurrencyLibrary.balanceOfSelf` | — | `CurrencyLibrary.balanceOfSelf` returns `Env.balance` when `currency == CurrencyLibrary.ADDRESS_ZERO`; otherwise it returns the ERC-20 `balanceOf` result for `currency` and `Env.self`, propagating a view error unchanged. Every successful execution preserves storage. | Verified |
| [P-57](#p-57) | `CustomRevert.bubbleUpAndRevertWith` | — | `CustomRevert.bubbleUpAndRevertWith` always returns an error `⟨"revert"⟩` under the generated FormalAst semantics; consequently, it has no successful return value or storage write. | Verified |
| [P-60](#p-60) | `PoolIdLibrary.toId` | — | `PoolIdLibrary.toId` always succeeds, writes no storage, and returns `ext.keccak [currency0, currency1, fee, toUnsigned 256 tickSpacing, hooks]`. | Verified |
| [P-61](#p-61) | `RadixPriceTree.best` | — | `RadixPriceTree.best` preserves storage on every successful call when its tree getter returns a fixed tree without changing state. If a successful call returns `(false, 0)`, the fixed tree has root zero. If it returns `(true, p)`, the fixed tree has a nonzero root and some leaf has price `p`. | Verified |
| [P-62](#p-62) | `AsyncFiller.bestOrder` | — | `AsyncFiller.bestOrder` selects the bids tree when `isBuy` is true and the asks tree otherwise. If the selected tree reports no order, it returns `(found, price, 0, 0)`. If an order is found, it delegates order selection to `AsyncFiller.bestAtPrice`, reads the selected order owner from `self_get`, and returns `(found, price, orderId, owner)`; any revert or storage write arises only from the delegated tree, price-selection call, or supplied getter/setter computations. | Verified |

## Property details

### P-01

**`AsyncSwap.asyncOrderInfo`** at `src/AsyncSwap.sol:233`

`AsyncSwap.asyncOrderInfo` always succeeds, returns the selected `asyncOrders[poolId].orders[orderId]` `amountIn` and `amountOutMin` values in that order, and preserves storage. Its returned values depend only on the `asyncOrders` mapping, so equal mappings give equal returns regardless of the environment or other storage.

**Assumptions.** None beyond the generated FormalAst model and the supplied external-state projection `ext.get`.

Theorems:

- `AsyncSwap.Swarm.AsyncOrderInfo.asyncOrderInfo_storage`
- `AsyncSwap.Swarm.AsyncOrderInfo.asyncOrderInfo_no_revert`
- `AsyncSwap.Swarm.AsyncOrderInfo.asyncOrderInfo_ok_iff`
- `AsyncSwap.Swarm.AsyncOrderInfo.asyncOrderInfo_reads_only_asyncOrders`

Lean (local only): `formal/Proofs/Swarm/AsyncSwapAsyncOrderInfo.lean`

### P-02

**`AsyncSwap.isExecutor`** at `src/AsyncSwap.sol:296`

`AsyncSwap.isExecutor` returns exactly `asyncOrders[poolId].isExecutor[maker][executor]`, preserves the entire modeled state, and has no function-body revert condition.

**Assumptions.** No additional logical hypotheses or external-call assumptions. The result concerns the generated function-body semantics; ABI decoding, nonpayable dispatch checks, and gas exhaustion are outside its scope.

Theorems:

- `AsyncSwap.Refinement.Swarm.AsyncSwapIsExecutor.isExecutor_storage`
- `AsyncSwap.Refinement.Swarm.AsyncSwapIsExecutor.isExecutor_no_revert`
- `AsyncSwap.Refinement.Swarm.AsyncSwapIsExecutor.isExecutor_success`

Lean (local only): `formal/Proofs/Swarm/AsyncSwapIsExecutor.lean`

### P-03

**`AsyncSwap.setExecutor`** at `src/AsyncSwap.sol:524`

> ⚠️ **Out of date.** `setExecutor` now reverts `CannotRevokeTrustedRouter` when a maker revokes the trusted Router.

`AsyncSwap.setExecutor` always succeeds in the generated model and returns unit. On success, assuming the external adapter satisfies `ext.get (ext.set w st) = st`, the projected storage updates only `asyncOrders[poolId].isExecutor[env.sender][executor]` to `allow`; every other pool/caller/executor permission entry remains unchanged. The model does not establish ABI, nonpayable, event, or gas-level properties.

**Assumptions.** The storage-footprint and permission-frame results assume `hget : ∀ w st, ext.get (ext.set w st) = st`. No law is assumed about outer world state beyond this getter/setter projection.

Theorems:

- `AsyncSwap.setExecutor_run`
- `AsyncSwap.setExecutor_ok_iff`
- `AsyncSwap.setExecutor_frame`
- `AsyncSwap.setExecutor_no_revert`
- `AsyncSwap.setExecutor_permission_frame`

### P-04

**`AsyncSwap.setDefaultMinOrder`** at `src/AsyncSwap.sol:253`

`AsyncSwap.setDefaultMinOrder` reverts with `NotOwner` exactly when the caller differs from the stored owner. An owner call succeeds for every modeled minimum, returns `()`, and produces exactly `ext.set s { ext.get s with defaultMinOrder := minimum }`. Under the storage read-after-write law, the resulting contract state differs only in `defaultMinOrder`, which equals `minimum`; owner and every other contract-state field are preserved. The body makes no external calls.

**Assumptions.** The theorems concern execution of the generated function body, not ABI decoding, Solidity's nonpayable entry check, or gas exhaustion. Application to Solidity assumes a valid uint256 argument, zero msg.value, and sufficient gas; the model represents the minimum as Nat. The frame theorem assumes ∀ w st, ext.get (ext.set w st) = st. Exact execution and guard theorems require no laws on Ext. Preservation of unrelated world components outside the contract state is not asserted.

Theorems:

- `AsyncSwap.setDefaultMinOrder_run`
- `AsyncSwap.setDefaultMinOrder_reverts_of_not_owner`
- `AsyncSwap.setDefaultMinOrder_ok_of_owner`
- `AsyncSwap.setDefaultMinOrder_ok_iff`
- `AsyncSwap.setDefaultMinOrder_frame`
- `AsyncSwap.setDefaultMinOrder_reverts_iff`

Lean (local only): `formal/Proofs/Swarm/AsyncSwapSetDefaultMinOrder.lean`

### P-05

**`Router.cancelOrder`** at `src/Router.sol:220`

`Router.cancelOrder` rejects a non-owner with `Only owner can cancel`. For the owner, it writes the caller to transient `USER_LOCATION` and calls `POOLMANAGER.unlock` with ABI-encoded action 2 (Cancel), every supplied order field, and maxMatches 0. It succeeds exactly when that external call succeeds, returns unit, and retains the external call's resulting world; external errors propagate unchanged. The local pre-call write preserves both persistent storage fields and every other transient slot.

**Assumptions.** The execution theorems hold for arbitrary external-call behavior. The projected local-storage footprint assumes ext.get (ext.set w st) = st. No storage preservation or cancellation semantics is assumed or proved for the opaque unlock call. These properties concern the generated function body, not the Solidity nonpayable dispatcher.

Theorems:

- `Router.Swarm.RouterCancelOrder.cancelOrder_run`
- `Router.Swarm.RouterCancelOrder.cancelOrder_reject`
- `Router.Swarm.RouterCancelOrder.cancelOrder_success_iff`
- `Router.Swarm.RouterCancelOrder.cancelOrder_error_iff`
- `Router.Swarm.RouterCancelOrder.beforeUnlock_footprint`

Lean (local only): `formal/Proofs/Swarm/RouterCancelOrder.lean`

### P-06

**`AsyncSwap.calculatePoolFee`** at `src/AsyncSwap.sol:305`

`AsyncSwap.calculatePoolFee` (`src/AsyncSwap.sol:353`), as implemented in the base `AsyncSwap` contract, is total, returns zero and leaves state unchanged:

- `calculatePoolFee_success`: for all arguments, environments and states `s`, the function body succeeds with result `(0, s)`. It returns fee `0` and writes no storage.
- `calculatePoolFee_ne_error`: the function body never reverts, for any arguments, environment or state.
- `calculatePoolFee_success_iff`: a successful outcome `(result, s')` occurs exactly when `result = 0` and `s' = s`, so the result and the empty write footprint are fully determined.

**Assumptions.** The theorems concern the generated def of the function body, whose arguments are unbounded `Nat`s. ABI decoding of calldata, including rejection of an out-of-range `uint24`, belongs to the external entry point and is not covered. The function is `public pure virtual`: the theorems describe the base implementation only, and a derived contract that overrides it is not covered.

Theorems:

- `AsyncSwap.Refinement.Swarm.AsyncSwapCalculatePoolFee.calculatePoolFee_success`
- `AsyncSwap.Refinement.Swarm.AsyncSwapCalculatePoolFee.calculatePoolFee_ne_error`
- `AsyncSwap.Refinement.Swarm.AsyncSwapCalculatePoolFee.calculatePoolFee_success_iff`

### P-07

**`Router.swap`** at `src/Router.sol:113`

`Router.swap` succeeds exactly when ABI decoding and all applicable local guards pass and the specified pool-manager `unlock` call succeeds. Successful decoding requires at least 128 bytes and two valid 160-bit address words. The caller must own the order; decoded user, executor, minimum output, and priority fee must match the owner, router, and order fields. Native input requires `msg.value = order.amountIn`; ERC20 input requires zero value. Local failures follow the modeled guard order, and unlock errors propagate. Before unlock, the Router storage projection changes only the two transient slots: `USER_LOCATION` receives the caller and `ASYNC_FILLER_LOCATION` receives the router address. Unlock receives the ABI-encoded Swap callback with the original order and zero maxMatches. The function discards unlock's return data, returns no value, and retains unlock's resulting state.

**Assumptions.** The boundary-storage guarantee assumes `ext.get (ext.set w t) = t` for every world and Router storage value. Results concern the generated model and its ABI semantics. The pool-manager call is an arbitrary external computation: no storage-preservation, callback-safety, fill, or balance guarantee is assumed or established for it. The footprint covers the Router storage projection immediately before unlock, not unrelated world state or final storage after callbacks.

Theorems:

- `Router.Swarm.RouterSwap.swap_run`
- `Router.Swarm.RouterSwap.swap_success_iff`
- `Router.Swarm.RouterSwap.swap_success_guards`
- `Router.Swarm.RouterSwap.swap_success_exact`
- `Router.Swarm.RouterSwap.swap_success_call_footprint`
- `Router.Swarm.RouterSwap.prepared_storage`
- `Router.Swarm.RouterSwap.prepared_footprint`

Lean (local only): `formal/Proofs/Functions/RouterSwap.lean`

### P-09

**`AsyncSwap.acceptOwnership`** at `src/AsyncSwap.sol:166`

`AsyncSwap.acceptOwnership` reverts with `NotOwner` exactly when the sender differs from `pendingOwner`. Otherwise it returns unit, sets `owner` to the sender, and clears `pendingOwner`. The exact execution theorem describes both storage writes without accessor assumptions. Under the storage-accessor laws, the resulting contract storage equals the original record with only those two fields updated; every other field is preserved. The body invokes no external-call handler.

**Assumptions.** The success and storage-footprint theorems assume ext.get (ext.set w s) = s and ext.set (ext.set w s) t = ext.set w t. Execution and rejection require no accessor laws or external-call assumptions. These properties concern the generated function body; event logs and the ABI-level nonpayable check are not modeled by this def.

Theorems:

- `AsyncSwap.Swarm.AcceptOwnership.execution`
- `AsyncSwap.Swarm.AcceptOwnership.reverts_iff`
- `AsyncSwap.Swarm.AcceptOwnership.success_iff`
- `AsyncSwap.Swarm.AcceptOwnership.storage_footprint`

Lean (local only): `formal/Proofs/Swarm/AsyncSwapAcceptOwnership.lean`

### P-10

**`AsyncSwap.setMinOrder`** at `src/AsyncSwap.sol:248`

In the generated function-body model, `AsyncSwap.setMinOrder` reverts exactly when the caller differs from the current owner, with `NotOwner`. For the owner it returns unit and sets `priceBooks[toId(key)].minOrder` to `minimum`. All other book fields, other pool IDs, and this contract's modeled storage fields outside `priceBooks` remain unchanged. The execution formula uses no external-call handlers.

**Assumptions.** Storage projection results assume ∀ w st, ext.get (ext.set w st) = st; preservation of world state outside this contract's storage projection is not established. Pool IDs use the generated model's pure ext.keccak function; no collision-freedom assumption is needed. Solidity correspondence is for well-formed, zero-value calls reaching the function body with sufficient gas; ABI decoding, nonpayable dispatch checks and gas failures are outside these theorems. Event logs are omitted by the generated model and are not verified.

Theorems:

- `AsyncSwap.setMinOrder_run`
- `AsyncSwap.setMinOrder_error_iff`
- `AsyncSwap.setMinOrder_reverts_of_not_owner`
- `AsyncSwap.setMinOrder_ok_of_owner`
- `AsyncSwap.setMinOrder_ok_iff`
- `AsyncSwap.setMinOrder_frame`
- `AsyncSwap.setMinOrder_storage`

Lean (local only): `formal/Proofs/Swarm/AsyncSwapSetMinOrder.lean`

### P-11

**`AsyncSwap.invalidateNonce`** at `src/AsyncSwap.sol:578`

`AsyncSwap.invalidateNonce` reverts with `NonceAlreadyUsed` exactly when `nonceUsed[msg.sender][nonce]` is true. Otherwise it returns unit and passes to the storage setter the original contract state with only that nonce entry set to true. With a lawful storage getter/setter, every other nonce entry and every other contract storage field remains unchanged. The exact execution equation uses no external-call handlers.

**Assumptions.** The theorems concern the generated function-body model. The frame theorem assumes ext.get (ext.set w s) = s; the execution and revert/success equivalences require no storage laws. Events and ABI-level nonpayable enforcement are not modeled by this definition. No claim is made about unrelated world state under an arbitrary ext.set.

Theorems:

- `AsyncSwap.Swarm.InvalidateNonce.run`
- `AsyncSwap.Swarm.InvalidateNonce.reverts_iff`
- `AsyncSwap.Swarm.InvalidateNonce.success_iff`
- `AsyncSwap.Swarm.InvalidateNonce.frame`

Lean (local only): `formal/Proofs/Swarm/AsyncSwapInvalidateNonce.lean`

### P-12

**`AsyncSwap.transferOwnership`** at `src/AsyncSwap.sol:159`

`AsyncSwap.transferOwnership` reverts with `NotOwner` when the caller is not the current owner. For the current owner, it reverts with `ZeroAddress` exactly when `newOwner = 0`; otherwise it returns unit and updates only `pendingOwner` to the nominated nonzero value, preserving the rest of the storage record.

**Assumptions.** The storage extension satisfies `ext.get (ext.set w s) = s`.

Theorems:

- `AsyncSwap.Swarm.TransferOwnership.execution`
- `AsyncSwap.Swarm.TransferOwnership.reverts_iff`
- `AsyncSwap.Swarm.TransferOwnership.success_iff`
- `AsyncSwap.Swarm.TransferOwnership.storage_footprint`

### P-14

**`Router.fillFromPoolLiquidity`** at `src/Router.sol:240`

`Router.fillFromPoolLiquidity` has no source-level guards. In the generated model, its outcome is determined by `POOLMANAGER.unlock`.

- **Execution (`fillFromPoolLiquidity_run`):** the function calls `unlock` on `POOLMANAGER` from the state `beforeUnlock`, with the payload `fillData order`: `abi.encode` of action `5` (`PoolLiquidityFill`), every field of `order` and `maxMatches = 0`. It discards the bytes `unlock` returns and returns unit.
- **Success (`fillFromPoolLiquidity_success_iff`):** the modelled function succeeds with final state `s'` if and only if that `unlock` call succeeds with final state `s'`.
- **Revert (`fillFromPoolLiquidity_error_iff`):** the modelled function reverts with `r` if and only if that `unlock` call reverts with `r`.
- **Writes before the call (`beforeUnlock_footprint`):** in the state `beforeUnlock`, which the run equation passes to `unlock`, transient `USER_LOCATION` holds `msg.sender` and transient `ASYNC_FILLER_LOCATION` holds `address(this)`. All other transient slots, `_nameFallback` and `_versionFallback` are unchanged.

**Assumptions.** `POOLMANAGER.unlock`, including any callback it makes into the Router, is an uninterpreted external call (`ext.call_IPoolManager_unlock`), so the final state `s'` and any revert are characterised only in terms of that call. The generated def starts after dispatch and does not model the compiler-generated reverts for nonzero `msg.value` (`nonpayable`) or invalid `AsyncOrder` calldata, so the success and revert equivalences assume a call that passes those checks. `beforeUnlock_footprint` assumes the state lens law `ext.get (ext.set w st) = st`. The `abiEncode` model is taken as generated and is not checked here against byte-level ABI encoding.

Theorems:

- `Router.Swarm.RouterFillFromPoolLiquidity.Router.fillFromPoolLiquidity_run`
- `Router.Swarm.RouterFillFromPoolLiquidity.Router.fillFromPoolLiquidity_success_iff`
- `Router.Swarm.RouterFillFromPoolLiquidity.Router.fillFromPoolLiquidity_error_iff`
- `Router.Swarm.RouterFillFromPoolLiquidity.beforeUnlock_footprint`

### P-15

**`BaseHook.beforeInitialize`** at `src/BaseHook.sol:35`

> ⚠️ **Out of date.** Pool creation is open since #61 (`81ba6b8`): `beforeInitialize` no longer checks `sender` is the owner.

`BaseHook.beforeInitialize` reverts in order unless the caller is the pool manager, `sender` is the owner, the pool key contains the numeraire, and the fee equals `LPFeeLibrary.DYNAMIC_FEE_FLAG`. On success it returns selector `0xdc98354e` and updates only the selected pool's `asyncOrders.poolManager`, `asyncOrders.numeraire`, `asyncOrders.feeVault`, and `priceBooks.minOrder` fields, with `minOrder` set to `defaultMinOrder`; it performs no external calls.

**Assumptions.** The generated `Ext` interface supplies the immutable values, state accessors, pool-id `keccak` computation, and state update operations represented by the generated model. The theorem establishes the generated model's behavior; no external-call behavior is needed because this slice contains no external calls.

Theorems:

- `Proofs.Functions.AsyncSwapBeforeInitialize.BaseHook_beforeInitialize_execution`

Lean (local only): `formal/Proofs/Functions/AsyncSwapBeforeInitialize.lean`

### P-17

**`NativeClaims.redeem`** at `src/NativeClaims.sol:30`

`NativeClaims.redeem` reverts with `ReentrantRedemption` when `_redeeming` is true. Otherwise, it reverts with `InvalidRedemption` when `recipient` or `amount` is zero. For nonzero inputs, it sets `_redeeming` to true, calls `poolManager.unlock(abi.encode(msg.sender, recipient, amount))`, propagates that call's revert, and on a successful return clears `_redeeming` and returns `()`; the local execution performs no other storage writes.

**Assumptions.** The external `IPoolManager.unlock` call is modeled by `Ext.call_IPoolManager_unlock`; its returned bytes and world state are otherwise unconstrained, including any storage changes it may make before returning.

Theorems:

- `Proofs.Functions.NativeClaimsRedeem.redeem_run`
- `Proofs.Functions.NativeClaimsRedeem.redeem_reverts_reentrant`
- `Proofs.Functions.NativeClaimsRedeem.redeem_reverts_invalid`
- `Proofs.Functions.NativeClaimsRedeem.redeem_success`

Lean (local only): `formal/Proofs/Functions/NativeClaimsRedeem.lean`

### P-18

**`TokenClaims.redeem`** at `src/TokenClaims.sol:30`

`TokenClaims.redeem` reverts with `ReentrantRedemption` when `_redeeming` is true and with `InvalidRedemption` when the recipient or amount is zero. When both guards pass, it sets `_redeeming` to true, calls `poolManager.unlock` with `abi.encode(msg.sender, currency, recipient, amount)`, propagates the external call's result, and clears `_redeeming` after a successful call.

**Assumptions.** The external `IPoolManager.unlock` behavior is represented by the generated `Ext.call_IPoolManager_unlock`; its returned world may change storage during the call.

Theorems:

- `TokenClaims.Swarm.Redeem.redeem_reentrant`
- `TokenClaims.Swarm.Redeem.redeem_invalid`
- `TokenClaims.Swarm.Redeem.redeem_call`
- `TokenClaims.Swarm.Redeem.redeem_guard_reverts`

### P-19

**`AsyncSwap.setExecutorWithSig`** at `src/AsyncSwap.sol:531`

> ⚠️ **Out of date.** `setExecutorWithSig` now also reverts `CannotRevokeTrustedRouter` (after the signature checks) when the grant revokes the trusted Router.

`AsyncSwap.setExecutorWithSig` checks its guards in source order: deadline, then nonce, then signature.

- **`setExecutorWithSig_reverts_expired`**: if `block.timestamp > deadline`, the call reverts `SignatureExpired`, whatever the nonce and signature.
- **`setExecutorWithSig_reverts_used_nonce`**: within the deadline, if `nonceUsed[maker][nonce]` is set, the call reverts `NonceAlreadyUsed`, whatever the signature.
- **`setExecutorWithSig_reverts_invalid_signature`**: within the deadline and with a fresh nonce, if `sigValid` is false, the call reverts `InvalidSignature`. `sigValid` is the closed form of `isValidSignatureNow`: ECDSA recovery of `maker` with no error, or an ERC-1271 static call to `maker` that succeeds and returns at least 32 bytes whose first word is the magic value. The check is over the EIP-712 digest of the struct hash of `key`, `maker`, `executor`, `allow`, `nonce` and `deadline`, and the static call observes the world with the nonce already spent.
- **`setExecutorWithSig_success`**: when all three guards pass, the call succeeds, and its post-world is the nonce write followed by the `isExecutor` write on the pool id of `key`.
- **`setExecutorWithSig_ok_iff`**: the call succeeds if and only if all three guards pass, so the model has no other revert path.
- **`setExecutorWithSig_footprint`**: on success, the new storage equals the old storage with `nonceUsed[maker][nonce] = true` and `asyncOrders[toId(key)].isExecutor[maker][executor] = allow`; every other storage field and entry is unchanged.
- **`setExecutorWithSig_no_replay`**: from the post-state of a successful call, a further `setExecutorWithSig` call with the same `(maker, nonce)` does not succeed, in any environment and with any other arguments. The theorem covers a call made directly from that post-state; it does not cover states reached through intervening transactions or other functions that use `nonceUsed`.

**Assumptions.** `setExecutorWithSig_footprint` and `setExecutorWithSig_no_replay` assume the storage lens law `ext.get (ext.set w s) = s`. `keccak`, `keccakBytes`, `ecrecover` and `staticCall` are uninterpreted functions, so these results establish which values are hashed and checked, and do not establish signature unforgeability or hash collision resistance. The static call is modelled as unable to write state, matching EVM STATICCALL. The EIP-712 immutables (`_cachedThis`, `_cachedChainId`, `_cachedDomainSeparator`, `_hashedName`, `_hashedVersion`) are opaque parameters, and hash preimages and calldata are taken as the generated model encodes them. Arguments are unbounded `Nat` values with no ABI range constraints. Events and gas are not modelled.

Theorems:

- `AsyncSwap.Swarm.SetExecutorWithSig.setExecutorWithSig_reverts_expired`
- `AsyncSwap.Swarm.SetExecutorWithSig.setExecutorWithSig_reverts_used_nonce`
- `AsyncSwap.Swarm.SetExecutorWithSig.setExecutorWithSig_reverts_invalid_signature`
- `AsyncSwap.Swarm.SetExecutorWithSig.setExecutorWithSig_success`
- `AsyncSwap.Swarm.SetExecutorWithSig.setExecutorWithSig_ok_iff`
- `AsyncSwap.Swarm.SetExecutorWithSig.setExecutorWithSig_footprint`
- `AsyncSwap.Swarm.SetExecutorWithSig.setExecutorWithSig_no_replay`

Lean (local only): `formal/Proofs/Functions/AsyncSwapSetExecutorWithSig.lean`

### P-22

**`FeeVault.collect`** at `src/FeeVault.sol:27`

`FeeVault.collect` propagates failure from `hook.owner()`, reverts with `Unauthorized` when `msg.sender` differs from the returned owner, and reverts with `ZeroAddress` when `recipient` is zero. When both guards pass, it calls `poolManager.unlock(abiEncode [currency, recipient])`, propagates that call's failure, returns `()`, and performs no local storage update; the resulting state is the state returned by `unlock`.

**Assumptions.** The generated external callbacks define the `hook.owner()` view and `poolManager.unlock` behavior. The theorem does not assume that either callback succeeds; any state change from `unlock` is represented by its returned state.

Theorems:

- `Proofs.Functions.FeeVaultCollect.collect_run`

Lean (local only): `formal/Proofs/Functions/FeeVaultCollect.lean`

### P-23

**`FeeVault.unlockCallback`** at `src/FeeVault.sol:34`

`FeeVault.unlockCallback` reverts with `Unauthorized` unless the caller is the PoolManager. For an authorized call with calldata containing two ABI words whose decoded values fit in 160 bits, balance lookup errors propagate; a zero balance returns empty bytes without changing the world state; a nonzero balance calls `burn(address(this), id, amount)` and then `take(currency, recipient, amount)`, propagating either error and otherwise returning empty bytes with the final external-call state.

**Assumptions.** The generated model treats the PoolManager burn/take calls and the balanceOf view as opaque external semantics; the success theorem assumes the calldata has at least 64 list elements and both ABI words decode to values below 2^160.

Theorems:

- `Proofs.Functions.FeeVaultUnlockCallback.unlockCallback_guard_reverts`
- `Proofs.Functions.FeeVaultUnlockCallback.unlockCallback_success`

Lean (local only): `formal/Proofs/Functions/FeeVaultUnlockCallback.lean`

### P-24

**`Router.swapWithSig`** at `src/Router.sol:180`

`Router.swapWithSig` reverts with `Native input needs swap()` whenever the selected input currency (`currency0` when `order.zeroForOne` is true, otherwise `currency1`) is zero; this path performs no later external calls or transient writes.

**Assumptions.** `CurrencyLibrary.isAddressZero` returns true exactly when the currency equals `CurrencyLibrary.ADDRESS_ZERO` (zero).

Theorems:

- `Router.Swarm.RouterSwapWithSig.swapWithSig_guard_reverts`

Lean (local only): `formal/Proofs/Functions/RouterSwapWithSig.lean`

### P-25

**`AsyncSwap.sweep`** at `src/AsyncSwap.sol:178`

`AsyncSwap.sweep` reverts with `NotOwner` when the caller is not the stored owner, and an owner call with a zero recipient reverts with `ZeroAddress`. For an owner call with a nonzero recipient, it invokes the modeled balance and transfer calls; if those calls return the stated successful results, the function returns unit with the transfer call’s post-world. The function body performs no contract-local storage write.

**Assumptions.** The generated `Ext` model abstracts the external balance and transfer calls, including their successful or reverting results and post-worlds; the proof treats those modeled results as given.

Theorems:

- `AsyncSwap.Swarm.Sweep.execution`
- `AsyncSwap.Swarm.Sweep.reverts_not_owner`
- `AsyncSwap.Swarm.Sweep.reverts_zero_address`
- `AsyncSwap.Swarm.Sweep.success`

Lean (local only): `formal/Proofs/Functions/AsyncSwapSweep.lean`

### P-27

**`AsyncSwap.cancelOrder`** at `src/AsyncSwap.sol:426`

`AsyncSwap.cancelOrder` propagates `NotAuthorizedExecutor` when the delegated executor condition is unauthorized and propagates `OrderNotFound` when the delegated order has zero `amountIn`, assuming successful generated `orderId` and pool-ID computations. When those computations succeed and the supplied `AsyncMatching.cancel` execution returns successfully with post-state `w'`, `AsyncSwap.cancelOrder` returns `Unit` with the same post-state. The success theorem covers wrapper delegation and propagation; the delegate's internal guards, external calls, and storage effects remain assumptions.

**Assumptions.** The reversion theorems assume successful `AsyncOrderLibrary.orderId` and both generated `PoolIdLibrary.toId` computations, plus the corresponding delegate guard conditions. The success theorem assumes successful ID computations and a successful `AsyncMatching.cancel` result for the generated async-order and price-book getters/setters; it does not prove the delegate's guards, external calls, storage footprint, or downstream `PriceLevelMissing` behavior.

Theorems:

- `AsyncSwap.Proofs.Functions.AsyncSwapCancelOrder.cancelOrder_reverts_unauthorized`
- `AsyncSwap.Proofs.Functions.AsyncSwapCancelOrder.cancelOrder_reverts_missing`
- `AsyncSwap.Proofs.Functions.AsyncSwapCancelOrder.cancelOrder_execution`

Lean (local only): `formal/Proofs/Functions/AsyncSwapCancelOrder.lean`

### P-28

**`AsyncSwap.executeOrder`** at `src/AsyncSwap.sol:315`

`AsyncSwap.executeOrder` reverts with `UnaccountedNativeOutput` when the generated execution reaches the native-output branch, `asyncOrderInfo` returns minimum output 1, `calculatePoolFee` returns 0 for that minimum output, and the pending native-deposit amount is less than 1. The theorem establishes this early revert before `AsyncMatching.fill` is called.

**Assumptions.** The generated ABI-word and ABI-uint decoding, order-id calculation, native-currency test, pool-id calculation, `asyncOrderInfo` view, and pool-fee calculation return the values specified by the theorem hypotheses; these modeled helper calls preserve the relevant state. The transient pending-deposit slot contains the stated amount.

Theorems:

- `AsyncSwap.Proofs.Functions.AsyncSwapExecuteOrder.executeOrder_native_output_reverts`

Lean (local only): `formal/Proofs/Functions/AsyncSwapExecuteOrder.lean`

### P-32

**`BaseHook.beforeSwap`** at `src/BaseHook.sol:143`

`BaseHook.beforeSwap` reverts with `NotPoolManager` when `env.sender ≠ ext.poolManager`. When `env.sender = ext.poolManager`, it returns exactly the successful result and post-state produced by `AsyncSwap._beforeSwap`, including any effects represented by that delegated result and post-state.

**Assumptions.** The success theorem assumes that `AsyncSwap._beforeSwap` evaluates successfully to the specified result and post-state. That assumption includes its downstream guards, external-call outcomes, arithmetic, and writes to `asyncOrders` and `priceBooks`.

Theorems:

- `Proofs.Functions.AsyncSwapBeforeSwap.BaseHook_beforeSwap_onlyPoolManager`
- `Proofs.Functions.AsyncSwapBeforeSwap.BaseHook_beforeSwap_execution`

Lean (local only): `formal/Proofs/Functions/AsyncSwapBeforeSwap.lean`

### P-33

**`Router.unlockCallback`** at `src/Router.sol:253`

`Router.unlockCallback` reverts with `"Caller is not PoolManager"` whenever the call sender differs from the configured `PoolManager`.

**Assumptions.** The theorem covers the access-control guard only. The generated model leaves external calls abstract; their revert behavior and successor storage are not constrained by this theorem.

Theorems:

- `Proofs.Functions.RouterUnlockCallback.Router_unlockCallback_onlyPoolManager`

Lean (local only): `formal/Proofs/Functions/RouterUnlockCallback.lean`

### P-34

**`AsyncSwap.matchBook`** at `src/AsyncSwap.sol:402`

`AsyncSwap.matchBook` returns zero without invoking `AsyncMatching.matchBook` when the pending match ID is nonzero and the corresponding order has nonzero input. Otherwise, assuming all three pool-ID computations succeed with the same pool ID and `AsyncMatching.matchBook` succeeds with post-state `w'` and result `n`, it returns `n` with post-state `w'`.

**Assumptions.** The early-return property assumes the transient pending-match slot and corresponding order lookup values. The execution property assumes three successful pool-ID computations and a successful `AsyncMatching.matchBook` trace; that delegate assumption covers its guards, arithmetic, external transfers, and asyncOrders/priceBooks storage effects.

Theorems:

- `AsyncSwap.matchBook_early_return`
- `AsyncSwap.matchBook_execution`

Lean (local only): `formal/Proofs/Functions/AsyncSwapMatchBook.lean`

### P-36

**`AsyncSwap.getHookPermissions`** at `src/AsyncSwap.sol:197`

`AsyncSwap.getHookPermissions` succeeds for every extension, environment, and storage state; returns the declared `Hooks.Permissions` record with `beforeInitialize`, `beforeAddLiquidity`, `beforeSwap`, and `beforeSwapReturnDelta` enabled and every other permission disabled; and leaves storage unchanged.

Theorems:

- `Proofs.Functions.AsyncSwapGetHookPermissions.getHookPermissions_run`

Lean (local only): `formal/Proofs/Functions/AsyncSwapGetHookPermissions.lean`

### P-37

**`AsyncSwap.asyncOrder`** at `src/AsyncSwap.sol:228`

`AsyncSwap.asyncOrder` never reverts; on every call it returns `asyncOrders[poolId].orders[orderId].amountIn` and preserves the complete modeled contract state. The generated function has no storage writes or external calls.

**Assumptions.** None beyond the generated model and the universally quantified `Ext`, pool ID, order ID, environment, and state parameters; the proof does not assume any additional contract behavior.

Theorems:

- `AsyncSwap.Swarm.AsyncOrder.asyncOrder_storage`
- `AsyncSwap.Swarm.AsyncOrder.asyncOrder_no_revert`
- `AsyncSwap.Swarm.AsyncOrder.asyncOrder_success`

Lean (local only): `formal/Proofs/Functions/AsyncSwapAsyncOrder.lean`

### P-38

**`AsyncSwap.asyncOrderPriorityFee`** at `src/AsyncSwap.sol:243`

`AsyncSwap.asyncOrderPriorityFee` always succeeds, returns the selected order's `priorityFee`, and leaves storage unchanged. Its result depends only on `asyncOrders`.

**Assumptions.** None beyond the generated `Ext` interface and the equality of `asyncOrders` in the read-footprint theorem.

Theorems:

- `AsyncSwap.Swarm.AsyncOrderPriorityFee.asyncOrderPriorityFee_storage`
- `AsyncSwap.Swarm.AsyncOrderPriorityFee.asyncOrderPriorityFee_no_revert`
- `AsyncSwap.Swarm.AsyncOrderPriorityFee.asyncOrderPriorityFee_ok_iff`
- `AsyncSwap.Swarm.AsyncOrderPriorityFee.asyncOrderPriorityFee_reads_only_asyncOrders`

Lean (local only): `formal/Proofs/Functions/AsyncSwapAsyncOrderPriorityFee.lean`

### P-39

**`AsyncSwap.bestOrder`** at `src/AsyncSwap.sol:261`

`AsyncSwap.bestOrder` propagates the successful result tuple returned by its delegated `AsyncMatching.bestOrder` call. If that delegated call returns the tuple without changing state, `AsyncSwap.bestOrder` also returns it without changing state.

**Assumptions.** The delegated `AsyncMatching.bestOrder` call preserves state whenever it succeeds with the specified result tuple. Revert behavior and the matcher’s internal selection logic are outside these theorems.

Theorems:

- `AsyncSwap.Swarm.BestOrder.bestOrder_success`
- `AsyncSwap.Swarm.BestOrder.bestOrder_success_preserves_state`

Lean (local only): `formal/Proofs/Functions/AsyncSwapBestOrder.lean`

### P-40

**`AsyncSwap.orderBookLevel`** at `src/AsyncSwap.sol:270`

`AsyncSwap.orderBookLevel` has no guards of its own: it reverts exactly when its delegated `AsyncFiller.level` computation reverts. On successful execution, it returns the delegated `(head, tail, count)` result and leaves the storage state unchanged.

**Assumptions.** For successful execution, the delegated `AsyncFiller.level` computation is assumed to leave storage unchanged, as stated by the `hdelegate` premise; no additional assumption is used for revert equivalence.

Theorems:

- `AsyncSwap.Swarm.OrderBookLevel.orderBookLevel_reverts_iff`
- `AsyncSwap.Swarm.OrderBookLevel.orderBookLevel_success`

Lean (local only): `formal/Proofs/Functions/AsyncSwapOrderBookLevel.lean`

### P-41

**`AsyncSwap.orderBookOrder`** at `src/AsyncSwap.sol:279`

`AsyncSwap.orderBookOrder` never reverts; it returns the owner, input amount, minimum output, price, buy flag, sequence, and priority fee stored in `asyncOrders[poolId].orders[orderId]`, and leaves storage unchanged.

**Assumptions.** None.

Theorems:

- `AsyncSwap.Swarm.OrderBookOrder.orderBookOrder_storage`
- `AsyncSwap.Swarm.OrderBookOrder.orderBookOrder_no_revert`
- `AsyncSwap.Swarm.OrderBookOrder.orderBookOrder_ok_iff`

Lean (local only): `formal/Proofs/Functions/AsyncSwapOrderBookOrder.lean`

### P-42

**`AsyncSwap.calculateHookFee`** at `src/AsyncSwap.sol:300`

`AsyncSwap.calculateHookFee` never reverts; on every call it returns fee `0` and preserves storage, so it has no storage writes or external-call effects.

**Assumptions.** None; the proof quantifies over arbitrary extension, argument, environment, and storage state.

Theorems:

- `AsyncSwap.Swarm.CalculateHookFee.calculateHookFee_spec`
- `AsyncSwap.Swarm.CalculateHookFee.calculateHookFee_no_revert`
- `AsyncSwap.Swarm.CalculateHookFee.calculateHookFee_ok_iff`

Lean (local only): `formal/Proofs/Functions/AsyncSwapCalculateHookFee.lean`

### P-43

**`AsyncSwap.DOMAIN_SEPARATOR`** at `src/AsyncSwap.sol:586`

`AsyncSwap.DOMAIN_SEPARATOR` does not revert. It returns the cached EIP-712 domain separator when `address(this)` and `chainid` equal their cached values; otherwise it returns `keccak(TYPE_HASH, hashedName, hashedVersion, chainid, address(this))`. Both branches preserve the complete world state and perform no storage writes.

**Assumptions.** The proof uses the generated model, in which the EIP-712 immutable values and `Ext.keccak` provide the modeled immutable and hashing behavior; no additional contract-state assumptions are required.

Theorems:

- `AsyncSwap.Proofs.Functions.AsyncSwapDOMAIN_SEPARATOR.domainSeparator_run`
- `AsyncSwap.Proofs.Functions.AsyncSwapDOMAIN_SEPARATOR.domainSeparator_success`

Lean (local only): `formal/Proofs/Functions/AsyncSwapDOMAIN_SEPARATOR.lean`

### P-45

**`Router.DOMAIN_SEPARATOR`** at `src/Router.sol:215`

`Router.DOMAIN_SEPARATOR` succeeds without a reverting guard and returns the cached EIP-712 domain separator when `address(this)` and `chainid` match the cached values; otherwise it returns the freshly built separator. Every successful call leaves the complete world state unchanged.

**Assumptions.** The generated `EIP712._domainSeparatorV4` and `_buildDomainSeparator` model is used as specified; no additional contract-state assumptions are required.

Theorems:

- `Router.Proofs.Functions.RouterDOMAIN_SEPARATOR.domainSeparator_run`
- `Router.Proofs.Functions.RouterDOMAIN_SEPARATOR.domainSeparator_success`

Lean (local only): `formal/Proofs/Functions/RouterDOMAIN_SEPARATOR.lean`

### P-46

**`BaseHook.afterInitialize`** at `src/BaseHook.sol:48`

`BaseHook.afterInitialize` reverts with `NotPoolManager` when the caller is not the configured pool manager; for the configured pool manager, it reverts with `HookNotImplemented` via the default `_afterInitialize` implementation. The modeled function therefore has no successful return and performs no storage writes.

**Assumptions.** The generated model uses the default `BaseHook._afterInitialize` implementation, which always reverts with `HookNotImplemented`.

Theorems:

- `Proofs.Functions.AsyncSwapAfterInitialize.BaseHook_afterInitialize_execution`

Lean (local only): `formal/Proofs/Functions/AsyncSwapAfterInitialize.lean`

### P-47

**`BaseHook.beforeAddLiquidity`** at `src/BaseHook.sol:61`

`BaseHook.beforeAddLiquidity` reverts with `NotPoolManager` unless the caller is the pool manager. When the guard holds, it returns selector `0x259982e5` and leaves storage unchanged.

Theorems:

- `Proofs.Functions.AsyncSwapBeforeAddLiquidity.BaseHook_beforeAddLiquidity_onlyPoolManager`
- `Proofs.Functions.AsyncSwapBeforeAddLiquidity.BaseHook_beforeAddLiquidity_execution`

Lean (local only): `formal/Proofs/Functions/AsyncSwapBeforeAddLiquidity.lean`

### P-48

**`BaseHook.beforeRemoveLiquidity`** at `src/BaseHook.sol:79`

`BaseHook.beforeRemoveLiquidity` reverts with `NotPoolManager` when the caller is not the configured pool manager; for the configured pool manager, the generated base implementation reverts with `HookNotImplemented`. It has no successful execution, storage write, or return value.

**Assumptions.** The generated model's `BaseHook._beforeRemoveLiquidity` is the modeled base implementation and unconditionally reverts with `HookNotImplemented`.

Theorems:

- `Proofs.Functions.AsyncSwapBeforeRemoveLiquidity.BaseHook_beforeRemoveLiquidity_execution`

Lean (local only): `formal/Proofs/Functions/AsyncSwapBeforeRemoveLiquidity.lean`

### P-49

**`BaseHook.afterAddLiquidity`** at `src/BaseHook.sol:97`

`BaseHook.afterAddLiquidity` reverts with `NotPoolManager` when `env.sender ≠ ext.poolManager`; otherwise it reverts with `HookNotImplemented` from the generated default `_afterAddLiquidity` implementation. Neither path changes storage, and no successful return value is produced.

**Assumptions.** None beyond the generated `AsyncSwap` model and its definitions.

Theorems:

- `Proofs.Functions.AsyncSwapAfterAddLiquidity.BaseHook_afterAddLiquidity_onlyPoolManager`
- `Proofs.Functions.AsyncSwapAfterAddLiquidity.BaseHook_afterAddLiquidity_execution`

Lean (local only): `formal/Proofs/Functions/AsyncSwapAfterAddLiquidity.lean`

### P-50

**`BaseHook.afterRemoveLiquidity`** at `src/BaseHook.sol:120`

`BaseHook.afterRemoveLiquidity` reverts with `NotPoolManager` when the caller is not `ext.poolManager`; when the caller is `ext.poolManager`, it reverts with `HookNotImplemented`. It performs no storage writes and has no successful return.

**Assumptions.** None; the proof evaluates the generated model for arbitrary environment and storage state.

Theorems:

- `Proofs.Functions.AsyncSwapAfterRemoveLiquidity.BaseHook_afterRemoveLiquidity_execution`

Lean (local only): `formal/Proofs/Functions/AsyncSwapAfterRemoveLiquidity.lean`

### P-51

**`BaseHook.afterSwap`** at `src/BaseHook.sol:160`

`BaseHook.afterSwap` reverts with `NotPoolManager` when `env.sender ≠ ext.poolManager`; when the caller is authorized, it reverts with `HookNotImplemented` from the default hook body. Consequently, the modeled function has no successful return path and performs no storage writes or external calls.

**Assumptions.** The generated model uses the default `BaseHook._afterSwap` implementation, which unconditionally reverts with `HookNotImplemented`.

Theorems:

- `Proofs.Functions.AsyncSwapAfterSwap.BaseHook_afterSwap_onlyPoolManager`
- `Proofs.Functions.AsyncSwapAfterSwap.BaseHook_afterSwap_execution`

Lean (local only): `formal/Proofs/Functions/AsyncSwapAfterSwap.lean`

### P-52

**`BaseHook.beforeDonate`** at `src/BaseHook.sol:179`

`BaseHook.beforeDonate` reverts with `NotPoolManager` when `env.sender ≠ ext.poolManager`; when `env.sender = ext.poolManager`, it reverts with `HookNotImplemented` via the generated `_beforeDonate` implementation. Consequently, every modeled call reverts and the function has no successful return or storage-write path.

**Assumptions.** The generated `Ext` environment and state semantics are used, and the generated base `_beforeDonate` definition unconditionally throws `HookNotImplemented`.

Theorems:

- `Proofs.Functions.AsyncSwapBeforeDonate.BaseHook_beforeDonate_onlyPoolManager`
- `Proofs.Functions.AsyncSwapBeforeDonate.BaseHook_beforeDonate_execution`

Lean (local only): `formal/Proofs/Functions/AsyncSwapBeforeDonate.lean`

### P-53

**`BaseHook.afterDonate`** at `src/BaseHook.sol:198`

`BaseHook.afterDonate` reverts with `NotPoolManager` when `env.sender` differs from `ext.poolManager`. When the caller is the configured pool manager, it reaches the generated default `_afterDonate`, which reverts with `HookNotImplemented`; consequently, no invocation returns a value, performs an external call, or writes storage.

**Assumptions.** The generated `Ext` environment and the generated default `BaseHook._afterDonate` implementation are used as specified; no additional assumptions are required.

Theorems:

- `Proofs.Functions.AsyncSwapAfterDonate.BaseHook_afterDonate_onlyPoolManager`
- `Proofs.Functions.AsyncSwapAfterDonate.BaseHook_afterDonate_execution`

Lean (local only): `formal/Proofs/Functions/AsyncSwapAfterDonate.lean`

### P-54

**`AsyncSwap.onlyOwner`** at —

`AsyncSwap.onlyOwner` reverts with `NotOwner` when `msg.sender` differs from the stored owner. When the caller is the stored owner, it runs the wrapped continuation unchanged and preserves its return value and resulting storage state; the modifier itself performs no storage writes or additional external calls.

**Assumptions.** The wrapped continuation `k` is taken from its generated monadic semantics; no additional assumptions are used.

Theorems:

- `AsyncSwap.onlyOwner_run`
- `AsyncSwap.onlyOwner_reverts_of_not_owner`
- `AsyncSwap.onlyOwner_ok_of_owner`

Lean (local only): `formal/Proofs/Functions/AsyncSwapOnlyOwner.lean`

### P-55

**`CurrencyLibrary.isAddressZero`** at —

`CurrencyLibrary.isAddressZero` always succeeds and returns whether `currency == CurrencyLibrary.ADDRESS_ZERO`; it preserves the complete storage state and performs no writes.

**Assumptions.** None beyond the generated `Ext` interface and the standard Reader/State/Except semantics.

Theorems:

- `AsyncSwap.Proofs.Functions.AsyncSwapIsAddressZero.isAddressZero_spec`
- `AsyncSwap.Proofs.Functions.AsyncSwapIsAddressZero.isAddressZero_no_revert`
- `AsyncSwap.Proofs.Functions.AsyncSwapIsAddressZero.isAddressZero_success`

Lean (local only): `formal/Proofs/Functions/AsyncSwapIsAddressZero.lean`

### P-56

**`CurrencyLibrary.balanceOfSelf`** at —

`CurrencyLibrary.balanceOfSelf` returns `Env.balance` when `currency == CurrencyLibrary.ADDRESS_ZERO`; otherwise it returns the ERC-20 `balanceOf` result for `currency` and `Env.self`, propagating a view error unchanged. Every successful execution preserves storage.

**Assumptions.** The generated `Ext.view_IERC20Minimal_balanceOf` supplies the external ERC-20 view result as `Except Revert Nat`; the generated `view` helper is read-only and propagates errors without changing storage.

Theorems:

- `AsyncSwap.Proofs.Functions.AsyncSwapBalanceOfSelf.balanceOfSelf_run`
- `AsyncSwap.Proofs.Functions.AsyncSwapBalanceOfSelf.balanceOfSelf_success`
- `AsyncSwap.Proofs.Functions.AsyncSwapBalanceOfSelf.balanceOfSelf_reverts_view`

Lean (local only): `formal/Proofs/Functions/AsyncSwapBalanceOfSelf.lean`

### P-57

**`CustomRevert.bubbleUpAndRevertWith`** at —

`CustomRevert.bubbleUpAndRevertWith` always returns an error `⟨"revert"⟩` under the generated FormalAst semantics; consequently, it has no successful return value or storage write.

**Assumptions.** The generated FormalAst model is the contract semantics; all parameters, environment values, and initial storage are arbitrary.

Theorems:

- `Proofs.Functions.AsyncSwapBubbleUpAndRevertWith.bubbleUpAndRevertWith_spec`
- `Proofs.Functions.AsyncSwapBubbleUpAndRevertWith.bubbleUpAndRevertWith_no_success`

Lean (local only): `formal/Proofs/Functions/AsyncSwapBubbleUpAndRevertWith.lean`

### P-60

**`PoolIdLibrary.toId`** at —

`PoolIdLibrary.toId` always succeeds, writes no storage, and returns `ext.keccak [currency0, currency1, fee, toUnsigned 256 tickSpacing, hooks]`.

**Assumptions.** None.

Theorems:

- `Proofs.Functions.AsyncSwapToId.PoolIdLibrary.toId_run`

Lean (local only): `formal/Proofs/Functions/AsyncSwapToId.lean`

### P-61

**`RadixPriceTree.best`** at —

`RadixPriceTree.best` preserves storage on every successful call when its tree getter returns a fixed tree without changing state. If a successful call returns `(false, 0)`, the fixed tree has root zero. If it returns `(true, p)`, the fixed tree has a nonzero root and some leaf has price `p`.

**Assumptions.** The tree getter returns the fixed tree `t` and leaves the abstract state unchanged for every environment and state. The theorem concerns successful executions; executions that exceed the generated loop bound revert.

Theorems:

- `AsyncSwap.Swarm.Best.best_result`
- `AsyncSwap.Swarm.Level.radix_best_result`

Lean (local only): `formal/Proofs/Functions/AsyncSwapBest.lean`

### P-62

**`AsyncFiller.bestOrder`** at —

`AsyncFiller.bestOrder` selects the bids tree when `isBuy` is true and the asks tree otherwise. If the selected tree reports no order, it returns `(found, price, 0, 0)`. If an order is found, it delegates order selection to `AsyncFiller.bestAtPrice`, reads the selected order owner from `self_get`, and returns `(found, price, orderId, owner)`; any revert or storage write arises only from the delegated tree, price-selection call, or supplied getter/setter computations.

**Assumptions.** The generated definitions of `RadixPriceTree.best`, `AsyncFiller.bestAtPrice`, and the supplied getter/setter computations determine their own reverts, reads, and writes; this theorem does not assume those delegated computations are effect-free.

Theorems:

- `AsyncSwap.Proofs.Functions.AsyncSwapBestOrder.bestOrder_spec`

Lean (local only): `formal/Proofs/Functions/AsyncSwapBestOrder.lean`
