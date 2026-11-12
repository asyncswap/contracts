// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AsyncFiller} from "@async-swap/libraries/AsyncFiller.sol";
import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";
import {PoolIdLibrary, PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";

/// @title MultiAsset
/// @author @msakiart
/// @notice Linked module for multi-asset trading: pool setup (including pools without the numeraire) and the hook's
///         side of flash fills and of fills paid in ERC-6909 claims. Public library calls use DELEGATECALL, so escrow,
///         books and the transient flash record stay in the hook.
library MultiAsset {
    using AsyncFiller for AsyncFiller.State;
    using PoolIdLibrary for PoolKey;

    /// @notice Close the order and credit its input, less the trade fee, to the filler as claims; record it as the
    ///         open flash fill. Returns the input credited and the output owed.
    uint8 internal constant BEGIN = 0;
    /// @notice Pay the maker of the open flash fill out of the output claims the Router has transferred to the hook.
    uint8 internal constant SETTLE = 1;
    /// @notice A full fill paid in claims (inside a flash fill): the hook already holds the output as claims.
    uint8 internal constant FILL = 2;

    /// @dev Transient record of the open flash fill, in the hook's context: its id, then the input and minimum output
    ///      it was opened at. Each slot is keccak256("asyncswap.flashFill.<name>") - 1.
    bytes32 private constant FLASH_ORDER_SLOT = 0xadcc9340e9b9520481a90c5e1cb2c7bb827085ef7c7b209a028db0fe766510cd;
    bytes32 private constant FLASH_AMOUNT_IN_SLOT = 0xa948fdbbf716a51dd3ab76f9643ccf5ff5ac531fed11e84d483629e540b40220;
    bytes32 private constant FLASH_AMOUNT_OUT_SLOT = 0x4af24310f6994917e24875d474455b553ed83a7345f90cd7dd124597d7de6b85;

    /// @notice Immutable hook settings `initialize` copies into each new pool.
    struct PoolConfig {
        IPoolManager poolManager;
        Currency numeraire;
        address feeVault;
        uint256 minOrder;
        uint64 priorityFeeCap;
        uint8 assetPrecision;
    }

    error FlashFillActive();
    error NumeraireRequired();
    error DynamicFeeRequired();
    error AssetHasNoCode();
    error NoFlashFill();

    /// @notice Set up a new pool's state and book. Anyone may open a pool that pairs the numeraire with a dynamic fee. A
    ///         pool without the numeraire (for example ETH/TOKEN) may be opened only once both of its tokens have a
    ///         numeraire pool on this hook with the same tick spacing, so every such order has a numeraire route for
    ///         fillers. On it `currency1` is the quote side, each side's minimum is its token's decimal floor (no dollar
    ///         minimum), and priority bids are refused (`AsyncFiller.NO_PRIORITY_BIDS`). No check reads a price.
    function initialize(
        mapping(PoolId => AsyncFiller.State) storage states,
        AsyncFiller.Book storage book,
        PoolKey calldata key,
        PoolConfig calldata config
    ) public {
        Currency numeraire = config.numeraire;
        bool hasNumeraire = key.currency0 == numeraire || key.currency1 == numeraire;
        if (!hasNumeraire) {
            _requireNumerairePool(states, numeraire, key.currency0, key.tickSpacing);
            _requireNumerairePool(states, numeraire, key.currency1, key.tickSpacing);
        }
        if (key.fee != LPFeeLibrary.DYNAMIC_FEE_FLAG) revert DynamicFeeRequired();
        AsyncFiller.State storage state = states[key.toId()];
        state.poolManager = config.poolManager;
        state.numeraire = numeraire;
        state.feeVault = config.feeVault;
        book.minOrder = hasNumeraire ? config.minOrder : _minAssetAmount(key.currency1, config.assetPrecision);
        book.priorityFeeCap = hasNumeraire ? config.priorityFeeCap : AsyncFiller.NO_PRIORITY_BIDS;
        // The asset side: the non-numeraire token, or `currency0` on a pool without the numeraire.
        book.minAssetAmount =
            _minAssetAmount(key.currency0 == numeraire ? key.currency1 : key.currency0, config.assetPrecision);
    }

    /// @dev Reverts `NumeraireRequired` unless `currency` already has a numeraire pool on this hook with `tickSpacing`.
    function _requireNumerairePool(
        mapping(PoolId => AsyncFiller.State) storage states,
        Currency numeraire,
        Currency currency,
        int24 tickSpacing
    ) private view {
        (Currency c0, Currency c1) = currency < numeraire ? (currency, numeraire) : (numeraire, currency);
        PoolKey memory numeraireKey = PoolKey({
            currency0: c0,
            currency1: c1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(this))
        });
        if (address(states[numeraireKey.toId()].poolManager) == address(0)) revert NumeraireRequired();
    }

    /// @dev 10^(decimals - assetPrecision) base units of `asset`, at least 1. Native ETH has 18 decimals. A token
    ///      without a readable `decimals()` gets the 1-unit floor, and reported decimals are capped at 36. An asset
    ///      with no code reverts: a pool opened before its token is deployed would otherwise keep a 1-unit floor.
    function _minAssetAmount(Currency asset, uint8 assetPrecision) private view returns (uint256) {
        uint256 decimals = 18;
        if (!asset.isAddressZero()) {
            if (Currency.unwrap(asset).code.length == 0) revert AssetHasNoCode();
            (bool ok, bytes memory ret) = Currency.unwrap(asset).staticcall(abi.encodeWithSignature("decimals()"));
            if (!ok || ret.length < 32) return 1;
            decimals = abi.decode(ret, (uint256));
            if (decimals > 36) decimals = 36;
        }
        return decimals > assetPrecision ? 10 ** (decimals - assetPrecision) : 1;
    }

    /// @dev The flash path charges no pool fee: `AsyncSwap.calculatePoolFee` is zero, and the 0.02% trade fee comes
    ///      out of what each side receives, as in a plain fill. `executor` is the hook's caller (the Router).
    function run(AsyncFiller.State storage self, AsyncFiller.Book storage book, bytes calldata args, address executor)
        public
        returns (uint256, uint256)
    {
        (uint8 op, AsyncOrder memory order, address filler) = abi.decode(args, (uint8, AsyncOrder, address));
        bytes32 id = keccak256(abi.encode(block.chainid, order.key.toId(), order.owner, order.zeroForOne, order.salt));
        if (op == BEGIN) return _begin(self, book, order, id, executor, filler);
        if (op == SETTLE) {
            _settle(self, order, id, filler);
        } else {
            _fill(self, book, order, id, executor, filler);
        }
        return (0, 0);
    }

    function _begin(
        AsyncFiller.State storage self,
        AsyncFiller.Book storage book,
        AsyncOrder memory order,
        bytes32 id,
        address executor,
        address filler
    ) private returns (uint256, uint256) {
        _openFlashFill(id);
        (uint256 amountIn, uint256 amountOut) = self.beginFlashFill(book, order, id, executor, filler);
        assembly ("memory-safe") {
            tstore(FLASH_AMOUNT_IN_SLOT, amountIn)
            tstore(FLASH_AMOUNT_OUT_SLOT, amountOut)
        }
        return (amountIn - AsyncFiller.tradeFee(amountIn), amountOut);
    }

    function _settle(AsyncFiller.State storage self, AsyncOrder memory order, bytes32 id, address filler) private {
        (uint256 amountIn, uint256 amountOut) = _closeFlashFill(id);
        self.settleClaimsOutput(order, id, filler, amountIn, amountOut);
    }

    function _fill(
        AsyncFiller.State storage self,
        AsyncFiller.Book storage book,
        AsyncOrder memory order,
        bytes32 id,
        address executor,
        address filler
    ) private {
        (uint256 amountIn, uint256 amountOut) = self.beginFlashFill(book, order, id, executor, filler);
        self.settleClaimsOutput(order, id, filler, amountIn, amountOut);
    }

    function _openFlashFill(bytes32 id) private {
        bytes32 active;
        assembly ("memory-safe") {
            active := tload(FLASH_ORDER_SLOT)
        }
        if (active != bytes32(0)) revert FlashFillActive();
        assembly ("memory-safe") {
            tstore(FLASH_ORDER_SLOT, id)
        }
    }

    function _closeFlashFill(bytes32 id) private returns (uint256 amountIn, uint256 amountOut) {
        bytes32 active;
        assembly ("memory-safe") {
            active := tload(FLASH_ORDER_SLOT)
            amountIn := tload(FLASH_AMOUNT_IN_SLOT)
            amountOut := tload(FLASH_AMOUNT_OUT_SLOT)
            tstore(FLASH_ORDER_SLOT, 0)
            tstore(FLASH_AMOUNT_IN_SLOT, 0)
            tstore(FLASH_AMOUNT_OUT_SLOT, 0)
        }
        if (active == bytes32(0) || active != id) revert NoFlashFill();
    }
}
