// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PriorityFeeTopUpTest} from "../../../test/PriorityFeeTopUp.t.sol";
import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";
import {PriorityFeeUpdates} from "../../../src/libraries/PriorityFeeUpdates.sol";
import {console2} from "forge-std/console2.sol";

/// @dev Exports committed book states; the runner measures fresh Router transactions on Anvil.
contract PriorityFeeTopUpGasTest is PriorityFeeTopUpTest {
    function _export(string memory name, AsyncOrder memory order) internal {
        vm.etch(address(router), address(router).code);
        vm.etch(address(token0), address(token0).code);
        vm.etch(address(token1), address(token1).code);
        // This library has not been called during setup; explicitly include it in the exported state.
        vm.etch(address(PriorityFeeUpdates), address(PriorityFeeUpdates).code);
        // dumpState exports accessed storage; load pool settlement fields even for a zero-bid book.
        hook.asyncOrders(poolId);
        vm.dumpState(string.concat("deployments/topup-", name, ".json"));
        console2.log(
            string.concat(
                "TX|",
                name,
                "|",
                vm.toString(address(router)),
                "|",
                vm.toString(order.owner),
                "|",
                vm.toString(abi.encodeCall(router.topUpPriorityFee, (order, uint256(100_000))))
            )
        );
    }

    function test_exportSinglePaid() public {
        _fund(alice);
        _export("single_paid", _place(alice, true, 1 ether, 2_000e6, 100_000));
    }

    function test_exportSingleZero() public {
        _fund(alice);
        _export("single_zero", _place(alice, true, 1 ether, 2_000e6, 0));
    }

    function test_exportCrowded() public {
        AsyncOrder memory target;
        for (uint256 i; i < 32; ++i) {
            address maker = address(uint160(0x30000 + i));
            _fund(maker);
            AsyncOrder memory order = _place(maker, true, 1 ether, 2_000e6, 100_000);
            if (i == 16) target = order;
        }
        _export("same_price_32", target);
    }

    function test_exportDistinct() public {
        AsyncOrder memory target;
        for (uint256 i; i < 256; ++i) {
            address maker = address(uint160(0x30000 + i));
            _fund(maker);
            AsyncOrder memory order = _place(maker, true, 1 ether, (2_000 + i) * 1e6, 100_000);
            if (i == 128) target = order;
        }
        _export("distinct_prices_256", target);
    }
}
