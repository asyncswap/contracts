// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {Router} from "src/Router.sol";
import {AsyncSwap} from "src/AsyncSwap.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {ISignatureTransfer} from "src/interfaces/ISignatureTransfer.sol";

/// @notice Deploy an updated Router alongside an existing immutable-hook deployment.
/// @dev The existing Router remains the creation route; this Router handles cancellation and claims.
contract DeployWithdrawalRouter is Script {
    function run() external returns (Router withdrawalRouter) {
        require(
            block.chainid == 1301 || block.chainid == 11155111 || block.chainid == 5042002 || block.chainid == 46630,
            "Testnets only"
        );
        string memory id = vm.toString(block.chainid);
        string memory registry = vm.readFile(string.concat("deployments/", id, "/", id, ".json"));
        IPoolManager manager = IPoolManager(vm.parseJsonAddress(registry, ".contracts.PoolManager.address"));
        AsyncSwap hook = AsyncSwap(payable(vm.parseJsonAddress(registry, ".contracts.AsyncSwap.address")));
        Router current = Router(payable(vm.parseJsonAddress(registry, ".contracts.Router.address")));
        require(
            address(hook.poolManager()) == address(manager) && hook.router() == address(current), "Registry mismatch"
        );
        ISignatureTransfer permit2 = current.PERMIT2();
        vm.startBroadcast();
        withdrawalRouter = new Router(manager, hook, permit2, current.MEV_TAX_GAS());
        vm.stopBroadcast();
    }
}
