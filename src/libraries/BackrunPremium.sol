// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AsyncFiller} from "@async-swap/libraries/AsyncFiller.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolIdLibrary, PoolKey} from "v4-core/types/PoolKey.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";

/// @title Backrun premium on pool-liquidity fills
/// @notice Linked library called by `AsyncMatching` in the hook's context.
library BackrunPremium {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    /// @dev Blocks a pool fill's starting tick stays the reference that later fills are measured against.
    uint256 internal constant BACKRUN_WINDOW = 2;

    /// @dev Backrun premium on a pool fill, taken from its output. The first pool fill in a window of
    ///      `BACKRUN_WINDOW` blocks records its starting tick as the reference. A later fill in the
    ///      window that moves the price back toward the reference pays half the price gap it closes:
    ///      `amountOut * avgGap / 2`, with the gap averaged over the fill's start and end ticks (one
    ///      tick is about 0.01%), so splitting a backrun does not lower its total. Half of the premium
    ///      is donated to in-range LPs and half credited to the FeeVault as claims.
    function charge(
        AsyncFiller.State storage self,
        PoolKey calldata key,
        Currency output,
        int24 tickBefore,
        uint256 amountOut
    ) public returns (uint256 premium) {
        if (self.refBlock == 0 || block.number > self.refBlock + BACKRUN_WINDOW) {
            (self.refTick, self.refBlock) = (tickBefore, uint64(block.number));
            return 0;
        }
        IPoolManager manager = self.poolManager;
        (, int24 tickAfter,,) = manager.getSlot0(key.toId());
        int256 from = int256(tickBefore) - self.refTick;
        int256 to = int256(tickAfter) - self.refTick;
        // Only a fill toward the reference pays; the part past it closes no gap.
        if (to * from <= 0) to = 0;
        uint256 gapBefore = SignedMath.abs(from);
        uint256 gapAfter = SignedMath.abs(to);
        if (gapAfter >= gapBefore) return 0;
        premium = Math.min(amountOut * (gapBefore + gapAfter) / 40_000, amountOut / 2);
        uint256 toLps = manager.getLiquidity(key.toId()) == 0 ? 0 : premium / 2;
        if (toLps != 0) {
            bool zero = output == key.currency0;
            manager.donate(key, zero ? toLps : 0, zero ? 0 : toLps, "");
        }
        manager.mint(self.feeVault, output.toId(), premium - toLps);
    }
}
