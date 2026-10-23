// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;
import {FormalMatchD} from "../harness/FormalMatchD.sol";

contract EligibleRemainderTest is FormalMatchD {
    function test_refreshWhenPriceKeyAndFeeAreUnchanged() public {
        uint256 size = 1e21;
        bytes32 first = _rest(key, alice, true, size, 3, 0);
        _rest(key, bob, false, 1, size / 3, 0);
        _run(_matchCalls(key));
        uint256 remaining = size - size / 3;
        assertEq(_info(poolId, first).amountIn, remaining);
        assertEq(_info(poolId, first).amountOutMin, 3);
        assertEq(_info(poolId, first).priorityFee, 0);
        assertEq(_info(poolId, first).price, 1);
        // Ceiling increased its exact ask despite an unchanged bucket, rank and sequence.
        bytes32 eligible = _rest(key, alice, true, size, 3, 0);
        bytes32 buy = _rest(key, bob, false, 1, size / 3, 0);
        vm.recordLogs();
        _run(_matchCalls(key));
        Op[] memory ops = _ops(vm.getRecordedLogs());
        Op memory trade = ops[ops.length - 1];
        assertEq(trade.kind, OP_MATCHED);
        assertEq(trade.tag, eligible);
        assertEq(trade.tag2, buy);
        assertEq(_info(poolId, first).amountIn, remaining);
    }
}
