// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {AsyncSwap} from "src/AsyncSwap.sol";
import {BaseHook} from "src/BaseHook.sol";
import {MockERC20} from "../utils/MockERC20.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/types/Currency.sol";

/// @dev Bypasses hook-address mining only, so the real constructor runs at an arbitrary address.
contract CtorHarness is AsyncSwap {
    constructor(IPoolManager manager, Currency quote, address owner_) AsyncSwap(manager, quote, owner_) {}

    function validateHookAddress(BaseHook) internal pure override {}
}

/// @notice Discharges the assumptions `CtorStorageSpec` and `Immutables` stated in
///         formal/Refinement/Swarm/AsyncSwapConstructor.lean for the opaque `AsyncSwap.constructor`.
contract AsyncSwapConstructorTest is Test {
    bytes32 constant TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    IPoolManager manager;
    MockERC20 usdc;

    function setUp() public {
        manager = new PoolManager(address(this));
        usdc = new MockERC20("USD Coin", "USDC", 6);
    }

    function _built(address self) internal view returns (bytes32) {
        return keccak256(abi.encode(TYPE_HASH, keccak256("AsyncSwap"), keccak256("1"), block.chainid, self));
    }

    /// CtorStorageSpec, guard 1: numeraire without code reverts InvalidNumeraire (even with owner 0).
    function testFuzz_ctor_invalidNumeraire(address num, address owner_) public {
        vm.assume(num.code.length == 0);
        vm.expectRevert(AsyncSwap.InvalidNumeraire.selector);
        new CtorHarness(manager, Currency.wrap(num), owner_);
    }

    /// CtorStorageSpec, guard 2: numeraire with code, zero owner reverts ZeroAddress.
    function test_ctor_zeroOwner() public {
        vm.expectRevert(AsyncSwap.ZeroAddress.selector);
        new CtorHarness(manager, Currency.wrap(address(usdc)), address(0));
    }

    /// CtorStorageSpec success + Immutables.
    function testFuzz_ctor_success(address owner_) public {
        vm.assume(owner_ != address(0));
        CtorHarness h = new CtorHarness(manager, Currency.wrap(address(usdc)), owner_);
        address a = address(h);
        // storage: only `owner` (slot 4) written
        assertEq(vm.load(a, bytes32(uint256(0))), bytes32(0), "_nameFallback");
        assertEq(vm.load(a, bytes32(uint256(1))), bytes32(0), "_versionFallback");
        assertEq(vm.load(a, bytes32(uint256(2))), bytes32(0));
        assertEq(vm.load(a, bytes32(uint256(3))), bytes32(0));
        assertEq(vm.load(a, bytes32(uint256(4))), bytes32(uint256(uint160(owner_))), "owner slot");
        assertEq(vm.load(a, bytes32(uint256(5))), bytes32(0), "pendingOwner");
        assertEq(vm.load(a, bytes32(uint256(6))), bytes32(0));
        assertEq(h.owner(), owner_);
        // immutables
        assertEq(address(h.poolManager()), address(manager));
        assertEq(Currency.unwrap(h.numeraire()), address(usdc));
        assertGt(address(h.feeVault()).code.length, 0);
        (, string memory name, string memory version, uint256 chainId, address verifying,,) = h.eip712Domain();
        assertEq(name, "AsyncSwap");
        assertEq(version, "1");
        assertEq(chainId, block.chainid);
        assertEq(verifying, a);
        assertEq(h.DOMAIN_SEPARATOR(), _built(a), "cached separator = built");
    }

    /// DOMAIN_SEPARATOR_eq_built after a chain id change.
    function test_domainSeparator_rebuiltAfterFork() public {
        CtorHarness h = new CtorHarness(manager, Currency.wrap(address(usdc)), address(this));
        vm.chainId(block.chainid + 7);
        assertEq(h.DOMAIN_SEPARATOR(), _built(address(h)));
    }
}
