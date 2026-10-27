// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;
import {FormalMatchD} from "../formal/FormalMatchD.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @dev Orders are built on net terms: each deposit nets exactly the stated input after the maker's
///      0.03% fee, so the book sees the same amounts and prices as before the fee.
contract EligibleRemainderTest is FormalMatchD {
    function _depositForNet(uint256 net) internal pure returns (uint256 g) {
        g = net * 10_000 / 9997;
        while (g - Math.mulDiv(g, 3, 10_000, Math.Rounding.Ceil) < net) g++;
        while (g - Math.mulDiv(g, 3, 10_000, Math.Rounding.Ceil) > net) g--;
        require(g - Math.mulDiv(g, 3, 10_000, Math.Rounding.Ceil) == net, "no deposit nets to this amount");
    }

    function test_refreshWhenPriceKeyAndFeeAreUnchanged() public {
        // A small fill of a large ask: its bid share rounds to zero and the ceiling nudges its
        // exact ask by about 3e-13, inside its tick.
        uint256 size = 1e30;
        uint256 minimum = 3e12 + 1;
        uint256 quote = 3e6;
        uint256 asset = quote * size / minimum;
        bytes32 first = _rest(key, alice, true, _depositForNet(size), minimum, 100_000);
        uint128 tick = _info(poolId, first).price;
        _rest(key, bob, false, _depositForNet(quote), asset, 100_000);
        _run(_matchCalls(key));
        uint256 remaining = size - asset;
        assertEq(_info(poolId, first).amountIn, remaining);
        assertGt(_info(poolId, first).amountOutMin * size, minimum * remaining, "ceiling raised the exact ask");
        assertEq(_info(poolId, first).priorityFee, 100_000, "bid unchanged");
        assertEq(_info(poolId, first).price, tick, "same tick");
        // The raised exact ask no longer crosses an identical buy, though its tick, rank and
        // sequence are unchanged; a fresh ask at the original price does.
        bytes32 eligible = _rest(key, alice, true, _depositForNet(size), minimum, 100_000);
        bytes32 buy = _rest(key, bob, false, _depositForNet(quote), asset, 100_000);
        vm.recordLogs();
        _run(_matchCalls(key));
        Op[] memory ops = _ops(vm.getRecordedLogs());
        Op memory trade = _matchedOp(ops);
        assertEq(trade.kind, OP_MATCHED);
        assertEq(trade.tag, eligible);
        assertEq(trade.tag2, buy);
        assertEq(_info(poolId, first).amountIn, remaining);
    }
}
