// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";
import {ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {MockERC20} from "../../test/utils/MockERC20.sol";

/// @notice Local development market for `script/local/up.sh`: initializes the USDC/asset pool on the
///         local hook as its owner, adds liquidity around the start price, and funds test wallets.
///         Inputs come from the environment (set by `up.sh`): POOL_MANAGER, HOOK, USDC, ASSET, INIT_TICK
///         and FUND (comma-separated wallets).
contract LocalMarket is Script {
    int24 internal constant TICK_SPACING = 60;

    function run() public {
        IPoolManager manager = IPoolManager(vm.envAddress("POOL_MANAGER"));
        address hook = vm.envAddress("HOOK");
        MockERC20 usdc = MockERC20(vm.envAddress("USDC"));
        MockERC20 asset = MockERC20(vm.envAddress("ASSET"));
        int24 tick = int24(vm.envInt("INIT_TICK")) / TICK_SPACING * TICK_SPACING;

        (address t0, address t1) =
            address(usdc) < address(asset) ? (address(usdc), address(asset)) : (address(asset), address(usdc));
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(t0),
            currency1: Currency.wrap(t1),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(hook)
        });

        vm.startBroadcast();
        manager.initialize(key, TickMath.getSqrtPriceAtTick(tick));

        // Liquidity of about ±10% around the start price, enough for pool fills and backruns.
        PoolModifyLiquidityTest lp = new PoolModifyLiquidityTest(manager);
        usdc.mint(msg.sender, 100_000_000e6);
        asset.mint(msg.sender, 100_000e18);
        usdc.approve(address(lp), type(uint256).max);
        asset.approve(address(lp), type(uint256).max);
        lp.modifyLiquidity(key, ModifyLiquidityParams(tick - 1_020, tick + 1_020, int256(_liquidity()), 0), "");

        string[] memory wallets = vm.split(vm.envOr("FUND", string("")), ",");
        for (uint256 i; i < wallets.length; ++i) {
            if (bytes(wallets[i]).length == 0) continue;
            address w = vm.parseAddress(wallets[i]);
            usdc.mint(w, 1_000_000e6);
            asset.mint(w, 1_000e18);
            payable(w).transfer(10 ether);
        }
        vm.stopBroadcast();

        console.log("currency0:", t0);
        console.log("currency1:", t1);
        console.log("start tick:", tick);
    }

    /// @dev Raw liquidity; with mixed decimals its token amounts depend on the price, so it's set by env.
    function _liquidity() internal view returns (uint256) {
        return vm.envOr("LIQUIDITY", uint256(1e15));
    }
}
