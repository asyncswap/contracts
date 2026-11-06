// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {AsyncFiller} from "src/libraries/AsyncFiller.sol";
import {AsyncMatching} from "src/libraries/AsyncMatching.sol";

/// @dev Invoke the actual production helper, not a copied arithmetic specification.
contract ProductionMatchAmounts {
    function matchAmounts(uint256 si, uint256 sm, uint256 bi, uint256 bm, bool makerBuy)
        external
        pure
        returns (uint256, uint256)
    {
        AsyncFiller.OrderInfo memory sell;
        AsyncFiller.OrderInfo memory buy;
        sell.amountIn = si;
        sell.amountOutMin = sm;
        buy.amountIn = bi;
        buy.amountOutMin = bm;
        AsyncFiller.MatchAmounts memory amounts = AsyncMatching._matchAmounts(sell, buy, makerBuy);
        return (amounts.assetAmount, amounts.quoteAmount);
    }
}

contract HuffProductionParityTest is Test {
    address kernel;
    ProductionMatchAmounts production;

    function setUp() public {
        bytes memory code = vm.parseBytes(vm.readFile("deployments/incoming-math-huff.hex"));
        address deployed;
        assembly ("memory-safe") { deployed := create(0, add(code, 32), mload(code)) }
        require(deployed != address(0), "kernel deployment failed");
        kernel = deployed;
        production = new ProductionMatchAmounts();
    }

    function _compare(uint256 si, uint256 sm, uint256 bi, uint256 bm, bool makerBuy) internal view {
        bytes memory data = abi.encodeCall(production.matchAmounts, (si, sm, bi, bm, makerBuy));
        (bool h, bytes memory hr) = kernel.staticcall(data);
        (bool s, bytes memory sr) = address(production).staticcall(data);
        assertEq(h, s, "success or overflow parity");
        assertEq(hr, sr, "production return/revert bytes");
    }

    function testFuzz_huffMatchesProduction(uint256 si, uint256 sm, uint256 bi, uint256 bm, bool makerBuy) public view {
        // Admission and reduction guarantee positive inputs/minima for a live matching pair.
        _compare(si == 0 ? 1 : si, sm == 0 ? 1 : sm, bi == 0 ? 1 : bi, bm == 0 ? 1 : bm, makerBuy);
    }

    function test_huffMatchesProductionBoundaries() public view {
        uint256[5] memory values = [uint256(1), 2, 1 << 127, 1 << 255, type(uint256).max];
        for (uint256 a; a < 5; ++a) {
            for (uint256 b; b < 5; ++b) {
                for (uint256 c; c < 5; ++c) {
                    for (uint256 d; d < 5; ++d) {
                        _compare(values[a], values[b], values[c], values[d], false);
                        _compare(values[a], values[b], values[c], values[d], true);
                    }
                }
            }
        }
    }
}
