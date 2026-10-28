// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {AsyncSwap} from "src/AsyncSwap.sol";
import {AsyncOrder} from "src/types/AsyncOrder.sol";

/// @notice Cancels several orders owned by the caller in one PoolManager unlock.
/// @dev Makers must authorize this contract as an executor for each order's pool.
contract BatchCancels {
    IPoolManager public immutable poolManager;
    AsyncSwap public immutable hook;
    address private cancellingOwner;

    error InvalidBatch();
    error NotOwner();
    error OnlyPoolManager();

    constructor(IPoolManager manager, AsyncSwap orderHook) {
        poolManager = manager;
        hook = orderHook;
    }

    function cancelOrders(AsyncOrder[] calldata orders) external {
        if (cancellingOwner != address(0) || orders.length == 0 || orders.length > 50) revert InvalidBatch();
        for (uint256 i; i < orders.length; ++i) {
            if (orders[i].owner != msg.sender) revert NotOwner();
        }
        cancellingOwner = msg.sender;
        poolManager.unlock(abi.encode(orders));
        cancellingOwner = address(0);
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert OnlyPoolManager();
        address owner = cancellingOwner;
        if (owner == address(0)) revert InvalidBatch();
        AsyncOrder[] memory orders = abi.decode(data, (AsyncOrder[]));
        for (uint256 i; i < orders.length; ++i) {
            if (orders[i].owner != owner) revert NotOwner();
            hook.cancelOrder(orders[i]);
        }
        return "";
    }
}
