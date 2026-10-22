# test/formal/: Formal Mind's Lean theorems, checked on the bytecode

The Lean proofs in [`formal/`](../../formal/README.md) are about the model that formal-ast generates
from solc's AST (`formal/Generated/`), not about the compiled contracts. Each test here takes one
theorem from `formal/Refinement/` whose statement is about a single call's outcome, and states the same
property on the real compiled contracts: the call reverts with the named error, returns the given value,
or writes only the storage the theorem names. A failing test is a counterexample, which means either
the translation is wrong or the code breaks the property. Don't weaken a test to make it pass.

```sh
forge test --match-path 'test/formal/*'
```

**Status:** `formal/Refinement` has 393 theorems, none with `sorry`. 285 have a test and 108 are left
out (reasons below). All 301 tests pass, at 256 fuzz runs and again at 2,000.

The spec libraries (`formal/AsyncSwapSpec`, `formal/AsyncSwapProtocol`) are not mapped here. Their
theorems are about the abstract `World` / `step` models, not a generated def, and reach the code only
through `Refinement/`.

## How a theorem becomes a test

- `.error ⟨"E"⟩` means `vm.expectRevert(E.selector)`. The model's `"abi.decode"` error and the
  library errors it writes as `""` are checked against the bytecode's real revert data: empty data,
  `AsyncFiller.NotAuthorizedExecutor()` and `AsyncFiller.OrderNotFound()`.
- `.ok (v, w')` means a return-value check plus the state after the call (getters, `vm.load`).
- `ext.get w' = ext.get w` and `_frame` / `_readOnly` mean that `vm.record()` / `vm.accesses` shows no
  SSTORE to the contract, or only the slots the theorem names. Those slots are also compared with
  `vm.load`.
- `_iff` theorems are tested in both directions with fuzzed inputs. `never_reverts` / `never_ok` are
  tested by fuzzing and asserting success or a revert.
- Theorems over an arbitrary state `w` are fuzzed over the inputs and run on several states: the
  fixture, real order books built through the Router (FIFO and PriorityFee modes, both sides), and
  storage written with `vm.store`.
- Calls to other contracts that the model leaves opaque (`ext.call_*`):
  - When the theorem is conditional on what such a call does, it is tested against the real contract
    where that contract meets the condition.
  - Otherwise the call is mocked with fuzzed results (`vm.mockCall` / `vm.mockCallRevert`), and
    `vm.expectCall` checks the exact calldata that is handed on.
- Transient state:
  - Hook functions that only run inside `PoolManager.unlock` are driven from a real unlock
    ([`HookUnlockBase.sol`](HookUnlockBase.sol)).
  - The pending-match hand-off and the native-deposit ledger come from real `_beforeSwap` / `receive`
    calls in the same transaction.
  - The Router's transient slots are read back through `unlockCallback`
    ([`FormalProbesA.sol`](FormalProbesA.sol)).
  - Reading or writing the hook's transient storage directly swaps in a small `tload`/`tstore` probe
    with `vm.etch` and puts the original code back afterwards ([`FormalSlotsB.sol`](FormalSlotsB.sol)).

Shared fixtures:
- [`FormalBase.sol`](FormalBase.sol): `SetupHook` plus two funded makers, `_placeOrder`, and AsyncSwap's
  storage slots.
- [`FormalProbesA.sol`](FormalProbesA.sol): Router mocks and probes for its transient slots.
- [`FormalSlotsB.sol`](FormalSlotsB.sol): order-book slot math, write-set checks and book builders.
- [`HookUnlockBase.sol`](HookUnlockBase.sol): the unlock driver.

## Where the model and the bytecode differ

No theorem fails on the bytecode. A few statements are looser than the EVM, though none of these
differences is reachable through a well-formed call:

- **Library errors lose their names.** In the TryFill, MatchNewOrder, RecordPriorityFee,
  FillOrderFromPoolLiquidity and BeforeSwap models, `AsyncFiller.NotAuthorizedExecutor` /
  `OrderNotFound` become `.error ⟨""⟩`. The CancelOrder and ExecuteOrder models do name them, so the
  translation is inconsistent.
  - One consequence: `tryFillOrderFromPoolLiquidity_notFound` holds in the model for any caller. On
    the bytecode, a non-executor gets `NotAuthorizedExecutor` first.
- **`abi.decode` failures** are `.error ⟨"abi.decode"⟩` in the model. On the bytecode they revert
  with empty data.
- **Enums are unbounded `Nat`s.**
  - For `mode ≥ 2`, `setOrderingMode` reverts during ABI decoding before `onlyOwner` runs, while the
    model predicts `NotOwner` or a write.
  - A stored mode byte ≥ 2 makes `orderingMode()` panic with `0x21`, while the model says it never
    reverts. That state can't be reached.
  - The `testFuzz_note_*` / `test_note_*` tests record both behaviours.
- **Loop bound vs gas.** `bestOrder_loopBound` reverts with `"loop bound"` after 2^64 steps in the
  model. The EVM runs out of gas instead, so the test checks only that the call reverts.
- **Router `unlock` return data.** The Router discards `unlock`'s result, but solc still decodes the
  returned `bytes`. Malformed return data (only possible with a mock) makes `matchBook` /
  `fillFromPoolLiquidity` revert where the model succeeds.
  - The model reads `unlockCallback`'s action as word 0 of `data`. The bytecode reads
    `calldataload(0x44)`. The two agree for the standard encoding the PoolManager uses.
- **Direct library call.** Calling `AsyncMatching.setOrderingMode` directly hits solc's guard against
  direct library calls, so `asyncMatching_setOrderingMode_direct_noPoolChange` holds only because
  every such call reverts. The test checks what can be observed: the hook's storage is unchanged.

## Halmos

Halmos isn't installed here. The `Halmos` column says whether a test could run symbolically:
- **yes (57 theorems):** it takes plain inputs and has no setup Halmos can't handle.
- **with edits (67 theorems):** it needs its `vm.record` / `vm.accesses` write-set check replaced by
  before/after `vm.load` comparisons.
- **no:** it uses mocks, signatures, real order books, unlock flows or gas exhaustion.

## Theorem → test map

The links point to the theorem's line in `formal/Refinement/`. The reasons for leaving a theorem out:
- **model-only helper:** a lemma about Lean defs, the monad, or ABI encoding, with no observable claim
  beyond the theorems that are tested.
- **cross-call invariant:** a spec `step_*` invariant carried over a `World`.
- **untestable hypothesis:** the theorem assumes something about an opaque call that the real callee
  can't do.

