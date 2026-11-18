// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SetupHook} from "./SetupHook.t.sol";
import {Launchpad} from "src/Launchpad.sol";
import {LaunchToken} from "src/LaunchToken.sol";
import {AsyncSwap} from "src/AsyncSwap.sol";
import {AsyncOrder} from "src/types/AsyncOrder.sol";
import {PoolKey, PoolIdLibrary} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

contract LaunchpadTest is SetupHook {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    Launchpad pad;
    address creator = makeAddr("creator");
    address buyer = makeAddr("buyer");

    function setUp() public virtual override {
        super.setUp();
        pad = new Launchpad(hook);
    }

    function _launch() internal returns (address token) {
        vm.prank(creator);
        token = pad.launch(Launchpad.LaunchParams("Orbit", "ORB", 1_000_000_000 ether, 1e15, "ipfs://metadata"));
    }

    function test_supplyAndPositionAreLocked() public {
        address token = _launch();
        LaunchToken asset = LaunchToken(token);
        assertEq(asset.totalSupply(), 1_000_000_000 ether);
        assertEq(asset.balanceOf(creator), 0);
        assertEq(asset.balanceOf(address(manager)) + asset.balanceOf(address(pad)), asset.totalSupply());
        assertEq(asset.creator(), creator);
        assertEq(asset.metadataURI(), "ipfs://metadata");
        (address feeRecipient, int24 lower, int24 upper, uint128 liquidity) = pad.launches(token);
        assertEq(feeRecipient, creator);
        assertGt(liquidity, 0);
        PoolKey memory market = pad.poolKey(token);
        (uint160 price,,,) = manager.getSlot0(market.toId());
        assertEq(price, TickMath.getSqrtPriceAtTick(token < Currency.unwrap(currency1) ? lower : upper));
        vm.prank(creator);
        (bool ok,) = address(pad).call(abi.encodeWithSignature("withdraw(address)", token));
        assertFalse(ok);
        vm.prank(creator);
        (ok,) = token.call(abi.encodeWithSignature("mint(address,uint256)", creator, 1 ether));
        assertFalse(ok);
    }

    function _fundBuyer() internal virtual {
        token1.mint(buyer, 100e6);
    }

    function _buy(address token) internal {
        PoolKey memory market = pad.poolKey(token);
        bool direction = Currency.unwrap(market.currency0) == Currency.unwrap(currency1);
        AsyncOrder memory order = AsyncOrder(
            market,
            buyer,
            direction,
            100e6,
            90_000 ether,
            0,
            direction ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1,
            0
        );
        _fundBuyer();
        vm.startPrank(buyer);
        token1.approve(address(router), 100e6);
        hook.setExecutor(market.toId(), address(router), true);
        router.swap(order, abi.encode(AsyncSwap.UserParams(buyer, address(router), order.amountOutMin, 0)));
        vm.stopPrank();
        // Full pool fills deliver ERC-20 output; partial fills may credit claims.
        assertGt(LaunchToken(token).balanceOf(buyer) + manager.balanceOf(buyer, uint256(uint160(token))), 90_000 ether);
    }

    function test_buyAndClaimFeesNeverWithdrawPrincipal() public {
        address token = _launch();
        _buy(token);
        (, int24 lower, int24 upper, uint128 beforeLiquidity) = pad.launches(token);
        uint256 beforeQuote = token1.balanceOf(creator);
        // Permissionless trigger always pays creator, never caller.
        vm.prank(buyer);
        pad.claimFees(token);
        assertGt(token1.balanceOf(creator), beforeQuote);
        (,,, uint128 afterLiquidity) = pad.launches(token);
        assertEq(afterLiquidity, beforeLiquidity);
        (uint128 actualLiquidity,,) = manager.getPositionInfo(
            pad.poolKey(token).toId(), address(pad), lower, upper, bytes32(uint256(uint160(token)))
        );
        assertEq(actualLiquidity, beforeLiquidity);
        uint256 afterQuote = token1.balanceOf(creator);
        pad.claimFees(token);
        assertEq(token1.balanceOf(creator), afterQuote);
    }

    function test_minimumStartingPrice() public {
        vm.prank(creator);
        address token = pad.launch(Launchpad.LaunchParams("Minimum", "MIN", 1_000_000_000 ether, 1, ""));
        (,,, uint128 liquidity) = pad.launches(token);
        assertGt(liquidity, 0);
        assertEq(LaunchToken(token).balanceOf(creator), 0);
        _buy(token);
        pad.claimFees(token);
        assertGt(token1.balanceOf(creator), 0);
        (,,, uint128 afterLiquidity) = pad.launches(token);
        assertEq(afterLiquidity, liquidity);
    }

    function test_multipleLaunchesSortBeforeNumeraire() public {
        for (uint256 i; i < 8; ++i) {
            address token = _launch();
            assertLt(uint160(token), uint160(Currency.unwrap(currency1)));
            _buy(token);
            pad.claimFees(token);
        }
    }

    function test_invalidParametersAndCallbackAccess() public {
        vm.expectRevert(Launchpad.InvalidLaunch.selector);
        pad.launch(Launchpad.LaunchParams("Orbit", "ORB", 0, 1e15, ""));
        vm.expectRevert(Launchpad.InvalidLaunch.selector);
        pad.launch(Launchpad.LaunchParams("Orbit", "ORB", 1e18, 0, ""));
        vm.expectRevert(Launchpad.UnknownToken.selector);
        pad.claimFees(address(1));
        vm.expectRevert(Launchpad.OnlyPoolManager.selector);
        pad.unlockCallback(abi.encode(address(1), true));
    }

    function testFuzz_fixedSupplyAndNoQuoteDeposit(uint96 supplySeed, uint64 priceSeed) public {
        uint256 supply = bound(uint256(supplySeed), 1_000_000 ether, 1_000_000_000 ether);
        uint256 price = bound(uint256(priceSeed), 1e12, 1e18);
        address token = pad.launch(Launchpad.LaunchParams("Orbit", "ORB", supply, price, ""));
        assertEq(LaunchToken(token).totalSupply(), supply);
        assertEq(LaunchToken(token).balanceOf(address(this)), 0);
        assertEq(LaunchToken(token).balanceOf(address(manager)) + LaunchToken(token).balanceOf(address(pad)), supply);
    }
}
