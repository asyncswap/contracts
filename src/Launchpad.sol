// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {LaunchToken} from "./LaunchToken.sol";
import {AsyncSwap} from "./AsyncSwap.sol";
import {CurrencySettler} from "./libraries/CurrencySettler.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/interfaces/callback/IUnlockCallback.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolKey, PoolIdLibrary} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

/// @notice Fixed-supply launches with permanently locked single-sided v4 liquidity.
/// No administrator, upgrade, withdrawal, position-transfer or sweep path exists. Anyone can collect
/// fees, but they always go to the immutable creator. Unused rounding dust remains locked here.
/// Initial price is an ask boundary, not a guaranteed sale or valuation. There is no separate sell order.
contract Launchpad is IUnlockCallback, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;
    using CurrencySettler for Currency;

    AsyncSwap public immutable hook;
    IPoolManager public immutable manager;
    Currency public immutable numeraire;
    uint256 private immutable quoteUnit;
    uint256 private constant Q96 = 1 << 96;

    struct Launch {
        address creator;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
    }

    struct LaunchParams {
        string name;
        string symbol;
        uint256 supply; // token base units (18 decimals)
        uint256 priceX18; // whole numeraire per whole token, scaled by 1e18
        string metadataURI; // public immutable image/social metadata URI
    }
    mapping(address token => Launch) public launches;
    mapping(address creator => uint256) public nextNonce;
    event MarketLaunched(
        address indexed creator,
        address indexed token,
        bytes32 indexed poolId,
        uint256 supply,
        uint256 requestedPriceX18,
        uint160 sqrtPriceX96,
        uint128 liquidity
    );
    event FeesClaimed(address indexed token, address indexed creator, uint256 amount0, uint256 amount1);
    error InvalidLaunch();
    error UnknownToken();
    error OnlyPoolManager();
    error UnexpectedDelta();

    constructor(AsyncSwap hook_) {
        hook = hook_;
        manager = hook_.poolManager();
        numeraire = hook_.numeraire();
        uint8 decimals = IERC20Metadata(Currency.unwrap(numeraire)).decimals();
        if (decimals > 18) revert InvalidLaunch();
        quoteUnit = 10 ** decimals;
    }

    /// @notice Atomically create token, initialize market, and lock its full supply as liquidity plus
    /// rounding dust. At the start only launch tokens are required, no numeraire deposit.
    /// @dev Price rounds UP to the nearest tick in numeraire/token terms. The position spans from
    /// that boundary toward the highest representable token price. Existing Router/hook are unchanged.
    function launch(LaunchParams calldata p) external nonReentrant returns (address token) {
        if (
            bytes(p.name).length == 0 || bytes(p.name).length > 64 || bytes(p.symbol).length == 0
                || bytes(p.symbol).length > 10 || bytes(p.metadataURI).length > 2048 || p.supply == 0
                || p.supply > type(uint128).max || p.priceX18 == 0
        ) revert InvalidLaunch();
        token = _deployToken(p);
        PoolKey memory key = poolKey(token);
        (uint160 start, int24 lower, int24 upper) = _range(token, p.priceX18);
        uint160 a = TickMath.getSqrtPriceAtTick(lower);
        uint160 b = TickMath.getSqrtPriceAtTick(upper);
        uint256 liquidity = token < Currency.unwrap(numeraire)
            ? Math.mulDiv(p.supply, Math.mulDiv(a, b, Q96), b - a)
            : Math.mulDiv(p.supply, Q96, b - a);
        if (liquidity == 0 || liquidity > uint128(type(int128).max)) revert InvalidLaunch();
        launches[token] = Launch(msg.sender, lower, upper, uint128(liquidity));
        manager.initialize(key, start);
        manager.unlock(abi.encode(token, true));
        emit MarketLaunched(
            msg.sender, token, PoolId.unwrap(key.toId()), p.supply, p.priceX18, start, uint128(liquidity)
        );
    }

    /// @dev The current hook requires active liquidity before trying a pool fill. A token1-only
    /// position starts at its exclusive upper tick and has no active liquidity. CREATE2 selects
    /// token0, whose lower tick is inclusive. Bound the search so unusual numeraires fail safely.
    function _deployToken(LaunchParams calldata p) private returns (address token) {
        bytes32 codeHash = keccak256(
            abi.encodePacked(
                type(LaunchToken).creationCode,
                abi.encode(p.name, p.symbol, p.supply, msg.sender, address(this), p.metadataURI)
            )
        );
        uint256 nonce = nextNonce[msg.sender];
        for (uint256 i; i < 128; ++i) {
            bytes32 salt = keccak256(abi.encode(msg.sender, nonce++));
            address predicted =
                address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, codeHash)))));
            if (predicted < Currency.unwrap(numeraire) && predicted.code.length == 0) {
                nextNonce[msg.sender] = nonce;
                return address(
                    new LaunchToken{salt: salt}(p.name, p.symbol, p.supply, msg.sender, address(this), p.metadataURI)
                );
            }
        }
        revert InvalidLaunch();
    }

    function poolKey(address token) public view returns (PoolKey memory) {
        Currency asset = Currency.wrap(token);
        bool first = token < Currency.unwrap(numeraire);
        return PoolKey(first ? asset : numeraire, first ? numeraire : asset, LPFeeLibrary.DYNAMIC_FEE_FLAG, 1, hook);
    }

    function _range(address token, uint256 priceX18) private view returns (uint160 start, int24 lower, int24 upper) {
        bool first = token < Currency.unwrap(numeraire);
        // raw quote/raw asset = priceX18 * quoteUnit / 1e36.
        uint256 ratioX192 = first
            ? Math.mulDiv(priceX18, 1 << 192, 1e36 / quoteUnit, Math.Rounding.Ceil)
            : Math.mulDiv(1e36 / quoteUnit, 1 << 192, priceX18);
        uint256 sqrt = Math.sqrt(ratioX192);
        if (sqrt <= TickMath.MIN_SQRT_PRICE || sqrt >= TickMath.MAX_SQRT_PRICE) revert InvalidLaunch();
        int24 tick = TickMath.getTickAtSqrtPrice(uint160(sqrt));
        // For token0, round above even a fractional sqrt that rounded down to an exact tick.
        if (first && (uint256(TickMath.getSqrtPriceAtTick(tick)) ** 2 < ratioX192)) ++tick;
        lower = first ? tick : TickMath.MIN_TICK;
        upper = first ? TickMath.MAX_TICK : tick;
        if (lower >= upper) revert InvalidLaunch();
        start = TickMath.getSqrtPriceAtTick(tick);
    }

    /// @notice Collect accrued trading fees without removing any liquidity or principal.
    function claimFees(address token) external nonReentrant {
        if (launches[token].creator == address(0)) revert UnknownToken();
        manager.unlock(abi.encode(token, false));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(manager)) revert OnlyPoolManager();
        (address token, bool add) = abi.decode(data, (address, bool));
        Launch memory info = launches[token];
        if (info.creator == address(0)) revert UnknownToken();
        PoolKey memory key = poolKey(token);
        (BalanceDelta delta,) = manager.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: info.tickLower,
                tickUpper: info.tickUpper,
                liquidityDelta: add ? int256(uint256(info.liquidity)) : int256(0),
                salt: bytes32(uint256(uint160(token)))
            }),
            ""
        );
        if (add) {
            // A launch must debit only the freshly minted token, never another launch's funds or quote tokens.
            int128 assetDelta = token < Currency.unwrap(numeraire) ? delta.amount0() : delta.amount1();
            int128 quoteDelta = token < Currency.unwrap(numeraire) ? delta.amount1() : delta.amount0();
            if (assetDelta >= 0 || quoteDelta != 0) revert UnexpectedDelta();
            Currency.wrap(token).settle(manager, address(this), uint256(-int256(assetDelta)), false);
        } else {
            if (delta.amount0() < 0 || delta.amount1() < 0) revert UnexpectedDelta();
            uint256 amount0 = uint128(delta.amount0());
            uint256 amount1 = uint128(delta.amount1());
            if (amount0 != 0) manager.take(key.currency0, info.creator, amount0);
            if (amount1 != 0) manager.take(key.currency1, info.creator, amount1);
            emit FeesClaimed(token, info.creator, amount0, amount1);
        }
        return "";
    }
}
