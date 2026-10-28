// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {SetupHook} from "./SetupHook.t.sol";
import {BatchClaims} from "src/BatchClaims.sol";
import {AsyncSwap} from "src/AsyncSwap.sol";
import {AsyncOrder} from "src/types/AsyncOrder.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {AsyncFiller} from "src/libraries/AsyncFiller.sol";

contract BatchClaimsTest is SetupHook {
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address recipient = makeAddr("recipient");
    BatchClaims claims;

    function setUp() public override {
        super.setUp();
        topUp(alice, 100 ether);
        topUp(bob, 100 ether);
        claims = new BatchClaims(manager);
    }

    function _swap(address trader, bool zeroForOne, uint256 amount) private {
        AsyncOrder memory order = AsyncOrder(key, trader, zeroForOne, amount, amount, 100_000, 2 ** 96, 0);
        vm.prank(trader);
        router.swap(order, abi.encode(AsyncSwap.UserParams(trader, address(router), amount, 100_000)));
    }

    function _creditBoth() private {
        vm.prank(alice);
        token0.approve(address(router), 100 ether);
        vm.prank(bob);
        token0.approve(address(router), 100 ether);
        _swap(alice, true, 10 ether);
        _swap(bob, false, 10 ether);
        _swap(bob, true, 5 ether);
        _swap(alice, false, 5 ether);
        assertEq(manager.balanceOf(alice, uint160(Currency.unwrap(currency0))), _afterFee(5 ether));
        assertEq(manager.balanceOf(alice, uint160(Currency.unwrap(currency1))), _afterFee(10 ether));
    }

    /// What a side receives from a fill: the amount less the 0.02% trade fee taken from proceeds.
    function _afterFee(uint256 amount) private pure returns (uint256) {
        return amount - AsyncFiller.tradeFee(amount);
    }

    function _currencies() private view returns (Currency[] memory currencies) {
        currencies = new Currency[](2);
        currencies[0] = currency0;
        currencies[1] = currency1;
    }

    function _amounts() private pure returns (uint256[] memory amounts) {
        amounts = new uint256[](2);
        amounts[0] = _afterFee(5 ether);
        amounts[1] = _afterFee(10 ether);
    }

    function test_redeemsTwoCurrenciesAtomicallyAfterOperatorApproval() public {
        _creditBoth();
        uint256 before0 = token0.balanceOf(recipient);
        uint256 before1 = token1.balanceOf(recipient);
        vm.prank(alice);
        vm.expectRevert();
        claims.redeem(_currencies(), recipient, _amounts());
        vm.prank(alice);
        manager.setOperator(address(claims), true);
        vm.prank(alice);
        claims.redeem(_currencies(), recipient, _amounts());
        assertEq(manager.balanceOf(alice, uint160(Currency.unwrap(currency0))), 0);
        assertEq(manager.balanceOf(alice, uint160(Currency.unwrap(currency1))), 0);
        assertEq(token0.balanceOf(recipient) - before0, _afterFee(5 ether));
        assertEq(token1.balanceOf(recipient) - before1, _afterFee(10 ether));
    }

    function test_rejectsDuplicateAndUnownedClaims() public {
        _creditBoth();
        vm.prank(alice);
        manager.setOperator(address(claims), true);
        Currency[] memory duplicate = _currencies();
        duplicate[1] = duplicate[0];
        vm.prank(alice);
        vm.expectRevert(BatchClaims.InvalidRedemption.selector);
        claims.redeem(duplicate, recipient, _amounts());
        vm.prank(bob);
        vm.expectRevert();
        claims.redeem(_currencies(), recipient, _amounts());
        assertEq(manager.balanceOf(alice, uint160(Currency.unwrap(currency0))), _afterFee(5 ether));
        assertEq(manager.balanceOf(alice, uint160(Currency.unwrap(currency1))), _afterFee(10 ether));
    }

    function test_rejectsInvalidInputAndDirectCallback() public {
        vm.expectRevert(BatchClaims.InvalidRedemption.selector);
        claims.redeem(new Currency[](0), recipient, new uint256[](0));
        vm.expectRevert(BatchClaims.InvalidRedemption.selector);
        claims.redeem(_currencies(), address(0), _amounts());
        vm.expectRevert(BatchClaims.OnlyPoolManager.selector);
        claims.unlockCallback("");
    }
}
