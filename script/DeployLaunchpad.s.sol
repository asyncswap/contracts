// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Script, console2} from "forge-std/Script.sol";
import {Launchpad} from "src/Launchpad.sol";
import {AsyncSwap} from "src/AsyncSwap.sol";

/// @notice Testnet-only deployment; run without --broadcast to simulate first.
contract DeployLaunchpad is Script {
    function run() external returns (Launchpad pad) {
        require(block.chainid == 1301 || block.chainid == 46630, "Testnet only");
        address target = block.chainid == 1301
            ? 0x91B1e6C36Af74737FF82A654Fa7a1747fE186888
            : 0x91E143120F9758b875713aA5E476E8e853C86888;
        require(target.code.length > 0, "Hook not deployed");
        vm.startBroadcast();
        pad = new Launchpad(AsyncSwap(payable(target)));
        vm.stopBroadcast();
        console2.log("Launchpad", address(pad));
    }
}
