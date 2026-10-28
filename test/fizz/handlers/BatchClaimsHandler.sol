// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../Base.sol";
import {Properties} from "../Properties.sol";

/// @notice Handles the interaction with BatchClaims
abstract contract BatchClaimsHandler is Properties {
    // ――――――――――――――――――――――――― Clamped ――――――――――――――――――――――――――

    /// @notice Redeem every nonzero claim balance (ETH and USDC) of the current actor in one call.
    function batchClaims_redeem_clamped() public {
        (Currency[] memory currencies, uint256[] memory amounts) = _ownClaims(actor);
        if (currencies.length == 0) return;
        batchClaims_redeem(currencies, actor, amounts);
    }

    // ―――――――――――――――――――――――― Unclamped ―――――――――――――――――――――――――

    function batchClaims_redeem(Currency[] memory currencies, address recipient, uint256[] memory amounts)
        public
        asActor
    {
        batchClaims.redeem(currencies, recipient, amounts);
    }

    // ――――――――――――――――――――――――― Internal ―――――――――――――――――――――――――

    function _ownClaims(address owner) internal view returns (Currency[] memory currencies, uint256[] memory amounts) {
        uint256 eth = manager.balanceOf(owner, 0);
        uint256 usd = manager.balanceOf(owner, uint160(address(usdc)));
        uint256 n = (eth != 0 ? 1 : 0) + (usd != 0 ? 1 : 0);
        currencies = new Currency[](n);
        amounts = new uint256[](n);
        uint256 i;
        if (eth != 0) (currencies[i], amounts[i++]) = (Currency.wrap(address(0)), eth);
        if (usd != 0) (currencies[i], amounts[i]) = (Currency.wrap(address(usdc)), usd);
    }
}
