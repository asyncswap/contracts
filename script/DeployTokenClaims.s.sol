// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {TokenClaims} from "src/TokenClaims.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

contract DeployTokenClaims is Script {
    function run() external returns (TokenClaims claims) {
        require(block.chainid == 130, "Unichain mainnet only");
        IPoolManager manager = IPoolManager(0x1F98400000000000000000000000000000000004);
        require(address(manager).code.length != 0, "Missing PoolManager");
        vm.startBroadcast();
        claims = new TokenClaims(manager);
        vm.stopBroadcast();
    }
}
