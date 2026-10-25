// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {AsyncSwap} from "src/AsyncSwap.sol";
import {AsyncOrder} from "src/types/AsyncOrder.sol";

/// @notice Cancels the caller's orders and redeems the caller's ERC-6909 PoolManager claims
///         atomically in one PoolManager unlock.
/// @dev Before cancelling, the maker must authorize this contract as an executor on the hook
///      for each order's pool. Before redeeming, the maker must authorize this contract as a
///      PoolManager operator. Either action can be omitted by passing an empty array.
contract BatchActions {
    IPoolManager public immutable poolManager;
    AsyncSwap public immutable hook;

    address private activeOwner;

    error InvalidBatch();
    error NotOwner();
    error WrongHook();
    error OnlyPoolManager();

    event ClaimRedeemed(address indexed owner, address indexed recipient, Currency indexed currency, uint256 amount);

    constructor(IPoolManager manager, AsyncSwap orderHook) {
        if (address(manager) == address(0) || address(orderHook) == address(0)) revert InvalidBatch();
        poolManager = manager;
        hook = orderHook;
    }

    /// @notice Perform either or both actions. All operations succeed or the transaction reverts.
    /// @param orders Open orders owned by msg.sender to cancel (maximum 50).
    /// @param currencies Claim currencies to redeem; address(0) denotes native ETH (maximum 16).
    /// @param amounts Raw claim amounts corresponding to currencies.
    /// @param recipient Address receiving redeemed ETH/ERC20 tokens.
    function execute(
        AsyncOrder[] calldata orders,
        Currency[] calldata currencies,
        uint256[] calldata amounts,
        address recipient
    ) external {
        uint256 orderCount = orders.length;
        uint256 claimCount = currencies.length;
        if (
            activeOwner != address(0) || (orderCount == 0 && claimCount == 0) || orderCount > 50 || claimCount > 16
                || claimCount != amounts.length || (claimCount != 0 && recipient == address(0))
        ) revert InvalidBatch();

        for (uint256 i; i < orderCount; ++i) {
            if (orders[i].owner != msg.sender) revert NotOwner();
            if (address(orders[i].key.hooks) != address(hook)) revert WrongHook();
        }
        for (uint256 i; i < claimCount; ++i) {
            if (amounts[i] == 0) revert InvalidBatch();
            for (uint256 j; j < i; ++j) {
                if (Currency.unwrap(currencies[i]) == Currency.unwrap(currencies[j])) revert InvalidBatch();
            }
        }

        activeOwner = msg.sender;
        poolManager.unlock(abi.encode(msg.sender, orders, currencies, amounts, recipient));
        activeOwner = address(0);
    }

    /// @dev PoolManager calls this only during execute. Cancels first so newly returned claims
    ///      can be redeemed in the same unlock if the caller included their amounts.
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert OnlyPoolManager();
        (
            address owner,
            AsyncOrder[] memory orders,
            Currency[] memory currencies,
            uint256[] memory amounts,
            address recipient
        ) = abi.decode(data, (address, AsyncOrder[], Currency[], uint256[], address));
        if (owner == address(0) || owner != activeOwner) revert InvalidBatch();

        for (uint256 i; i < orders.length; ++i) {
            hook.cancelOrder(orders[i]);
        }
        for (uint256 i; i < currencies.length; ++i) {
            Currency currency = currencies[i];
            uint256 amount = amounts[i];
            poolManager.burn(owner, uint160(Currency.unwrap(currency)), amount);
            poolManager.take(currency, recipient, amount);
            emit ClaimRedeemed(owner, recipient, currency, amount);
        }
        return "";
    }
}
