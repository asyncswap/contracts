// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {MockERC20} from "../../../test/utils/MockERC20.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SwapRouterNoChecks} from "v4-core/test/SwapRouterNoChecks.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";

/// @dev Official core test adapters, not Universal Router. Receipt measurement runs on separate Anvil transactions.
contract V4CapacityTest is Test {
    using PoolIdLibrary for PoolKey;
    uint256 constant COUNT = 500;
    uint256 constant FUNDS = 1e30;
    PoolManager manager;
    MockERC20 asset;
    MockERC20 quote;
    PoolKey key;

    function setUp() public {
        manager = new PoolManager(address(this));
        deployCodeTo("MockERC20.sol", abi.encode("Asset", "ASSET", uint8(18)), address(0x100000));
        deployCodeTo("MockERC20.sol", abi.encode("Quote", "QUOTE", uint8(6)), address(0x200000));
        asset = MockERC20(address(0x100000));
        quote = MockERC20(address(0x200000));
        key = PoolKey(Currency.wrap(address(asset)), Currency.wrap(address(quote)), 3000, 60, IHooks(address(0)));
    }

    function _seedLiquidity() internal {
        // Populate state in the exported test transaction so dumpState includes the pool and LP balances.
        // Approximately 1,000 quote units per asset after the 18/6 decimal conversion.
        manager.initialize(key, TickMath.getSqrtPriceAtTick(-207240));
        PoolModifyLiquidityTest lp = new PoolModifyLiquidityTest(manager);
        asset.mint(address(this), 1e36);
        quote.mint(address(this), 1e36);
        asset.approve(address(lp), type(uint256).max);
        quote.approve(address(lp), type(uint256).max);
        // Deep full-range liquidity keeps all measured swaps inside the same initialized range.
        lp.modifyLiquidity(key, ModifyLiquidityParams(-887220, 887220, 1e22, 0), "");
    }

    function _export(string memory name, bool sell, bool checked) internal {
        _seedLiquidity();
        address adapter = checked ? address(new PoolSwapTest(manager)) : address(new SwapRouterNoChecks(manager));
        uint256 input = sell ? 1 ether : 1000e6;
        SwapParams memory params =
            SwapParams(sell, -int256(input), sell ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1);
        bytes memory data = checked
            ? abi.encodeCall(PoolSwapTest.swap, (key, params, PoolSwapTest.TestSettings(false, false), bytes("")))
            : abi.encodeCall(SwapRouterNoChecks.swap, (key, params));
        for (uint256 i; i < COUNT; ++i) {
            address actor = address(uint160(0x400000 + i));
            asset.mint(actor, FUNDS);
            quote.mint(actor, FUNDS);
            vm.startPrank(actor);
            asset.approve(adapter, type(uint256).max);
            quote.approve(adapter, type(uint256).max);
            vm.stopPrank();
            console2.log(string.concat("TX|", name, "|", vm.toString(actor), "|", vm.toString(data)));
        }
        vm.etch(adapter, adapter.code);
        vm.etch(address(asset), address(asset).code);
        vm.etch(address(quote), address(quote).code);
        vm.dumpState(string.concat("deployments/v4-capacity-", name, ".json"));
        console2.log(
            string.concat(
                "META|",
                name,
                "|",
                vm.toString(adapter),
                "|",
                vm.toString(address(manager)),
                "|",
                vm.toString(PoolId.unwrap(key.toId())),
                "|",
                vm.toString(input)
            )
        );
    }

    function test_exportMinimalBuy() public {
        _export("minimal_buy", false, false);
    }

    function test_exportMinimalSell() public {
        _export("minimal_sell", true, false);
    }

    function test_exportCheckedBuy() public {
        _export("checked_buy", false, true);
    }

    function test_exportCheckedSell() public {
        _export("checked_sell", true, true);
    }
}
