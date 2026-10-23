// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {UniswapAddresses} from "./config/UniswapAddresses.sol";
import {DeploymentsRegistry} from "./lib/Deployments.sol";
import {AsyncSwap} from "@async-swap/AsyncSwap.sol";
import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";
import {AsyncFiller} from "@async-swap/libraries/AsyncFiller.sol";
import {Vm} from "forge-std/Vm.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/Test.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolIdLibrary, PoolKey} from "v4-core/types/PoolKey.sol";

/// @notice Shared helpers for deploy/runtime scripts in protocol/.
/// @dev Mirrors contracts/script/FFIHelper.sol but adapted to the new AsyncOrder shape
///      (amountOutMin + nonce) and the protocol/ source layout.
contract FFIHelper is Script, DeploymentsRegistry {
    using stdJson for string;
    using PoolIdLibrary for PoolKey;

    address internal constant OWNER_DEFAULT = 0xb1F0982E02f9F71E60512fd47471d76610CcB556;
    address internal constant OWNER_ANVIL = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    /// @dev Deployer and hook owner. Anvil uses the first default account; elsewhere the
    ///      `DEPLOY_OWNER` env var (set by the chain wrapper from the Foundry keystore) wins over the default.
    address internal OWNER =
        block.chainid == UniswapAddresses.CHAIN_ID_ANVIL ? OWNER_ANVIL : vm.envOr("DEPLOY_OWNER", OWNER_DEFAULT);

    /// @notice Resolves the PoolManager address: canonical chain → use canonical;
    ///         otherwise read the registry written by 00_DeployPoolManager.
    function _getDeployedPoolManager() internal view returns (address) {
        if (UniswapAddresses.hasCanonicalPoolManager(block.chainid)) {
            return UniswapAddresses.poolManager(block.chainid);
        }
        Entry memory pm = _readEntry(block.chainid, "PoolManager");
        require(pm.addr != address(0), "PoolManager not in registry --run 00_DeployPoolManager first");
        return pm.addr;
    }

    function _getDeployedHook() internal view returns (address hookAddress, address routerAddress) {
        Entry memory hook = _readEntry(block.chainid, "AsyncSwap");
        Entry memory router = _readEntry(block.chainid, "Router");
        require(hook.addr != address(0), "AsyncSwap hook not in registry --run 01_DeployHook first");
        require(router.addr != address(0), "Router not in registry --run 01_DeployHook first");
        return (hook.addr, router.addr);
    }

    /* ------------------------- pool key persistence ------------------------- */

    function _poolKeyPath() internal view returns (string memory) {
        return string.concat(
            vm.projectRoot(), "/deployments/", vm.toString(block.chainid), "/", vm.toString(block.chainid), "-pool.json"
        );
    }

    /// @notice Persist the active PoolKey to a sidecar JSON so swap/fill scripts can rebuild it
    ///         without scraping broadcast logs.
    function _savePoolKey(PoolKey memory key) internal {
        string memory k = "poolkey";
        vm.serializeAddress(k, "currency0", Currency.unwrap(key.currency0));
        vm.serializeAddress(k, "currency1", Currency.unwrap(key.currency1));
        vm.serializeUint(k, "fee", uint256(key.fee));
        vm.serializeInt(k, "tickSpacing", int256(key.tickSpacing));
        string memory j = vm.serializeAddress(k, "hooks", address(key.hooks));
        vm.writeJson(j, _poolKeyPath());
    }

    function _loadPoolKey() internal view returns (PoolKey memory key) {
        string memory json = vm.readFile(_poolKeyPath());
        key.currency0 = Currency.wrap(json.readAddress(".currency0"));
        key.currency1 = Currency.wrap(json.readAddress(".currency1"));
        key.fee = uint24(json.readUint(".fee"));
        key.tickSpacing = int24(json.readInt(".tickSpacing"));
        key.hooks = AsyncSwap(payable(json.readAddress(".hooks")));
    }

    /* ------------------------- last order persistence ------------------------- */

    struct OrderRecord {
        address owner;
        bool zeroForOne;
        uint256 amountIn;
        uint256 amountOutMin;
        uint160 sqrtPrice;
        /// @dev Salt seen when the script simulated the order. The hook derives the real salt from
        ///      the block it lands in, so `_loadOrder` reads that from the chain instead.
        bytes32 salt;
        /// @dev Block the order was submitted from; the real `AsyncOrderCreated` event is at or after it.
        uint256 fromBlock;
    }

    function _orderPath() internal view returns (string memory) {
        return string.concat(
            vm.projectRoot(),
            "/deployments/",
            vm.toString(block.chainid),
            "/",
            vm.toString(block.chainid),
            "-order.json"
        );
    }

    /// @notice Persist the most-recently-submitted order so 05_ExecuteOrder can fill it without
    ///         relying on event log positions in the broadcast artifact.
    function _saveOrder(OrderRecord memory r) internal {
        string memory k = "lastOrder";
        vm.serializeAddress(k, "owner", r.owner);
        vm.serializeBool(k, "zeroForOne", r.zeroForOne);
        vm.serializeUint(k, "amountIn", r.amountIn);
        vm.serializeUint(k, "amountOutMin", r.amountOutMin);
        vm.serializeUint(k, "sqrtPrice", uint256(r.sqrtPrice));
        vm.serializeUint(k, "fromBlock", r.fromBlock);
        string memory j = vm.serializeBytes32(k, "salt", r.salt);
        vm.writeJson(j, _orderPath());
    }

    function _loadOrder() internal view returns (AsyncOrder memory order) {
        PoolKey memory key = _loadPoolKey();
        string memory json = vm.readFile(_orderPath());
        order = AsyncOrder({
            key: key,
            owner: json.readAddress(".owner"),
            zeroForOne: json.readBool(".zeroForOne"),
            amountIn: json.readUint(".amountIn"),
            amountOutMin: json.readUint(".amountOutMin"),
            priorityFee: 0,
            sqrtPrice: uint160(json.readUint(".sqrtPrice")),
            salt: json.readBytes32(".salt")
        });
        if (vm.keyExistsJson(json, ".fromBlock")) {
            order.salt = _onchainSalt(order, json.readUint(".fromBlock"));
        }
    }

    /// @notice The salt the hook assigned to `order`, read from the newest matching
    ///         `AsyncOrderCreated` event (same pool, owner, side and amounts) since `fromBlock`.
    function _onchainSalt(AsyncOrder memory order, uint256 fromBlock) internal view returns (bytes32) {
        bytes32[] memory topics = new bytes32[](2);
        topics[0] = AsyncFiller.AsyncOrderCreated.selector;
        topics[1] = PoolId.unwrap(order.key.toId());
        Vm.EthGetLogs[] memory logs = vm.eth_getLogs(fromBlock, block.number, address(order.key.hooks), topics);
        for (uint256 i = logs.length; i > 0; i--) {
            Vm.EthGetLogs memory log = logs[i - 1];
            if (log.topics.length < 4 || address(uint160(uint256(log.topics[3]))) != order.owner) continue;
            (bool zeroForOne, uint256 amountIn, uint256 amountOutMin, bytes32 salt) =
                abi.decode(log.data, (bool, uint256, uint256, bytes32));
            if (zeroForOne == order.zeroForOne && amountIn == order.amountIn && amountOutMin == order.amountOutMin) {
                return salt;
            }
        }
        revert("AsyncOrderCreated for the saved order not found on chain");
    }

    /// @notice The priority bid an order pays, in numeraire (USDC) base units: `PRIORITY_FEE` if
    ///         set, otherwise the least bid the hook accepts. Mirrors `AsyncFiller.minPriorityFee`:
    ///         min($0.10, 0.1% of the order's USDC notional), where the notional is a buy's input
    ///         or a sell's minimum output.
    function _priorityFee(Currency numeraire, Currency input, uint256 amountIn, uint256 amountOutMin)
        internal
        view
        returns (uint256)
    {
        uint256 notional = input == numeraire ? amountIn : amountOutMin;
        uint256 tiered = notional * 10 / 10_000;
        return vm.envOr("PRIORITY_FEE", tiered < 100_000 ? tiered : 100_000);
    }

    /// @notice Approve the Router for an order's input and its priority bid. The bid is pulled in
    ///         the numeraire; when that is also the input, one approval covers both. Native input is
    ///         sent as `msg.value` and needs no approval.
    function _approveOrderFunds(address router, Currency numeraire, Currency input, uint256 amountIn, uint256 bid)
        internal
    {
        if (input == numeraire) {
            IERC20Like(Currency.unwrap(numeraire)).approve(router, amountIn + bid);
            return;
        }
        if (!input.isAddressZero()) IERC20Like(Currency.unwrap(input)).approve(router, amountIn);
        if (bid != 0) IERC20Like(Currency.unwrap(numeraire)).approve(router, bid);
    }
}

interface IERC20Like {
    function approve(address spender, uint256 amount) external returns (bool);
}
