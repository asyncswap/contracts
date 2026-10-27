// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AsyncOrder} from "src/types/AsyncOrder.sol";
import {AsyncSwap} from "src/AsyncSwap.sol";
import {SetupHook} from "./SetupHook.t.sol";

contract ProtocolFeeTest is SetupHook {
    function test_fillSplitsHundredUsdcAndPaysFullInput() public {
        address maker = makeAddr("maker");
        address filler = makeAddr("filler");
        topUp(maker, 1 ether);
        topUp(filler, 100_000_000);
        // 99_970_000 net plus the filler's 0.03% (30_000) is exactly 100_000_000 gross.
        AsyncOrder memory order = AsyncOrder(key, maker, true, 1 ether, 99_970_000, 100_000, 2 ** 96, bytes32(0));
        vm.startPrank(maker);
        token0.approve(address(router), 1 ether);
        router.swap(order, abi.encode(AsyncSwap.UserParams(maker, address(router), 99_970_000, 100_000)));
        vm.stopPrank();
        order.salt = _expectedSalt(maker, 1 ether, 99_970_000);
        // The maker's 0.03% input fee is escrowed beside the net input the filler receives.
        uint256 inputFee = Math.mulDiv(1 ether, 3, 10_000, Math.Rounding.Ceil);
        uint256 netIn = 1 ether - inputFee;
        assertEq(hook.asyncOrderInputFee(poolId, _orderIdFor(maker, true, order.salt)), inputFee);
        order.amountIn = netIn;
        uint256 makerBefore = token1.balanceOf(maker);
        uint256 fillerBefore = token0.balanceOf(filler);
        vm.startPrank(filler);
        token1.approve(address(router), 100_000_000);
        vm.expectRevert("Price exceeds maxPrice");
        router.fillOrder(order, 99_970_000, "");
        assertEq(token1.balanceOf(filler), 100_000_000);
        router.fillOrder(order, 100_000_000, "");
        vm.stopPrank();
        assertEq(token1.balanceOf(maker) - makerBefore, 99_970_000);
        assertEq(token0.balanceOf(filler) - fillerBefore, netIn);
        assertEq(token1.balanceOf(filler), 0);
        // Vault: the maker's input fee in the input currency; the filler's fee plus the bid in currency1.
        assertEq(manager.balanceOf(address(hook.feeVault()), currency0.toId()), inputFee);
        assertEq(manager.balanceOf(address(hook.feeVault()), currency1.toId()), 30_000 + 100_000);
    }

    function test_feeIsPointZeroThreePercent() public view {
        assertEq(hook.calculatePoolFee(0x800000, 0.9997 ether), 0.0003 ether);
        assertEq(hook.calculatePoolFee(0x800000, 9_997_000), 3_000);
    }

    function test_feeRoundsDownAtSmallestUnit() public view {
        assertEq(hook.calculatePoolFee(0x800000, 3_332), 0);
        assertEq(hook.calculatePoolFee(0x800000, 3_333), 1);
        assertEq(hook.calculatePoolFee(0x800000, 6_664), 1);
        assertEq(hook.calculatePoolFee(0x800000, 6_665), 2);
    }

    function testFuzz_feeIsPointZeroThreePercentOfGross(uint128 net) public view {
        uint256 fee = hook.calculatePoolFee(0x800000, net);
        uint256 gross = uint256(net) + fee;
        assertEq(fee, (gross * 3) / 10_000);
        assertEq(gross - fee, net);
    }

    function testFuzz_feeCannotOverflow(uint256 amount) public view {
        uint256 fee = hook.calculatePoolFee(0x800000, amount);
        assertEq(fee, (amount / 9997) * 3 + ((amount % 9997) * 3) / 9997);
        assertLe(fee, amount);
    }
}
