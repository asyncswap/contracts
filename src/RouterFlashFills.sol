// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IAsyncSwapCallback} from "@async-swap/interfaces/IAsyncSwapCallback.sol";
import {IAsyncSwapFlashFiller} from "@async-swap/interfaces/IAsyncSwapFlashFiller.sol";
import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {TransientStateLibrary} from "v4-core/libraries/TransientStateLibrary.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolIdLibrary, PoolKey} from "v4-core/types/PoolKey.sol";
import {AsyncSwap} from "src/AsyncSwap.sol";

/// @title RouterFlashFills
/// @author @msakiart
/// @notice The Router's flash-fill surface (`IAsyncSwapCallback`). The Router creates this module in its constructor
///         and runs it by DELEGATECALL from its `fallback`, so every call executes as the Router: the hook sees the
///         Router as caller, and the transient filler slot lives in the Router's context. Kept out of the Router so
///         its runtime stays under EIP-170.
/// @dev Called directly (not through the Router) every hook call reverts `NotTrustedRouter`.
contract RouterFlashFills is IAsyncSwapCallback {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    IPoolManager immutable POOLMANAGER;
    AsyncSwap immutable HOOK;
    uint256 immutable MEV_TAX_GAS;

    /// @dev Router transient slot this module shares (see Router).
    /// keccak256("Router.FlashFiller") - 1: the filler of the flash fill in progress, zero otherwise.
    bytes32 constant FLASH_FILLER_LOCATION = 0x8a32db0797977fc7694da75ada74debc8ae08fbf3557ccd5133e780e8ba11369;
    /// @dev First word of the Router's unlock data for a flash fill: `Router.ActionType.FlashFill`.
    uint8 constant FLASH_FILL_ACTION = 9;

    uint8 constant BEGIN = 0;
    uint8 constant SETTLE = 1;
    uint8 constant FILL = 2;

    /// @notice A flash fill is already running.
    error FlashFillActive();
    /// @notice An in-callback entry point was called by anyone but the filler of the running flash fill.
    error NotFlashFiller();

    event MevTaxPaid(address indexed payer, uint256 amount);

    /// @notice The filler left `owed` of the MEV tax of its fills unpaid.
    error MevTaxUnpaid(uint256 owed);

    constructor(IPoolManager _poolManager, AsyncSwap _hook, uint256 _mevTaxGas) {
        POOLMANAGER = _poolManager;
        HOOK = _hook;
        MEV_TAX_GAS = _mevTaxGas;
    }

    /// @inheritdoc IAsyncSwapCallback
    function fillOrderWithCallback(AsyncOrder calldata order, uint256 maxPrice, bytes calldata data) external payable {
        if (_flashFiller() != address(0)) revert FlashFillActive();
        POOLMANAGER.unlock(abi.encode(FLASH_FILL_ACTION, order, msg.sender, maxPrice, data, msg.value));
    }

    /// @notice Body of a flash fill: the Router's `unlockCallback` forwards its calldata here (running as the Router)
    ///         when the action is a flash fill. Input first, callback, then the output check and payout.
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(POOLMANAGER), "Caller is not PoolManager");
        (, AsyncOrder memory order, address filler, uint256 maxPrice, bytes memory fillerData, uint256 prepaid) =
            abi.decode(data, (uint8, AsyncOrder, address, uint256, bytes, uint256));
        _checkFill(order, maxPrice);
        _chargeMevTax(filler);
        (uint256 amountIn, uint256 amountOwed) = _hookCall(BEGIN, order, filler);
        assembly ("memory-safe") {
            tstore(FLASH_FILLER_LOCATION, filler)
        }
        IAsyncSwapFlashFiller(filler).asyncSwapFlashFill(order, amountIn, amountOwed, fillerData);
        assembly ("memory-safe") {
            tstore(FLASH_FILLER_LOCATION, 0)
        }
        // The maker check is on what the filler holds at the end, whatever route it took.
        POOLMANAGER.transferFrom(filler, address(HOOK), _output(order).toId(), amountOwed);
        _hookCall(SETTLE, order, filler);
        _settleMevTax(filler, prepaid);
        return "";
    }

    /// @inheritdoc IAsyncSwapCallback
    function fillOrderInCallback(AsyncOrder calldata order, uint256 maxPrice) external {
        _onlyFlashFiller();
        uint256 owed = _checkFill(order, maxPrice);
        _chargeMevTax(msg.sender);
        POOLMANAGER.transferFrom(msg.sender, address(HOOK), _output(order).toId(), owed);
        _hookCall(FILL, order, msg.sender);
    }

    /// @inheritdoc IAsyncSwapCallback
    function matchBookInCallback(PoolKey calldata key, uint8 maxMatches) external returns (uint8) {
        _onlyFlashFiller();
        return HOOK.matchBook(key, maxMatches);
    }

    /// @inheritdoc IAsyncSwapCallback
    function mevTaxFor(uint256 fills) external view returns (uint256) {
        return _mevTax() * fills;
    }

    /// @inheritdoc IAsyncSwapCallback
    function mevTaxOwed() external view returns (uint256) {
        int256 delta = TransientStateLibrary.currencyDelta(POOLMANAGER, address(this), CurrencyLibrary.ADDRESS_ZERO);
        return delta < 0 ? uint256(-delta) : 0;
    }

    function _mevTax() private view returns (uint256) {
        return tx.gasprice > block.basefee ? (tx.gasprice - block.basefee) * MEV_TAX_GAS : 0;
    }

    /// @dev Pays one fill's MEV tax to the FeeVault as native claims now; the Router owes it to the PoolManager
    ///      until `_settleMevTax`.
    function _chargeMevTax(address filler) private {
        uint256 tax = _mevTax();
        if (tax == 0) return;
        POOLMANAGER.mint(address(HOOK.feeVault()), 0, tax);
        emit MevTaxPaid(filler, tax);
    }

    /// @dev Settles the prepayment, then requires the Router's native delta to be covered: the filler may have paid
    ///      with `settleFor(router)` in its callback. A surplus goes back to the filler.
    function _settleMevTax(address filler, uint256 prepaid) private {
        if (prepaid != 0) {
            POOLMANAGER.sync(CurrencyLibrary.ADDRESS_ZERO);
            POOLMANAGER.settle{value: prepaid}();
        }
        int256 delta = TransientStateLibrary.currencyDelta(POOLMANAGER, address(this), CurrencyLibrary.ADDRESS_ZERO);
        if (delta < 0) revert MevTaxUnpaid(uint256(-delta));
        if (delta > 0) POOLMANAGER.take(CurrencyLibrary.ADDRESS_ZERO, filler, uint256(delta));
    }

    function _hookCall(uint8 op, AsyncOrder memory order, address filler) private returns (uint256, uint256) {
        return HOOK.flashFill(abi.encode(op, order, filler));
    }

    function _onlyFlashFiller() private view {
        if (msg.sender != _flashFiller() || msg.sender == address(0)) revert NotFlashFiller();
    }

    function _flashFiller() private view returns (address filler) {
        assembly ("memory-safe") {
            filler := tload(FLASH_FILLER_LOCATION)
        }
    }

    function _output(AsyncOrder memory order) private pure returns (Currency) {
        return order.zeroForOne ? order.key.currency1 : order.key.currency0;
    }

    /// @dev Checks the live order against the filler's bounds and returns the output owed: the live minimum, at most
    ///      `maxPrice`, for a live input of at least `order.amountIn`. A missing order is left for the hook to reject.
    ///      The flash path charges no pool fee, so the hook burns exactly the live minimum it returns.
    function _checkFill(AsyncOrder memory order, uint256 maxPrice) private view returns (uint256 livePrice) {
        bytes32 id = keccak256(abi.encode(block.chainid, order.key.toId(), order.owner, order.zeroForOne, order.salt));
        uint256 liveAmountIn;
        (liveAmountIn, livePrice) = HOOK.asyncOrderInfo(order.key.toId(), id);
        require(liveAmountIn == 0 || liveAmountIn >= order.amountIn, "Input below order.amountIn");
        require(livePrice <= maxPrice, "Price exceeds maxPrice");
    }
}
