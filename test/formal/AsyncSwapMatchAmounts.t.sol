// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {FormalMatchD} from "./FormalMatchD.sol";
import {AsyncFiller} from "@async-swap/libraries/AsyncFiller.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {stdError} from "forge-std/StdError.sol";

/// @notice Calls OpenZeppelin's real `Math.mulDiv` (internal), compiled with the project's settings.
contract MathMulDivHarness {
    function floor(uint256 x, uint256 y, uint256 d) external pure returns (uint256) {
        return Math.mulDiv(x, y, d);
    }

    function ceil(uint256 x, uint256 y, uint256 d) external pure returns (uint256) {
        return Math.mulDiv(x, y, d, Math.Rounding.Ceil);
    }
}

/// @notice Bytecode checks of `formal/Refinement/Swarm/AsyncSwapMatchAmounts.lean`.
///         `_matchAmounts` is private: it runs once per `_matchPair`, which `matchBook(key, 1)` reaches
///         exactly once on a crossed book of one resting sell and one resting buy (`FormalMatchD`).
///         Its result is observable as the `AsyncOrdersMatched` amounts (non-zero result) or as a
///         `false` `_matchPair` with no effect (a zero amount). `floor_run` / `ceil_run` are about the
///         model's `mulDivFloor` / `mulDivRnd`, i.e. OpenZeppelin `Math.mulDiv`, checked on a harness.
contract AsyncSwapMatchAmountsFormalTest is FormalMatchD {
    MathMulDivHarness mh;

    function setUp() public override {
        super.setUp();
        mh = new MathMulDivHarness();
    }

    // ------------------------------------------------------------------ Math.mulDiv

    /// @dev Full 512-bit product `x·y = hi·2^256 + lo`.
    function _mul512(uint256 x, uint256 y) internal pure returns (uint256 hi, uint256 lo) {
        assembly {
            let mm := mulmod(x, y, not(0))
            lo := mul(x, y)
            hi := sub(sub(mm, lo), lt(mm, lo))
        }
    }

    /// @dev Checks `r = ⌊x·y/d⌋` exactly: `r·d = x·y - (x·y mod d)` as 512-bit numbers.
    function _assertFloor(uint256 x, uint256 y, uint256 d, uint256 r) internal pure {
        (uint256 hi, uint256 lo) = _mul512(x, y);
        uint256 rem = mulmod(x, y, d);
        (uint256 hi2, uint256 lo2) = _mul512(r, d);
        uint256 borrow = lo < rem ? 1 : 0;
        assertEq(lo2, lo - rem, "floor: low word");
        assertEq(hi2, hi - borrow, "floor: high word");
    }

    /// @dev Biases `d` to 0 and to small values so the guard branches are hit.
    function _den(uint256 d, uint8 sel) internal pure returns (uint256) {
        if (sel % 4 == 0) return 0;
        if (sel % 4 == 1) return d % 1000;
        return d;
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapMatchAmounts.lean:27 — `mulDivFloor x y d` (OZ `Math.mulDiv`) is panic 0x12 when d = 0, `MathOverflowedMulDiv` when x·y/d ≥ 2^256, else `x·y/d`.
    function testFuzz_finding_floor_run(uint256 x, uint256 y, uint256 d, uint8 sel) public {
        d = _den(d, sel);
        (uint256 hi,) = _mul512(x, y);
        if (d == 0) {
            vm.expectRevert(stdError.divisionError);
            mh.floor(x, y, d);
        } else if (hi >= d) {
            // x·y/d ≥ 2^256  ⇔  x·y ≥ d·2^256  ⇔  hi ≥ d
            vm.expectRevert(Math.MathOverflowedMulDiv.selector);
            mh.floor(x, y, d);
        } else {
            _assertFloor(x, y, d, mh.floor(x, y, d));
        }
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapMatchAmounts.lean:33 — `mulDivRnd x y d 1` (OZ `Math.mulDiv(.., Ceil)`) is panic 0x12 when d = 0, `MathOverflowedMulDiv` when x·y/d ≥ 2^256, the floor when exact, else floor + 1 (panic 0x11 if that overflows).
    function testFuzz_finding_ceil_run(uint256 x, uint256 y, uint256 d, uint8 sel) public {
        d = _den(d, sel);
        (uint256 hi,) = _mul512(x, y);
        if (d == 0) {
            vm.expectRevert(stdError.divisionError);
            mh.ceil(x, y, d);
        } else if (hi >= d) {
            vm.expectRevert(Math.MathOverflowedMulDiv.selector);
            mh.ceil(x, y, d);
        } else {
            uint256 f = mh.floor(x, y, d);
            _assertFloor(x, y, d, f);
            if (mulmod(x, y, d) == 0) {
                assertEq(mh.ceil(x, y, d), f, "exact: floor");
            } else if (f < type(uint256).max) {
                assertEq(mh.ceil(x, y, d), f + 1, "inexact: floor + 1");
            } else {
                vm.expectRevert(stdError.arithmeticError);
                mh.ceil(x, y, d);
            }
        }
    }

    // ------------------------------------------------------------------ _matchAmounts through matchBook

    /// @dev `_matchAmounts(sell, buy, rb)` as `_matchPair` runs it: when the pair crosses (so `_matchPair`
    ///      runs) the call never reverts; a non-zero spec result is exactly the `AsyncOrdersMatched`
    ///      amounts; a zero spec amount gives `false` with no effect at all.
    function _checkSpec(uint256[6] memory s, bool rb, uint256 extra) internal returns (Run memory r) {
        Case memory c = _mkCase(s, (rb ? 1 : 0) | (extra & ~uint256(1)));
        assertEq(_makerBuy(_info(c.pid, c.buyId), _info(c.pid, c.sellId)), rb, "resting side");
        vm.record();
        r = _exec(c);
        (, bytes32[] memory writes) = vm.accesses(address(hook));
        if (!r.crosses) {
            assertEq(r.matched, 0, "no cross: no match");
            return r;
        }
        if (r.asset == 0 || r.quote == 0) {
            assertEq(r.matched, 0, "zero spec amount: _matchPair is false");
            assertEq(r.ops.length, 0, "zero spec amount: no transfer, no event");
            assertEq(writes.length, 0, "zero spec amount: no hook SSTORE");
        } else {
            assertEq(r.matched, 1, "non-zero spec amounts: _matchPair is true");
            Op memory last = r.ops[r.ops.length - 1];
            assertEq(last.kind, OP_MATCHED, "match event");
            assertEq(last.amount, r.asset, "assetAmount = spec");
            assertEq(last.amount2, r.quote, "quoteAmount = spec");
        }
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapMatchAmounts.lean:98 — resting buy: a successful `_matchAmounts` leaves the world unchanged and returns `AsyncSwap.matchAmounts sell buy true`.
    function testFuzz_ok_restingBuy(uint256[6] memory s, uint8 flags) public {
        _checkSpec(s, true, flags);
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapMatchAmounts.lean:116 — resting sell: a successful `_matchAmounts` leaves the world unchanged and returns `AsyncSwap.matchAmounts sell buy false`.
    function testFuzz_ok_restingSell(uint256[6] memory s, uint8 flags) public {
        _checkSpec(s, false, flags);
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapMatchAmounts.lean:138 — every successful `_matchAmounts` run leaves the world unchanged and returns exactly the spec `AsyncSwap.matchAmounts` amounts.
    function testFuzz_matchAmounts_ok(uint256[6] memory s, bool rb, uint8 flags) public {
        _checkSpec(s, rb, flags);
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapMatchAmounts.lean:157 — a non-zero result spends at most each escrow and honours both limit prices.
    function testFuzz_matchAmounts_ok_sound(uint256[6] memory s, bool rb, uint8 flags) public {
        Run memory r = _checkSpec(s, rb, flags);
        if (r.matched == 0) return;
        Op memory m = r.ops[r.ops.length - 1];
        assertLe(m.amount, r.sell0.amountIn, "asset <= sell escrow");
        assertLe(m.amount2, r.buy0.amountIn, "quote <= buy escrow");
        assertLe(m.amount * r.sell0.amountOutMin, m.amount2 * r.sell0.amountIn, "seller limit");
        assertLe(m.amount2 * r.buy0.amountOutMin, m.amount * r.buy0.amountIn, "buyer limit");
    }

    /// @dev Crossed pair with strictly ordered keys (bid > ask), so `_crosses` returns without
    ///      arithmetic and `_matchPair` → `_matchAmounts` runs; then the stored amounts are replaced.
    function _zeroRestingMin(uint256[6] memory s, bool rb, uint256 sellIn, uint256 buyIn)
        internal
        returns (Case memory c, bool reached)
    {
        c = _mkCase(s, rb ? 1 : 0);
        AsyncFiller.OrderInfo memory b = _info(c.pid, c.buyId);
        AsyncFiller.OrderInfo memory sl = _info(c.pid, c.sellId);
        if (b.price <= sl.price) return (c, false);
        _storeWord(c.pid, c.sellId, 1, bound(sellIn, 1, type(uint256).max));
        _storeWord(c.pid, c.buyId, 1, bound(buyIn, 1, type(uint256).max));
        _storeWord(c.pid, rb ? c.buyId : c.sellId, 2, 0);
        reached = true;
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapMatchAmounts.lean:175 — with the buyer resting and `buy.amountOutMin = 0` (any amounts), `_matchAmounts` reverts with panic 0x12.
    function testFuzz_finding_matchAmounts_reverts_restingBuy(uint256[6] memory s, uint256 sellIn, uint256 buyIn)
        public
    {
        (Case memory c, bool reached) = _zeroRestingMin(s, true, sellIn, buyIn);
        if (!reached) return;
        vm.expectRevert(stdError.divisionError);
        _run(_matchCalls(c.k));
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapMatchAmounts.lean:183 — with the seller resting and `sell.amountOutMin = 0` (any amounts), `_matchAmounts` reverts with panic 0x12.
    function testFuzz_finding_matchAmounts_reverts_restingSell(uint256[6] memory s, uint256 sellIn, uint256 buyIn)
        public
    {
        (Case memory c, bool reached) = _zeroRestingMin(s, false, sellIn, buyIn);
        if (!reached) return;
        vm.expectRevert(stdError.divisionError);
        _run(_matchCalls(c.k));
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapMatchAmounts.lean:191 — resting buy, uint128 amounts, `buy.amountOutMin > 0`: `_matchAmounts` never reverts.
    function testFuzz_noerr_restingBuy(uint256[6] memory s, uint8 flags) public {
        _checkSpec(s, true, flags);
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapMatchAmounts.lean:228 — resting sell, uint128 amounts, `sell.amountOutMin > 0`: `_matchAmounts` never reverts.
    function testFuzz_noerr_restingSell(uint256[6] memory s, uint8 flags) public {
        _checkSpec(s, false, flags);
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapMatchAmounts.lean:268 — uint128 amounts and a positive resting `amountOutMin`: `_matchAmounts` succeeds with the spec amounts and an unchanged world.
    function testFuzz_matchAmounts_succeeds(uint256[6] memory s, bool rb, uint8 flags) public {
        _checkSpec(s, rb, flags);
    }
}
