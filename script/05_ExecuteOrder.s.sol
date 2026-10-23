// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {FFIHelper, IERC20Like} from "./FFIHelper.sol";
import {AsyncSwap} from "@async-swap/AsyncSwap.sol";
import {Router} from "@async-swap/Router.sol";
import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";
import {console} from "forge-std/Script.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolIdLibrary, PoolKey} from "v4-core/types/PoolKey.sol";

/// @notice Fills the most-recently-submitted async order (loaded from the deployments sidecar) as it
///         stands now. The Router charges the order's live minimum plus the 0.3% protocol fee, and
///         the order may have been repriced or partly matched since it was saved, so the script
///         reads the live amounts from the hook, pays exactly that gross amount (approving it for
///         ERC-20 output, sending it as `msg.value` for native output) and caps the fill at it.
contract ExecuteAsyncOrderScript is FFIHelper {
    using PoolIdLibrary for PoolKey;

    Router router;
    AsyncSwap hook;
    AsyncOrder order;

    function setUp() public {
        (address h, address r) = _getDeployedHook();
        hook = AsyncSwap(payable(h));
        router = Router(r);
        order = _loadOrder();
    }

    function run() public {
        bytes32 id = keccak256(abi.encode(block.chainid, order.key.toId(), order.owner, order.zeroForOne, order.salt));
        (uint256 liveIn, uint256 liveOutMin) = hook.asyncOrderInfo(order.key.toId(), id);
        require(liveIn != 0, "order is no longer open");
        uint256 gross = liveOutMin + hook.calculatePoolFee(order.key.fee, liveOutMin);
        // `order.amountIn` is the least input the filler accepts; take the live remainder.
        order.amountIn = liveIn;

        Currency output = order.zeroForOne ? order.key.currency1 : order.key.currency0;
        vm.startBroadcast(OWNER);
        if (output.isAddressZero()) {
            router.fillOrder{value: gross}(order, gross, "");
        } else {
            IERC20Like(Currency.unwrap(output)).approve(address(router), gross);
            router.fillOrder(order, gross, "");
        }
        vm.stopBroadcast();

        console.log("Async order filled. salt:");
        console.logBytes32(order.salt);
        console.log("Input received:", liveIn);
        console.log("Paid (minimum + 0.3% fee):", gross);
    }
}
