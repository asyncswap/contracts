// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {V4CapacityTest} from "../../uniswap-v4/fixtures/V4Capacity.t.sol";
import {RouterParameters} from "../../../.local/universal-router/contracts/types/RouterParameters.sol";
import {IUniversalRouter} from "../../../.local/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {IAllowanceTransfer} from "../../../.local/universal-router/lib/permit2/src/interfaces/IAllowanceTransfer.sol";
import {IV4Router} from "../../../.local/universal-router/lib/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "../../../.local/universal-router/lib/v4-periphery/src/libraries/Actions.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {console2} from "forge-std/console2.sol";

/// @dev Deploy separately built release bytecode so UR keeps its release compiler settings.
contract UniversalCapacityTest is V4CapacityTest {
    using PoolIdLibrary for PoolKey;
    IAllowanceTransfer permit;
    IUniversalRouter universal;

    function _route(bool sell, uint256 input, uint256 minimum, uint256 deadline) internal view returns (bytes memory) {
        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));
        bytes[] memory params = new bytes[](3);
        params[0] =
            abi.encode(IV4Router.ExactInputSingleParams(key, sell, uint128(input), uint128(minimum), 0, bytes("")));
        params[1] = abi.encode(sell ? key.currency0 : key.currency1, input);
        params[2] = abi.encode(sell ? key.currency1 : key.currency0, minimum);
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);
        return abi.encodeCall(IUniversalRouter.execute, (hex"10", inputs, deadline));
    }

    function _exportUniversal(string memory name, bool sell, bool unlimited) internal {
        _seedLiquidity();
        permit = IAllowanceTransfer(deployCode("deployments/benchmark-Permit2.json"));
        RouterParameters memory config;
        config.permit2 = address(permit);
        config.v4PoolManager = address(manager);
        universal = IUniversalRouter(deployCode("deployments/benchmark-UniversalRouter.json", abi.encode(config)));
        require(address(universal).code.length <= 24576, "Router exceeds EIP-170");
        uint256 input = sell ? 1 ether : 1000e6;
        uint256 minimum = sell ? 990e6 : 0.99 ether;
        bytes memory data = _route(sell, input, minimum, 10000);
        for (uint256 i; i < COUNT; ++i) {
            address actor = address(uint160(0x400000 + i));
            asset.mint(actor, FUNDS);
            quote.mint(actor, FUNDS);
            vm.startPrank(actor);
            asset.approve(address(permit), type(uint256).max);
            quote.approve(address(permit), type(uint256).max);
            // Finite allowance exercises the packed allowance update; unlimited is a standing max approval.
            permit.approve(
                sell ? address(asset) : address(quote),
                address(universal),
                unlimited ? type(uint160).max : uint160(input),
                type(uint48).max
            );
            vm.stopPrank();
            console2.log(string.concat("TX|", name, "|", vm.toString(actor), "|", vm.toString(data)));
        }
        // Confirm the measured execute selector enforces the user-facing guards before exporting state.
        vm.warp(1000);
        vm.prank(address(0x400000));
        (bool expired, bytes memory expiredReason) = address(universal).call(_route(sell, input, minimum, 999));
        require(!expired, "Expired route accepted");
        assertEq(bytes4(expiredReason), IUniversalRouter.TransactionDeadlinePassed.selector);
        vm.prank(address(0x400000));
        (bool unfillable, bytes memory minimumReason) = address(universal).call(_route(sell, input, minimum * 2, 10000));
        require(!unfillable, "Minimum output ignored");
        assertEq(bytes4(minimumReason), IV4Router.V4TooLittleReceived.selector);
        vm.etch(address(universal), address(universal).code);
        vm.etch(address(permit), address(permit).code);
        vm.etch(address(asset), address(asset).code);
        vm.etch(address(quote), address(quote).code);
        vm.dumpState(string.concat("deployments/universal-capacity-", name, ".json"));
        console2.log(
            string.concat(
                "META|",
                name,
                "|",
                vm.toString(address(universal)),
                "|",
                vm.toString(address(manager)),
                "|",
                vm.toString(PoolId.unwrap(key.toId())),
                "|",
                vm.toString(input)
            )
        );
        console2.log(string.concat("PERMIT|", name, "|", vm.toString(address(permit))));
    }

    function test_universalMaxBuy() public {
        _exportUniversal("max_buy", false, true);
    }

    function test_universalMaxSell() public {
        _exportUniversal("max_sell", true, true);
    }

    function test_universalFiniteBuy() public {
        _exportUniversal("finite_buy", false, false);
    }

    function test_universalFiniteSell() public {
        _exportUniversal("finite_sell", true, false);
    }
}
