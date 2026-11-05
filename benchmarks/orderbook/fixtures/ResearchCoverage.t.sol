// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {ResearchLiveTest} from "./ResearchLive.t.sol";
import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";
import {ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";

/// @dev Extends the original public-API fixtures with mirrored books, crowded ticks and active LPs.
contract ResearchCoverageTest is ResearchLiveTest {
    function _bids(uint256 n) internal {
        for (uint256 i; i < n; ++i) {
            address actor = address(uint160(0x10000 + i));
            _fund(actor);
            orders.push(_submit(_order(actor, false, 2_000e6 - i * 1e6, 1 ether)));
        }
        _fund(extra);
        AsyncOrder memory fresh = _order(extra, false, 2_001e6, 1 ether);
        AsyncOrder memory expected = fresh;
        expected.salt = _expectedSalt(extra, fresh.amountIn, fresh.amountOutMin);
        _log("bids/place", n, address(router), extra, _swapData(fresh), expected);
        AsyncOrder memory middle = orders[n / 2];
        _log("bids/cancel", n, address(router), middle.owner, abi.encodeCall(router.cancelOrder, (middle)), expected);
        _log(
            "bids/reprice",
            n,
            address(hook),
            middle.owner,
            abi.encodeCall(hook.updatePrice, (middle, 2 ether)),
            expected
        );
        fresh = _order(extra, true, 8 ether, 8 * (2_000e6 - n * 1e6));
        expected = fresh;
        expected.salt = _expectedSalt(extra, fresh.amountIn, fresh.amountOutMin);
        _log("bids/incoming_8", n, address(router), extra, _swapData(fresh), expected);
        _submit(fresh);
        for (uint256 i; i < 8; ++i) {
            assertEq(hook.asyncOrder(poolId, _orderIdFor(orders[i].owner, false, orders[i].salt)), 0);
        }
        assertGt(hook.asyncOrder(poolId, _orderIdFor(orders[8].owner, false, orders[8].salt)), 0);
    }

    function test_bids32() public {
        _bids(32);
    }

    function test_bids256() public {
        _bids(256);
    }

    function test_mixedExactPricesAndExistingLevel() public {
        uint128 first;
        for (uint256 i; i < 32; ++i) {
            address actor = address(uint160(0x10000 + i));
            _fund(actor);
            orders.push(_submit(_order(actor, true, 1 ether, 2_000e6 + i * 1000)));
            (,,, uint128 tick,,,) = hook.orderBookOrder(poolId, _orderIdFor(actor, true, orders[i].salt));
            if (i == 0) first = tick;
            else assertEq(tick, first, "fixture must crowd one tick");
        }
        _fund(extra);
        AsyncOrder memory fresh = _order(extra, true, 1 ether, 2_000e6 + 500);
        AsyncOrder memory expected = fresh;
        expected.salt = _expectedSalt(extra, fresh.amountIn, fresh.amountOutMin);
        _log("mixed_tick/append_existing", 32, address(router), extra, _swapData(fresh), expected);
        AsyncOrder memory middle = orders[16];
        _log(
            "mixed_tick/cancel",
            32,
            address(router),
            middle.owner,
            abi.encodeCall(router.cancelOrder, (middle)),
            expected
        );
        _log(
            "mixed_tick/reprice_inside",
            32,
            address(hook),
            middle.owner,
            abi.encodeCall(hook.updatePrice, (middle, 2_000e6 + 250)),
            expected
        );
        fresh = _order(extra, false, 8 * (2_000e6 + 32_000), 8 ether);
        expected = fresh;
        expected.salt = _expectedSalt(extra, fresh.amountIn, fresh.amountOutMin);
        _log("mixed_tick/incoming_8", 32, address(router), extra, _swapData(fresh), expected);
    }

    function _liquidity(bool buy) internal {
        PoolModifyLiquidityTest lp = new PoolModifyLiquidityTest(manager);
        token0.mint(address(this), 1e30);
        token1.mint(address(this), 1e30);
        token0.approve(address(lp), type(uint256).max);
        token1.approve(address(lp), type(uint256).max);
        lp.modifyLiquidity(key, ModifyLiquidityParams(-60, 60, 1e24, 0), "");
        for (uint256 i; i < 32; ++i) {
            address actor = address(uint160(0x10000 + i));
            _fund(actor);
            orders.push(_submit(_order(actor, buy, buy ? 1 ether : 0.95 ether, buy ? 1.05 ether : 1 ether)));
        }
        _fund(extra);
        AsyncOrder memory fresh = _order(extra, !buy, buy ? 10.5 ether : 10 ether, buy ? 9.9 ether : 9.4 ether);
        AsyncOrder memory expected = fresh;
        expected.salt = _expectedSalt(extra, fresh.amountIn, fresh.amountOutMin);
        _log(buy ? "lp/buy" : "lp/sell", 32, address(router), extra, _swapData(fresh), expected);
        _submit(fresh);
        assertEq(hook.asyncOrder(poolId, _orderIdFor(extra, fresh.zeroForOne, expected.salt)), 0, "LP fills incoming");
        assertGt(
            hook.asyncOrder(poolId, _orderIdFor(orders[0].owner, orders[0].zeroForOne, orders[0].salt)),
            0,
            "worse book remains resting"
        );
    }

    function test_lpBuy() public {
        _liquidity(true);
    }

    function test_lpSell() public {
        _liquidity(false);
    }
}
