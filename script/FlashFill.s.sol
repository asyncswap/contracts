// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AsyncSwapFlashFiller} from "@async-swap/periphery/AsyncSwapFlashFiller.sol";
import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";
import {Script, console} from "forge-std/Script.sol";

/// @notice Runs a flash fill through a filler built on `AsyncSwapFlashFiller`, sending exactly the ETH the MEV tax
///         needs. The tax depends on the priority fee, so pass the gas price you will broadcast with: the quote is
///         simulated at that price.
///
///   FILLER=<filler> FILLS=<fills in the callback, the order itself included> \
///   forge script script/FlashFill.s.sol --sig "run(bytes,uint256,bytes)" <abi-encoded order> <maxPrice> <route data> \
///     --rpc-url $RPC --with-gas-price <wei> --priority-gas-price <wei> --broadcast
///
/// @dev The filler pays `ROUTER.mevTaxOwed()` from its own balance inside the callback, so a quote that is a little
///      high only leaves ETH in the filler; `ethNeeded` already counts what it holds.
contract FlashFill is Script {
    function run(bytes calldata encodedOrder, uint256 maxPrice, bytes calldata data) external {
        AsyncSwapFlashFiller filler = AsyncSwapFlashFiller(payable(vm.envAddress("FILLER")));
        uint256 fills = vm.envOr("FILLS", uint256(1));
        AsyncOrder memory order = abi.decode(encodedOrder, (AsyncOrder));

        uint256 value = filler.ethNeeded(fills);
        console.log("MEV tax for fills:", fills);
        console.log("ETH to send:", value);

        vm.startBroadcast();
        filler.fill{value: value}(order, maxPrice, data);
        vm.stopBroadcast();
    }
}
