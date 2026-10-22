// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {AsyncSwap} from "src/AsyncSwap.sol";
import {BaseHook} from "src/BaseHook.sol";
import {Router} from "src/Router.sol";
import {MockERC20} from "../utils/MockERC20.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {ISignatureTransfer} from "@async-swap/interfaces/ISignatureTransfer.sol";

contract DomainHarness is AsyncSwap {
    constructor(IPoolManager manager, Currency quote, address owner_) AsyncSwap(manager, quote, owner_) {}

    function validateHookAddress(BaseHook) internal pure override {}
}

interface IERC5267 {
    function eip712Domain()
        external
        view
        returns (bytes1, string memory, string memory, uint256, address, bytes32, uint256[] memory);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

/// @notice Discharges the assumptions `DomainSpec` / `ShortStringSpec` of
///         formal/Refinement/Swarm/{AsyncSwap,Router}Eip712Domain.lean for the opaque
///         `EIP712.eip712Domain`: it returns (0x0f, name, version, block.chainid, address(this), 0, []),
///         writes no storage, and its fields rebuild DOMAIN_SEPARATOR(), also after a chain id change.
contract Eip712DomainTest is Test {
    bytes32 constant TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    IPoolManager manager;
    MockERC20 usdc;
    DomainHarness hook;
    Router router;

    function setUp() public {
        manager = new PoolManager(address(this));
        usdc = new MockERC20("USD Coin", "USDC", 6);
        hook = new DomainHarness(manager, Currency.wrap(address(usdc)), address(this));
        router = new Router(manager, AsyncSwap(payable(address(hook))), ISignatureTransfer(address(0xBEEF)));
    }

    function _check(address c, string memory expName, uint32 chainBump) internal {
        if (chainBump != 0) vm.chainId(block.chainid + chainBump);
        vm.record();
        (bytes1 f, string memory n, string memory v, uint256 chainId, address verifying, bytes32 salt, uint256[] memory ex)
        = IERC5267(c).eip712Domain();
        (, bytes32[] memory writes) = vm.accesses(c);
        assertEq(writes.length, 0, "eip712Domain writes no storage");
        assertEq(f, bytes1(0x0f), "fields");
        assertEq(n, expName, "name");
        assertEq(v, "1", "version");
        assertEq(chainId, block.chainid, "chainId");
        assertEq(verifying, c, "verifyingContract");
        assertEq(salt, bytes32(0), "salt");
        assertEq(ex.length, 0, "extensions");
        bytes32 rebuilt = keccak256(abi.encode(TYPE_HASH, keccak256(bytes(n)), keccak256(bytes(v)), chainId, verifying));
        assertEq(IERC5267(c).DOMAIN_SEPARATOR(), rebuilt, "ERC-5267 rebuild = DOMAIN_SEPARATOR");
        // short strings: fallback slots unused
        assertEq(vm.load(c, bytes32(uint256(0))), bytes32(0), "_nameFallback");
        assertEq(vm.load(c, bytes32(uint256(1))), bytes32(0), "_versionFallback");
    }

    function testFuzz_asyncSwap_eip712Domain(uint32 bump) public {
        _check(address(hook), "AsyncSwap", bump);
    }

    function testFuzz_router_eip712Domain(uint32 bump) public {
        _check(address(router), "AsyncSwap Router", bump);
    }
}