### `Refinement/AsyncSwap.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `isExecutor_refines` | [AsyncSwap.lean:49](../../formal/Refinement/AsyncSwap.lean#L49) | [`RefinementAsyncSwap.t.sol`](RefinementAsyncSwap.t.sol) `testFuzz_isExecutor_refines` | with edits |
| `setExecutor_run` | [AsyncSwap.lean:57](../../formal/Refinement/AsyncSwap.lean#L57) | [`RefinementAsyncSwap.t.sol`](RefinementAsyncSwap.t.sol) `testFuzz_setExecutor_run` | with edits |
| `setExecutor_refines` | [AsyncSwap.lean:65](../../formal/Refinement/AsyncSwap.lean#L65) | [`RefinementAsyncSwap.t.sol`](RefinementAsyncSwap.t.sol) `testFuzz_setExecutor_refines` | yes |
| `setExecutor_frame` | [AsyncSwap.lean:81](../../formal/Refinement/AsyncSwap.lean#L81) | [`RefinementAsyncSwap.t.sol`](RefinementAsyncSwap.t.sol) `testFuzz_setExecutor_frame` | no |

Left out:

| Theorem | Lean | Reason |
|---|---|---|
| `setExecutor_escrow` | [AsyncSwap.lean:110](../../formal/Refinement/AsyncSwap.lean#L110) | cross-call invariant (spec `step_escrow` carried over a World) |
| `setExecutor_bal_nonneg` | [AsyncSwap.lean:117](../../formal/Refinement/AsyncSwap.lean#L117) | cross-call invariant (spec `step_bal_nonneg`) |
| `setExecutor_claims_nonneg` | [AsyncSwap.lean:124](../../formal/Refinement/AsyncSwap.lean#L124) | cross-call invariant (spec `step_claims_nonneg`) |
| `setExecutor_backing` | [AsyncSwap.lean:131](../../formal/Refinement/AsyncSwap.lean#L131) | cross-call invariant (spec `step_backing`) |
| `setExecutor_conservation` | [AsyncSwap.lean:138](../../formal/Refinement/AsyncSwap.lean#L138) | cross-call invariant / `_conservation` over a World |
| `setExecutor_reserves_nonneg` | [AsyncSwap.lean:147](../../formal/Refinement/AsyncSwap.lean#L147) | cross-call invariant (spec `step_reserves_nonneg`) |

### `Refinement/Monad.lean`


Left out:

| Theorem | Lean | Reason |
|---|---|---|
| `run_bind` | [Monad.lean:14](../../formal/Refinement/Monad.lean#L14) | model-only helper (simp lemma about the Lean monad / ABI encoding) |
| `run_pure` | [Monad.lean:20](../../formal/Refinement/Monad.lean#L20) | model-only helper (simp lemma about the Lean monad / ABI encoding) |
| `run_read` | [Monad.lean:23](../../formal/Refinement/Monad.lean#L23) | model-only helper (simp lemma about the Lean monad / ABI encoding) |
| `run_readThe` | [Monad.lean:26](../../formal/Refinement/Monad.lean#L26) | model-only helper (simp lemma about the Lean monad / ABI encoding) |
| `run_get` | [Monad.lean:29](../../formal/Refinement/Monad.lean#L29) | model-only helper (simp lemma about the Lean monad / ABI encoding) |
| `run_modify` | [Monad.lean:32](../../formal/Refinement/Monad.lean#L32) | model-only helper (simp lemma about the Lean monad / ABI encoding) |
| `run_throw` | [Monad.lean:35](../../formal/Refinement/Monad.lean#L35) | model-only helper (simp lemma about the Lean monad / ABI encoding) |
| `run_ite` | [Monad.lean:38](../../formal/Refinement/Monad.lean#L38) | model-only helper (simp lemma about the Lean monad / ABI encoding) |
| `run_map` | [Monad.lean:47](../../formal/Refinement/Monad.lean#L47) | model-only helper (simp lemma about the Lean monad / ABI encoding) |
| `ite_ok_error_eq_ok` | [Monad.lean:58](../../formal/Refinement/Monad.lean#L58) | model-only helper (simp lemma about the Lean monad / ABI encoding) |

### `Refinement/Router.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `swap_sound` | [Router.lean:155](../../formal/Refinement/Router.lean#L155) | [`RefinementRouter.t.sol`](RefinementRouter.t.sol) `testFuzz_swap_sound` | no |
| `swap_complete` | [Router.lean:168](../../formal/Refinement/Router.lean#L168) | [`RefinementRouter.t.sol`](RefinementRouter.t.sol) `testFuzz_swap_complete` | no |
| `cancelOrder_sound` | [Router.lean:197](../../formal/Refinement/Router.lean#L197) | [`RefinementRouter.t.sol`](RefinementRouter.t.sol) `testFuzz_cancelOrder_sound` | no |
| `cancelOrder_complete` | [Router.lean:206](../../formal/Refinement/Router.lean#L206) | [`RefinementRouter.t.sol`](RefinementRouter.t.sol) `testFuzz_cancelOrder_complete` | no |
| `unlockCallback_cancel` | [Router.lean:269](../../formal/Refinement/Router.lean#L269) | [`RefinementRouter.t.sol`](RefinementRouter.t.sol) `testFuzz_unlockCallback_cancel` | no |
| `unlockCallback_fill_maxPrice` | [Router.lean:318](../../formal/Refinement/Router.lean#L318) | [`RefinementRouter.t.sol`](RefinementRouter.t.sol) `testFuzz_unlockCallback_fill_maxPrice` | no |
| `fillOrder_value_sound` | [Router.lean:380](../../formal/Refinement/Router.lean#L380) | [`RefinementRouter.t.sol`](RefinementRouter.t.sol) `testFuzz_fillOrder_value_sound` | no |
| `fillOrder_forwards` | [Router.lean:398](../../formal/Refinement/Router.lean#L398) | [`RefinementRouter.t.sol`](RefinementRouter.t.sol) `testFuzz_fillOrder_forwards` | no |
| `fillOrder_maxPrice` | [Router.lean:425](../../formal/Refinement/Router.lean#L425) | [`RefinementRouter.t.sol`](RefinementRouter.t.sol) `testFuzz_fillOrder_maxPrice` | no |

Left out:

| Theorem | Lean | Reason |
|---|---|---|
| `bytesWord_append` | [Router.lean:37](../../formal/Refinement/Router.lean#L37) | model-only helper (Lean lemma about `bytesWord`) |
| `bytesWord_bytes` | [Router.lean:40](../../formal/Refinement/Router.lean#L40) | model-only helper (`bytesWord`) |
| `bytesWord_wordBytes` | [Router.lean:60](../../formal/Refinement/Router.lean#L60) | model-only helper (`bytesWord`/`wordBytes`) |
| `length_wordBytes` | [Router.lean:64](../../formal/Refinement/Router.lean#L64) | model-only helper (simp lemma about the Lean monad / ABI encoding) |
| `abiEncode_cons` | [Router.lean:67](../../formal/Refinement/Router.lean#L67) | model-only helper (`abiEncode`) |
| `length_abiEncode` | [Router.lean:70](../../formal/Refinement/Router.lean#L70) | model-only helper (simp lemma about the Lean monad / ABI encoding) |
| `take_drop_abiEncode_cons` | [Router.lean:76](../../formal/Refinement/Router.lean#L76) | model-only helper (`abiEncode` word slicing) |
| `take_abiEncode_cons` | [Router.lean:86](../../formal/Refinement/Router.lean#L86) | model-only helper (simp lemma about the Lean monad / ABI encoding) |
| `bytesWord_wordBytes_of_lt` | [Router.lean:90](../../formal/Refinement/Router.lean#L90) | model-only helper (`bytesWord`/`wordBytes`) |
| `Binds.isNative_input` | [Router.lean:127](../../formal/Refinement/Router.lean#L127) | model-only helper (spec `Config.isNative` vs `inputCurrency` abstraction) |
| `swapGuard_router` | [Router.lean:145](../../formal/Refinement/Router.lean#L145) | spec-only lemma (about `V2.Protocol.swapGuard`, no contract call) |
| `userParamsOf_abiEncode` | [Router.lean:187](../../formal/Refinement/Router.lean#L187) | model-only helper (round trip of the model's `abiEncode`/`userParamsOf`) |
| `spec_cancelOrder_owner` | [Router.lean:214](../../formal/Refinement/Router.lean#L214) | spec-only lemma (about `V2.Protocol.cancelOrder`, no contract call) |
| `ybool_le_one` | [Router.lean:238](../../formal/Refinement/Router.lean#L238) | model-only helper (simp lemma about the Lean monad / ABI encoding) |
| `ybool_beq_one` | [Router.lean:239](../../formal/Refinement/Router.lean#L239) | model-only helper (simp lemma about the Lean monad / ABI encoding) |
| `toUnsigned_lt` | [Router.lean:241](../../formal/Refinement/Router.lean#L241) | model-only helper (`toUnsigned`) |
| `toSigned_toUnsigned` | [Router.lean:247](../../formal/Refinement/Router.lean#L247) | model-only helper (`toSigned`/`toUnsigned`) |
| `Binds.isNative_output` | [Router.lean:298](../../formal/Refinement/Router.lean#L298) | model-only helper (spec `isNative` vs `outputCurrency` abstraction) |
| `run_view` | [Router.lean:355](../../formal/Refinement/Router.lean#L355) | model-only helper (simp lemma about the Lean monad / ABI encoding) |
| `view_ok_iff` | [Router.lean:360](../../formal/Refinement/Router.lean#L360) | model-only helper (`Except` match on `view`) |

### `Refinement/Swarm/AsyncMatchingSetOrderingModeDirect.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `asyncMatching_setOrderingMode_direct_noPoolChange` | [AsyncMatchingSetOrderingModeDirect.lean:52](../../formal/Refinement/Swarm/AsyncMatchingSetOrderingModeDirect.lean#L52) | [`AsyncMatchingSetOrderingModeDirect.t.sol`](AsyncMatchingSetOrderingModeDirect.t.sol) `testFuzz_asyncMatching_setOrderingMode_direct_noPoolChange` | no |

Left out:

| Theorem | Lean | Reason |
|---|---|---|
| `asyncMatching_setOrderingMode_frame` | [AsyncMatchingSetOrderingModeDirect.lean:28](../../formal/Refinement/Swarm/AsyncMatchingSetOrderingModeDirect.lean#L28) | model-only generic frame lemma over abstract accessors `book_get`/`book_set`; its concrete two-account instance is tested (direct_noPoolChange) |

### `Refinement/Swarm/AsyncSwapAcceptOwnership.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `acceptOwnership_run` | [AsyncSwapAcceptOwnership.lean:20](../../formal/Refinement/Swarm/AsyncSwapAcceptOwnership.lean#L20) | [`AsyncSwapAcceptOwnership.t.sol`](AsyncSwapAcceptOwnership.t.sol) `testFuzz_acceptOwnership_run` | with edits |
| `acceptOwnership_notPending` | [AsyncSwapAcceptOwnership.lean:30](../../formal/Refinement/Swarm/AsyncSwapAcceptOwnership.lean#L30) | [`AsyncSwapAcceptOwnership.t.sol`](AsyncSwapAcceptOwnership.t.sol) `testFuzz_acceptOwnership_notPending` | with edits |
| `acceptOwnership_reverts_iff` | [AsyncSwapAcceptOwnership.lean:36](../../formal/Refinement/Swarm/AsyncSwapAcceptOwnership.lean#L36) | [`AsyncSwapAcceptOwnership.t.sol`](AsyncSwapAcceptOwnership.t.sol) `testFuzz_acceptOwnership_reverts_iff` | with edits |
| `acceptOwnership_ok_iff` | [AsyncSwapAcceptOwnership.lean:45](../../formal/Refinement/Swarm/AsyncSwapAcceptOwnership.lean#L45) | [`AsyncSwapAcceptOwnership.t.sol`](AsyncSwapAcceptOwnership.t.sol) `testFuzz_acceptOwnership_ok_iff` | with edits |
| `acceptOwnership_ok_state` | [AsyncSwapAcceptOwnership.lean:56](../../formal/Refinement/Swarm/AsyncSwapAcceptOwnership.lean#L56) | [`AsyncSwapAcceptOwnership.t.sol`](AsyncSwapAcceptOwnership.t.sol) `testFuzz_acceptOwnership_ok_state` | with edits |

### `Refinement/Swarm/AsyncSwapAfterAddLiquidity.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `afterAddLiquidity_notPoolManager` | [AsyncSwapAfterAddLiquidity.lean:20](../../formal/Refinement/Swarm/AsyncSwapAfterAddLiquidity.lean#L20) | [`AsyncSwapAfterAddLiquidity.t.sol`](AsyncSwapAfterAddLiquidity.t.sol) `testFuzz_afterAddLiquidity_notPoolManager` | yes |
| `afterAddLiquidity_poolManager` | [AsyncSwapAfterAddLiquidity.lean:28](../../formal/Refinement/Swarm/AsyncSwapAfterAddLiquidity.lean#L28) | [`AsyncSwapAfterAddLiquidity.t.sol`](AsyncSwapAfterAddLiquidity.t.sol) `testFuzz_afterAddLiquidity_poolManager` | yes |
| `afterAddLiquidity_spec` | [AsyncSwapAfterAddLiquidity.lean:37](../../formal/Refinement/Swarm/AsyncSwapAfterAddLiquidity.lean#L37) | [`AsyncSwapAfterAddLiquidity.t.sol`](AsyncSwapAfterAddLiquidity.t.sol) `testFuzz_afterAddLiquidity_spec` | yes |
| `afterAddLiquidity_never_ok` | [AsyncSwapAfterAddLiquidity.lean:49](../../formal/Refinement/Swarm/AsyncSwapAfterAddLiquidity.lean#L49) | [`AsyncSwapAfterAddLiquidity.t.sol`](AsyncSwapAfterAddLiquidity.t.sol) `testFuzz_afterAddLiquidity_never_ok` | yes |

### `Refinement/Swarm/AsyncSwapAfterDonate.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `afterDonate_notPoolManager` | [AsyncSwapAfterDonate.lean:20](../../formal/Refinement/Swarm/AsyncSwapAfterDonate.lean#L20) | [`AsyncSwapAfterDonate.t.sol`](AsyncSwapAfterDonate.t.sol) `testFuzz_afterDonate_notPoolManager` | yes |
| `afterDonate_poolManager` | [AsyncSwapAfterDonate.lean:26](../../formal/Refinement/Swarm/AsyncSwapAfterDonate.lean#L26) | [`AsyncSwapAfterDonate.t.sol`](AsyncSwapAfterDonate.t.sol) `testFuzz_afterDonate_poolManager` | yes |
| `afterDonate_spec` | [AsyncSwapAfterDonate.lean:33](../../formal/Refinement/Swarm/AsyncSwapAfterDonate.lean#L33) | [`AsyncSwapAfterDonate.t.sol`](AsyncSwapAfterDonate.t.sol) `testFuzz_afterDonate_spec` | yes |
| `afterDonate_never_ok` | [AsyncSwapAfterDonate.lean:45](../../formal/Refinement/Swarm/AsyncSwapAfterDonate.lean#L45) | [`AsyncSwapAfterDonate.t.sol`](AsyncSwapAfterDonate.t.sol) `testFuzz_afterDonate_never_ok` | yes |

### `Refinement/Swarm/AsyncSwapAfterInitialize.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `afterInitialize_notPoolManager` | [AsyncSwapAfterInitialize.lean:20](../../formal/Refinement/Swarm/AsyncSwapAfterInitialize.lean#L20) | [`AsyncSwapAfterInitialize.t.sol`](AsyncSwapAfterInitialize.t.sol) `testFuzz_afterInitialize_notPoolManager` | yes |
| `afterInitialize_hookNotImplemented` | [AsyncSwapAfterInitialize.lean:26](../../formal/Refinement/Swarm/AsyncSwapAfterInitialize.lean#L26) | [`AsyncSwapAfterInitialize.t.sol`](AsyncSwapAfterInitialize.t.sol) `testFuzz_afterInitialize_hookNotImplemented` | yes |
| `afterInitialize_spec` | [AsyncSwapAfterInitialize.lean:33](../../formal/Refinement/Swarm/AsyncSwapAfterInitialize.lean#L33) | [`AsyncSwapAfterInitialize.t.sol`](AsyncSwapAfterInitialize.t.sol) `testFuzz_afterInitialize_spec` | yes |
| `afterInitialize_never_ok` | [AsyncSwapAfterInitialize.lean:45](../../formal/Refinement/Swarm/AsyncSwapAfterInitialize.lean#L45) | [`AsyncSwapAfterInitialize.t.sol`](AsyncSwapAfterInitialize.t.sol) `testFuzz_afterInitialize_never_ok` | yes |

### `Refinement/Swarm/AsyncSwapAfterRemoveLiquidity.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `afterRemoveLiquidity_notPoolManager` | [AsyncSwapAfterRemoveLiquidity.lean:20](../../formal/Refinement/Swarm/AsyncSwapAfterRemoveLiquidity.lean#L20) | [`AsyncSwapAfterRemoveLiquidity.t.sol`](AsyncSwapAfterRemoveLiquidity.t.sol) `testFuzz_afterRemoveLiquidity_notPoolManager` | yes |
| `afterRemoveLiquidity_hookNotImplemented` | [AsyncSwapAfterRemoveLiquidity.lean:28](../../formal/Refinement/Swarm/AsyncSwapAfterRemoveLiquidity.lean#L28) | [`AsyncSwapAfterRemoveLiquidity.t.sol`](AsyncSwapAfterRemoveLiquidity.t.sol) `testFuzz_afterRemoveLiquidity_hookNotImplemented` | yes |
| `afterRemoveLiquidity_spec` | [AsyncSwapAfterRemoveLiquidity.lean:37](../../formal/Refinement/Swarm/AsyncSwapAfterRemoveLiquidity.lean#L37) | [`AsyncSwapAfterRemoveLiquidity.t.sol`](AsyncSwapAfterRemoveLiquidity.t.sol) `testFuzz_afterRemoveLiquidity_spec` | yes |
| `afterRemoveLiquidity_never_ok` | [AsyncSwapAfterRemoveLiquidity.lean:50](../../formal/Refinement/Swarm/AsyncSwapAfterRemoveLiquidity.lean#L50) | [`AsyncSwapAfterRemoveLiquidity.t.sol`](AsyncSwapAfterRemoveLiquidity.t.sol) `testFuzz_afterRemoveLiquidity_never_ok` | yes |

### `Refinement/Swarm/AsyncSwapAfterSwap.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `afterSwap_notPoolManager` | [AsyncSwapAfterSwap.lean:20](../../formal/Refinement/Swarm/AsyncSwapAfterSwap.lean#L20) | [`AsyncSwapAfterSwap.t.sol`](AsyncSwapAfterSwap.t.sol) `testFuzz_afterSwap_notPoolManager` | yes |
| `afterSwap_hookNotImplemented` | [AsyncSwapAfterSwap.lean:28](../../formal/Refinement/Swarm/AsyncSwapAfterSwap.lean#L28) | [`AsyncSwapAfterSwap.t.sol`](AsyncSwapAfterSwap.t.sol) `testFuzz_afterSwap_hookNotImplemented` | yes |
| `afterSwap_spec` | [AsyncSwapAfterSwap.lean:36](../../formal/Refinement/Swarm/AsyncSwapAfterSwap.lean#L36) | [`AsyncSwapAfterSwap.t.sol`](AsyncSwapAfterSwap.t.sol) `testFuzz_afterSwap_spec` | yes |
| `afterSwap_never_ok` | [AsyncSwapAfterSwap.lean:49](../../formal/Refinement/Swarm/AsyncSwapAfterSwap.lean#L49) | [`AsyncSwapAfterSwap.t.sol`](AsyncSwapAfterSwap.t.sol) `testFuzz_afterSwap_never_ok` | yes |

### `Refinement/Swarm/AsyncSwapAsyncOrder.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `asyncOrder_run` | [AsyncSwapAsyncOrder.lean:20](../../formal/Refinement/Swarm/AsyncSwapAsyncOrder.lean#L20) | [`AsyncSwapAsyncOrder.t.sol`](AsyncSwapAsyncOrder.t.sol) `testFuzz_asyncOrder_run` | with edits |
| `asyncOrder_never_reverts` | [AsyncSwapAsyncOrder.lean:25](../../formal/Refinement/Swarm/AsyncSwapAsyncOrder.lean#L25) | [`AsyncSwapAsyncOrder.t.sol`](AsyncSwapAsyncOrder.t.sol) `testFuzz_asyncOrder_never_reverts` | with edits |
| `asyncOrder_ok_iff` | [AsyncSwapAsyncOrder.lean:31](../../formal/Refinement/Swarm/AsyncSwapAsyncOrder.lean#L31) | [`AsyncSwapAsyncOrder.t.sol`](AsyncSwapAsyncOrder.t.sol) `testFuzz_asyncOrder_ok_iff` | no |
| `asyncOrder_reads_only_asyncOrders` | [AsyncSwapAsyncOrder.lean:41](../../formal/Refinement/Swarm/AsyncSwapAsyncOrder.lean#L41) | [`AsyncSwapAsyncOrder.t.sol`](AsyncSwapAsyncOrder.t.sol) `testFuzz_asyncOrder_reads_only_asyncOrders` | with edits |

### `Refinement/Swarm/AsyncSwapAsyncOrderInfo.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `asyncOrderInfo_run` | [AsyncSwapAsyncOrderInfo.lean:21](../../formal/Refinement/Swarm/AsyncSwapAsyncOrderInfo.lean#L21) | [`AsyncSwapAsyncOrderInfo.t.sol`](AsyncSwapAsyncOrderInfo.t.sol) `testFuzz_asyncOrderInfo_run` | with edits |
| `asyncOrderInfo_never_reverts` | [AsyncSwapAsyncOrderInfo.lean:27](../../formal/Refinement/Swarm/AsyncSwapAsyncOrderInfo.lean#L27) | [`AsyncSwapAsyncOrderInfo.t.sol`](AsyncSwapAsyncOrderInfo.t.sol) `testFuzz_asyncOrderInfo_never_reverts` | with edits |
| `asyncOrderInfo_ok_iff` | [AsyncSwapAsyncOrderInfo.lean:33](../../formal/Refinement/Swarm/AsyncSwapAsyncOrderInfo.lean#L33) | [`AsyncSwapAsyncOrderInfo.t.sol`](AsyncSwapAsyncOrderInfo.t.sol) `testFuzz_asyncOrderInfo_ok_iff` | no |
| `asyncOrderInfo_reads_only_asyncOrders` | [AsyncSwapAsyncOrderInfo.lean:44](../../formal/Refinement/Swarm/AsyncSwapAsyncOrderInfo.lean#L44) | [`AsyncSwapAsyncOrderInfo.t.sol`](AsyncSwapAsyncOrderInfo.t.sol) `testFuzz_asyncOrderInfo_reads_only_asyncOrders` | with edits |

### `Refinement/Swarm/AsyncSwapAsyncOrderPriorityFee.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `asyncOrderPriorityFee_run` | [AsyncSwapAsyncOrderPriorityFee.lean:21](../../formal/Refinement/Swarm/AsyncSwapAsyncOrderPriorityFee.lean#L21) | [`AsyncSwapAsyncOrderPriorityFee.t.sol`](AsyncSwapAsyncOrderPriorityFee.t.sol) `testFuzz_asyncOrderPriorityFee_run` | with edits |
| `asyncOrderPriorityFee_never_reverts` | [AsyncSwapAsyncOrderPriorityFee.lean:30](../../formal/Refinement/Swarm/AsyncSwapAsyncOrderPriorityFee.lean#L30) | [`AsyncSwapAsyncOrderPriorityFee.t.sol`](AsyncSwapAsyncOrderPriorityFee.t.sol) `testFuzz_asyncOrderPriorityFee_never_reverts` | with edits |
| `asyncOrderPriorityFee_ok_iff` | [AsyncSwapAsyncOrderPriorityFee.lean:36](../../formal/Refinement/Swarm/AsyncSwapAsyncOrderPriorityFee.lean#L36) | [`AsyncSwapAsyncOrderPriorityFee.t.sol`](AsyncSwapAsyncOrderPriorityFee.t.sol) `testFuzz_asyncOrderPriorityFee_ok_iff` | with edits |
| `asyncOrderPriorityFee_not_escrowed` | [AsyncSwapAsyncOrderPriorityFee.lean:46](../../formal/Refinement/Swarm/AsyncSwapAsyncOrderPriorityFee.lean#L46) | [`AsyncSwapAsyncOrderPriorityFee.t.sol`](AsyncSwapAsyncOrderPriorityFee.t.sol) `testFuzz_asyncOrderPriorityFee_not_escrowed` | no |
| `asyncOrderPriorityFee_escrowed` | [AsyncSwapAsyncOrderPriorityFee.lean:52](../../formal/Refinement/Swarm/AsyncSwapAsyncOrderPriorityFee.lean#L52) | [`AsyncSwapAsyncOrderPriorityFee.t.sol`](AsyncSwapAsyncOrderPriorityFee.t.sol) `testFuzz_asyncOrderPriorityFee_escrowed` | no |
| `asyncOrderPriorityFee_reads_only_asyncOrders` | [AsyncSwapAsyncOrderPriorityFee.lean:59](../../formal/Refinement/Swarm/AsyncSwapAsyncOrderPriorityFee.lean#L59) | [`AsyncSwapAsyncOrderPriorityFee.t.sol`](AsyncSwapAsyncOrderPriorityFee.t.sol) `testFuzz_asyncOrderPriorityFee_reads_only_asyncOrders` | with edits |

### `Refinement/Swarm/AsyncSwapBeforeAddLiquidity.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `beforeAddLiquidity_notPoolManager` | [AsyncSwapBeforeAddLiquidity.lean:19](../../formal/Refinement/Swarm/AsyncSwapBeforeAddLiquidity.lean#L19) | [`AsyncSwapBeforeAddLiquidity.t.sol`](AsyncSwapBeforeAddLiquidity.t.sol) `testFuzz_beforeAddLiquidity_notPoolManager` | yes |
| `beforeAddLiquidity_ok` | [AsyncSwapBeforeAddLiquidity.lean:26](../../formal/Refinement/Swarm/AsyncSwapBeforeAddLiquidity.lean#L26) | [`AsyncSwapBeforeAddLiquidity.t.sol`](AsyncSwapBeforeAddLiquidity.t.sol) `testFuzz_beforeAddLiquidity_ok (+ test_beforeAddLiquidity_ok_viaPoolManager)` | no |
| `beforeAddLiquidity_spec` | [AsyncSwapBeforeAddLiquidity.lean:35](../../formal/Refinement/Swarm/AsyncSwapBeforeAddLiquidity.lean#L35) | [`AsyncSwapBeforeAddLiquidity.t.sol`](AsyncSwapBeforeAddLiquidity.t.sol) `testFuzz_beforeAddLiquidity_spec` | no |
| `beforeAddLiquidity_frame` | [AsyncSwapBeforeAddLiquidity.lean:47](../../formal/Refinement/Swarm/AsyncSwapBeforeAddLiquidity.lean#L47) | [`AsyncSwapBeforeAddLiquidity.t.sol`](AsyncSwapBeforeAddLiquidity.t.sol) `testFuzz_beforeAddLiquidity_frame` | no |

### `Refinement/Swarm/AsyncSwapBeforeDonate.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `beforeDonate_notPoolManager` | [AsyncSwapBeforeDonate.lean:20](../../formal/Refinement/Swarm/AsyncSwapBeforeDonate.lean#L20) | [`AsyncSwapBeforeDonate.t.sol`](AsyncSwapBeforeDonate.t.sol) `testFuzz_beforeDonate_notPoolManager` | yes |
| `beforeDonate_poolManager` | [AsyncSwapBeforeDonate.lean:26](../../formal/Refinement/Swarm/AsyncSwapBeforeDonate.lean#L26) | [`AsyncSwapBeforeDonate.t.sol`](AsyncSwapBeforeDonate.t.sol) `testFuzz_beforeDonate_poolManager` | yes |
| `beforeDonate_spec` | [AsyncSwapBeforeDonate.lean:33](../../formal/Refinement/Swarm/AsyncSwapBeforeDonate.lean#L33) | [`AsyncSwapBeforeDonate.t.sol`](AsyncSwapBeforeDonate.t.sol) `testFuzz_beforeDonate_spec` | yes |
| `beforeDonate_never_ok` | [AsyncSwapBeforeDonate.lean:45](../../formal/Refinement/Swarm/AsyncSwapBeforeDonate.lean#L45) | [`AsyncSwapBeforeDonate.t.sol`](AsyncSwapBeforeDonate.t.sol) `testFuzz_beforeDonate_never_ok` | yes |

### `Refinement/Swarm/AsyncSwapBeforeInitialize.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `beforeInitialize_notPoolManager` | [AsyncSwapBeforeInitialize.lean:52](../../formal/Refinement/Swarm/AsyncSwapBeforeInitialize.lean#L52) | [`AsyncSwapBeforeInitialize.t.sol`](AsyncSwapBeforeInitialize.t.sol) `testFuzz_beforeInitialize_notPoolManager` | yes |
| `beforeInitialize_numeraireRequired` | [AsyncSwapBeforeInitialize.lean:58](../../formal/Refinement/Swarm/AsyncSwapBeforeInitialize.lean#L58) | [`AsyncSwapBeforeInitialize.t.sol`](AsyncSwapBeforeInitialize.t.sol) `testFuzz_beforeInitialize_numeraireRequired` | yes |
| `beforeInitialize_dynamicFeeRequired` | [AsyncSwapBeforeInitialize.lean:67](../../formal/Refinement/Swarm/AsyncSwapBeforeInitialize.lean#L67) | [`AsyncSwapBeforeInitialize.t.sol`](AsyncSwapBeforeInitialize.t.sol) `testFuzz_beforeInitialize_dynamicFeeRequired (+ test_beforeInitialize_dynamicFeeRequired_viaPoolManager)` | yes |
| `beforeInitialize_run_ok` | [AsyncSwapBeforeInitialize.lean:78](../../formal/Refinement/Swarm/AsyncSwapBeforeInitialize.lean#L78) | [`AsyncSwapBeforeInitialize.t.sol`](AsyncSwapBeforeInitialize.t.sol) `testFuzz_beforeInitialize_run_ok (+ test_beforeInitialize_run_ok_viaPoolManager)` | no |
| `beforeInitialize_ok` | [AsyncSwapBeforeInitialize.lean:97](../../formal/Refinement/Swarm/AsyncSwapBeforeInitialize.lean#L97) | [`AsyncSwapBeforeInitialize.t.sol`](AsyncSwapBeforeInitialize.t.sol) `testFuzz_beforeInitialize_ok` | no |
| `beforeInitialize_ok_inv` | [AsyncSwapBeforeInitialize.lean:105](../../formal/Refinement/Swarm/AsyncSwapBeforeInitialize.lean#L105) | [`AsyncSwapBeforeInitialize.t.sol`](AsyncSwapBeforeInitialize.t.sol) `testFuzz_beforeInitialize_ok_inv` | no |
| `beforeInitialize_succeeds_iff` | [AsyncSwapBeforeInitialize.lean:124](../../formal/Refinement/Swarm/AsyncSwapBeforeInitialize.lean#L124) | [`AsyncSwapBeforeInitialize.t.sol`](AsyncSwapBeforeInitialize.t.sol) `testFuzz_beforeInitialize_succeeds_iff` | yes |
| `beforeInitialize_frame` | [AsyncSwapBeforeInitialize.lean:145](../../formal/Refinement/Swarm/AsyncSwapBeforeInitialize.lean#L145) | [`AsyncSwapBeforeInitialize.t.sol`](AsyncSwapBeforeInitialize.t.sol) `testFuzz_beforeInitialize_frame` | no |

Left out:

| Theorem | Lean | Reason |
|---|---|---|
| `beforeInit_world_get` | [AsyncSwapBeforeInitialize.lean:88](../../formal/Refinement/Swarm/AsyncSwapBeforeInitialize.lean#L88) | model-only helper (rewrites Lean `beforeInit_world` into `beforeInit_state`; its content is covered by the `beforeInitialize_ok`/`_run_ok` tests) |

### `Refinement/Swarm/AsyncSwapBeforeRemoveLiquidity.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `beforeRemoveLiquidity_notPoolManager` | [AsyncSwapBeforeRemoveLiquidity.lean:20](../../formal/Refinement/Swarm/AsyncSwapBeforeRemoveLiquidity.lean#L20) | [`AsyncSwapBeforeRemoveLiquidity.t.sol`](AsyncSwapBeforeRemoveLiquidity.t.sol) `testFuzz_beforeRemoveLiquidity_notPoolManager` | yes |
| `beforeRemoveLiquidity_hookNotImplemented` | [AsyncSwapBeforeRemoveLiquidity.lean:28](../../formal/Refinement/Swarm/AsyncSwapBeforeRemoveLiquidity.lean#L28) | [`AsyncSwapBeforeRemoveLiquidity.t.sol`](AsyncSwapBeforeRemoveLiquidity.t.sol) `testFuzz_beforeRemoveLiquidity_hookNotImplemented` | yes |
| `beforeRemoveLiquidity_spec` | [AsyncSwapBeforeRemoveLiquidity.lean:37](../../formal/Refinement/Swarm/AsyncSwapBeforeRemoveLiquidity.lean#L37) | [`AsyncSwapBeforeRemoveLiquidity.t.sol`](AsyncSwapBeforeRemoveLiquidity.t.sol) `testFuzz_beforeRemoveLiquidity_spec` | yes |
| `beforeRemoveLiquidity_never_ok` | [AsyncSwapBeforeRemoveLiquidity.lean:49](../../formal/Refinement/Swarm/AsyncSwapBeforeRemoveLiquidity.lean#L49) | [`AsyncSwapBeforeRemoveLiquidity.t.sol`](AsyncSwapBeforeRemoveLiquidity.t.sol) `testFuzz_beforeRemoveLiquidity_never_ok` | yes |

### `Refinement/Swarm/AsyncSwapBeforeSwap.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `beforeSwap_notPoolManager` | [AsyncSwapBeforeSwap.lean:78](../../formal/Refinement/Swarm/AsyncSwapBeforeSwap.lean#L78) | [`AsyncSwapBeforeSwap.t.sol`](AsyncSwapBeforeSwap.t.sol) `testFuzz_beforeSwap_notPoolManager` | yes |
| `beforeSwap_exactInputOnly` | [AsyncSwapBeforeSwap.lean:84](../../formal/Refinement/Swarm/AsyncSwapBeforeSwap.lean#L84) | [`AsyncSwapBeforeSwap.t.sol`](AsyncSwapBeforeSwap.t.sol) `testFuzz_beforeSwap_exactInputOnly` | yes |
| `beforeSwap_negOverflow` | [AsyncSwapBeforeSwap.lean:91](../../formal/Refinement/Swarm/AsyncSwapBeforeSwap.lean#L91) | [`AsyncSwapBeforeSwap.t.sol`](AsyncSwapBeforeSwap.t.sol) `testFuzz_beforeSwap_negOverflow` | yes |
| `beforeSwap_badDecode` | [AsyncSwapBeforeSwap.lean:101](../../formal/Refinement/Swarm/AsyncSwapBeforeSwap.lean#L101) | [`AsyncSwapBeforeSwap.t.sol`](AsyncSwapBeforeSwap.t.sol) `testFuzz_beforeSwap_badDecode, testFuzz_beforeSwap_badDecode_dirtyAddress` | yes |
| `beforeSwap_notExecutor` | [AsyncSwapBeforeSwap.lean:143](../../formal/Refinement/Swarm/AsyncSwapBeforeSwap.lean#L143) | [`AsyncSwapBeforeSwap.t.sol`](AsyncSwapBeforeSwap.t.sol) `testFuzz_beforeSwap_notExecutor` | yes |
| `beforeSwap_run_ok` | [AsyncSwapBeforeSwap.lean:161](../../formal/Refinement/Swarm/AsyncSwapBeforeSwap.lean#L161) | [`AsyncSwapBeforeSwap.t.sol`](AsyncSwapBeforeSwap.t.sol) `testFuzz_beforeSwap_run_ok, testFuzz_beforeSwap_run_ok_tailErrors, test_beforeSwap_run_ok_viaRouter` | no |
| `beforeSwap_ok_inv` | [AsyncSwapBeforeSwap.lean:178](../../formal/Refinement/Swarm/AsyncSwapBeforeSwap.lean#L178) | [`AsyncSwapBeforeSwap.t.sol`](AsyncSwapBeforeSwap.t.sol) `testFuzz_beforeSwap_ok_inv` | no |
| `beforeSwap_ok_returns` | [AsyncSwapBeforeSwap.lean:200](../../formal/Refinement/Swarm/AsyncSwapBeforeSwap.lean#L200) | [`AsyncSwapBeforeSwap.t.sol`](AsyncSwapBeforeSwap.t.sol) `testFuzz_beforeSwap_ok_returns` | no |
| `beforeSwap_succeeds_iff` | [AsyncSwapBeforeSwap.lean:213](../../formal/Refinement/Swarm/AsyncSwapBeforeSwap.lean#L213) | [`AsyncSwapBeforeSwap.t.sol`](AsyncSwapBeforeSwap.t.sol) `testFuzz_beforeSwap_succeeds_iff` | no |
| `beforeSwap_ok_delta` | [AsyncSwapBeforeSwap.lean:288](../../formal/Refinement/Swarm/AsyncSwapBeforeSwap.lean#L288) | [`AsyncSwapBeforeSwap.t.sol`](AsyncSwapBeforeSwap.t.sol) `testFuzz_beforeSwap_ok_delta` | no |

Left out:

| Theorem | Lean | Reason |
|---|---|---|
| `beforeSwap_frame` | [AsyncSwapBeforeSwap.lean:227](../../formal/Refinement/Swarm/AsyncSwapBeforeSwap.lean#L227) | hypothesis on opaque ext calls (`fn_AsyncSwap_createOrder_1681` leaving the hook's storage unchanged); the real `_createOrder` always writes `asyncOrders`/`priceBooks` on success, so the hypothesis cannot be set up concretely (vacuous on the bytecode) |
| `amountTaken_eq` | [AsyncSwapBeforeSwap.lean:247](../../formal/Refinement/Swarm/AsyncSwapBeforeSwap.lean#L247) | model-only helper (Lean arithmetic lemma about `amountTaken`/`toUnsigned`; observable content tested via `beforeSwap_run_ok` claims-balance check) |
| `delta_eq` | [AsyncSwapBeforeSwap.lean:260](../../formal/Refinement/Swarm/AsyncSwapBeforeSwap.lean#L260) | model-only helper (Lean bit-arithmetic lemma about `delta`/`wrapI`/`yshl`; observable content tested via `beforeSwap_ok_delta`) |

### `Refinement/Swarm/AsyncSwapBestOrder.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `bestOrder_run` | [AsyncSwapBestOrder.lean:155](../../formal/Refinement/Swarm/AsyncSwapBestOrder.lean#L155) | [`AsyncSwapBestOrder.t.sol`](AsyncSwapBestOrder.t.sol) `testFuzz_bestOrder_run, AsyncSwapBestOrder.t.sol: testFuzz_bestOrder_run_synthetic` | no |
| `bestOrder_empty` | [AsyncSwapBestOrder.lean:202](../../formal/Refinement/Swarm/AsyncSwapBestOrder.lean#L202) | [`AsyncSwapBestOrder.t.sol`](AsyncSwapBestOrder.t.sol) `testFuzz_bestOrder_empty` | no |
| `bestOrder_loopBound` | [AsyncSwapBestOrder.lean:208](../../formal/Refinement/Swarm/AsyncSwapBestOrder.lean#L208) | [`AsyncSwapBestOrder.t.sol`](AsyncSwapBestOrder.t.sol) `testFuzz_bestOrder_loopBound` | no |
| `bestOrder_ok` | [AsyncSwapBestOrder.lean:218](../../formal/Refinement/Swarm/AsyncSwapBestOrder.lean#L218) | [`AsyncSwapBestOrder.t.sol`](AsyncSwapBestOrder.t.sol) `testFuzz_bestOrder_ok` | no |
| `bestOrder_readOnly` | [AsyncSwapBestOrder.lean:251](../../formal/Refinement/Swarm/AsyncSwapBestOrder.lean#L251) | [`AsyncSwapBestOrder.t.sol`](AsyncSwapBestOrder.t.sol) `testFuzz_bestOrder_readOnly` | no |

Left out:

| Theorem | Lean | Reason |
|---|---|---|
| `firstLeaf_spec` | [AsyncSwapBestOrder.lean:57](../../formal/Refinement/Swarm/AsyncSwapBestOrder.lean#L57) | model-only helper (Lean lemma about `firstLeaf`/`walkN`) |
| `body_run` | [AsyncSwapBestOrder.lean:82](../../formal/Refinement/Swarm/AsyncSwapBestOrder.lean#L82) | model-only helper (Lean lemma about one loop-body step of `RadixPriceTree.best`) |
| `loop_run` | [AsyncSwapBestOrder.lean:101](../../formal/Refinement/Swarm/AsyncSwapBestOrder.lean#L101) | model-only helper (Lean lemma about the `forIn` loop of `RadixPriceTree.best`) |
| `best_run` | [AsyncSwapBestOrder.lean:134](../../formal/Refinement/Swarm/AsyncSwapBestOrder.lean#L134) | model-only helper (internal `RadixPriceTree.best` with an abstract read-only accessor); observable content is checked through bestOrder_run/_empty/_loopBound |

### `Refinement/Swarm/AsyncSwapCalculateHookFee.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `calculateHookFee_run` | [AsyncSwapCalculateHookFee.lean:20](../../formal/Refinement/Swarm/AsyncSwapCalculateHookFee.lean#L20) | [`AsyncSwapCalculateHookFee.t.sol`](AsyncSwapCalculateHookFee.t.sol) `testFuzz_calculateHookFee_run` | with edits |
| `calculateHookFee_never_reverts` | [AsyncSwapCalculateHookFee.lean:24](../../formal/Refinement/Swarm/AsyncSwapCalculateHookFee.lean#L24) | [`AsyncSwapCalculateHookFee.t.sol`](AsyncSwapCalculateHookFee.t.sol) `testFuzz_calculateHookFee_never_reverts` | with edits |
| `calculateHookFee_ok_iff` | [AsyncSwapCalculateHookFee.lean:30](../../formal/Refinement/Swarm/AsyncSwapCalculateHookFee.lean#L30) | [`AsyncSwapCalculateHookFee.t.sol`](AsyncSwapCalculateHookFee.t.sol) `testFuzz_calculateHookFee_ok_iff` | with edits |
| `calculateHookFee_const` | [AsyncSwapCalculateHookFee.lean:38](../../formal/Refinement/Swarm/AsyncSwapCalculateHookFee.lean#L38) | [`AsyncSwapCalculateHookFee.t.sol`](AsyncSwapCalculateHookFee.t.sol) `testFuzz_calculateHookFee_const` | with edits |

### `Refinement/Swarm/AsyncSwapCalculatePoolFee.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `calculatePoolFee_run` | [AsyncSwapCalculatePoolFee.lean:32](../../formal/Refinement/Swarm/AsyncSwapCalculatePoolFee.lean#L32) | [`AsyncSwapCalculatePoolFee.t.sol`](AsyncSwapCalculatePoolFee.t.sol) `testFuzz_calculatePoolFee_run` | with edits |
| `calculatePoolFee_ok` | [AsyncSwapCalculatePoolFee.lean:46](../../formal/Refinement/Swarm/AsyncSwapCalculatePoolFee.lean#L46) | [`AsyncSwapCalculatePoolFee.t.sol`](AsyncSwapCalculatePoolFee.t.sol) `testFuzz_calculatePoolFee_ok, AsyncSwapCalculatePoolFee.t.sol: test_calculatePoolFee_ok_edges` | with edits |
| `calculatePoolFee_le` | [AsyncSwapCalculatePoolFee.lean:53](../../formal/Refinement/Swarm/AsyncSwapCalculatePoolFee.lean#L53) | [`AsyncSwapCalculatePoolFee.t.sol`](AsyncSwapCalculatePoolFee.t.sol) `testFuzz_calculatePoolFee_le` | with edits |

Left out:

| Theorem | Lean | Reason |
|---|---|---|
| `pf_eq` | [AsyncSwapCalculatePoolFee.lean:26](../../formal/Refinement/Swarm/AsyncSwapCalculatePoolFee.lean#L26) | model-only helper (Lean arithmetic on `pf`); its content is checked by calculatePoolFee_run/_ok |
| `pf_le` | [AsyncSwapCalculatePoolFee.lean:28](../../formal/Refinement/Swarm/AsyncSwapCalculatePoolFee.lean#L28) | model-only helper (Lean arithmetic on `pf`); its content is checked by calculatePoolFee_le |

### `Refinement/Swarm/AsyncSwapCancelOrder.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `cancelOrder_run` | [AsyncSwapCancelOrder.lean:74](../../formal/Refinement/Swarm/AsyncSwapCancelOrder.lean#L74) | [`AsyncSwapCancelOrder.t.sol`](AsyncSwapCancelOrder.t.sol) `testFuzz_cancelOrder_run` | no |
| `cancelOrder_unauthorized` | [AsyncSwapCancelOrder.lean:101](../../formal/Refinement/Swarm/AsyncSwapCancelOrder.lean#L101) | [`AsyncSwapCancelOrder.t.sol`](AsyncSwapCancelOrder.t.sol) `testFuzz_cancelOrder_unauthorized` | no |
| `cancelOrder_notFound` | [AsyncSwapCancelOrder.lean:108](../../formal/Refinement/Swarm/AsyncSwapCancelOrder.lean#L108) | [`AsyncSwapCancelOrder.t.sol`](AsyncSwapCancelOrder.t.sol) `testFuzz_cancelOrder_notFound` | no |
| `cancelOrder_ok` | [AsyncSwapCancelOrder.lean:172](../../formal/Refinement/Swarm/AsyncSwapCancelOrder.lean#L172) | [`AsyncSwapCancelOrder.t.sol`](AsyncSwapCancelOrder.t.sol) `testFuzz_cancelOrder_ok, testFuzz_cancelOrder_ok_nativeInput, testFuzz_cancelOrder_ok_paidBid` | no |
| `cancelOrder_reentry_reverts` | [AsyncSwapCancelOrder.lean:215](../../formal/Refinement/Swarm/AsyncSwapCancelOrder.lean#L215) | [`AsyncSwapCancelOrder.t.sol`](AsyncSwapCancelOrder.t.sol) `testFuzz_cancelOrder_reentry_reverts` | no |

Left out:

| Theorem | Lean | Reason |
|---|---|---|
| `selfGet_run` | [AsyncSwapCancelOrder.lean:116](../../formal/Refinement/Swarm/AsyncSwapCancelOrder.lean#L116) | model-only helper (Lean accessor `selfGet` unfolds, `rfl`) |
| `selfSet_run` | [AsyncSwapCancelOrder.lean:119](../../formal/Refinement/Swarm/AsyncSwapCancelOrder.lean#L119) | model-only helper (Lean accessor `selfSet` unfolds, `rfl`) |
| `tail_ok` | [AsyncSwapCancelOrder.lean:130](../../formal/Refinement/Swarm/AsyncSwapCancelOrder.lean#L130) | model-only helper (step decomposition of the Lean def `tail`); its observable content is checked under cancelOrder_ok |
| `delWorld_order` | [AsyncSwapCancelOrder.lean:208](../../formal/Refinement/Swarm/AsyncSwapCancelOrder.lean#L208) | model-only helper (lemma about the Lean def `delWorld`); consequence tested in cancelOrder_reentry_reverts |

### `Refinement/Swarm/AsyncSwapDOMAIN_SEPARATOR.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `DOMAIN_SEPARATOR_spec` | [AsyncSwapDOMAIN_SEPARATOR.lean:29](../../formal/Refinement/Swarm/AsyncSwapDOMAIN_SEPARATOR.lean#L29) | [`AsyncSwapDOMAIN_SEPARATOR.t.sol`](AsyncSwapDOMAIN_SEPARATOR.t.sol) `testFuzz_DOMAIN_SEPARATOR_spec` | with edits |
| `DOMAIN_SEPARATOR_never_reverts` | [AsyncSwapDOMAIN_SEPARATOR.lean:40](../../formal/Refinement/Swarm/AsyncSwapDOMAIN_SEPARATOR.lean#L40) | [`AsyncSwapDOMAIN_SEPARATOR.t.sol`](AsyncSwapDOMAIN_SEPARATOR.t.sol) `testFuzz_DOMAIN_SEPARATOR_never_reverts` | with edits |
| `DOMAIN_SEPARATOR_preserves` | [AsyncSwapDOMAIN_SEPARATOR.lean:45](../../formal/Refinement/Swarm/AsyncSwapDOMAIN_SEPARATOR.lean#L45) | [`AsyncSwapDOMAIN_SEPARATOR.t.sol`](AsyncSwapDOMAIN_SEPARATOR.t.sol) `testFuzz_DOMAIN_SEPARATOR_preserves` | with edits |

### `Refinement/Swarm/AsyncSwapExecuteOrder.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `pf_le` | [AsyncSwapExecuteOrder.lean:122](../../formal/Refinement/Swarm/AsyncSwapExecuteOrder.lean#L122) | [`AsyncSwapExecuteOrder.t.sol`](AsyncSwapExecuteOrder.t.sol) `testFuzz_pf_le` | yes |
| `calculatePoolFee_run` | [AsyncSwapExecuteOrder.lean:124](../../formal/Refinement/Swarm/AsyncSwapExecuteOrder.lean#L124) | [`AsyncSwapExecuteOrder.t.sol`](AsyncSwapExecuteOrder.t.sol) `testFuzz_calculatePoolFee_run` | yes |
| `fill_run` | [AsyncSwapExecuteOrder.lean:137](../../formal/Refinement/Swarm/AsyncSwapExecuteOrder.lean#L137) | [`AsyncSwapExecuteOrder.t.sol`](AsyncSwapExecuteOrder.t.sol) `testFuzz_fill_run` | no |
| `afterNative_run` | [AsyncSwapExecuteOrder.lean:162](../../formal/Refinement/Swarm/AsyncSwapExecuteOrder.lean#L162) | [`AsyncSwapExecuteOrder.t.sol`](AsyncSwapExecuteOrder.t.sol) `testFuzz_afterNative_run` | no |
| `executeOrder_run` | [AsyncSwapExecuteOrder.lean:188](../../formal/Refinement/Swarm/AsyncSwapExecuteOrder.lean#L188) | [`AsyncSwapExecuteOrder.t.sol`](AsyncSwapExecuteOrder.t.sol) `testFuzz_executeOrder_run` | no |
| `executeOrder_decode` | [AsyncSwapExecuteOrder.lean:237](../../formal/Refinement/Swarm/AsyncSwapExecuteOrder.lean#L237) | [`AsyncSwapExecuteOrder.t.sol`](AsyncSwapExecuteOrder.t.sol) `testFuzz_executeOrder_decode` | no |
| `executeOrder_unaccountedNative` | [AsyncSwapExecuteOrder.lean:245](../../formal/Refinement/Swarm/AsyncSwapExecuteOrder.lean#L245) | [`AsyncSwapExecuteOrder.t.sol`](AsyncSwapExecuteOrder.t.sol) `testFuzz_executeOrder_unaccountedNative` | no |
| `executeOrder_nativeOverflow` | [AsyncSwapExecuteOrder.lean:256](../../formal/Refinement/Swarm/AsyncSwapExecuteOrder.lean#L256) | [`AsyncSwapExecuteOrder.t.sol`](AsyncSwapExecuteOrder.t.sol) `testFuzz_executeOrder_nativeOverflow` | no |
| `executeOrder_unauthorized` | [AsyncSwapExecuteOrder.lean:275](../../formal/Refinement/Swarm/AsyncSwapExecuteOrder.lean#L275) | [`AsyncSwapExecuteOrder.t.sol`](AsyncSwapExecuteOrder.t.sol) `testFuzz_executeOrder_unauthorized` | no |
| `executeOrder_notFound` | [AsyncSwapExecuteOrder.lean:290](../../formal/Refinement/Swarm/AsyncSwapExecuteOrder.lean#L290) | [`AsyncSwapExecuteOrder.t.sol`](AsyncSwapExecuteOrder.t.sol) `testFuzz_executeOrder_notFound` | no |
| `executeOrder_ok` | [AsyncSwapExecuteOrder.lean:323](../../formal/Refinement/Swarm/AsyncSwapExecuteOrder.lean#L323) | [`AsyncSwapExecuteOrder.t.sol`](AsyncSwapExecuteOrder.t.sol) `testFuzz_executeOrder_ok (ERC20 output), testFuzz_executeOrder_ok_native (native output; ledger decremented by exactly m + pf(m), checked by a second fill needing exactly the remainder vs. remainder + 1)` | no |

Left out:

| Theorem | Lean | Reason |
|---|---|---|
| `selfGet_run` | [AsyncSwapExecuteOrder.lean:73](../../formal/Refinement/Swarm/AsyncSwapExecuteOrder.lean#L73) | model-only helper (Lean accessor unfolds, `rfl`) |
| `executeOrder_viewRevert` | [AsyncSwapExecuteOrder.lean:266](../../formal/Refinement/Swarm/AsyncSwapExecuteOrder.lean#L266) | hypothesis on opaque ext call `view_AsyncSwap_asyncOrderInfo` reverting; the real `asyncOrderInfo` is a plain storage read that cannot revert (short of OOG), so it cannot be set up concretely |
| `tstoreWorld_frame` | [AsyncSwapExecuteOrder.lean:307](../../formal/Refinement/Swarm/AsyncSwapExecuteOrder.lean#L307) | model-only frame lemma about the Lean def `tstoreWorld`; the observable part (ledger decremented by exactly m + pf(m), orders untouched by that step) is checked in testFuzz_executeOrder_ok_native |

### `Refinement/Swarm/AsyncSwapFillOrderFromPoolLiquidity.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `fillOrderFromPoolLiquidity_notSelf` | [AsyncSwapFillOrderFromPoolLiquidity.lean:120](../../formal/Refinement/Swarm/AsyncSwapFillOrderFromPoolLiquidity.lean#L120) | [`AsyncSwapFillOrderFromPoolLiquidity.t.sol`](AsyncSwapFillOrderFromPoolLiquidity.t.sol) `testFuzz_fillOrderFromPoolLiquidity_notSelf` | yes |
| `fillOrderFromPoolLiquidity_notFound` | [AsyncSwapFillOrderFromPoolLiquidity.lean:126](../../formal/Refinement/Swarm/AsyncSwapFillOrderFromPoolLiquidity.lean#L126) | [`AsyncSwapFillOrderFromPoolLiquidity.t.sol`](AsyncSwapFillOrderFromPoolLiquidity.t.sol) `testFuzz_fillOrderFromPoolLiquidity_notFound` | no |
| `fillOrderFromPoolLiquidity_noLiquidity` | [AsyncSwapFillOrderFromPoolLiquidity.lean:133](../../formal/Refinement/Swarm/AsyncSwapFillOrderFromPoolLiquidity.lean#L133) | [`AsyncSwapFillOrderFromPoolLiquidity.t.sol`](AsyncSwapFillOrderFromPoolLiquidity.t.sol) `testFuzz_fillOrderFromPoolLiquidity_noLiquidity` | no |
| `swapAgainstPool_ok` | [AsyncSwapFillOrderFromPoolLiquidity.lean:175](../../formal/Refinement/Swarm/AsyncSwapFillOrderFromPoolLiquidity.lean#L175) | [`AsyncSwapFillOrderFromPoolLiquidity.t.sol`](AsyncSwapFillOrderFromPoolLiquidity.t.sol) `testFuzz_swapAgainstPool_ok` | no |
| `fillOrderFromPoolLiquidity_ok` | [AsyncSwapFillOrderFromPoolLiquidity.lean:261](../../formal/Refinement/Swarm/AsyncSwapFillOrderFromPoolLiquidity.lean#L261) | [`AsyncSwapFillOrderFromPoolLiquidity.t.sol`](AsyncSwapFillOrderFromPoolLiquidity.t.sol) `testFuzz_fillOrderFromPoolLiquidity_ok` | no |
| `fillOrderFromPoolLiquidity_ok_full` | [AsyncSwapFillOrderFromPoolLiquidity.lean:293](../../formal/Refinement/Swarm/AsyncSwapFillOrderFromPoolLiquidity.lean#L293) | [`AsyncSwapFillOrderFromPoolLiquidity.t.sol`](AsyncSwapFillOrderFromPoolLiquidity.t.sol) `testFuzz_fillOrderFromPoolLiquidity_ok_full` | no |
| `fillOrderFromPoolLiquidity_reentry_reverts` | [AsyncSwapFillOrderFromPoolLiquidity.lean:362](../../formal/Refinement/Swarm/AsyncSwapFillOrderFromPoolLiquidity.lean#L362) | [`AsyncSwapFillOrderFromPoolLiquidity.t.sol`](AsyncSwapFillOrderFromPoolLiquidity.t.sol) `testFuzz_fillOrderFromPoolLiquidity_reentry_reverts` | no |

Left out:

| Theorem | Lean | Reason |
|---|---|---|
| `selfGet_run` | [AsyncSwapFillOrderFromPoolLiquidity.lean:50](../../formal/Refinement/Swarm/AsyncSwapFillOrderFromPoolLiquidity.lean#L50) | model-only helper (`rfl`) |
| `selfSet_run` | [AsyncSwapFillOrderFromPoolLiquidity.lean:53](../../formal/Refinement/Swarm/AsyncSwapFillOrderFromPoolLiquidity.lean#L53) | model-only helper (`rfl`) |
| `fillOrderFromPoolLiquidity_eq` | [AsyncSwapFillOrderFromPoolLiquidity.lean:76](../../formal/Refinement/Swarm/AsyncSwapFillOrderFromPoolLiquidity.lean#L76) | `*_eq` unfolding into `AsyncMatching.fillFromPoolLiquidity`; its guard is tested as fillOrderFromPoolLiquidity_notSelf and the stored-maker payout in _ok_full |
| `fill_eq` | [AsyncSwapFillOrderFromPoolLiquidity.lean:93](../../formal/Refinement/Swarm/AsyncSwapFillOrderFromPoolLiquidity.lean#L93) | `*_eq` unfolding into `_swapAgainstPool` + Lean `tail`; observable parts tested as _notFound / swapAgainstPool_ok / _ok_full |
| `toSigned256_small` | [AsyncSwapFillOrderFromPoolLiquidity.lean:147](../../formal/Refinement/Swarm/AsyncSwapFillOrderFromPoolLiquidity.lean#L147) | model-only helper (Lean arithmetic lemma about `toSigned`) |
| `wrapI128_small` | [AsyncSwapFillOrderFromPoolLiquidity.lean:156](../../formal/Refinement/Swarm/AsyncSwapFillOrderFromPoolLiquidity.lean#L156) | model-only helper (Lean arithmetic lemma about `wrapI`) |
| `ite_error_ok_eq_ok` | [AsyncSwapFillOrderFromPoolLiquidity.lean:164](../../formal/Refinement/Swarm/AsyncSwapFillOrderFromPoolLiquidity.lean#L164) | model-only helper (Lean `ite`/`Except` lemma) |
| `tail_ok` | [AsyncSwapFillOrderFromPoolLiquidity.lean:224](../../formal/Refinement/Swarm/AsyncSwapFillOrderFromPoolLiquidity.lean#L224) | model-only helper (step decomposition of the Lean def `tail`); content checked in _ok_full |
| `selfSet_get` | [AsyncSwapFillOrderFromPoolLiquidity.lean:337](../../formal/Refinement/Swarm/AsyncSwapFillOrderFromPoolLiquidity.lean#L337) | model-only frame lemma (Lean setter footprint) |
| `bookSet_get` | [AsyncSwapFillOrderFromPoolLiquidity.lean:343](../../formal/Refinement/Swarm/AsyncSwapFillOrderFromPoolLiquidity.lean#L343) | model-only frame lemma (Lean setter footprint) |
| `delWorld_get` | [AsyncSwapFillOrderFromPoolLiquidity.lean:349](../../formal/Refinement/Swarm/AsyncSwapFillOrderFromPoolLiquidity.lean#L349) | model-only frame lemma (Lean def `delWorld`) |
| `delWorld_order` | [AsyncSwapFillOrderFromPoolLiquidity.lean:356](../../formal/Refinement/Swarm/AsyncSwapFillOrderFromPoolLiquidity.lean#L356) | model-only helper (Lean def `delWorld`); consequence tested in _reentry_reverts |

### `Refinement/Swarm/AsyncSwapGetHookPermissions.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `getHookPermissions_run` | [AsyncSwapGetHookPermissions.lean:29](../../formal/Refinement/Swarm/AsyncSwapGetHookPermissions.lean#L29) | [`AsyncSwapGetHookPermissions.t.sol`](AsyncSwapGetHookPermissions.t.sol) `testFuzz_getHookPermissions_run` | with edits |
| `getHookPermissions_never_reverts` | [AsyncSwapGetHookPermissions.lean:33](../../formal/Refinement/Swarm/AsyncSwapGetHookPermissions.lean#L33) | [`AsyncSwapGetHookPermissions.t.sol`](AsyncSwapGetHookPermissions.t.sol) `testFuzz_getHookPermissions_never_reverts` | with edits |
| `getHookPermissions_ok_iff` | [AsyncSwapGetHookPermissions.lean:39](../../formal/Refinement/Swarm/AsyncSwapGetHookPermissions.lean#L39) | [`AsyncSwapGetHookPermissions.t.sol`](AsyncSwapGetHookPermissions.t.sol) `test_getHookPermissions_ok_iff` | with edits |
| `getHookPermissions_fields` | [AsyncSwapGetHookPermissions.lean:47](../../formal/Refinement/Swarm/AsyncSwapGetHookPermissions.lean#L47) | [`AsyncSwapGetHookPermissions.t.sol`](AsyncSwapGetHookPermissions.t.sol) `test_getHookPermissions_fields` | with edits |

### `Refinement/Swarm/AsyncSwapInvalidateNonce.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `invalidateNonce_run` | [AsyncSwapInvalidateNonce.lean:20](../../formal/Refinement/Swarm/AsyncSwapInvalidateNonce.lean#L20) | [`AsyncSwapInvalidateNonce.t.sol`](AsyncSwapInvalidateNonce.t.sol) `testFuzz_invalidateNonce_run` | with edits |
| `invalidateNonce_reverts_iff` | [AsyncSwapInvalidateNonce.lean:31](../../formal/Refinement/Swarm/AsyncSwapInvalidateNonce.lean#L31) | [`AsyncSwapInvalidateNonce.t.sol`](AsyncSwapInvalidateNonce.t.sol) `testFuzz_invalidateNonce_reverts_iff` | with edits |
| `invalidateNonce_used` | [AsyncSwapInvalidateNonce.lean:38](../../formal/Refinement/Swarm/AsyncSwapInvalidateNonce.lean#L38) | [`AsyncSwapInvalidateNonce.t.sol`](AsyncSwapInvalidateNonce.t.sol) `testFuzz_invalidateNonce_used` | with edits |
| `invalidateNonce_ok_iff` | [AsyncSwapInvalidateNonce.lean:44](../../formal/Refinement/Swarm/AsyncSwapInvalidateNonce.lean#L44) | [`AsyncSwapInvalidateNonce.t.sol`](AsyncSwapInvalidateNonce.t.sol) `testFuzz_invalidateNonce_ok_iff` | with edits |
| `invalidateNonce_ok_state` | [AsyncSwapInvalidateNonce.lean:52](../../formal/Refinement/Swarm/AsyncSwapInvalidateNonce.lean#L52) | [`AsyncSwapInvalidateNonce.t.sol`](AsyncSwapInvalidateNonce.t.sol) `testFuzz_invalidateNonce_ok_state` | with edits |
| `invalidateNonce_other_maker` | [AsyncSwapInvalidateNonce.lean:75](../../formal/Refinement/Swarm/AsyncSwapInvalidateNonce.lean#L75) | [`AsyncSwapInvalidateNonce.t.sol`](AsyncSwapInvalidateNonce.t.sol) `testFuzz_invalidateNonce_other_maker` | with edits |

### `Refinement/Swarm/AsyncSwapMatchBook.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `asyncMatching_matchBook_ok` | [AsyncSwapMatchBook.lean:96](../../formal/Refinement/Swarm/AsyncSwapMatchBook.lean#L96) | [`AsyncSwapMatchBook.t.sol`](AsyncSwapMatchBook.t.sol) `testFuzz_asyncMatching_matchBook_ok` | no |
| `matchBook_invalidBound` | [AsyncSwapMatchBook.lean:161](../../formal/Refinement/Swarm/AsyncSwapMatchBook.lean#L161) | [`AsyncSwapMatchBook.t.sol`](AsyncSwapMatchBook.t.sol) `testFuzz_matchBook_invalidBound` | yes |
| `matchBook_ok` | [AsyncSwapMatchBook.lean:173](../../formal/Refinement/Swarm/AsyncSwapMatchBook.lean#L173) | [`AsyncSwapMatchBook.t.sol`](AsyncSwapMatchBook.t.sol) `testFuzz_matchBook_ok` | no |
| `matchBook_bound_noOk` | [AsyncSwapMatchBook.lean:180](../../formal/Refinement/Swarm/AsyncSwapMatchBook.lean#L180) | [`AsyncSwapMatchBook.t.sol`](AsyncSwapMatchBook.t.sol) `testFuzz_matchBook_bound_noOk` | no |

Left out:

| Theorem | Lean | Reason |
|---|---|---|
| `returns_pure` | [AsyncSwapMatchBook.lean:39](../../formal/Refinement/Swarm/AsyncSwapMatchBook.lean#L39) | model-only helper (`Returns` calculus) |
| `returns_bind` | [AsyncSwapMatchBook.lean:44](../../formal/Refinement/Swarm/AsyncSwapMatchBook.lean#L44) | model-only helper (`Returns` calculus) |
| `returns_bind_any` | [AsyncSwapMatchBook.lean:53](../../formal/Refinement/Swarm/AsyncSwapMatchBook.lean#L53) | model-only helper (`Returns` calculus) |
| `returns_ite` | [AsyncSwapMatchBook.lean:57](../../formal/Refinement/Swarm/AsyncSwapMatchBook.lean#L57) | model-only helper (`Returns` calculus) |
| `returns_forIn_list` | [AsyncSwapMatchBook.lean:69](../../formal/Refinement/Swarm/AsyncSwapMatchBook.lean#L69) | model-only helper (loop-invariant rule) |
| `returns_forIn_range` | [AsyncSwapMatchBook.lean:85](../../formal/Refinement/Swarm/AsyncSwapMatchBook.lean#L85) | model-only helper (loop-invariant rule) |
| `matchBook_eq` | [AsyncSwapMatchBook.lean:152](../../formal/Refinement/Swarm/AsyncSwapMatchBook.lean#L152) | `*_eq` unfolding of `AsyncSwap.matchBook` into `AsyncMatching.matchBook` |
| `selfSet_run` | [AsyncSwapMatchBook.lean:189](../../formal/Refinement/Swarm/AsyncSwapMatchBook.lean#L189) | model-only helper (`rfl`) |
| `bookSet_run` | [AsyncSwapMatchBook.lean:193](../../formal/Refinement/Swarm/AsyncSwapMatchBook.lean#L193) | model-only helper (`rfl`) |
| `selfGet_run` | [AsyncSwapMatchBook.lean:198](../../formal/Refinement/Swarm/AsyncSwapMatchBook.lean#L198) | model-only helper (`rfl`) |
| `bookGet_run` | [AsyncSwapMatchBook.lean:201](../../formal/Refinement/Swarm/AsyncSwapMatchBook.lean#L201) | model-only helper (`rfl`) |
| `selfSet_frame` | [AsyncSwapMatchBook.lean:205](../../formal/Refinement/Swarm/AsyncSwapMatchBook.lean#L205) | model-only frame lemma (Lean setter footprint) |
| `bookSet_frame` | [AsyncSwapMatchBook.lean:221](../../formal/Refinement/Swarm/AsyncSwapMatchBook.lean#L221) | model-only frame lemma (Lean setter footprint) |

### `Refinement/Swarm/AsyncSwapMatchNewOrder.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `matchNewOrder_run` | [AsyncSwapMatchNewOrder.lean:74](../../formal/Refinement/Swarm/AsyncSwapMatchNewOrder.lean#L74) | [`AsyncSwapMatchNewOrder.t.sol`](AsyncSwapMatchNewOrder.t.sol) `testFuzz_matchNewOrder_run` | no |
| `matchNewOrder_unauthorized` | [AsyncSwapMatchNewOrder.lean:140](../../formal/Refinement/Swarm/AsyncSwapMatchNewOrder.lean#L140) | [`AsyncSwapMatchNewOrder.t.sol`](AsyncSwapMatchNewOrder.t.sol) `testFuzz_matchNewOrder_unauthorized` | no |
| `matchNewOrder_wrongOwner` | [AsyncSwapMatchNewOrder.lean:169](../../formal/Refinement/Swarm/AsyncSwapMatchNewOrder.lean#L169) | [`AsyncSwapMatchNewOrder.t.sol`](AsyncSwapMatchNewOrder.t.sol) `testFuzz_matchNewOrder_wrongOwner` | no |
| `matchIncoming_empty` | [AsyncSwapMatchNewOrder.lean:181](../../formal/Refinement/Swarm/AsyncSwapMatchNewOrder.lean#L181) | [`AsyncSwapMatchNewOrder.t.sol`](AsyncSwapMatchNewOrder.t.sol) `test_matchIncoming_empty` | no |
| `matchNewOrder_emptyOrder` | [AsyncSwapMatchNewOrder.lean:191](../../formal/Refinement/Swarm/AsyncSwapMatchNewOrder.lean#L191) | [`AsyncSwapMatchNewOrder.t.sol`](AsyncSwapMatchNewOrder.t.sol) `testFuzz_matchNewOrder_emptyOrder` | no |
| `matchNewOrder_reentry_reverts` | [AsyncSwapMatchNewOrder.lean:207](../../formal/Refinement/Swarm/AsyncSwapMatchNewOrder.lean#L207) | [`AsyncSwapMatchNewOrder.t.sol`](AsyncSwapMatchNewOrder.t.sol) `testFuzz_matchNewOrder_reentry_reverts` | no |
| `matchIncoming_le` | [AsyncSwapMatchNewOrder.lean:223](../../formal/Refinement/Swarm/AsyncSwapMatchNewOrder.lean#L223) | [`AsyncSwapMatchNewOrder.t.sol`](AsyncSwapMatchNewOrder.t.sol) `testFuzz_matchIncoming_le` | no |
| `matchNewOrder_ok` | [AsyncSwapMatchNewOrder.lean:252](../../formal/Refinement/Swarm/AsyncSwapMatchNewOrder.lean#L252) | [`AsyncSwapMatchNewOrder.t.sol`](AsyncSwapMatchNewOrder.t.sol) `testFuzz_matchNewOrder_ok` | no |

Left out:

| Theorem | Lean | Reason |
|---|---|---|
| `ite_pos'` | [AsyncSwapMatchNewOrder.lean:47](../../formal/Refinement/Swarm/AsyncSwapMatchNewOrder.lean#L47) | model-only helper (Lean `ite` lemma) |
| `ite_neg'` | [AsyncSwapMatchNewOrder.lean:49](../../formal/Refinement/Swarm/AsyncSwapMatchNewOrder.lean#L49) | model-only helper (Lean `ite` lemma) |
| `run_tryCatch'` | [AsyncSwapMatchNewOrder.lean:53](../../formal/Refinement/Swarm/AsyncSwapMatchNewOrder.lean#L53) | model-only helper (semantics of the model's `tryCatch`) |
| `clearWorld_frame` | [AsyncSwapMatchNewOrder.lean:147](../../formal/Refinement/Swarm/AsyncSwapMatchNewOrder.lean#L147) | model-only frame lemma about the Lean def `clearWorld` (transient slots are not readable from a test); its consequence (pending match consumed) is tested in matchNewOrder_reentry_reverts / _run |
| `returns_throw` | [AsyncSwapMatchNewOrder.lean:216](../../formal/Refinement/Swarm/AsyncSwapMatchNewOrder.lean#L216) | model-only helper (`Returns` calculus) |

### `Refinement/Swarm/AsyncSwapOnlyOwner.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `onlyOwner_notOwner` | [AsyncSwapOnlyOwner.lean:20](../../formal/Refinement/Swarm/AsyncSwapOnlyOwner.lean#L20) | [`AsyncSwapOnlyOwner.t.sol`](AsyncSwapOnlyOwner.t.sol) `testFuzz_onlyOwner_notOwner` | with edits |
| `onlyOwner_owner` | [AsyncSwapOnlyOwner.lean:25](../../formal/Refinement/Swarm/AsyncSwapOnlyOwner.lean#L25) | [`AsyncSwapOnlyOwner.t.sol`](AsyncSwapOnlyOwner.t.sol) `testFuzz_onlyOwner_owner` | with edits |
| `onlyOwner_run` | [AsyncSwapOnlyOwner.lean:32](../../formal/Refinement/Swarm/AsyncSwapOnlyOwner.lean#L32) | [`AsyncSwapOnlyOwner.t.sol`](AsyncSwapOnlyOwner.t.sol) `testFuzz_onlyOwner_run` | with edits |
| `onlyOwner_reverts_NotOwner_iff` | [AsyncSwapOnlyOwner.lean:40](../../formal/Refinement/Swarm/AsyncSwapOnlyOwner.lean#L40) | [`AsyncSwapOnlyOwner.t.sol`](AsyncSwapOnlyOwner.t.sol) `testFuzz_onlyOwner_reverts_NotOwner_iff` | with edits |
| `onlyOwner_ok` | [AsyncSwapOnlyOwner.lean:47](../../formal/Refinement/Swarm/AsyncSwapOnlyOwner.lean#L47) | [`AsyncSwapOnlyOwner.t.sol`](AsyncSwapOnlyOwner.t.sol) `testFuzz_onlyOwner_ok` | with edits |

Left out:

| Theorem | Lean | Reason |
|---|---|---|
| `onlyOwner_pure_storage` | [AsyncSwapOnlyOwner.lean:56](../../formal/Refinement/Swarm/AsyncSwapOnlyOwner.lean#L56) | no contract entry point applies `onlyOwner` to a trivial body (`pure a`); a model-only instance of `onlyOwner_ok` (which is tested) |

### `Refinement/Swarm/AsyncSwapOrderBookLevel.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `orderBookLevel_readOnly` | [AsyncSwapOrderBookLevel.lean:63](../../formal/Refinement/Swarm/AsyncSwapOrderBookLevel.lean#L63) | [`AsyncSwapOrderBookLevel.t.sol`](AsyncSwapOrderBookLevel.t.sol) `testFuzz_orderBookLevel_readOnly` | no |
| `orderBookLevel_view` | [AsyncSwapOrderBookLevel.lean:73](../../formal/Refinement/Swarm/AsyncSwapOrderBookLevel.lean#L73) | [`AsyncSwapOrderBookLevel.t.sol`](AsyncSwapOrderBookLevel.t.sol) `testFuzz_orderBookLevel_view` | no |
| `orderBookLevel_congr` | [AsyncSwapOrderBookLevel.lean:86](../../formal/Refinement/Swarm/AsyncSwapOrderBookLevel.lean#L86) | [`AsyncSwapOrderBookLevel.t.sol`](AsyncSwapOrderBookLevel.t.sol) `testFuzz_orderBookLevel_congr` | no |

Left out:

| Theorem | Lean | Reason |
|---|---|---|
| `orderBookLevel_eq` | [AsyncSwapOrderBookLevel.lean:41](../../formal/Refinement/Swarm/AsyncSwapOrderBookLevel.lean#L41) | `*_eq` rewriting the generated def into the opaque `ext.fn_AsyncFiller_level_6002` (no observable claim beyond the others) |
| `orderBookLevel_run` | [AsyncSwapOrderBookLevel.lean:48](../../formal/Refinement/Swarm/AsyncSwapOrderBookLevel.lean#L48) | `*_run` that only unfolds into the opaque `ext.fn_AsyncFiller_level_6002` (no observable value) |
| `orderBookLevel_reverts_iff` | [AsyncSwapOrderBookLevel.lean:55](../../formal/Refinement/Swarm/AsyncSwapOrderBookLevel.lean#L55) | statement about the opaque `ext.fn_AsyncFiller_level_6002` (reverts iff the callee does); the callee cannot be run separately from the hook. Never-reverts on real books is checked by orderBookLevel_view |

### `Refinement/Swarm/AsyncSwapOrderBookOrder.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `orderBookOrder_run` | [AsyncSwapOrderBookOrder.lean:25](../../formal/Refinement/Swarm/AsyncSwapOrderBookOrder.lean#L25) | [`AsyncSwapOrderBookOrder.t.sol`](AsyncSwapOrderBookOrder.t.sol) `testFuzz_orderBookOrder_run` | with edits |
| `orderBookOrder_never_reverts` | [AsyncSwapOrderBookOrder.lean:32](../../formal/Refinement/Swarm/AsyncSwapOrderBookOrder.lean#L32) | [`AsyncSwapOrderBookOrder.t.sol`](AsyncSwapOrderBookOrder.t.sol) `testFuzz_orderBookOrder_never_reverts` | with edits |
| `orderBookOrder_readOnly` | [AsyncSwapOrderBookOrder.lean:37](../../formal/Refinement/Swarm/AsyncSwapOrderBookOrder.lean#L37) | [`AsyncSwapOrderBookOrder.t.sol`](AsyncSwapOrderBookOrder.t.sol) `testFuzz_orderBookOrder_readOnly` | no |
| `orderBookOrder_congr` | [AsyncSwapOrderBookOrder.lean:44](../../formal/Refinement/Swarm/AsyncSwapOrderBookOrder.lean#L44) | [`AsyncSwapOrderBookOrder.t.sol`](AsyncSwapOrderBookOrder.t.sol) `testFuzz_orderBookOrder_congr` | with edits |

### `Refinement/Swarm/AsyncSwapOrderingMode.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `orderingMode_run` | [AsyncSwapOrderingMode.lean:18](../../formal/Refinement/Swarm/AsyncSwapOrderingMode.lean#L18) | [`AsyncSwapOrderingMode.t.sol`](AsyncSwapOrderingMode.t.sol) `testFuzz_orderingMode_run` | with edits |
| `orderingMode_never_reverts` | [AsyncSwapOrderingMode.lean:24](../../formal/Refinement/Swarm/AsyncSwapOrderingMode.lean#L24) | [`AsyncSwapOrderingMode.t.sol`](AsyncSwapOrderingMode.t.sol) `testFuzz_orderingMode_never_reverts` | with edits |
| `orderingMode_frame` | [AsyncSwapOrderingMode.lean:29](../../formal/Refinement/Swarm/AsyncSwapOrderingMode.lean#L29) | [`AsyncSwapOrderingMode.t.sol`](AsyncSwapOrderingMode.t.sol) `testFuzz_orderingMode_frame` | with edits |
| `orderingMode_result` | [AsyncSwapOrderingMode.lean:34](../../formal/Refinement/Swarm/AsyncSwapOrderingMode.lean#L34) | [`AsyncSwapOrderingMode.t.sol`](AsyncSwapOrderingMode.t.sol) `testFuzz_orderingMode_result` | with edits |

### `Refinement/Swarm/AsyncSwapReceive.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `receive_run` | [AsyncSwapReceive.lean:32](../../formal/Refinement/Swarm/AsyncSwapReceive.lean#L32) | [`AsyncSwapReceive.t.sol`](AsyncSwapReceive.t.sol) `testFuzz_receive_run` | no |
| `receive_never_reverts` | [AsyncSwapReceive.lean:37](../../formal/Refinement/Swarm/AsyncSwapReceive.lean#L37) | [`AsyncSwapReceive.t.sol`](AsyncSwapReceive.t.sol) `testFuzz_receive_never_reverts` | no |
| `receive_ok` | [AsyncSwapReceive.lean:42](../../formal/Refinement/Swarm/AsyncSwapReceive.lean#L42) | [`AsyncSwapReceive.t.sol`](AsyncSwapReceive.t.sol) `testFuzz_receive_ok` | no |
| `receive_frame` | [AsyncSwapReceive.lean:50](../../formal/Refinement/Swarm/AsyncSwapReceive.lean#L50) | [`AsyncSwapReceive.t.sol`](AsyncSwapReceive.t.sol) `testFuzz_receive_frame` | no |

### `Refinement/Swarm/AsyncSwapRecordPriorityFee.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `recordPriorityFee_run` | [AsyncSwapRecordPriorityFee.lean:87](../../formal/Refinement/Swarm/AsyncSwapRecordPriorityFee.lean#L87) | [`AsyncSwapRecordPriorityFee.t.sol`](AsyncSwapRecordPriorityFee.t.sol) `testFuzz_recordPriorityFee_run` | no |
| `recordPriorityFee_unauthorized` | [AsyncSwapRecordPriorityFee.lean:154](../../formal/Refinement/Swarm/AsyncSwapRecordPriorityFee.lean#L154) | [`AsyncSwapRecordPriorityFee.t.sol`](AsyncSwapRecordPriorityFee.t.sol) `testFuzz_recordPriorityFee_unauthorized` | no |
| `recordPriorityFee_wrong_maker` | [AsyncSwapRecordPriorityFee.lean:160](../../formal/Refinement/Swarm/AsyncSwapRecordPriorityFee.lean#L160) | [`AsyncSwapRecordPriorityFee.t.sol`](AsyncSwapRecordPriorityFee.t.sol) `testFuzz_recordPriorityFee_wrong_maker` | no |
| `recordPriorityFee_escrowed_reverts` | [AsyncSwapRecordPriorityFee.lean:169](../../formal/Refinement/Swarm/AsyncSwapRecordPriorityFee.lean#L169) | [`AsyncSwapRecordPriorityFee.t.sol`](AsyncSwapRecordPriorityFee.t.sol) `testFuzz_recordPriorityFee_escrowed_reverts` | no |
| `recordPriorityFee_amount_mismatch_reverts` | [AsyncSwapRecordPriorityFee.lean:181](../../formal/Refinement/Swarm/AsyncSwapRecordPriorityFee.lean#L181) | [`AsyncSwapRecordPriorityFee.t.sol`](AsyncSwapRecordPriorityFee.t.sol) `testFuzz_recordPriorityFee_amount_mismatch_reverts` | no |
| `recordPriorityFee_ok` | [AsyncSwapRecordPriorityFee.lean:197](../../formal/Refinement/Swarm/AsyncSwapRecordPriorityFee.lean#L197) | [`AsyncSwapRecordPriorityFee.t.sol`](AsyncSwapRecordPriorityFee.t.sol) `testFuzz_recordPriorityFee_ok` | no |
| `recordPriorityFee_twice_reverts` | [AsyncSwapRecordPriorityFee.lean:264](../../formal/Refinement/Swarm/AsyncSwapRecordPriorityFee.lean#L264) | [`AsyncSwapRecordPriorityFee.t.sol`](AsyncSwapRecordPriorityFee.t.sol) `testFuzz_recordPriorityFee_twice_reverts` | no |

Left out:

| Theorem | Lean | Reason |
|---|---|---|
| `ite_pos'` | [AsyncSwapRecordPriorityFee.lean:42](../../formal/Refinement/Swarm/AsyncSwapRecordPriorityFee.lean#L42) | model-only helper (Lean `ite` lemma) |
| `ite_neg'` | [AsyncSwapRecordPriorityFee.lean:44](../../formal/Refinement/Swarm/AsyncSwapRecordPriorityFee.lean#L44) | model-only helper (Lean `ite` lemma) |
| `flagWorld_frame` | [AsyncSwapRecordPriorityFee.lean:231](../../formal/Refinement/Swarm/AsyncSwapRecordPriorityFee.lean#L231) | model-only frame lemma about the Lean def `flagWorld` (the flag write in isolation is not observable apart from the re-queue); flag/priorityKey after a real call checked in recordPriorityFee_run |

### `Refinement/Swarm/AsyncSwapSetExecutorWithSig.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `setExecutorWithSig_expired` | [AsyncSwapSetExecutorWithSig.lean:94](../../formal/Refinement/Swarm/AsyncSwapSetExecutorWithSig.lean#L94) | [`AsyncSwapSetExecutorWithSig.t.sol`](AsyncSwapSetExecutorWithSig.t.sol) `testFuzz_setExecutorWithSig_expired` | no |
| `setExecutorWithSig_nonce_used` | [AsyncSwapSetExecutorWithSig.lean:103](../../formal/Refinement/Swarm/AsyncSwapSetExecutorWithSig.lean#L103) | [`AsyncSwapSetExecutorWithSig.t.sol`](AsyncSwapSetExecutorWithSig.t.sol) `testFuzz_setExecutorWithSig_nonce_used` | no |
| `setExecutorWithSig_invalid_sig` | [AsyncSwapSetExecutorWithSig.lean:112](../../formal/Refinement/Swarm/AsyncSwapSetExecutorWithSig.lean#L112) | [`AsyncSwapSetExecutorWithSig.t.sol`](AsyncSwapSetExecutorWithSig.t.sol) `testFuzz_setExecutorWithSig_invalid_sig` | no |
| `setExecutorWithSig_ok` | [AsyncSwapSetExecutorWithSig.lean:124](../../formal/Refinement/Swarm/AsyncSwapSetExecutorWithSig.lean#L124) | [`AsyncSwapSetExecutorWithSig.t.sol`](AsyncSwapSetExecutorWithSig.t.sol) `testFuzz_setExecutorWithSig_ok` | no |
| `setExecutorWithSig_ok_inv` | [AsyncSwapSetExecutorWithSig.lean:139](../../formal/Refinement/Swarm/AsyncSwapSetExecutorWithSig.lean#L139) | [`AsyncSwapSetExecutorWithSig.t.sol`](AsyncSwapSetExecutorWithSig.t.sol) `testFuzz_setExecutorWithSig_ok_inv (the same signature succeeds iff none of key/maker/executor/allow/nonce/deadline is altered)` | no |
| `setExecutorWithSig_ok_state` | [AsyncSwapSetExecutorWithSig.lean:187](../../formal/Refinement/Swarm/AsyncSwapSetExecutorWithSig.lean#L187) | [`AsyncSwapSetExecutorWithSig.t.sol`](AsyncSwapSetExecutorWithSig.t.sol) `testFuzz_setExecutorWithSig_ok_state` | no |
| `setExecutorWithSig_frame` | [AsyncSwapSetExecutorWithSig.lean:206](../../formal/Refinement/Swarm/AsyncSwapSetExecutorWithSig.lean#L206) | [`AsyncSwapSetExecutorWithSig.t.sol`](AsyncSwapSetExecutorWithSig.t.sol) `testFuzz_setExecutorWithSig_frame` | no |
| `setExecutorWithSig_no_replay` | [AsyncSwapSetExecutorWithSig.lean:252](../../formal/Refinement/Swarm/AsyncSwapSetExecutorWithSig.lean#L252) | [`AsyncSwapSetExecutorWithSig.t.sol`](AsyncSwapSetExecutorWithSig.t.sol) `testFuzz_setExecutorWithSig_no_replay` | no |

Left out:

| Theorem | Lean | Reason |
|---|---|---|
| `tryRecover_preserves` | [AsyncSwapSetExecutorWithSig.lean:31](../../formal/Refinement/Swarm/AsyncSwapSetExecutorWithSig.lean#L31) | model-only helper (storage neutrality of the Lean def `ECDSA.tryRecover`; an internal pure function in the bytecode) |
| `tryRecover_9821_preserves` | [AsyncSwapSetExecutorWithSig.lean:39](../../formal/Refinement/Swarm/AsyncSwapSetExecutorWithSig.lean#L39) | model-only helper (as above) |
| `isValidSignatureNow_preserves` | [AsyncSwapSetExecutorWithSig.lean:49](../../formal/Refinement/Swarm/AsyncSwapSetExecutorWithSig.lean#L49) | model-only helper (storage neutrality of a Lean def, conditional on the opaque ERC-1271 call) |
| `hashTypedDataV4_preserves` | [AsyncSwapSetExecutorWithSig.lean:64](../../formal/Refinement/Swarm/AsyncSwapSetExecutorWithSig.lean#L64) | model-only helper (storage neutrality of a Lean def, conditional on opaque `toTypedDataHash`) |

### `Refinement/Swarm/AsyncSwapSetOrderingMode.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `setOrderingMode_run` | [AsyncSwapSetOrderingMode.lean:24](../../formal/Refinement/Swarm/AsyncSwapSetOrderingMode.lean#L24) | [`AsyncSwapSetOrderingMode.t.sol`](AsyncSwapSetOrderingMode.t.sol) `testFuzz_setOrderingMode_run` | with edits |
| `setOrderingMode_notOwner` | [AsyncSwapSetOrderingMode.lean:38](../../formal/Refinement/Swarm/AsyncSwapSetOrderingMode.lean#L38) | [`AsyncSwapSetOrderingMode.t.sol`](AsyncSwapSetOrderingMode.t.sol) `testFuzz_setOrderingMode_notOwner` | with edits |
| `setOrderingMode_ok_owner` | [AsyncSwapSetOrderingMode.lean:44](../../formal/Refinement/Swarm/AsyncSwapSetOrderingMode.lean#L44) | [`AsyncSwapSetOrderingMode.t.sol`](AsyncSwapSetOrderingMode.t.sol) `testFuzz_setOrderingMode_ok_owner` | with edits |
| `setOrderingMode_ok_iff` | [AsyncSwapSetOrderingMode.lean:53](../../formal/Refinement/Swarm/AsyncSwapSetOrderingMode.lean#L53) | [`AsyncSwapSetOrderingMode.t.sol`](AsyncSwapSetOrderingMode.t.sol) `testFuzz_setOrderingMode_ok_iff` | no |
| `setOrderingMode_ok_state` | [AsyncSwapSetOrderingMode.lean:67](../../formal/Refinement/Swarm/AsyncSwapSetOrderingMode.lean#L67) | [`AsyncSwapSetOrderingMode.t.sol`](AsyncSwapSetOrderingMode.t.sol) `testFuzz_setOrderingMode_ok_state` | with edits |

### `Refinement/Swarm/AsyncSwapSweep.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `sweep_notOwner` | [AsyncSwapSweep.lean:36](../../formal/Refinement/Swarm/AsyncSwapSweep.lean#L36) | [`AsyncSwapSweep.t.sol`](AsyncSwapSweep.t.sol) `testFuzz_sweep_notOwner` | with edits |
| `sweep_zeroTo` | [AsyncSwapSweep.lean:43](../../formal/Refinement/Swarm/AsyncSwapSweep.lean#L43) | [`AsyncSwapSweep.t.sol`](AsyncSwapSweep.t.sol) `testFuzz_sweep_zeroTo` | with edits |
| `sweep_reverts_unless` | [AsyncSwapSweep.lean:51](../../formal/Refinement/Swarm/AsyncSwapSweep.lean#L51) | [`AsyncSwapSweep.t.sol`](AsyncSwapSweep.t.sol) `testFuzz_sweep_reverts_unless` | with edits |
| `sweep_run` | [AsyncSwapSweep.lean:62](../../formal/Refinement/Swarm/AsyncSwapSweep.lean#L62) | [`AsyncSwapSweep.t.sol`](AsyncSwapSweep.t.sol) `testFuzz_sweep_run` | no |
| `sweep_ok` | [AsyncSwapSweep.lean:81](../../formal/Refinement/Swarm/AsyncSwapSweep.lean#L81) | [`AsyncSwapSweep.t.sol`](AsyncSwapSweep.t.sol) `testFuzz_sweep_ok` | with edits |
| `sweep_storage_unchanged` | [AsyncSwapSweep.lean:104](../../formal/Refinement/Swarm/AsyncSwapSweep.lean#L104) | [`AsyncSwapSweep.t.sol`](AsyncSwapSweep.t.sol) `testFuzz_sweep_storage_unchanged` | with edits |

Left out:

| Theorem | Lean | Reason |
|---|---|---|
| `balanceOfSelf_noWrite` | [AsyncSwapSweep.lean:23](../../formal/Refinement/Swarm/AsyncSwapSweep.lean#L23) | model-only helper (Lean lemma about the internal `CurrencyLibrary.balanceOfSelf`, no external entry point); its consequence is covered by sweep_run/sweep_storage_unchanged |

### `Refinement/Swarm/AsyncSwapTransferOwnership.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `transferOwnership_run` | [AsyncSwapTransferOwnership.lean:20](../../formal/Refinement/Swarm/AsyncSwapTransferOwnership.lean#L20) | [`AsyncSwapTransferOwnership.t.sol`](AsyncSwapTransferOwnership.t.sol) `testFuzz_transferOwnership_run` | with edits |
| `transferOwnership_notOwner` | [AsyncSwapTransferOwnership.lean:30](../../formal/Refinement/Swarm/AsyncSwapTransferOwnership.lean#L30) | [`AsyncSwapTransferOwnership.t.sol`](AsyncSwapTransferOwnership.t.sol) `testFuzz_transferOwnership_notOwner` | with edits |
| `transferOwnership_zero` | [AsyncSwapTransferOwnership.lean:36](../../formal/Refinement/Swarm/AsyncSwapTransferOwnership.lean#L36) | [`AsyncSwapTransferOwnership.t.sol`](AsyncSwapTransferOwnership.t.sol) `testFuzz_transferOwnership_zero` | with edits |
| `transferOwnership_ok_iff` | [AsyncSwapTransferOwnership.lean:43](../../formal/Refinement/Swarm/AsyncSwapTransferOwnership.lean#L43) | [`AsyncSwapTransferOwnership.t.sol`](AsyncSwapTransferOwnership.t.sol) `testFuzz_transferOwnership_ok_iff` | with edits |
| `transferOwnership_reverts_iff` | [AsyncSwapTransferOwnership.lean:52](../../formal/Refinement/Swarm/AsyncSwapTransferOwnership.lean#L52) | [`AsyncSwapTransferOwnership.t.sol`](AsyncSwapTransferOwnership.t.sol) `testFuzz_transferOwnership_reverts_iff` | with edits |
| `transferOwnership_ok_state` | [AsyncSwapTransferOwnership.lean:61](../../formal/Refinement/Swarm/AsyncSwapTransferOwnership.lean#L61) | [`AsyncSwapTransferOwnership.t.sol`](AsyncSwapTransferOwnership.t.sol) `testFuzz_transferOwnership_ok_state` | with edits |

### `Refinement/Swarm/AsyncSwapTryFillOrderFromPoolLiquidity.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `tryFillOrderFromPoolLiquidity_eq` | [AsyncSwapTryFillOrderFromPoolLiquidity.lean:46](../../formal/Refinement/Swarm/AsyncSwapTryFillOrderFromPoolLiquidity.lean#L46) | [`AsyncSwapTryFillOrderFromPoolLiquidity.t.sol`](AsyncSwapTryFillOrderFromPoolLiquidity.t.sol) `testFuzz_tryFillOrderFromPoolLiquidity_eq` | no |
| `tryFillOrderFromPoolLiquidity_notExecutor` | [AsyncSwapTryFillOrderFromPoolLiquidity.lean:72](../../formal/Refinement/Swarm/AsyncSwapTryFillOrderFromPoolLiquidity.lean#L72) | [`AsyncSwapTryFillOrderFromPoolLiquidity.t.sol`](AsyncSwapTryFillOrderFromPoolLiquidity.t.sol) `testFuzz_tryFillOrderFromPoolLiquidity_notExecutor` | no |
| `tryFillOrderFromPoolLiquidity_notFound` | [AsyncSwapTryFillOrderFromPoolLiquidity.lean:79](../../formal/Refinement/Swarm/AsyncSwapTryFillOrderFromPoolLiquidity.lean#L79) | [`AsyncSwapTryFillOrderFromPoolLiquidity.t.sol`](AsyncSwapTryFillOrderFromPoolLiquidity.t.sol) `testFuzz_tryFillOrderFromPoolLiquidity_notFound` | no |
| `tryFillOrderFromPoolLiquidity_pass` | [AsyncSwapTryFillOrderFromPoolLiquidity.lean:88](../../formal/Refinement/Swarm/AsyncSwapTryFillOrderFromPoolLiquidity.lean#L88) | [`AsyncSwapTryFillOrderFromPoolLiquidity.t.sol`](AsyncSwapTryFillOrderFromPoolLiquidity.t.sol) `testFuzz_tryFillOrderFromPoolLiquidity_pass` | no |
| `tryFillOrderFromPoolLiquidity_ok` | [AsyncSwapTryFillOrderFromPoolLiquidity.lean:103](../../formal/Refinement/Swarm/AsyncSwapTryFillOrderFromPoolLiquidity.lean#L103) | [`AsyncSwapTryFillOrderFromPoolLiquidity.t.sol`](AsyncSwapTryFillOrderFromPoolLiquidity.t.sol) `testFuzz_tryFillOrderFromPoolLiquidity_ok` | no |
| `tryFillOrderFromPoolLiquidity_reverts_iff` | [AsyncSwapTryFillOrderFromPoolLiquidity.lean:129](../../formal/Refinement/Swarm/AsyncSwapTryFillOrderFromPoolLiquidity.lean#L129) | [`AsyncSwapTryFillOrderFromPoolLiquidity.t.sol`](AsyncSwapTryFillOrderFromPoolLiquidity.t.sol) `testFuzz_tryFillOrderFromPoolLiquidity_reverts_iff` | no |
| `tryFillOrderFromPoolLiquidity_false_noop` | [AsyncSwapTryFillOrderFromPoolLiquidity.lean:151](../../formal/Refinement/Swarm/AsyncSwapTryFillOrderFromPoolLiquidity.lean#L151) | [`AsyncSwapTryFillOrderFromPoolLiquidity.t.sol`](AsyncSwapTryFillOrderFromPoolLiquidity.t.sol) `testFuzz_tryFillOrderFromPoolLiquidity_false_noop` | no |
| `tryFillOrderFromPoolLiquidity_storage` | [AsyncSwapTryFillOrderFromPoolLiquidity.lean:160](../../formal/Refinement/Swarm/AsyncSwapTryFillOrderFromPoolLiquidity.lean#L160) | [`AsyncSwapTryFillOrderFromPoolLiquidity.t.sol`](AsyncSwapTryFillOrderFromPoolLiquidity.t.sol) `testFuzz_tryFillOrderFromPoolLiquidity_storage (self-call reverts ⇒ every hook slot read or written during the call, found with `vm.record` on a snapshot pass, holds its old value)` | no |

Left out:

| Theorem | Lean | Reason |
|---|---|---|
| `run_tryCatch` | [AsyncSwapTryFillOrderFromPoolLiquidity.lean:30](../../formal/Refinement/Swarm/AsyncSwapTryFillOrderFromPoolLiquidity.lean#L30) | model-only helper (simp lemma about the Lean monad / ABI encoding) |

### `Refinement/Swarm/AsyncSwapUpdatePrice.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `updatePrice_run` | [AsyncSwapUpdatePrice.lean:74](../../formal/Refinement/Swarm/AsyncSwapUpdatePrice.lean#L74) | [`AsyncSwapUpdatePrice.t.sol`](AsyncSwapUpdatePrice.t.sol) `testFuzz_updatePrice_run` | no |
| `updatePrice_notOwner` | [AsyncSwapUpdatePrice.lean:94](../../formal/Refinement/Swarm/AsyncSwapUpdatePrice.lean#L94) | [`AsyncSwapUpdatePrice.t.sol`](AsyncSwapUpdatePrice.t.sol) `testFuzz_updatePrice_notOwner` | yes |
| `updatePrice_zero` | [AsyncSwapUpdatePrice.lean:100](../../formal/Refinement/Swarm/AsyncSwapUpdatePrice.lean#L100) | [`AsyncSwapUpdatePrice.t.sol`](AsyncSwapUpdatePrice.t.sol) `testFuzz_updatePrice_zero` | yes |
| `updatePrice_notFound` | [AsyncSwapUpdatePrice.lean:106](../../formal/Refinement/Swarm/AsyncSwapUpdatePrice.lean#L106) | [`AsyncSwapUpdatePrice.t.sol`](AsyncSwapUpdatePrice.t.sol) `testFuzz_updatePrice_notFound` | no |
| `priceKey_ok` | [AsyncSwapUpdatePrice.lean:129](../../formal/Refinement/Swarm/AsyncSwapUpdatePrice.lean#L129) | [`AsyncSwapUpdatePrice.t.sol`](AsyncSwapUpdatePrice.t.sol) `testFuzz_priceKey_ok` | no |
| `mid_ok` | [AsyncSwapUpdatePrice.lean:165](../../formal/Refinement/Swarm/AsyncSwapUpdatePrice.lean#L165) | [`AsyncSwapUpdatePrice.t.sol`](AsyncSwapUpdatePrice.t.sol) `testFuzz_mid_ok` | no |
| `midState_order` | [AsyncSwapUpdatePrice.lean:192](../../formal/Refinement/Swarm/AsyncSwapUpdatePrice.lean#L192) | [`AsyncSwapUpdatePrice.t.sol`](AsyncSwapUpdatePrice.t.sol) `testFuzz_midState_order` | no |
| `midState_other_order` | [AsyncSwapUpdatePrice.lean:202](../../formal/Refinement/Swarm/AsyncSwapUpdatePrice.lean#L202) | [`AsyncSwapUpdatePrice.t.sol`](AsyncSwapUpdatePrice.t.sol) `testFuzz_midState_other_order (other order in a price level the repriced order neither leaves nor joins; see note 4)` | no |
| `midState_other_pool` | [AsyncSwapUpdatePrice.lean:207](../../formal/Refinement/Swarm/AsyncSwapUpdatePrice.lean#L207) | [`AsyncSwapUpdatePrice.t.sol`](AsyncSwapUpdatePrice.t.sol) `testFuzz_midState_other_pool` | no |
| `midState_frame` | [AsyncSwapUpdatePrice.lean:212](../../formal/Refinement/Swarm/AsyncSwapUpdatePrice.lean#L212) | [`AsyncSwapUpdatePrice.t.sol`](AsyncSwapUpdatePrice.t.sol) `testFuzz_midState_frame` | no |
| `updatePrice_ok` | [AsyncSwapUpdatePrice.lean:225](../../formal/Refinement/Swarm/AsyncSwapUpdatePrice.lean#L225) | [`AsyncSwapUpdatePrice.t.sol`](AsyncSwapUpdatePrice.t.sol) `testFuzz_updatePrice_ok` | no |

Left out:

| Theorem | Lean | Reason |
|---|---|---|
| `post_ok` | [AsyncSwapUpdatePrice.lean:112](../../formal/Refinement/Swarm/AsyncSwapUpdatePrice.lean#L112) | model-only helper (Lean `ite`/`Except` lemma) |
| `upd_upd` | [AsyncSwapUpdatePrice.lean:148](../../formal/Refinement/Swarm/AsyncSwapUpdatePrice.lean#L148) | model-only helper (lemma about Lean `upd`) |

### `Refinement/Swarm/AsyncSwapUpdatePriceWithSig.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `verify_run` | [AsyncSwapUpdatePriceWithSig.lean:59](../../formal/Refinement/Swarm/AsyncSwapUpdatePriceWithSig.lean#L59) | [`AsyncSwapUpdatePriceWithSig.t.sol`](AsyncSwapUpdatePriceWithSig.t.sol) `testFuzz_verify_run` | no |
| `updatePriceWithSig_run` | [AsyncSwapUpdatePriceWithSig.lean:79](../../formal/Refinement/Swarm/AsyncSwapUpdatePriceWithSig.lean#L79) | [`AsyncSwapUpdatePriceWithSig.t.sol`](AsyncSwapUpdatePriceWithSig.t.sol) `testFuzz_updatePriceWithSig_run` | no |
| `updatePriceWithSig_expired` | [AsyncSwapUpdatePriceWithSig.lean:108](../../formal/Refinement/Swarm/AsyncSwapUpdatePriceWithSig.lean#L108) | [`AsyncSwapUpdatePriceWithSig.t.sol`](AsyncSwapUpdatePriceWithSig.t.sol) `testFuzz_updatePriceWithSig_expired` | yes |
| `updatePriceWithSig_nonceUsed` | [AsyncSwapUpdatePriceWithSig.lean:114](../../formal/Refinement/Swarm/AsyncSwapUpdatePriceWithSig.lean#L114) | [`AsyncSwapUpdatePriceWithSig.t.sol`](AsyncSwapUpdatePriceWithSig.t.sol) `testFuzz_updatePriceWithSig_nonceUsed` | no |
| `updatePriceWithSig_invalidSig` | [AsyncSwapUpdatePriceWithSig.lean:122](../../formal/Refinement/Swarm/AsyncSwapUpdatePriceWithSig.lean#L122) | [`AsyncSwapUpdatePriceWithSig.t.sol`](AsyncSwapUpdatePriceWithSig.t.sol) `testFuzz_updatePriceWithSig_invalidSig` | no |
| `updatePriceWithSig_zero` | [AsyncSwapUpdatePriceWithSig.lean:132](../../formal/Refinement/Swarm/AsyncSwapUpdatePriceWithSig.lean#L132) | [`AsyncSwapUpdatePriceWithSig.t.sol`](AsyncSwapUpdatePriceWithSig.t.sol) `testFuzz_updatePriceWithSig_zero` | no |
| `updatePriceWithSig_notFound` | [AsyncSwapUpdatePriceWithSig.lean:139](../../formal/Refinement/Swarm/AsyncSwapUpdatePriceWithSig.lean#L139) | [`AsyncSwapUpdatePriceWithSig.t.sol`](AsyncSwapUpdatePriceWithSig.t.sol) `testFuzz_updatePriceWithSig_notFound` | no |
| `updatePriceWithSig_noOwnerGuard` | [AsyncSwapUpdatePriceWithSig.lean:150](../../formal/Refinement/Swarm/AsyncSwapUpdatePriceWithSig.lean#L150) | [`AsyncSwapUpdatePriceWithSig.t.sol`](AsyncSwapUpdatePriceWithSig.t.sol) `testFuzz_updatePriceWithSig_noOwnerGuard` | no |
| `verify_ok_inv` | [AsyncSwapUpdatePriceWithSig.lean:183](../../formal/Refinement/Swarm/AsyncSwapUpdatePriceWithSig.lean#L183) | [`AsyncSwapUpdatePriceWithSig.t.sol`](AsyncSwapUpdatePriceWithSig.t.sol) `testFuzz_verify_ok_inv` | no |
| `updatePriceWithSig_missing_reverts` | [AsyncSwapUpdatePriceWithSig.lean:219](../../formal/Refinement/Swarm/AsyncSwapUpdatePriceWithSig.lean#L219) | [`AsyncSwapUpdatePriceWithSig.t.sol`](AsyncSwapUpdatePriceWithSig.t.sol) `testFuzz_updatePriceWithSig_missing_reverts` | no |
| `updatePriceWithSig_ok` | [AsyncSwapUpdatePriceWithSig.lean:242](../../formal/Refinement/Swarm/AsyncSwapUpdatePriceWithSig.lean#L242) | [`AsyncSwapUpdatePriceWithSig.t.sol`](AsyncSwapUpdatePriceWithSig.t.sol) `testFuzz_updatePriceWithSig_ok` | no |
| `updatePriceWithSig_burns_nonce` | [AsyncSwapUpdatePriceWithSig.lean:297](../../formal/Refinement/Swarm/AsyncSwapUpdatePriceWithSig.lean#L297) | [`AsyncSwapUpdatePriceWithSig.t.sol`](AsyncSwapUpdatePriceWithSig.t.sol) `testFuzz_updatePriceWithSig_burns_nonce` | no |

Left out:

| Theorem | Lean | Reason |
|---|---|---|
| `burn_asyncOrders` | [AsyncSwapUpdatePriceWithSig.lean:213](../../formal/Refinement/Swarm/AsyncSwapUpdatePriceWithSig.lean#L213) | model-only frame lemma about the Lean def `burn` |

### `Refinement/Swarm/FeeVaultCollect.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `collect_run` | [FeeVaultCollect.lean:31](../../formal/Refinement/Swarm/FeeVaultCollect.lean#L31) | [`FeeVaultCollect.t.sol`](FeeVaultCollect.t.sol) `testFuzz_collect_run` | no |
| `collect_owner_view_reverts` | [FeeVaultCollect.lean:58](../../formal/Refinement/Swarm/FeeVaultCollect.lean#L58) | [`FeeVaultCollect.t.sol`](FeeVaultCollect.t.sol) `testFuzz_collect_owner_view_reverts` | no |
| `collect_unauthorized` | [FeeVaultCollect.lean:64](../../formal/Refinement/Swarm/FeeVaultCollect.lean#L64) | [`FeeVaultCollect.t.sol`](FeeVaultCollect.t.sol) `testFuzz_collect_unauthorized` | yes |
| `collect_zero_recipient` | [FeeVaultCollect.lean:70](../../formal/Refinement/Swarm/FeeVaultCollect.lean#L70) | [`FeeVaultCollect.t.sol`](FeeVaultCollect.t.sol) `testFuzz_collect_zero_recipient` | yes |
| `collect_ok` | [FeeVaultCollect.lean:78](../../formal/Refinement/Swarm/FeeVaultCollect.lean#L78) | [`FeeVaultCollect.t.sol`](FeeVaultCollect.t.sol) `testFuzz_collect_ok` | no |
| `collect_only_owner` | [FeeVaultCollect.lean:101](../../formal/Refinement/Swarm/FeeVaultCollect.lean#L101) | [`FeeVaultCollect.t.sol`](FeeVaultCollect.t.sol) `testFuzz_collect_only_owner` | yes |
| `collect_reverts_iff` | [FeeVaultCollect.lean:108](../../formal/Refinement/Swarm/FeeVaultCollect.lean#L108) | [`FeeVaultCollect.t.sol`](FeeVaultCollect.t.sol) `testFuzz_collect_reverts_iff` | no |

### `Refinement/Swarm/FeeVaultUnlockCallback.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `unlockCallback_run` | [FeeVaultUnlockCallback.lean:59](../../formal/Refinement/Swarm/FeeVaultUnlockCallback.lean#L59) | [`FeeVaultUnlockCallback.t.sol`](FeeVaultUnlockCallback.t.sol) `testFuzz_unlockCallback_run` | no |
| `unlockCallback_unauthorized` | [FeeVaultUnlockCallback.lean:86](../../formal/Refinement/Swarm/FeeVaultUnlockCallback.lean#L86) | [`FeeVaultUnlockCallback.t.sol`](FeeVaultUnlockCallback.t.sol) `testFuzz_unlockCallback_unauthorized` | yes |
| `unlockCallback_badData` | [FeeVaultUnlockCallback.lean:92](../../formal/Refinement/Swarm/FeeVaultUnlockCallback.lean#L92) | [`FeeVaultUnlockCallback.t.sol`](FeeVaultUnlockCallback.t.sol) `testFuzz_unlockCallback_badData` | no |
| `unlockCallback_view_reverts` | [FeeVaultUnlockCallback.lean:98](../../formal/Refinement/Swarm/FeeVaultUnlockCallback.lean#L98) | [`FeeVaultUnlockCallback.t.sol`](FeeVaultUnlockCallback.t.sol) `testFuzz_unlockCallback_view_reverts` | no |
| `unlockCallback_zero` | [FeeVaultUnlockCallback.lean:105](../../formal/Refinement/Swarm/FeeVaultUnlockCallback.lean#L105) | [`FeeVaultUnlockCallback.t.sol`](FeeVaultUnlockCallback.t.sol) `testFuzz_unlockCallback_zero` | no |
| `unlockCallback_nonzero` | [FeeVaultUnlockCallback.lean:113](../../formal/Refinement/Swarm/FeeVaultUnlockCallback.lean#L113) | [`FeeVaultUnlockCallback.t.sol`](FeeVaultUnlockCallback.t.sol) `testFuzz_unlockCallback_nonzero` | no |
| `unlockCallback_ok` | [FeeVaultUnlockCallback.lean:125](../../formal/Refinement/Swarm/FeeVaultUnlockCallback.lean#L125) | [`FeeVaultUnlockCallback.t.sol`](FeeVaultUnlockCallback.t.sol) `testFuzz_unlockCallback_ok` | no |
| `unlockCallback_take_eq_own_balance` | [FeeVaultUnlockCallback.lean:165](../../formal/Refinement/Swarm/FeeVaultUnlockCallback.lean#L165) | [`FeeVaultUnlockCallback.t.sol`](FeeVaultUnlockCallback.t.sol) `testFuzz_unlockCallback_take_eq_own_balance` | no |
| `unlockCallback_burn_fails` | [FeeVaultUnlockCallback.lean:182](../../formal/Refinement/Swarm/FeeVaultUnlockCallback.lean#L182) | [`FeeVaultUnlockCallback.t.sol`](FeeVaultUnlockCallback.t.sol) `testFuzz_unlockCallback_burn_fails (ManagerLocked) + test_unlockCallback_burn_fails_overflow (SafeCastOverflow inside a real unlock)` | no |
| `unlockCallback_reverts_iff` | [FeeVaultUnlockCallback.lean:191](../../formal/Refinement/Swarm/FeeVaultUnlockCallback.lean#L191) | [`FeeVaultUnlockCallback.t.sol`](FeeVaultUnlockCallback.t.sol) `testFuzz_unlockCallback_reverts_iff` | no |

### `Refinement/Swarm/NativeClaimsRedeem.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `redeem_run` | [NativeClaimsRedeem.lean:29](../../formal/Refinement/Swarm/NativeClaimsRedeem.lean#L29) | [`NativeClaimsRedeem.t.sol`](NativeClaimsRedeem.t.sol) `testFuzz_redeem_run` | no |
| `redeem_reentrant` | [NativeClaimsRedeem.lean:53](../../formal/Refinement/Swarm/NativeClaimsRedeem.lean#L53) | [`NativeClaimsRedeem.t.sol`](NativeClaimsRedeem.t.sol) `testFuzz_redeem_reentrant` | yes |
| `redeem_invalid` | [NativeClaimsRedeem.lean:59](../../formal/Refinement/Swarm/NativeClaimsRedeem.lean#L59) | [`NativeClaimsRedeem.t.sol`](NativeClaimsRedeem.t.sol) `testFuzz_redeem_invalid` | yes |
| `redeem_ok` | [NativeClaimsRedeem.lean:67](../../formal/Refinement/Swarm/NativeClaimsRedeem.lean#L67) | [`NativeClaimsRedeem.t.sol`](NativeClaimsRedeem.t.sol) `testFuzz_redeem_ok` | no |
| `redeem_reverts_iff` | [NativeClaimsRedeem.lean:88](../../formal/Refinement/Swarm/NativeClaimsRedeem.lean#L88) | [`NativeClaimsRedeem.t.sol`](NativeClaimsRedeem.t.sol) `testFuzz_redeem_reverts_iff` | no |
| `redeem_ok_state` | [NativeClaimsRedeem.lean:109](../../formal/Refinement/Swarm/NativeClaimsRedeem.lean#L109) | [`NativeClaimsRedeem.t.sol`](NativeClaimsRedeem.t.sol) `testFuzz_redeem_ok_state` | no |
| `redeem_nested_reverts` | [NativeClaimsRedeem.lean:117](../../formal/Refinement/Swarm/NativeClaimsRedeem.lean#L117) | [`NativeClaimsRedeem.t.sol`](NativeClaimsRedeem.t.sol) `testFuzz_redeem_nested_reverts` | no |

### `Refinement/Swarm/NativeClaimsUnlockCallback.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `unlockCallback_run` | [NativeClaimsUnlockCallback.lean:46](../../formal/Refinement/Swarm/NativeClaimsUnlockCallback.lean#L46) | [`NativeClaimsUnlockCallback.t.sol`](NativeClaimsUnlockCallback.t.sol) `testFuzz_unlockCallback_run (locked) + testFuzz_unlockCallback_run_unlocked (via real unlock)` | no |
| `unlockCallback_onlyPoolManager` | [NativeClaimsUnlockCallback.lean:70](../../formal/Refinement/Swarm/NativeClaimsUnlockCallback.lean#L70) | [`NativeClaimsUnlockCallback.t.sol`](NativeClaimsUnlockCallback.t.sol) `testFuzz_unlockCallback_onlyPoolManager` | yes |
| `unlockCallback_badData` | [NativeClaimsUnlockCallback.lean:76](../../formal/Refinement/Swarm/NativeClaimsUnlockCallback.lean#L76) | [`NativeClaimsUnlockCallback.t.sol`](NativeClaimsUnlockCallback.t.sol) `testFuzz_unlockCallback_badData` | no |
| `unlockCallback_ok` | [NativeClaimsUnlockCallback.lean:85](../../formal/Refinement/Swarm/NativeClaimsUnlockCallback.lean#L85) | [`NativeClaimsUnlockCallback.t.sol`](NativeClaimsUnlockCallback.t.sol) `testFuzz_unlockCallback_ok` | no |
| `unlockCallback_burn_fails` | [NativeClaimsUnlockCallback.lean:112](../../formal/Refinement/Swarm/NativeClaimsUnlockCallback.lean#L112) | [`NativeClaimsUnlockCallback.t.sol`](NativeClaimsUnlockCallback.t.sol) `testFuzz_unlockCallback_burn_fails` | no |
| `unlockCallback_reverts_iff` | [NativeClaimsUnlockCallback.lean:119](../../formal/Refinement/Swarm/NativeClaimsUnlockCallback.lean#L119) | [`NativeClaimsUnlockCallback.t.sol`](NativeClaimsUnlockCallback.t.sol) `testFuzz_unlockCallback_reverts_iff` | no |
| `unlockCallback_ok_args` | [NativeClaimsUnlockCallback.lean:154](../../formal/Refinement/Swarm/NativeClaimsUnlockCallback.lean#L154) | [`NativeClaimsUnlockCallback.t.sol`](NativeClaimsUnlockCallback.t.sol) `testFuzz_unlockCallback_ok_args` | no |

### `Refinement/Swarm/RouterCancelWithSig.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `cancelWithSig_expired` | [RouterCancelWithSig.lean:107](../../formal/Refinement/Swarm/RouterCancelWithSig.lean#L107) | [`RouterCancelWithSig.t.sol`](RouterCancelWithSig.t.sol) `testFuzz_cancelWithSig_expired` | yes |
| `cancelWithSig_nonce_used` | [RouterCancelWithSig.lean:112](../../formal/Refinement/Swarm/RouterCancelWithSig.lean#L112) | [`RouterCancelWithSig.t.sol`](RouterCancelWithSig.t.sol) `testFuzz_cancelWithSig_nonce_used` | yes |
| `cancelWithSig_info_revert` | [RouterCancelWithSig.lean:118](../../formal/Refinement/Swarm/RouterCancelWithSig.lean#L118) | [`RouterCancelWithSig.t.sol`](RouterCancelWithSig.t.sol) `testFuzz_cancelWithSig_info_revert` | no |
| `cancelWithSig_invalid_sig` | [RouterCancelWithSig.lean:150](../../formal/Refinement/Swarm/RouterCancelWithSig.lean#L150) | [`RouterCancelWithSig.t.sol`](RouterCancelWithSig.t.sol) `testFuzz_cancelWithSig_invalid_sig` | no |
| `cancelWithSig_ok` | [RouterCancelWithSig.lean:163](../../formal/Refinement/Swarm/RouterCancelWithSig.lean#L163) | [`RouterCancelWithSig.t.sol`](RouterCancelWithSig.t.sol) `testFuzz_cancelWithSig_ok` | no |
| `cancelWithSig_ok_inv` | [RouterCancelWithSig.lean:178](../../formal/Refinement/Swarm/RouterCancelWithSig.lean#L178) | [`RouterCancelWithSig.t.sol`](RouterCancelWithSig.t.sol) `testFuzz_cancelWithSig_ok_inv` | no |
| `cancelWithSig_ok_state` | [RouterCancelWithSig.lean:224](../../formal/Refinement/Swarm/RouterCancelWithSig.lean#L224) | [`RouterCancelWithSig.t.sol`](RouterCancelWithSig.t.sol) `testFuzz_cancelWithSig_ok_state` | no |
| `cancelWithSig_reentry_reverts` | [RouterCancelWithSig.lean:254](../../formal/Refinement/Swarm/RouterCancelWithSig.lean#L254) | [`RouterCancelWithSig.t.sol`](RouterCancelWithSig.t.sol) `testFuzz_cancelWithSig_reentry_reverts` | with edits |
| `cancelWithSig_no_replay` | [RouterCancelWithSig.lean:266](../../formal/Refinement/Swarm/RouterCancelWithSig.lean#L266) | [`RouterCancelWithSig.t.sol`](RouterCancelWithSig.t.sol) `testFuzz_cancelWithSig_no_replay` | no |

Left out:

| Theorem | Lean | Reason |
|---|---|---|
| `ite_pair_fst` | [RouterCancelWithSig.lean:29](../../formal/Refinement/Swarm/RouterCancelWithSig.lean#L29) | model-only helper (simp lemma about the Lean monad / ABI encoding) |
| `ite_pair_snd` | [RouterCancelWithSig.lean:32](../../formal/Refinement/Swarm/RouterCancelWithSig.lean#L32) | model-only helper (simp lemma about the Lean monad / ABI encoding) |
| `tryRecover_preserves` | [RouterCancelWithSig.lean:38](../../formal/Refinement/Swarm/RouterCancelWithSig.lean#L38) | model-only helper (internal library `ECDSA.tryRecover` writes nothing; not externally callable; footprint covered by cancelWithSig_ok_state) |
| `tryRecover_5888_preserves` | [RouterCancelWithSig.lean:46](../../formal/Refinement/Swarm/RouterCancelWithSig.lean#L46) | model-only helper (internal `ECDSA.tryRecover` overload; covered by cancelWithSig_ok_state) |
| `isValidSignatureNow_preserves` | [RouterCancelWithSig.lean:56](../../formal/Refinement/Swarm/RouterCancelWithSig.lean#L56) | model-only helper (internal `SignatureChecker`; hypothesis on opaque `ext.fn_..._isValidERC1271SignatureNow`; covered by cancelWithSig_ok_state) |
| `hashTypedDataV4_preserves` | [RouterCancelWithSig.lean:71](../../formal/Refinement/Swarm/RouterCancelWithSig.lean#L71) | model-only helper (internal `_hashTypedDataV4`; hypothesis on opaque `ext.fn_MessageHashUtils_toTypedDataHash`) |
| `cancelWithSig_eq_prefix` | [RouterCancelWithSig.lean:127](../../formal/Refinement/Swarm/RouterCancelWithSig.lean#L127) | `*_run`-style unfolding into a Lean expression (observable content tested by _invalid_sig / _ok / _ok_inv) |
| `burn_frame` | [RouterCancelWithSig.lean:239](../../formal/Refinement/Swarm/RouterCancelWithSig.lean#L239) | model-only helper (about the Lean `burn` def; its EVM content is checked in cancelWithSig_ok_state) |

### `Refinement/Swarm/RouterDOMAIN_SEPARATOR.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `DOMAIN_SEPARATOR_spec` | [RouterDOMAIN_SEPARATOR.lean:29](../../formal/Refinement/Swarm/RouterDOMAIN_SEPARATOR.lean#L29) | [`RouterDOMAIN_SEPARATOR.t.sol`](RouterDOMAIN_SEPARATOR.t.sol) `testFuzz_DOMAIN_SEPARATOR_spec` | with edits |
| `DOMAIN_SEPARATOR_never_reverts` | [RouterDOMAIN_SEPARATOR.lean:40](../../formal/Refinement/Swarm/RouterDOMAIN_SEPARATOR.lean#L40) | [`RouterDOMAIN_SEPARATOR.t.sol`](RouterDOMAIN_SEPARATOR.t.sol) `testFuzz_DOMAIN_SEPARATOR_never_reverts` | yes |
| `DOMAIN_SEPARATOR_preserves` | [RouterDOMAIN_SEPARATOR.lean:45](../../formal/Refinement/Swarm/RouterDOMAIN_SEPARATOR.lean#L45) | [`RouterDOMAIN_SEPARATOR.t.sol`](RouterDOMAIN_SEPARATOR.t.sol) `testFuzz_DOMAIN_SEPARATOR_preserves` | with edits |

### `Refinement/Swarm/RouterFillFromPoolLiquidity.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `fillFromPoolLiquidity_eq` | [RouterFillFromPoolLiquidity.lean:28](../../formal/Refinement/Swarm/RouterFillFromPoolLiquidity.lean#L28) | [`RouterFillFromPoolLiquidity.t.sol`](RouterFillFromPoolLiquidity.t.sol) `testFuzz_fillFromPoolLiquidity_eq` | no |
| `fillFromPoolLiquidity_revert_iff` | [RouterFillFromPoolLiquidity.lean:37](../../formal/Refinement/Swarm/RouterFillFromPoolLiquidity.lean#L37) | [`RouterFillFromPoolLiquidity.t.sol`](RouterFillFromPoolLiquidity.t.sol) `testFuzz_fillFromPoolLiquidity_revert_iff` | no |
| `fillFromPoolLiquidity_ok_iff` | [RouterFillFromPoolLiquidity.lean:48](../../formal/Refinement/Swarm/RouterFillFromPoolLiquidity.lean#L48) | [`RouterFillFromPoolLiquidity.t.sol`](RouterFillFromPoolLiquidity.t.sol) `testFuzz_fillFromPoolLiquidity_ok_iff` | no |
| `fillFromPoolLiquidityPre_get` | [RouterFillFromPoolLiquidity.lean:58](../../formal/Refinement/Swarm/RouterFillFromPoolLiquidity.lean#L58) | [`RouterFillFromPoolLiquidity.t.sol`](RouterFillFromPoolLiquidity.t.sol) `testFuzz_fillFromPoolLiquidityPre_get` | no |

### `Refinement/Swarm/RouterMatchBook.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `matchBook_eq` | [RouterMatchBook.lean:27](../../formal/Refinement/Swarm/RouterMatchBook.lean#L27) | [`RouterMatchBook.t.sol`](RouterMatchBook.t.sol) `testFuzz_matchBook_eq` | no |
| `matchBook_revert_iff` | [RouterMatchBook.lean:34](../../formal/Refinement/Swarm/RouterMatchBook.lean#L34) | [`RouterMatchBook.t.sol`](RouterMatchBook.t.sol) `testFuzz_matchBook_revert_iff` | no |
| `matchBook_ok_iff` | [RouterMatchBook.lean:43](../../formal/Refinement/Swarm/RouterMatchBook.lean#L43) | [`RouterMatchBook.t.sol`](RouterMatchBook.t.sol) `testFuzz_matchBook_ok_iff` | no |

### `Refinement/Swarm/RouterSwapWithSig.lean`

| Theorem | Lean | Test | Halmos |
|---|---|---|---|
| `swapWithSig_native` | [RouterSwapWithSig.lean:47](../../formal/Refinement/Swarm/RouterSwapWithSig.lean#L47) | [`RouterSwapWithSig.t.sol`](RouterSwapWithSig.t.sol) `testFuzz_swapWithSig_native` | yes |
| `swapWithSig_noGrant` | [RouterSwapWithSig.lean:55](../../formal/Refinement/Swarm/RouterSwapWithSig.lean#L55) | [`RouterSwapWithSig.t.sol`](RouterSwapWithSig.t.sol) `testFuzz_swapWithSig_noGrant` | no |
| `swapWithSig_alreadyExecutor` | [RouterSwapWithSig.lean:64](../../formal/Refinement/Swarm/RouterSwapWithSig.lean#L64) | [`RouterSwapWithSig.t.sol`](RouterSwapWithSig.t.sol) `testFuzz_swapWithSig_alreadyExecutor` | no |
| `swapWithSig_isExecutor_revert` | [RouterSwapWithSig.lean:75](../../formal/Refinement/Swarm/RouterSwapWithSig.lean#L75) | [`RouterSwapWithSig.t.sol`](RouterSwapWithSig.t.sol) `testFuzz_swapWithSig_isExecutor_revert` | no |
| `swapWithSig_grant` | [RouterSwapWithSig.lean:88](../../formal/Refinement/Swarm/RouterSwapWithSig.lean#L88) | [`RouterSwapWithSig.t.sol`](RouterSwapWithSig.t.sol) `testFuzz_swapWithSig_grant` | no |
| `swapWithSig_ok_input` | [RouterSwapWithSig.lean:107](../../formal/Refinement/Swarm/RouterSwapWithSig.lean#L107) | [`RouterSwapWithSig.t.sol`](RouterSwapWithSig.t.sol) `testFuzz_swapWithSig_ok_input` | no |
| `swapWithSigPre_get` | [RouterSwapWithSig.lean:116](../../formal/Refinement/Swarm/RouterSwapWithSig.lean#L116) | [`RouterSwapWithSig.t.sol`](RouterSwapWithSig.t.sol) `testFuzz_swapWithSigPre_get` | no |
| `swapWithSigPre_user` | [RouterSwapWithSig.lean:124](../../formal/Refinement/Swarm/RouterSwapWithSig.lean#L124) | [`RouterSwapWithSig.t.sol`](RouterSwapWithSig.t.sol) `testFuzz_swapWithSigPre_user` | no |
| `swapWithSigPre_filler` | [RouterSwapWithSig.lean:130](../../formal/Refinement/Swarm/RouterSwapWithSig.lean#L130) | [`RouterSwapWithSig.t.sol`](RouterSwapWithSig.t.sol) `testFuzz_swapWithSigPre_filler` | no |
