// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {FormalSlotsB} from "./FormalSlotsB.sol";
import {AsyncFiller} from "@async-swap/libraries/AsyncFiller.sol";
import {AsyncMatching} from "@async-swap/libraries/AsyncMatching.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

/// @notice Bytecode checks of `formal/Refinement/Swarm/AsyncMatchingSetOrderingModeDirect.lean`: a direct CALL to the
///         linked `AsyncMatching` library's `setOrderingMode` cannot change any of the hook's books.
contract AsyncMatchingSetOrderingModeDirectFormalTest is FormalSlotsB {
    address lib;

    function setUp() public override {
        super.setUp();
        // Find the library account the hook actually DELEGATECALLs (the linked AsyncMatching).
        vm.startStateDiffRecording();
        hook.orderingMode(poolId); // no library call; warm-up
        hook.setOrderingMode(key, AsyncFiller.OrderingMode.FIFO);
        VmSafe.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        for (uint256 i; i < acc.length; ++i) {
            if (acc[i].kind == VmSafe.AccountAccessKind.DelegateCall) lib = acc[i].account;
        }
        require(lib != address(0) && lib.code.length > 0, "linked library not found");
    }

    /// @notice formal/Refinement/Swarm/AsyncMatchingSetOrderingModeDirect.lean:52 — a direct call to the library, with
    ///         any storage pointer / poolId / mode, leaves the hook's storage (every pool's orderingMode) unchanged.
    function testFuzz_asyncMatching_setOrderingMode_direct_noPoolChange(
        address caller,
        uint256 bookPtr,
        bytes32 pid,
        bool m,
        bool pointAtHookBook
    ) public {
        if (pointAtHookBook) bookPtr = uint256(_bookSlot(poolId));
        bytes32 hookBook = _loadHook(_bookSlot(poolId));
        bytes32 fuzzBook = _loadHook(bytes32(bookPtr));
        uint8 modeBefore = uint8(hook.orderingMode(poolId));
        vm.record();
        vm.prank(caller);
        (bool ok,) = lib.call(
            abi.encodeWithSelector(AsyncMatching.setOrderingMode.selector, bookPtr, PoolId.wrap(pid), m ? 1 : 0)
        );
        ok; // success or not, the hook's state must be untouched
        _assertNoHookWrites();
        assertEq(_loadHook(_bookSlot(poolId)), hookBook);
        assertEq(_loadHook(bytes32(bookPtr)), fuzzBook);
        assertEq(uint8(hook.orderingMode(poolId)), modeBefore);
    }
}
