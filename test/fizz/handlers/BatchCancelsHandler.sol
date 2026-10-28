// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../Base.sol";
import {Properties} from "../Properties.sol";

/// @notice Handles the interaction with BatchCancels
abstract contract BatchCancelsHandler is Properties {
    // ――――――――――――――――――――――――― Clamped ――――――――――――――――――――――――――

    /// @notice Cancel up to `count` live orders of one maker in a single batch.
    function batchCancels_cancelOrders_clamped(uint256 entropy, uint8 count) public {
        (bool found, AsyncOrder memory first) = pickLiveOrder(entropy);
        if (!found) return;
        actor = first.owner;
        AsyncOrder[] memory batch = _liveOrdersOf(actor, clampBetween(count, 1, 5));
        batchCancels_cancelOrders(batch);
    }

    // ―――――――――――――――――――――――― Unclamped ―――――――――――――――――――――――――

    function batchCancels_cancelOrders(AsyncOrder[] memory batch) public asActor {
        batchCancels.cancelOrders(batch);
    }

    // ――――――――――――――――――――――――― Internal ―――――――――――――――――――――――――

    function _liveOrdersOf(address owner, uint256 max) internal view returns (AsyncOrder[] memory batch) {
        AsyncOrder[] memory buffer = new AsyncOrder[](max);
        uint256 n;
        for (uint256 i; i < orders.length && n < max; ++i) {
            if (orders[i].owner == owner && liveAmountIn(orders[i]) != 0) buffer[n++] = orders[i];
        }
        batch = new AsyncOrder[](n);
        for (uint256 i; i < n; ++i) {
            batch[i] = buffer[i];
        }
    }
}
