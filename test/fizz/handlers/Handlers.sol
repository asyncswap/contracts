// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../Base.sol";
import {AsyncSwapHandler} from "./AsyncSwapHandler.sol";
import {BatchActionsHandler} from "./BatchActionsHandler.sol";
import {FeeVaultHandler} from "./FeeVaultHandler.sol";
import {NativeClaimsHandler} from "./NativeClaimsHandler.sol";
import {RouterHandler} from "./RouterHandler.sol";
import {TokenClaimsHandler} from "./TokenClaimsHandler.sol";

/// @notice Inherits from all the handlers to expose all entry points in a single contract.
///         Manages environment changes (e.g. current actor, current token, mocks setup, etc.).
///         `BatchActionsHandler` already inherits the BatchCancels and BatchClaims handlers.
abstract contract Handlers is
    AsyncSwapHandler,
    BatchActionsHandler,
    FeeVaultHandler,
    NativeClaimsHandler,
    RouterHandler,
    TokenClaimsHandler
{
    function setCurrentActor(uint256 entropy) public {
        actor = actors[entropy % actors.length];
    }
}
