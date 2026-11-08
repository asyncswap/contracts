// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/types/Currency.sol";

/// @notice Require full ERC-20 delivery without charging extra to the sender; token-reported success is insufficient.
library TokenTransfers {
    using SafeERC20 for IERC20;
    error TokenNotSupported(address token);

    struct Balances {
        uint256 from;
        uint256 to;
    }

    function snapshot(address token, address from, address to) internal view returns (Balances memory balances) {
        balances.from = IERC20(token).balanceOf(from);
        balances.to = IERC20(token).balanceOf(to);
    }

    function verify(address token, address from, address to, uint256 amount, Balances memory before) internal view {
        uint256 afterFrom = IERC20(token).balanceOf(from);
        uint256 afterTo = IERC20(token).balanceOf(to);
        // Check direction before subtraction so every mismatch uses the same explicit error.
        // A callback may add unrelated funds (e.g. LP funding); those must not cause a false short-payment rejection.
        if (from == to) {
            if (afterFrom != before.from || afterTo != before.to) revert TokenNotSupported(token);
        } else if (
            (afterFrom < before.from && before.from - afterFrom > amount) || afterTo < before.to
                || afterTo - before.to < amount
        ) {
            revert TokenNotSupported(token);
        }
    }

    function transferFrom(address token, address from, address to, uint256 amount) internal {
        uint256 before = IERC20(token).balanceOf(from);
        IERC20(token).safeTransferFrom(from, to, amount);
        verifyDebit(token, from, amount, before);
    }

    /// @dev PoolManager verifies deposit credit at settlement. Preserve CurrencyNotSettled for short deposits.
    function verifyDebit(address token, address from, uint256 amount, uint256 before) internal view {
        uint256 afterBalance = IERC20(token).balanceOf(from);
        if (afterBalance < before && before - afterBalance > amount) revert TokenNotSupported(token);
    }

    function transfer(address token, address to, uint256 amount) internal {
        Balances memory before = snapshot(token, address(this), to);
        IERC20(token).safeTransfer(to, amount);
        verify(token, address(this), to, amount, before);
    }

    /// @dev A liquidity miss may leave an order resting; an unsupported token must fail the caller explicitly.
    function bubbleUnsupported(bytes memory reason) internal pure {
        if (reason.length >= 4 && bytes4(reason) == TokenNotSupported.selector) {
            assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
        }
    }

    function take(IPoolManager manager, Currency currency, address to, uint256 amount) internal {
        address token = Currency.unwrap(currency);
        if (token == address(0)) {
            manager.take(currency, to, amount);
            return;
        }
        Balances memory before = snapshot(token, address(manager), to);
        manager.take(currency, to, amount);
        verify(token, address(manager), to, amount, before);
    }
}
