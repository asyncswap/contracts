// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {ISignatureTransfer} from "@async-swap/interfaces/ISignatureTransfer.sol";
import {UniswapAddresses} from "./config/UniswapAddresses.sol";
import {FFIHelper} from "./FFIHelper.sol";
import {AsyncSwap} from "@async-swap/AsyncSwap.sol";
import {Router} from "@async-swap/Router.sol";
import {console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

/// @notice Deploys the Router (the one swap caller the hook accepts) and then the AsyncSwap hook (with the
///         required permission flags + 0x91 prefix) at the address the Router was built with, then records both into the deployments registry. Salt mining is offline via FFI
///         to `script/mine-hook-salt.ts`.
contract DeployHookScript is FFIHelper {
    IPoolManager manager;
    AsyncSwap public hook;
    Router router;

    /// @dev Top-byte prefix used to visually identify the hook (0x91...).
    uint160 internal constant HOOK_PREFIX = uint160(0x91) << 152;
    uint160 internal constant HOOK_PREFIX_MASK = uint160(0xFF) << 152;
    /// @dev Canonical Permit2 (same address on every chain).
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    /// @dev Arachnid's deterministic deployment proxy, which the hook salt is mined against.
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function setUp() public {
        manager = IPoolManager(_getDeployedPoolManager());
    }

    function run() public {
        uint160 hookFlags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );

        // The chain wrapper resolves this from script/config/chains.json and validates its code.
        // It is intentionally not a user-editable .env value.
        Currency numeraire = Currency.wrap(vm.envAddress("DEPLOY_NUMERAIRE_ADDRESS"));
        require(Currency.unwrap(numeraire).code.length > 0, "Configured numeraire must be a deployed token");
        // The hook trusts only the Router as swap caller, and the Router takes the hook in its constructor: the
        // Router goes first, as OWNER's next CREATE, pointing at the hook's mined address.
        address predictedRouter = vm.computeCreateAddress(OWNER, vm.getNonce(OWNER));
        // Pools get a $10 minimum order (DEPLOY_MIN_ORDER_USD). The hook scales it, and its $0.10 priority-bid
        // cap, by the numeraire's decimals. Both are fixed at deployment.
        uint256 minOrderUsd = vm.envOr("DEPLOY_MIN_ORDER_USD", uint256(10));
        // Order creation and fills pay an MEV tax of their priority fee per gas times this, fixed at deployment.
        // It is per chain (deployment.mevTaxGas in script/config/chains.json, exported by deploy.sh) and has no
        // default: only on a chain ordered by priority fee does it capture searcher bids (20M gas, about 30x an
        // order's gas, takes roughly 97% of them); elsewhere it would only tax ordinary tips, so it is 0.
        uint256 mevTaxGas = vm.envUint("DEPLOY_MEV_TAX_GAS");
        bytes memory creationCode = type(AsyncSwap).creationCode;
        bytes memory constructorArgs = abi.encode(
            address(manager),
            numeraire,
            OWNER,
            predictedRouter,
            minOrderUsd,
            uint8(4) // orders trade at least 0.0001 of a whole asset token
        );
        bytes32 initCodeHash = keccak256(abi.encodePacked(creationCode, constructorArgs));

        bytes32 salt = _readSaltEnv();
        if (salt == bytes32(0)) {
            salt = _mineSaltViaFfi(initCodeHash);
        }

        address predicted = _computeCreate2Address(CREATE2_DEPLOYER, salt, initCodeHash);
        require((uint160(predicted) & Hooks.ALL_HOOK_MASK) == hookFlags, "salt does not produce required hook flags");
        require((uint160(predicted) & HOOK_PREFIX_MASK) == HOOK_PREFIX, "salt does not produce required 0x91 prefix");
        require(predicted.code.length == 0, "hook already deployed at predicted address");

        console.log("hook salt:");
        console.logBytes32(salt);
        console.log("predicted hook address:", predicted);

        vm.startBroadcast(OWNER);
        router = new Router(manager, AsyncSwap(payable(predicted)), ISignatureTransfer(PERMIT2), mevTaxGas);
        require(address(router) == predictedRouter, "deployed router address mismatch");
        // Through the CREATE2 factory explicitly, as the library scripts do: on some chains Forge runs
        // `new AsyncSwap{salt: salt}` as a CREATE2 from the sender instead, missing the mined address.
        (bool ok,) = CREATE2_DEPLOYER.call(abi.encodePacked(salt, creationCode, constructorArgs));
        require(ok, "hook CREATE2 deployment failed");
        hook = AsyncSwap(payable(predicted));
        require(address(hook).code.length > 0, "deployed hook address mismatch");
        require(hook.owner() == OWNER, "hook owner mismatch");
        vm.stopBroadcast();

        if (!vm.envOr("DEPLOY_DRY_RUN", false)) {
            _recordDeployments();
        }
    }

    function _recordDeployments() internal {
        uint256 deployBlock = block.number;
        // Elsewhere 00_DeployPoolManager has already recorded the PoolManager it deployed.
        if (UniswapAddresses.hasCanonicalPoolManager(block.chainid)) {
            _upsertEntry(
                block.chainid,
                Entry({
                    name: "PoolManager",
                    addr: address(manager),
                    startBlock: UniswapAddresses.poolManagerStartBlock(block.chainid),
                    txHash: bytes32(0)
                })
            );
        }
        _upsertEntry(
            block.chainid, Entry({name: "AsyncSwap", addr: address(hook), startBlock: deployBlock, txHash: bytes32(0)})
        );
        _upsertEntry(
            block.chainid, Entry({name: "Router", addr: address(router), startBlock: deployBlock, txHash: bytes32(0)})
        );
        _upsertEntry(
            block.chainid,
            Entry({name: "FeeVault", addr: address(hook.feeVault()), startBlock: deployBlock, txHash: bytes32(0)})
        );
    }

    /// @dev Calls `bun run script/mine-hook-salt.ts --ffi --init-code-hash <hash>`.
    function _mineSaltViaFfi(bytes32 initCodeHash) internal returns (bytes32) {
        string[] memory cmd = new string[](6);
        cmd[0] = "bun";
        cmd[1] = "run";
        cmd[2] = "script/mine-hook-salt.ts";
        cmd[3] = "--ffi";
        cmd[4] = "--init-code-hash";
        cmd[5] = vm.toString(initCodeHash);

        bytes memory out = vm.ffi(cmd);
        require(out.length == 32, "miner returned unexpected output length");
        // forge-lint: disable-next-line(unsafe-typecast)
        return bytes32(out);
    }

    function _readSaltEnv() internal view returns (bytes32) {
        try vm.envBytes32("HOOK_SALT") returns (bytes32 s) {
            return s;
        } catch {
            return bytes32(0);
        }
    }

    function _computeCreate2Address(address deployer, bytes32 salt, bytes32 initCodeHash)
        internal
        pure
        returns (address)
    {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xFF), deployer, salt, initCodeHash)))));
    }
}
