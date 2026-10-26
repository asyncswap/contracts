// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/types/Currency.sol";

/// @notice Atomically redeems a caller's PoolManager ERC-6909 claims for several currencies.
/// @dev The caller must first make this contract an operator on PoolManager. The operator
///      permission is used only for claims owned by msg.sender and paid to their recipient.
contract BatchClaims {
    IPoolManager public immutable poolManager;
    bool private _redeeming;

    error OnlyPoolManager();
    error InvalidRedemption();
    error ReentrantRedemption();
    event ClaimRedeemed(address indexed owner, address indexed recipient, Currency indexed currency, uint256 amount);

    constructor(IPoolManager manager) {
        poolManager = manager;
    }

    modifier nonReentrant() {
        if (_redeeming) revert ReentrantRedemption();
        _redeeming = true;
        _;
        _redeeming = false;
    }

    function redeem(Currency[] calldata currencies, address recipient, uint256[] calldata amounts)
        external
        nonReentrant
    {
        uint256 length = currencies.length;
        if (recipient == address(0) || length == 0 || length != amounts.length || length > 16) {
            revert InvalidRedemption();
        }
        for (uint256 i; i < length; ++i) {
            if (amounts[i] == 0) revert InvalidRedemption();
            for (uint256 j; j < i; ++j) {
                if (Currency.unwrap(currencies[i]) == Currency.unwrap(currencies[j])) revert InvalidRedemption();
            }
        }
        poolManager.unlock(abi.encode(msg.sender, recipient, currencies, amounts));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert OnlyPoolManager();
        (address owner, address recipient, Currency[] memory currencies, uint256[] memory amounts) =
            abi.decode(data, (address, address, Currency[], uint256[]));
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
