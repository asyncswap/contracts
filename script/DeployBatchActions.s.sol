// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {AsyncSwap} from "src/AsyncSwap.sol";
import {BatchActions} from "src/BatchActions.sol";

/// @notice Deploy the combined cancel/claim helper to Unichain mainnet.
/// @dev Set HOOK_ADDRESS to the deployed Async Swap hook. Foundry obtains the signing key
///      from --account or another standard signer flag; this script never reads a raw key.
contract DeployBatchActions is Script {
    address internal constant UNICHAIN_POOL_MANAGER = 0x1F98400000000000000000000000000000000004;

    function run() external returns (BatchActions actions) {
        require(block.chainid == 130, "Unichain mainnet only");
        address hookAddress = vm.envAddress("HOOK_ADDRESS");
        require(hookAddress.code.length != 0, "Missing Async Swap hook");
        require(UNICHAIN_POOL_MANAGER.code.length != 0, "Missing PoolManager");

        IPoolManager manager = IPoolManager(UNICHAIN_POOL_MANAGER);
        AsyncSwap hook = AsyncSwap(payable(hookAddress));
        require(address(hook.poolManager()) == address(manager), "Hook uses another PoolManager");

        vm.startBroadcast();
        actions = new BatchActions(manager, hook);
        vm.stopBroadcast();
    }
}
