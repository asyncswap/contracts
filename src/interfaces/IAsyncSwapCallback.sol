// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

/// @title IAsyncSwapCallback
/// @notice The Router's callback fill surface: `fillOrderWithCallback` opens a fill and calls the filler back
///         (`IAsyncSwapFlashFiller.asyncSwapFlashFill`); the `...InCallback` functions are the only Router calls
///         accepted while that callback runs, and only from its filler. Every other Router entry point reverts
///         `FlashFillActive` until the callback returns.
interface IAsyncSwapCallback {
    /// @notice Fill `order` with no inventory: input first as claims, callback, then the owed output as claims.
    ///         Every fill in the callback (this one and each `fillOrderInCallback`) owes the MEV tax, paid to the
    ///         FeeVault when the fill runs. `msg.value` prepays it, any amount; the filler may also pay inside its
    ///         callback with `PoolManager.settleFor(router)`. A surplus is returned to the filler in ETH and a
    ///         shortfall reverts `MevTaxUnpaid`.
    function fillOrderWithCallback(AsyncOrder calldata order, uint256 maxPrice, bytes calldata data) external payable;

    /// @notice Inside the callback: fill another open order, paying its output and receiving its input as claims.
    ///         The filler pays the order's minimum output plus any live Dutch auction premium (`auctionPremium` on the
    ///         hook), and approves the Router for both; `maxPrice` bounds the total.
    function fillOrderInCallback(AsyncOrder calldata order, uint256 maxPrice) external;

    /// @notice Inside the callback: continue a crossed book.
    function matchBookInCallback(PoolKey calldata key, uint8 maxMatches) external returns (uint8);

    /// @notice MEV tax for `fills` fills at this transaction's priority fee. Off chain, simulate with the gas price
    ///         you will send (`eth_call` with `gasPrice`); on chain it is exact for the running transaction.
    function mevTaxFor(uint256 fills) external view returns (uint256);

    /// @notice Inside the callback: the MEV tax the Router still owes for this flash fill, every fill charged so far
    ///         less what was paid. Settle exactly this with `PoolManager.settleFor(router)` before returning.
    function mevTaxOwed() external view returns (uint256);
}
