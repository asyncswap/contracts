// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";

/// @title IAsyncSwapFlashFiller
/// @notice Callback a filler contract implements to use `Router.flashFill`.
interface IAsyncSwapFlashFiller {
    /// @notice Called by the Router inside its PoolManager unlock, after the order was closed and its input,
    ///         less the 0.02% trade fee, credited to the filler as ERC-6909 claims (`amountIn` of the input
    ///         currency, id 0 for native ETH).
    /// @dev Before returning, the filler must hold `amountOwed` claims of the order's output currency and allow
    ///      the Router to transfer them (`PoolManager.approve(router, id, amountOwed)` or an operator grant). Inside
    ///      the callback it may swap on any v4 pool, `burn`/`mint`/`take`/`settle`, and fill other Async Swap orders
    ///      through `IAsyncSwapCallback.fillOrderInCallback` and `matchBookInCallback`. Every delta it opens must be zero
    ///      when the Router's unlock ends.
    function asyncSwapFlashFill(AsyncOrder calldata order, uint256 amountIn, uint256 amountOwed, bytes calldata data)
        external;
}
