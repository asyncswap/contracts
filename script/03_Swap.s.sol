// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {FFIHelper} from "./FFIHelper.sol";
import {AsyncSwap} from "@async-swap/AsyncSwap.sol";
import {AsyncFiller} from "@async-swap/libraries/AsyncFiller.sol";
import {Router} from "@async-swap/Router.sol";
import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";
import {console} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolIdLibrary, PoolKey} from "v4-core/types/PoolKey.sol";

/// @notice Submits an async swap order via the Router, authorizing the Router first if needed and
///         paying the hook's minimum priority bid (or `PRIORITY_FEE`). The hook assigns the salt
///         from the block the order lands in, so the script saves the order and the block it was
///         submitted from; 04_Cancel and 05_Execute read the real salt from the chain.
contract SwapScript is FFIHelper {
    using PoolIdLibrary for PoolKey;

    Router router;
    PoolKey key;

    // Amounts are supplied explicitly in each token's base units: USDC uses six
    // decimals while the paired asset may use a different scale.

    function setUp() public {
        (, address r) = _getDeployedHook();
        router = Router(r);
        key = _loadPoolKey();
    }

    function run() public {
        uint160 sqrtPrice = 2 ** 96;
        bool zeroForOne = vm.envOr("ZERO_FOR_ONE", true);
        uint256 amountIn = vm.envUint("AMOUNT_IN");
        uint256 amountOutMin = vm.envUint("AMOUNT_OUT_MIN");
        Currency input = zeroForOne ? key.currency0 : key.currency1;
        Currency numeraire = AsyncSwap(payable(address(key.hooks))).numeraire();
        uint256 bid = _priorityFee(numeraire, input, amountIn, amountOutMin);

        AsyncOrder memory order = AsyncOrder({
            key: key,
            owner: OWNER,
            zeroForOne: zeroForOne,
            amountIn: amountIn,
            amountOutMin: amountOutMin,
            priorityFee: bid,
            sqrtPrice: sqrtPrice,
            // Initial submit: ignored by the hook, which assigns its own salt.
            salt: bytes32(0)
        });

        // The hook rejects orders whose executor the maker has not authorized
        // (NotAuthorizedExecutor). Grant the Router on first use.
        AsyncSwap hook = AsyncSwap(payable(address(key.hooks)));
        if (!hook.isExecutor(key.toId(), OWNER, address(router))) {
            vm.startBroadcast(OWNER);
            hook.setExecutor(key.toId(), address(router), true);
            vm.stopBroadcast();
            console.log("Authorized the Router as executor for OWNER");
        }

        // The salt in these logs is the simulated one; 04/05 read the real one from the chain,
        // starting at this block.
        uint256 fromBlock = block.number;
        vm.recordLogs();
        vm.startBroadcast(OWNER);
        _approveOrderFunds(address(router), numeraire, input, amountIn, bid);
        router.swap{value: input.isAddressZero() ? amountIn : 0}(
            order,
            abi.encode(
                AsyncSwap.UserParams({
                    user: OWNER, executor: address(router), amountOutMin: amountOutMin, priorityFee: bid
                })
            )
        );
        vm.stopBroadcast();

        bytes32 salt = _extractSalt();

        _saveOrder(
            OrderRecord({
                owner: OWNER,
                zeroForOne: order.zeroForOne,
                amountIn: order.amountIn,
                amountOutMin: order.amountOutMin,
                sqrtPrice: sqrtPrice,
                salt: salt,
                fromBlock: fromBlock
            })
        );

        console.log("Async order submitted. Priority bid (USDC base units):", bid);
    }

    /// @dev Find the `AsyncOrderCreated` log in the broadcast and return the salt
    ///      from its data field. Layout matches the event signature in AsyncFiller.
    function _extractSalt() private view returns (bytes32) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = AsyncFiller.AsyncOrderCreated.selector;
        for (uint256 i = logs.length; i > 0; i--) {
            Vm.Log memory log = logs[i - 1];
            if (log.topics.length > 0 && log.topics[0] == sig) {
                // Non-indexed data layout: (bool zeroForOne, uint256 amountIn,
                // uint256 amountOutMin, bytes32 salt). Salt is the 4th word.
                (,,, bytes32 salt) = abi.decode(log.data, (bool, uint256, uint256, bytes32));
                return salt;
            }
        }
        revert("AsyncOrderCreated event not found in broadcast logs");
    }
}
