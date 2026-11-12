// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IAsyncSwapCallback} from "@async-swap/interfaces/IAsyncSwapCallback.sol";
import {IAsyncSwapFlashFiller} from "@async-swap/interfaces/IAsyncSwapFlashFiller.sol";
import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

/// @title AsyncSwapFlashFiller
/// @notice Base for flash fillers. Write `_route`; this contract handles the rest:
///         - only the Router may call the callback, and only for a fill this contract started;
///         - it approves the Router for the output owed to the maker;
///         - it pays the exact MEV tax owed, from its ETH balance, so `fill` needs no `msg.value`.
///         Keep enough ETH in the contract for the tax (send it with `fill`, or fund it beforehand).
///         Surplus and refunds stay in the contract; `withdraw` sends them to the owner.
abstract contract AsyncSwapFlashFiller is IAsyncSwapFlashFiller {
    IPoolManager public immutable POOLMANAGER;
    IAsyncSwapCallback public immutable ROUTER;
    address public immutable OWNER;

    /// @notice The contract holds less ETH than the MEV tax it owes.
    error MevTaxBalanceTooLow(uint256 owed, uint256 balance);
    error NotRouter();
    error NotOwner();

    constructor(IPoolManager poolManager, IAsyncSwapCallback router, address owner) {
        POOLMANAGER = poolManager;
        ROUTER = router;
        OWNER = owner;
    }

    /// @notice Starts a flash fill of `order`. Any ETH sent stays here to pay the MEV tax.
    function fill(AsyncOrder calldata order, uint256 maxPrice, bytes calldata data) external payable {
        if (msg.sender != OWNER) revert NotOwner();
        ROUTER.fillOrderWithCallback(order, maxPrice, data);
    }

    /// @notice The ETH `fill` needs for the MEV tax of `fills` fills at this gas price, less what the contract holds.
    function ethNeeded(uint256 fills) external view returns (uint256) {
        uint256 tax = ROUTER.mevTaxFor(fills);
        return tax > address(this).balance ? tax - address(this).balance : 0;
    }

    /// @inheritdoc IAsyncSwapFlashFiller
    function asyncSwapFlashFill(AsyncOrder calldata order, uint256 amountIn, uint256 amountOwed, bytes calldata data)
        external
    {
        if (msg.sender != address(ROUTER)) revert NotRouter();
        _route(order, amountIn, amountOwed, data);
        Currency output = order.zeroForOne ? order.key.currency1 : order.key.currency0;
        POOLMANAGER.approve(address(ROUTER), output.toId(), amountOwed);
        _payMevTax();
    }

    /// @notice Sends `amount` ETH and ERC-6909 claims of `ids` held here to the owner.
    function withdraw(uint256 amount, uint256[] calldata ids, uint256[] calldata amounts) external {
        if (msg.sender != OWNER) revert NotOwner();
        for (uint256 i; i < ids.length; ++i) {
            POOLMANAGER.transfer(OWNER, ids[i], amounts[i]);
        }
        if (amount != 0) {
            (bool ok,) = OWNER.call{value: amount}("");
            require(ok, "ETH transfer failed");
        }
    }

    /// @dev Turn `amountIn` input claims into at least `amountOwed` output claims held by this contract. Runs inside
    ///      the PoolManager unlock: swap on v4 pools, call `ROUTER.fillOrderInCallback` or `matchBookInCallback`.
    ///      Every delta this contract opens must be zero when it returns.
    function _route(AsyncOrder calldata order, uint256 amountIn, uint256 amountOwed, bytes calldata data)
        internal
        virtual;

    function _payMevTax() private {
        uint256 owed = ROUTER.mevTaxOwed();
        if (owed == 0) return;
        if (address(this).balance < owed) revert MevTaxBalanceTooLow(owed, address(this).balance);
        POOLMANAGER.sync(CurrencyLibrary.ADDRESS_ZERO);
        POOLMANAGER.settleFor{value: owed}(address(ROUTER));
    }

    receive() external payable {}
}
