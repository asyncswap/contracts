// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../Base.sol";
import {Properties} from "../Properties.sol";
import {BatchCancelsHandler} from "./BatchCancelsHandler.sol";
import {BatchClaimsHandler} from "./BatchClaimsHandler.sol";

/// @notice Handles the interaction with BatchActions
abstract contract BatchActionsHandler is BatchCancelsHandler, BatchClaimsHandler {
    // ――――――――――――――――――――――――― Clamped ――――――――――――――――――――――――――

    /// @notice Cancel some of one maker's orders and redeem that maker's claims in one unlock.
    function batchActions_execute_clamped(uint256 entropy, uint8 count, bool withClaims) public {
        (bool found, AsyncOrder memory first) = pickLiveOrder(entropy);
        if (found) actor = first.owner;
        AsyncOrder[] memory batch = found ? _liveOrdersOf(actor, clampBetween(count, 1, 5)) : new AsyncOrder[](0);
        Currency[] memory currencies;
        uint256[] memory amounts;
        if (withClaims) (currencies, amounts) = _ownClaims(actor);
        if (batch.length == 0 && currencies.length == 0) return;
        batchActions_execute(batch, currencies, amounts, actor);
    }

    // ―――――――――――――――――――――――― Unclamped ―――――――――――――――――――――――――

    function batchActions_execute(
        AsyncOrder[] memory batch,
        Currency[] memory currencies,
        uint256[] memory amounts,
        address recipient
    ) public asActor {
        batchActions.execute(batch, currencies, amounts, recipient);
    }
}
