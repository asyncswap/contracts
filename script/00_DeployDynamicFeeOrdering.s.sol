// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {FFIHelper} from "./FFIHelper.sol";
import {DynamicFeeOrdering} from "@async-swap/libraries/DynamicFeeOrdering.sol";
import {console} from "forge-std/Script.sol";

/// @notice Deploys the external `DynamicFeeOrdering` library through the deterministic CREATE2 deployer
///         so its address is the same on every chain and known before any transaction is sent.
///         `AsyncMatching` links against this address, so it must exist before that library
///         is deployed (and before `01_DeployHook` mines the hook salt).
/// @dev    Idempotent: if code already exists at the predicted address the script only records it.
contract DeployDynamicFeeOrdering is FFIHelper {
    /// @dev Arachnid's deterministic deployment proxy, present on every chain the registry lists.
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    /// @dev Fixed salt: the library has no constructor arguments, so one salt pins one address per bytecode.
    bytes32 internal constant LIBRARY_SALT = keccak256("asyncswap.v2.DynamicFeeOrdering");

    function predicted() public pure returns (address) {
        bytes32 initCodeHash = keccak256(type(DynamicFeeOrdering).creationCode);
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xFF), CREATE2_DEPLOYER, LIBRARY_SALT, initCodeHash))))
        );
    }

    function run() public {
        require(CREATE2_DEPLOYER.code.length > 0, "CREATE2 deployer missing on this chain");
        address target = predicted();
        console.log("DynamicFeeOrdering predicted address:", target);

        if (target.code.length == 0) {
            vm.startBroadcast(OWNER);
            (bool ok,) = CREATE2_DEPLOYER.call(abi.encodePacked(LIBRARY_SALT, type(DynamicFeeOrdering).creationCode));
            vm.stopBroadcast();
            require(ok, "DynamicFeeOrdering CREATE2 deployment failed");
            require(target.code.length > 0, "DynamicFeeOrdering has no code after deployment");
            console.log("DynamicFeeOrdering deployed.");
        } else {
            console.log("DynamicFeeOrdering already deployed; recording only.");
        }

        if (!vm.envOr("DEPLOY_DRY_RUN", false)) {
            _upsertEntry(
                block.chainid,
                Entry({name: "DynamicFeeOrdering", addr: target, startBlock: block.number, txHash: bytes32(0)})
            );
        }
    }
}
