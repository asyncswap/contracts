// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TickMath} from "v4-core/libraries/TickMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @notice Book levels on Uniswap v4 ticks: an order sits at the floor tick (spacing 1, 0.01% steps)
///         of its exact currency1/currency0 limit. Levels are a fixed relative width at any price and
///         for any token decimals; the exact limit still decides crossing within a level.
library TickPrice {
    /// @notice Radix key of an order's level, ordered by numeraire per asset. Monotone in the exact
    ///         price, so distinct keys order prices strictly. Keys run from 1 to 2 * MAX_TICK + 1;
    ///         ratios beyond the v4 price range share the end keys.
    function key(bool isBuy, bool zeroForOne, uint256 amountIn, uint256 amountOut) public pure returns (uint128) {
        // currency1 per currency0: a currency0 seller's output over its input, otherwise the reverse.
        int24 tick = zeroForOne ? floorTick(amountOut, amountIn) : floorTick(amountIn, amountOut);
        return isBuy != zeroForOne
            ? uint128(uint24(tick - TickMath.MIN_TICK)) + 1
            : uint128(uint24(TickMath.MAX_TICK - tick)) + 1;
    }

    /// @notice Largest tick whose price is at most num/den, clamped to the v4 tick range. Monotone in
    ///         num/den. Two regimes keep sqrt(num/den) * 2^96 well inside one tick of exact.
    function floorTick(uint256 num, uint256 den) internal pure returns (int24) {
        uint256 sqrtPrice;
        if (num / den < 1 << 64) {
            sqrtPrice = Math.sqrt(Math.mulDiv(num, 1 << 192, den));
        } else {
            if (num / den >= 1 << 128) return TickMath.MAX_TICK;
            sqrtPrice = Math.sqrt(Math.mulDiv(num, 1 << 128, den)) << 32;
        }
        if (sqrtPrice < TickMath.MIN_SQRT_PRICE) return TickMath.MIN_TICK;
        if (sqrtPrice >= TickMath.MAX_SQRT_PRICE) return TickMath.MAX_TICK;
        return TickMath.getTickAtSqrtPrice(uint160(sqrtPrice));
    }
}
