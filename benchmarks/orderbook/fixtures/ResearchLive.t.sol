// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SetupHook} from "test/SetupHook.t.sol";
import {AsyncSwap} from "@async-swap/AsyncSwap.sol";
import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";
import {console2} from "forge-std/console2.sol";

/// @notice Public Router/hook operations. Gross call gas excludes setup, approvals, intrinsic gas and refunds.
contract ResearchLiveTest is SetupHook {
    struct Access {
        address target;
        bytes32[] reads;
        bytes32[] writes;
    }
    AsyncOrder[] internal orders;
    address internal extra = address(0xeeee);

    function _fund(address actor) internal {
        topUp(actor, 1e30);
        vm.startPrank(actor);
        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    function _order(address actor, bool sell, uint256 input, uint256 minimum)
        internal
        view
        returns (AsyncOrder memory o)
    {
        o = AsyncOrder(key, actor, sell, input, minimum, 100_000, 2 ** 96, bytes32(0));
    }

    function _swapData(AsyncOrder memory o) internal view returns (bytes memory) {
        return abi.encodeCall(
            router.swap, (o, abi.encode(AsyncSwap.UserParams(o.owner, address(router), o.amountOutMin, o.priorityFee)))
        );
    }

    function _submit(AsyncOrder memory o) internal returns (AsyncOrder memory) {
        vm.prank(o.owner);
        (bool ok, bytes memory result) = address(router).call(_swapData(o));
        if (!ok) {
            assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
        }
        o.salt = _expectedSalt(o.owner, o.amountIn, o.amountOutMin);
        return o;
    }

    function _digest(AsyncOrder memory extraOrder) internal view returns (bytes32 h) {
        for (uint256 i; i <= orders.length; ++i) {
            AsyncOrder memory o = i == orders.length ? extraOrder : orders[i];
            bytes32 id = _orderIdFor(o.owner, o.zeroForOne, o.salt);
            (address maker, uint256 ai, uint256 ao, uint128 p, bool buy, uint64 seq, uint64 fee) =
                hook.orderBookOrder(poolId, id);
            h = keccak256(abi.encode(h, maker, ai, ao, p, buy, seq, fee));
            h = keccak256(
                abi.encode(
                    h,
                    token0.balanceOf(o.owner),
                    token1.balanceOf(o.owner),
                    manager.balanceOf(o.owner, currency0.toId()),
                    manager.balanceOf(o.owner, currency1.toId())
                )
            );
        }
        for (uint256 i; i < 2; ++i) {
            (bool found, uint128 p, bytes32 id, address maker) = hook.bestOrder(poolId, i == 0);
            h = keccak256(abi.encode(h, found, p, id, maker));
        }
        h = keccak256(
            abi.encode(
                h,
                manager.balanceOf(address(hook), currency0.toId()),
                manager.balanceOf(address(hook), currency1.toId()),
                manager.balanceOf(address(hook.feeVault()), currency0.toId()),
                manager.balanceOf(address(hook.feeVault()), currency1.toId())
            )
        );
    }

    function _measure(address target, address actor, bytes memory data, AsyncOrder memory extraOrder)
        internal
        returns (uint256 used, bytes32 digest)
    {
        uint256 snap = vm.snapshotState();
        vm.record();
        vm.prank(actor);
        (bool ok, bytes memory result) = target.call(data);
        if (!ok) {
            assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
        }
        address[6] memory targets = [
            address(router), address(hook), address(manager), address(token0), address(token1), address(hook.feeVault())
        ];
        Access[] memory accesses = new Access[](6);
        for (uint256 i; i < 6; ++i) {
            (bytes32[] memory r, bytes32[] memory w) = vm.accesses(targets[i]);
            accesses[i] = Access(targets[i], r, w);
        }
        require(vm.revertToState(snap));
        for (uint256 i; i < 6; ++i) {
            for (uint256 j; j < accesses[i].reads.length; ++j) {
                vm.coolSlot(targets[i], accesses[i].reads[j]);
            }
            for (uint256 j; j < accesses[i].writes.length; ++j) {
                vm.coolSlot(targets[i], accesses[i].writes[j]);
            }
            vm.cool(targets[i]);
        }
        vm.prank(actor);
        uint256 beforeGas = gasleft();
        (ok, result) = target.call(data);
        used = beforeGas - gasleft();
        if (!ok) {
            assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
        }
        digest = _digest(extraOrder);
        require(vm.revertToState(snap));
    }

    function _log(
        string memory workload,
        uint256 n,
        address target,
        address actor,
        bytes memory data,
        AsyncOrder memory extraOrder
    ) internal {
        (uint256 used, bytes32 digest) = _measure(target, actor, data, extraOrder);
        console2.log(
            string.concat("LIVE|", workload, "|", vm.toString(n), "|", vm.toString(used), "|", vm.toString(digest))
        );
    }

    function _bench(uint256 n, bool distinct) internal {
        uint256 highest = 1000e6;
        for (uint256 i; i < n; ++i) {
            address actor = address(uint160(0x10000 + i));
            _fund(actor);
            uint256 quote = 1000e6 + (distinct ? i * 1e6 : 0);
            highest = quote;
            orders.push(_submit(_order(actor, true, 1 ether, quote)));
        }
        _fund(extra);
        string memory shape = distinct ? "distinct" : "same_price";
        AsyncOrder memory fresh = _order(extra, true, 1 ether, highest + 1e6);
        AsyncOrder memory expected = fresh;
        expected.salt = _expectedSalt(extra, fresh.amountIn, fresh.amountOutMin);
        if (vm.envOr("EXPORT_RESEARCH_FIXTURE", false)) {
            vm.etch(address(router), address(router).code);
            vm.dumpState("deployments/research-fixture.json");
            _export("place", address(router), extra, _swapData(fresh));
            _export("cancel", address(router), orders[n / 2].owner, abi.encodeCall(router.cancelOrder, (orders[n / 2])));
            _export(
                "reprice",
                address(hook),
                orders[n / 2].owner,
                abi.encodeCall(hook.updatePrice, (orders[n / 2], highest + 2e6))
            );
            _export("incoming_8", address(router), extra, _swapData(_order(extra, false, 8 * (highest + 1e6), 8 ether)));
        }
        _log(string.concat(shape, "/place"), n, address(router), extra, _swapData(fresh), expected);
        AsyncOrder memory middle = orders[n / 2];
        _log(
            string.concat(shape, "/cancel"),
            n,
            address(router),
            middle.owner,
            abi.encodeCall(router.cancelOrder, (middle)),
            expected
        );
        _log(
            string.concat(shape, "/reprice"),
            n,
            address(hook),
            middle.owner,
            abi.encodeCall(hook.updatePrice, (middle, highest + 2e6)),
            expected
        );
        fresh = _order(extra, false, 8 * (highest + 1e6), 8 ether);
        expected = fresh;
        expected.salt = _expectedSalt(extra, fresh.amountIn, fresh.amountOutMin);
        _log(string.concat(shape, "/incoming_8"), n, address(router), extra, _swapData(fresh), expected);
        // Independent correctness checks outside the measured region.
        _submit(fresh);
        for (uint256 i; i < 8; ++i) {
            assertEq(hook.asyncOrder(poolId, _orderIdFor(orders[i].owner, true, orders[i].salt)), 0);
        }
        assertEq(hook.asyncOrder(poolId, _orderIdFor(orders[8].owner, true, orders[8].salt)), 1 ether);
    }

    function _export(string memory name, address target, address actor, bytes memory data) internal pure {
        console2.log(
            string.concat("TX|", name, "|", vm.toString(target), "|", vm.toString(actor), "|", vm.toString(data))
        );
    }

    function test_samePrice32() public {
        _bench(32, false);
    }

    function test_samePrice256() public {
        _bench(256, false);
    }

    function test_samePrice1024() public {
        _bench(1024, false);
    }

    function test_distinct32() public {
        _bench(32, true);
    }

    function test_distinct256() public {
        _bench(256, true);
    }

    function test_distinct1024() public {
        _bench(1024, true);
    }
}
