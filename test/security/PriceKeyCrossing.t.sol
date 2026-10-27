// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {SetupHook} from "../SetupHook.t.sol";
import {AsyncSwap} from "@async-swap/AsyncSwap.sol";
import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @notice Crossing is decided exactly. Book price keys are truncated WAD ratios, so two orders
///         can share a key without crossing; `AsyncMatching._crosses` resolves equal keys with a
///         full-precision cross-multiply. An equal-key pair that does not cross rests; a later better-key incoming
///         order can still trade, and an exact tie executes. Same-key head blocking is
///         reproduced separately in CoarsePriceBlocking.t.sol. See
///         docs/price-key-crossing.md.
contract PriceKeyCrossingTest is SetupHook {
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

    /// @dev The deposit whose net of the 0.03% input fee is exactly `net`: the book prices and
    ///      crosses orders on their net input, so each pair below is built on net amounts.
    function _gross(uint256 net) internal pure returns (uint256 g) {
        g = net * 10_000 / 9997;
        while (g - Math.mulDiv(g, 3, 10_000, Math.Rounding.Ceil) < net) g++;
        while (g - Math.mulDiv(g, 3, 10_000, Math.Rounding.Ceil) > net) g--;
        require(g - Math.mulDiv(g, 3, 10_000, Math.Rounding.Ceil) == net, "no deposit nets to this amount");
    }

    /// @dev Rest an order whose net input is `net`.
    function _submit(address o, bool zeroForOne, uint256 net, uint256 amtOutMin) internal {
        uint256 amtIn = _gross(net);
        AsyncOrder memory ord = AsyncOrder(key, o, zeroForOne, amtIn, amtOutMin, 100_000, 2 ** 96, bytes32(0));
        bytes memory data = abi.encode(AsyncSwap.UserParams(o, address(router), amtOutMin, 100_000));
        vm.startPrank(o);
        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        router.swap(ord, data);
        vm.stopPrank();
    }

    /// @dev Live net input of the order `_submit(o, zeroForOne, net, amtOutMin)` created.
    function _remaining(address o, bool zeroForOne, uint256 net, uint256 amtOutMin) internal view returns (uint256) {
        bytes32 id = _orderIdFor(o, zeroForOne, _expectedSalt(o, _gross(net), amtOutMin));
        return hook.asyncOrder(poolId, id);
    }

    // currency1 is the numeraire. Buyer: zeroForOne=false (pays currency1). Seller: zeroForOne=true.

    /// @dev An equal-key, non-crossing pair does not block this later incoming sell
    ///      with a strictly better price key. It does not test same-key orders hidden behind a head.
    function test_equalKeyNonCrossingPairDoesNotBlockMatching() public {
        // Buy and sell whose keys both truncate to 3000000000000000001 but do NOT actually cross.
        _submit(alice, false, 3e18 + 1, 1e18); // resting buy  B1 (best bid, key K)
        _submit(bob, true, 1e18 - 1, 3e18 - 2); // resting sell S1 (best ask, key K) -- does not cross B1

        // Both rest, neither matched the other (no fabricated trade).
        assertEq(_remaining(alice, false, 3e18 + 1, 1e18), 3e18 + 1, "B1 untouched by the collision");
        assertEq(_remaining(bob, true, 1e18 - 1, 3e18 - 2), 1e18 - 1, "S1 untouched by the collision");

        // A genuinely crossing sell (ask key 2e18 < K) arrives and MUST match B1.
        _submit(bob, true, 1e18, 2e18); // S2

        assertEq(_remaining(alice, false, 3e18 + 1, 1e18), 0, "B1 fully matched against S2");
        assertEq(_remaining(bob, true, 1e18, 2e18), 0, "S2 fully consumed");
        assertEq(_remaining(bob, true, 1e18 - 1, 3e18 - 2), 1e18 - 1, "S1 still resting, correctly left alone");
    }

    /// @dev matchBook on a book holding only an equal-key, non-crossing pair returns 0 and leaves
    ///      both orders intact.
    function test_matchBookMakesNoFalseMatch() public {
        _submit(alice, false, 3e18 + 1, 1e18);
        _submit(bob, true, 1e18 - 1, 3e18 - 2);

        uint8 matched = hook.matchBook(key, 8);
        assertEq(matched, 0, "no match: the pair does not truly cross");
        assertEq(_remaining(alice, false, 3e18 + 1, 1e18), 3e18 + 1, "buy intact");
        assertEq(_remaining(bob, true, 1e18 - 1, 3e18 - 2), 1e18 - 1, "sell intact");
    }

    /// @dev An exact tie (buyIn*sellIn == sellOut*buyOut) at equal keys must execute rather
    ///      than resting.
    function test_exactTieExecutes() public {
        _submit(alice, false, 3e18, 1e18); // buy  key 3e18
        _submit(bob, true, 1e18, 3e18); // sell key 3e18, exact tie with the buy

        assertEq(_remaining(alice, false, 3e18, 1e18), 0, "buy matched on the exact tie");
        assertEq(_remaining(bob, true, 1e18, 3e18), 0, "sell matched on the exact tie");
    }
}
