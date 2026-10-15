// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {SetupHook} from "../SetupHook.t.sol";
import {AsyncSwap} from "@async-swap/AsyncSwap.sol";
import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";

/// @notice M01 (Medium) regression: price-key collisions must not wedge the matching engine.
///
/// Crossing was decided by comparing two uint128 WAD price keys, each a truncating mulDiv in
/// `AsyncFiller._priceKey`. Two orders can round to the SAME key while, at full precision, they
/// do not cross (buyIn*sellIn < sellOut*buyOut). `_matchAmounts` then correctly returns (0,0) and
/// `_matchPair` returns false, but both `matchIncoming` and `matchBook` used to `break` on that
/// result. Because the colliding pair sits at the best bid AND best ask, the break permanently
/// stalled all automatic matching at the top of book.
///
/// Fix: `AsyncMatching._crosses` trusts the keys only when strictly ordered (truncation cannot
/// invert a strict inequality) and decides the ambiguous equal-key case with a full-precision
/// cross-multiply, treating the exact tie as a cross. A pair that only collides-by-key is then
/// correctly seen as non-crossing (so it never blocks genuinely crossing orders), and every real
/// cross — including the exact tie — executes.
contract M01_PriceKeyCollisionStallTest is SetupHook {
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    event AsyncOrdersMatched(
        bytes32 indexed poolId, bytes32 indexed sellOrderId, bytes32 indexed buyOrderId, uint256 a, uint256 q
    );

    function setUp() public override {
        super.setUp();
        topUp(alice, 100 ether);
        topUp(bob, 100 ether);
    }

    function _submit(address o, bool zeroForOne, uint256 amtIn, uint256 amtOutMin) internal {
        AsyncOrder memory ord = AsyncOrder(key, o, zeroForOne, amtIn, amtOutMin, 0, 2 ** 96, bytes32(0));
        bytes memory data = abi.encode(AsyncSwap.UserParams(o, address(router), amtOutMin, 0));
        vm.startPrank(o);
        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        router.swap(ord, data);
        vm.stopPrank();
    }

    function _remaining(address o, bool zeroForOne, uint256 amtIn, uint256 amtOutMin) internal view returns (uint256) {
        bytes32 id = _orderIdFor(o, zeroForOne, _expectedSalt(o, amtIn, amtOutMin));
        return hook.asyncOrder(poolId, id);
    }

    // currency1 is the numeraire. Buyer: zeroForOne=false (pays currency1). Seller: zeroForOne=true.

    /// @dev A key-colliding, non-crossing pair at the top of book must NOT block a genuinely
    ///      crossing order from matching. Previously the pair wedged the engine.
    function test_M01_keyCollisionDoesNotWedgeBook() public {
        // Buy and sell whose keys both truncate to 3000000000000000001 but do NOT actually cross.
        _submit(alice, false, 3e18 + 1, 1e18); // resting buy  B1 (best bid, key K)
        _submit(bob, true, 1e18 - 1, 3e18 - 2); // resting sell S1 (best ask, key K) -- does not cross B1

        // Both rest, neither matched the other (no fabricated trade).
        assertEq(_remaining(alice, false, 3e18 + 1, 1e18), 3e18 + 1, "B1 untouched by the collision");
        assertEq(_remaining(bob, true, 1e18 - 1, 3e18 - 2), 1e18 - 1, "S1 untouched by the collision");

        // A genuinely crossing sell (ask key 2e18 < K) arrives and MUST match B1.
        _submit(bob, true, 1e18, 2e18); // S2

        assertEq(_remaining(alice, false, 3e18 + 1, 1e18), 0, "B1 fully matched against S2 (book not wedged)");
        assertEq(_remaining(bob, true, 1e18, 2e18), 0, "S2 fully consumed");
        assertEq(_remaining(bob, true, 1e18 - 1, 3e18 - 2), 1e18 - 1, "S1 still resting, correctly left alone");
    }

    /// @dev matchBook on a book holding only a key-colliding non-crossing pair returns 0 and leaves
    ///      both orders intact. This is correct (they do not cross), not a wedge.
    function test_M01_matchBookMakesNoFalseMatch() public {
        _submit(alice, false, 3e18 + 1, 1e18);
        _submit(bob, true, 1e18 - 1, 3e18 - 2);

        uint8 matched = hook.matchBook(key, 8);
        assertEq(matched, 0, "no match: the pair does not truly cross");
        assertEq(_remaining(alice, false, 3e18 + 1, 1e18), 3e18 + 1, "buy intact");
        assertEq(_remaining(bob, true, 1e18 - 1, 3e18 - 2), 1e18 - 1, "sell intact");
    }

    /// @dev An exact tie (buyIn*sellIn == sellOut*buyOut) at equal keys must execute rather
    ///      than resting.
    function test_M01_exactTieExecutes() public {
        _submit(alice, false, 3e18, 1e18); // buy  key 3e18
        _submit(bob, true, 1e18, 3e18); // sell key 3e18, exact tie with the buy

        assertEq(_remaining(alice, false, 3e18, 1e18), 0, "buy matched on the exact tie");
        assertEq(_remaining(bob, true, 1e18, 3e18), 0, "sell matched on the exact tie");
    }
}
