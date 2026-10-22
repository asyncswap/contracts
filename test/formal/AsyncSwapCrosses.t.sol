// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {AsyncBookHarness, FormalRefA} from "./FormalHarnessesA.sol";
import {AsyncFiller} from "@async-swap/libraries/AsyncFiller.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {FullMath} from "v4-core/libraries/FullMath.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

/// @notice Bytecode checks of `formal/Refinement/Swarm/AsyncSwapCrosses.lean`. The private
///         `AsyncMatching._crosses(buyKey, sellKey, buy, sell)` is observed through the linked
///         `AsyncMatching.matchBook(maxMatches = 1)` on a harness book (FIFO) holding one bid at key `bk`
///         and one ask at key `sk`. The ask's stored `isBuy` is then set to true, so `_matchPair` returns
///         false right after reading the two orders' `isBuy` word (slot 6 of `OrderInfo`): nothing is
///         written either way, and that slot is read iff `_crosses` returned true (it is read nowhere else
///         before). A revert inside `_crosses` (`Math.mulDiv`) is matchBook's revert.
///         `_matchPair` reads `isBuy` only when both `amountIn`s are nonzero, so the returned value is
///         observed for nonzero `amountIn`s (on the hook an order with `amountIn = 0` does not exist);
///         reverts and the frame are checked for all inputs.
contract AsyncSwapCrossesFormalTest is FormalRefA {
    bytes32 constant BID = keccak256("bid");
    bytes32 constant ASK = keccak256("ask");

    AsyncBookHarness h;
    PoolKey key;

    struct Amounts {
        uint256 bIn;
        uint256 bOut;
        uint256 sIn;
        uint256 sOut;
    }

    function setUp() public {
        h = new AsyncBookHarness();
        key = PoolKey(Currency.wrap(address(1)), Currency.wrap(address(2)), 0x800000, 60, IHooks(address(0)));
    }

    function _order(bool isBuy, uint128 price, uint256 amountIn, uint256 amountOutMin, uint64 seq)
        internal
        pure
        returns (AsyncFiller.OrderInfo memory o)
    {
        o.owner = address(0xA11CE);
        o.amountIn = amountIn;
        o.amountOutMin = amountOutMin;
        o.price = price;
        o.isBuy = isBuy;
        o.sequence = seq;
        o.priorityFeeEscrowed = true;
    }

    function _book(uint128 bk, uint128 sk, Amounts memory a) internal {
        h.setOrder(BID, _order(true, bk, a.bIn, a.bOut, 1));
        h.append(BID);
        h.setOrder(ASK, _order(false, sk, a.sIn, a.sOut, 2));
        h.append(ASK);
        h.setIsBuy(ASK, true);
    }

    /// @dev Runs matchBook once. Returns (reverted, revert data, crosses-was-true).
    function _run() internal returns (bool reverted, bytes memory ret, bool crossed) {
        bytes32 isBuyWord = bytes32(uint256(h.orderSlot(BID)) + 6);
        vm.record();
        bool ok;
        (ok, ret) = address(h).call(abi.encodeCall(h.matchBook, (key, 1)));
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(h));
        reverted = !ok;
        if (ok) {
            assertEq(abi.decode(ret, (uint8)), 0, "no match executed");
            assertEq(writes.length, 0, "_crosses writes nothing");
        }
        for (uint256 i; i < reads.length; ++i) {
            if (reads[i] == isBuyWord) crossed = true;
        }
    }

    function _observable(Amounts memory a) internal pure returns (bool) {
        return a.bIn != 0 && a.sIn != 0;
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapCrosses.lean:21 — full run: distinct keys return bk > sk; equal
    ///         keys panic 0x12 if sell.amountOutMin = 0, else return mulDiv(buy.in, sell.in, sell.out) >= buy.out
    ///         when the quotient fits, else revert MathOverflowedMulDiv.
    function testFuzz_finding_crosses_run(uint128 bk, uint128 sk, Amounts memory a, bool sameKey, bool zeroDen) public {
        if (sameKey) sk = bk;
        if (zeroDen) a.sOut = 0;
        _book(bk, sk, a);
        (bool reverted, bytes memory ret, bool crossed) = _run();
        if (bk != sk) {
            assertFalse(reverted, "distinct keys never revert");
            if (_observable(a)) assertEq(crossed, bk > sk);
        } else if (a.sOut == 0) {
            assertTrue(reverted);
            assertEq(ret, _panic(0x12), "panic 0x12");
        } else if (_quotientFits(a.bIn, a.sIn, a.sOut)) {
            assertFalse(reverted);
            if (_observable(a)) assertEq(crossed, FullMath.mulDiv(a.bIn, a.sIn, a.sOut) >= a.bOut);
        } else {
            assertTrue(reverted);
            assertEq(ret, abi.encodeWithSelector(Math.MathOverflowedMulDiv.selector));
        }
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapCrosses.lean:42 — distinct keys: never reverts, returns
    ///         buyKey > sellKey, whatever the orders hold (zero denominators included).
    function testFuzz_crosses_ne_any(uint128 bk, uint128 sk, Amounts memory a) public {
        vm.assume(bk != sk);
        _book(bk, sk, a);
        (bool reverted,, bool crossed) = _run();
        assertFalse(reverted);
        if (_observable(a)) assertEq(crossed, bk > sk);
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapCrosses.lean:49 — equal keys and sell.amountOutMin = 0: reverts
    ///         with panic 0x12 (whatever the amounts).
    function testFuzz_finding_crosses_reverts_div0(uint128 k, uint256 bIn, uint256 bOut, uint256 sIn) public {
        _book(k, k, Amounts(bIn, bOut, sIn, 0));
        (bool reverted, bytes memory ret,) = _run();
        assertTrue(reverted);
        assertEq(ret, _panic(0x12), "panic 0x12");
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapCrosses.lean:49 — fixed counterexample to crosses_reverts_div0:
    ///         equal keys, sell.amountOutMin = 0 and buy.amountIn * sell.amountIn >= 2^256. The model predicts
    ///         panic 0x12; OpenZeppelin 5.0's mulDiv reverts MathOverflowedMulDiv (it checks
    ///         `denominator <= prod1` before dividing).
    function test_finding_crosses_reverts_div0_counterexample() public {
        _book(1, 1, Amounts(2 ** 128, 1, 2 ** 128, 0));
        (bool reverted, bytes memory ret,) = _run();
        assertTrue(reverted);
        assertEq(ret, _panic(0x12), "panic 0x12");
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapCrosses.lean:56 — equal keys, sell.amountOutMin != 0 and
    ///         buy.amountIn * sell.amountIn / sell.amountOutMin >= 2^256: reverts MathOverflowedMulDiv.
    function testFuzz_crosses_reverts_overflow(uint128 k, Amounts memory a) public {
        vm.assume(a.sOut != 0 && !_quotientFits(a.bIn, a.sIn, a.sOut));
        _book(k, k, a);
        (bool reverted, bytes memory ret,) = _run();
        assertTrue(reverted);
        assertEq(ret, abi.encodeWithSelector(Math.MathOverflowedMulDiv.selector));
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapCrosses.lean:68 — with storage-reading getters, a successful
    ///         _crosses leaves the state unchanged.
    function testFuzz_crosses_frame(uint128 bk, uint128 sk, Amounts memory a, bool sameKey) public {
        if (sameKey) sk = bk;
        _book(bk, sk, a);
        _run(); // asserts no SSTORE whenever the call succeeds
    }
}
