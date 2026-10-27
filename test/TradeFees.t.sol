// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {SetupHook} from "./SetupHook.t.sol";
import {AsyncSwap} from "@async-swap/AsyncSwap.sol";
import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";
import {ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";

/// @notice The fee schedule end to end: 0.03% of each side's input to the protocol on book matches
///         and filler fills, and 0.02% to LPs plus 0.01% to the protocol on pool-liquidity fills.
contract TradeFeesTest is SetupHook {
    using StateLibrary for IPoolManager;

    address alice = makeAddr("alice"); // maker
    address bob = makeAddr("bob"); // counterparty / filler

    function setUp() public override {
        super.setUp();
        topUp(alice, 1_000 ether);
        topUp(bob, 1_000 ether);
    }

    /* ----------------------------------- helpers ----------------------------------- */

    function _fee(uint256 amount) internal pure returns (uint256) {
        return Math.mulDiv(amount, 3, 10_000, Math.Rounding.Ceil);
    }

    function _vault(Currency currency) internal view returns (uint256) {
        return manager.balanceOf(address(hook.feeVault()), currency.toId());
    }

    function _escrow(Currency currency) internal view returns (uint256) {
        return manager.balanceOf(address(hook), currency.toId());
    }

    function _id(AsyncOrder memory order) internal view returns (bytes32) {
        return _orderIdFor(order.owner, order.zeroForOne, order.salt);
    }

    /// @dev Submit through the Router as `maker` with a 100_000 bid. Returns the order with its assigned salt.
    function _submit(address maker, bool zeroForOne, uint256 amountIn, uint256 amountOutMin)
        internal
        returns (AsyncOrder memory order)
    {
        order = AsyncOrder(key, maker, zeroForOne, amountIn, amountOutMin, 100_000, 2 ** 96, bytes32(0));
        MockERC20 input = zeroForOne ? token0 : token1;
        vm.startPrank(maker);
        input.approve(address(router), amountIn + 100_000);
        router.swap(order, abi.encode(AsyncSwap.UserParams(maker, address(router), amountOutMin, 100_000)));
        vm.stopPrank();
        order.salt = _expectedSalt(maker, amountIn, amountOutMin);
    }

    /* ------------------------------------ tests ------------------------------------ */

    function test_admissionSetsAsideTheMakersFee() public {
        AsyncOrder memory ask = _submit(alice, true, 10 ether, 9 ether);
        (uint256 amountIn, uint256 amountOutMin) = hook.asyncOrderInfo(poolId, _id(ask));
        assertEq(amountIn, 10 ether - _fee(10 ether), "the book trades the deposit less the fee");
        assertEq(amountOutMin, 9 ether, "the signed minimum is unchanged");
        assertEq(hook.asyncOrderInputFee(poolId, _id(ask)), _fee(10 ether), "fee escrowed with the order");
        assertEq(_escrow(currency0), 10 ether, "the whole deposit is escrowed");
        assertEq(_vault(currency0), 0, "no fee is earned before a fill");
    }

    function test_cancelRefundsTheWholeDeposit() public {
        AsyncOrder memory ask = _submit(alice, true, 10 ether, 9 ether);
        uint256 before = token0.balanceOf(alice);
        vm.prank(alice);
        router.cancelOrder(ask);
        assertEq(token0.balanceOf(alice) - before, 10 ether, "net input and fee both refunded");
        assertEq(_escrow(currency0), 0);
        assertEq(_vault(currency0), 0, "cancel charges no trade fee");
    }

    function test_fillerFillChargesMakerAndFiller() public {
        AsyncOrder memory ask = _submit(alice, true, 10 ether, 9 ether);
        uint256 net = 10 ether - _fee(10 ether);
        uint256 fillerFee = hook.calculatePoolFee(key.fee, 9 ether);
        uint256 gross = 9 ether + fillerFee;
        assertEq(fillerFee, gross * 3 / 10_000, "the filler pays 0.03% of gross output");

        uint256 aliceOut = token1.balanceOf(alice);
        uint256 bobIn = token0.balanceOf(bob);
        uint256 bobOut = token1.balanceOf(bob);
        ask.amountIn = net; // a filler accepts the live input, which excludes the maker's fee
        vm.prank(bob);
        router.fillOrder(ask, gross, "");

        assertEq(token1.balanceOf(alice) - aliceOut, 9 ether, "maker receives exactly the signed minimum");
        assertEq(bobOut - token1.balanceOf(bob), gross, "filler pays minimum plus 0.03%");
        assertEq(token0.balanceOf(bob) - bobIn, net, "filler receives the input less the maker's fee");
        assertEq(_vault(currency0), _fee(10 ether), "maker's 0.03% in the input token");
        assertEq(_vault(currency1), fillerFee + 100_000, "filler's 0.03% plus the bid in the output token");
        assertEq(_escrow(currency0), 0);
    }

    function test_bookMatchChargesBothSides() public {
        AsyncOrder memory ask = _submit(alice, true, 100 ether, 90 ether);
        AsyncOrder memory bid = _submit(bob, false, 100 ether, 90 ether);
        uint256 askNet = 100 ether - _fee(100 ether);
        uint256 bidNet = 100 ether - _fee(100 ether);
        // The older ask sets the price: all of its net asset for its 90 quote minimum.
        uint256 quoteUsed = 90 ether;
        uint256 bidFeePaid = Math.mulDiv(_fee(100 ether), quoteUsed, bidNet);
        uint256 bidBidPaid = Math.mulDiv(100_000, quoteUsed, bidNet);

        assertEq(hook.asyncOrder(poolId, _id(ask)), 0, "ask fully used");
        assertEq(manager.balanceOf(bob, currency0.toId()), askNet, "buyer receives the ask's net input");
        assertEq(manager.balanceOf(alice, currency1.toId()), quoteUsed, "seller receives its minimum");
        assertEq(_vault(currency0), _fee(100 ether), "seller's whole fee in the asset");
        assertEq(_vault(currency1), bidFeePaid + 100_000 + bidBidPaid, "buyer's pro-rata fee plus both bids");

        (uint256 bidLeft,) = hook.asyncOrderInfo(poolId, _id(bid));
        uint256 bidFeeLeft = hook.asyncOrderInputFee(poolId, _id(bid));
        assertEq(bidLeft, bidNet - quoteUsed, "unused quote rests");
        assertEq(bidFeeLeft, _fee(100 ether) - bidFeePaid, "the rest of the buyer's fee stays escrowed");
        assertEq(_escrow(currency1), bidLeft + bidFeeLeft + (100_000 - bidBidPaid), "escrow backs the remainder");
    }

    /// Limits that meet exactly crossed when matches were free; each side's fee now has to fit in the spread.
    function test_exactlyTouchingLimitsRest() public {
        AsyncOrder memory ask = _submit(alice, true, 100 ether, 100 ether);
        AsyncOrder memory bid = _submit(bob, false, 100 ether, 100 ether);
        assertEq(hook.asyncOrder(poolId, _id(ask)), 100 ether - _fee(100 ether), "ask rests");
        assertEq(hook.asyncOrder(poolId, _id(bid)), 100 ether - _fee(100 ether), "bid rests");
        assertEq(_vault(currency0) + _vault(currency1), 0, "no fee without a trade");
    }

    function test_lpFillPaysLpsTwoBpsAndProtocolOneBp() public {
        PoolModifyLiquidityTest lp = new PoolModifyLiquidityTest(manager);
        token0.mint(address(this), 1e30);
        token1.mint(address(this), 1e30);
        token0.approve(address(lp), type(uint256).max);
        token1.approve(address(lp), type(uint256).max);
        lp.modifyLiquidity(key, ModifyLiquidityParams(-60, 60, 1e24, 0), "");
        (,,, uint24 feeBefore) = manager.getSlot0(poolId);

        uint256 aliceOut = token1.balanceOf(alice);
        AsyncOrder memory ask = _submit(alice, true, 10 ether, 9 ether);
        uint256 protocolFee = Math.mulDiv(10 ether, 1, 10_000, Math.Rounding.Ceil);
        uint256 swapped = 10 ether - protocolFee;

        assertEq(hook.asyncOrder(poolId, _id(ask)), 0, "filled from the pool");
        assertEq(_escrow(currency0), 0, "the whole deposit left escrow");
        assertEq(_vault(currency0), protocolFee, "protocol takes 0.01% of the deposit");
        assertEq(_vault(currency1), 100_000, "the bid goes to the FeeVault");
        (uint256 feeGrowth0, uint256 feeGrowth1) = manager.getFeeGrowthGlobals(poolId);
        uint256 expectedGrowth0 = (swapped * 200 / 1e6) * (2 ** 128) / 1e24; // 0.02% LP fee * Q128 / liquidity
        assertApproxEqRel(feeGrowth0, expectedGrowth0, 0.001e18, "0.02% of the swapped input accrues to LPs");
        assertEq(feeGrowth1, 0);
        // The maker paid its 100_000 bid in token1 when submitting.
        assertGe(token1.balanceOf(alice) + 100_000 - aliceOut, 9 ether, "maker receives at least the minimum");
        (,,, uint24 feeAfter) = manager.getSlot0(poolId);
        assertEq(feeAfter, feeBefore, "temporary LP fee restored");
    }
}
