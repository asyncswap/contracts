// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {AsyncSwap} from "@async-swap/AsyncSwap.sol";
import {Router} from "@async-swap/Router.sol";
import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";
import {MockERC20} from "../../test/utils/MockERC20.sol";

/// @notice Smoke test for the local stack: a funded wallet places a 1,000 USDC market buy through the
///         Router with the minimum bid. With an empty book it fills from pool liquidity.
contract Smoke is Script {
    using StateLibrary for IPoolManager;

    IPoolManager manager;
    MockERC20 usdc;
    MockERC20 asset;

    function run() public {
        manager = IPoolManager(vm.envAddress("POOL_MANAGER"));
        AsyncSwap hook = AsyncSwap(payable(vm.envAddress("HOOK")));
        Router router = Router(payable(vm.envAddress("ROUTER")));
        usdc = MockERC20(vm.envAddress("USDC"));
        asset = MockERC20(vm.envAddress("ASSET"));
        bool usdcIs0 = address(usdc) < address(asset);
        PoolKey memory key = _key(address(hook), usdcIs0);
        _logPool(key.toId());

        uint256 bid = 100_000; // 0.10 USDC, the protocol minimum for this size
        uint256 assetBefore = _assetHeld();
        vm.startBroadcast();
        hook.setExecutor(key.toId(), address(router), true);
        usdc.approve(address(router), 1_000e6 + bid);
        // A 1,000 USDC buy (zeroForOne when USDC is currency0), limit 0.3 asset: about 3,333 USDC each.
        AsyncOrder memory order = AsyncOrder(key, msg.sender, usdcIs0, 1_000e6, 0.3e18, bid, 0, bytes32(0));
        router.swap(order, abi.encode(AsyncSwap.UserParams(msg.sender, address(router), 0.3e18, bid)));
        vm.stopBroadcast();

        uint256 got = _assetHeld() - assetBefore;
        console.log("asset received (wei):", got);
        require(got > 0.3e18, "market buy did not fill");
        _logPool(key.toId());
    }

    function _key(address hook, bool usdcIs0) internal view returns (PoolKey memory) {
        return PoolKey(
            Currency.wrap(usdcIs0 ? address(usdc) : address(asset)),
            Currency.wrap(usdcIs0 ? address(asset) : address(usdc)),
            LPFeeLibrary.DYNAMIC_FEE_FLAG,
            60,
            IHooks(hook)
        );
    }

    function _assetHeld() internal view returns (uint256) {
        return asset.balanceOf(msg.sender) + manager.balanceOf(msg.sender, uint256(uint160(address(asset))));
    }

    function _logPool(PoolId id) internal view {
        (, int24 tick,,) = manager.getSlot0(id);
        console.log("pool tick:", tick);
        console.log("pool liquidity:", manager.getLiquidity(id));
    }
}
