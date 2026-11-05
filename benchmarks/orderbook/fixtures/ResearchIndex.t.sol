// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {RadixPriceTree} from "@async-swap/libraries/RadixPriceTree.sol";
import {TickBitmap} from "@async-swap/libraries/TickBitmap.sol";
import {AsyncFiller} from "@async-swap/libraries/AsyncFiller.sol";
import {EligiblePrice} from "@async-swap/libraries/EligiblePrice.sol";

contract IndexHarness {
    using RadixPriceTree for RadixPriceTree.Tree;
    using TickBitmap for TickBitmap.Tree;
    RadixPriceTree.Tree private radix;
    TickBitmap.Tree private bitmap;
    bool immutable useBitmap;

    constructor(bool use_) {
        useBitmap = use_;
    }

    function insert(uint128 key) external returns (bool) {
        return useBitmap ? bitmap.insert(key) : radix.insert(key);
    }

    function remove(uint128 key) external {
        if (useBitmap) bitmap.remove(key);
        else radix.remove(key);
    }

    function best(bool highest) external view returns (bool, uint128) {
        return useBitmap ? bitmap.best(highest) : radix.best(highest);
    }
}

/// @dev Queue bookkeeping only. No funding/authorization API is being proposed by this harness.
contract RekeyHarness {
    using AsyncFiller for AsyncFiller.State;
    using AsyncFiller for AsyncFiller.Book;
    using RadixPriceTree for RadixPriceTree.Tree;
    AsyncFiller.State private state;
    AsyncFiller.Book private book;
    bool immutable localOnly;

    constructor(bool local_) {
        localOnly = local_;
    }

    function seed(uint256 count) external {
        for (uint256 i = 1; i <= count; ++i) {
            AsyncFiller.OrderInfo storage o = state.orders[bytes32(i)];
            o.owner = address(uint160(i));
            o.amountIn = 1 ether;
            o.amountOutMin = 1e9;
            o.price = 1000;
            o.sequence = ++book.nextSequence;
            o.createdSequence = o.sequence;
            o.priorityFee = uint64(100_000 + i);
            o.zeroForOne = true;
            AsyncFiller._append(state, book, bytes32(i));
        }
    }

    function rekey(uint256 id, uint64 fee) external {
        bytes32 key = bytes32(id);
        AsyncFiller.OrderInfo storage o = state.orders[key];
        require(o.amountIn != 0 && fee > o.priorityFee);
        if (!localOnly) {
            AsyncFiller._remove(state, book, key);
            o.priorityFee = fee;
            o.sequence = ++book.nextSequence;
            AsyncFiller._append(state, book, key);
        } else {
            // Fee-only changes keep price and order counts fixed, so retain the outer level.
            // Reinsert the inner key and repair exact-price bounds after its topology changes.
            AsyncFiller.PriceLevel storage level = book.askLevels[o.price];
            EligiblePrice.remove(level.priorityOrders, level.exactBounds, o.priorityKey, false);
            delete level.priorityOrderIds[o.priorityKey];
            o.priorityFee = fee;
            o.sequence = ++book.nextSequence;
            // Larger fees rank first; inverted sequence breaks fee ties by earlier arrival.
            o.priorityKey = (uint128(fee) << 64) | uint128(type(uint64).max - o.sequence);
            level.priorityOrders.insert(o.priorityKey);
            state.refreshExactPrice(book, key);
            level.priorityOrderIds[o.priorityKey] = key;
        }
    }

    function digest(uint256 count) external view returns (bytes32 h) {
        (bool found, uint128 price, bytes32 id, address maker) = state.bestOrder(book, false);
        h = keccak256(
            abi.encode(found, price, id, maker, book.openOrderCount, book.nextSequence, book.askLevels[1000].orderCount)
        );
        for (uint256 i = 1; i <= count; ++i) {
            h = keccak256(abi.encode(h, state.orders[bytes32(i)]));
        }
    }
}

contract ResearchIndexTest is Test {
    event Bench(string implementation, string workload, uint256 size, uint256 grossGas);

    function _log(string memory implementation, string memory workload, uint256 size, uint256 used) internal {
        console2.log(
            string.concat("BENCH|", implementation, "|", workload, "|", vm.toString(size), "|", vm.toString(used))
        );
    }

    function _measure(address target, bytes memory data) internal returns (uint256 used) {
        uint256 snap = vm.snapshotState();
        vm.record();
        (bool ok,) = target.call(data);
        require(ok, "dry call failed");
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(target);
        require(vm.revertToState(snap));
        for (uint256 i; i < reads.length; ++i) {
            vm.coolSlot(target, reads[i]);
        }
        for (uint256 i; i < writes.length; ++i) {
            vm.coolSlot(target, writes[i]);
        }
        vm.cool(target);
        uint256 beforeGas = gasleft();
        (ok,) = target.call(data);
        used = beforeGas - gasleft();
        require(ok, "measured call failed");
        require(vm.revertToState(snap));
    }

    function _key(uint256 i, bool sparse) internal pure returns (uint128) {
        return sparse ? uint128(1 + (i * 1733) % 1_774_545) : uint128(800_000 + i);
    }

    function _bench(uint256 n, bool sparse) internal {
        IndexHarness a = new IndexHarness(false);
        IndexHarness b = new IndexHarness(true);
        for (uint256 i; i < n; ++i) {
            a.insert(_key(i, sparse));
            b.insert(_key(i, sparse));
        }
        _benchOne(a, "radix", n, sparse);
        _benchOne(b, "bitmap", n, sparse);
    }

    function _benchOne(IndexHarness h, string memory kind, uint256 n, bool sparse) internal {
        string memory shape = sparse ? "sparse" : "dense";
        _log(kind, string.concat(shape, "/best"), n, _measure(address(h), abi.encodeCall(h.best, (false))));
        _log(
            kind, string.concat(shape, "/insert"), n, _measure(address(h), abi.encodeCall(h.insert, (_key(n, sparse))))
        );
        _log(
            kind,
            string.concat(shape, "/remove"),
            n,
            _measure(address(h), abi.encodeCall(h.remove, (_key(n / 2, sparse))))
        );
    }

    function test_benchmarkIndex() public {
        uint256[4] memory sizes = [uint256(1), 32, 256, 1024];
        for (uint256 i; i < sizes.length; ++i) {
            _bench(sizes[i], false);
            _bench(sizes[i], true);
        }
    }

    function test_benchmarkRekey() public {
        uint256[4] memory sizes = [uint256(1), 32, 256, 1024];
        for (uint256 i; i < sizes.length; ++i) {
            uint256 n = sizes[i];
            RekeyHarness a = new RekeyHarness(false);
            RekeyHarness b = new RekeyHarness(true);
            a.seed(n);
            b.seed(n);
            uint256 id = (n + 1) / 2;
            _log("remove_append", "fee_rekey", n, _measure(address(a), abi.encodeCall(a.rekey, (id, 1_000_000))));
            _log("priority_only", "fee_rekey", n, _measure(address(b), abi.encodeCall(b.rekey, (id, 1_000_000))));
            a.rekey(id, 1_000_000);
            b.rekey(id, 1_000_000);
            assertEq(a.digest(n), b.digest(n));
        }
    }

    function testFuzz_indexMatchesLinearScan(uint256 seed) public {
        IndexHarness a = new IndexHarness(false);
        IndexHarness b = new IndexHarness(true);
        uint128[64] memory keys;
        bool[64] memory active;
        keys[0] = 1;
        keys[1] = 255;
        keys[2] = 256;
        keys[3] = 65535;
        keys[4] = 65536;
        keys[5] = 1_774_545;
        for (uint256 i = 6; i < 64; ++i) {
            keys[i] = uint128(100_000 + i * 1000);
        }
        for (uint256 step; step < 128; ++step) {
            seed = uint256(keccak256(abi.encode(seed, step)));
            uint256 j = seed % 64;
            if (active[j] && seed & 128 != 0) {
                a.remove(keys[j]);
                b.remove(keys[j]);
                active[j] = false;
            } else {
                assertEq(a.insert(keys[j]), !active[j]);
                assertEq(b.insert(keys[j]), !active[j]);
                active[j] = true;
            }
            uint128 low = type(uint128).max;
            uint128 high;
            for (uint256 i; i < 64; ++i) {
                if (active[i]) {
                    if (keys[i] < low) low = keys[i];
                    if (keys[i] > high) high = keys[i];
                }
            }
            for (uint256 k; k < 2; ++k) {
                IndexHarness h = k == 0 ? a : b;
                (bool f, uint128 p) = h.best(false);
                assertEq(f, high != 0);
                if (f) assertEq(p, low);
                (f, p) = h.best(true);
                assertEq(f, high != 0);
                if (f) assertEq(p, high);
            }
        }
    }

    function test_bitmapBoundariesAndEmpty() public {
        IndexHarness b = new IndexHarness(true);
        (bool f,) = b.best(false);
        assertFalse(f);
        vm.expectRevert(TickBitmap.InvalidKey.selector);
        b.insert(0);
        vm.expectRevert(TickBitmap.InvalidKey.selector);
        b.insert(1_774_546);
        vm.expectRevert(TickBitmap.PriceLevelMissing.selector);
        b.remove(1);
        b.insert(1);
        b.insert(1_774_545);
        b.remove(1);
        b.remove(1_774_545);
        (f,) = b.best(true);
        assertFalse(f);
        assertTrue(b.insert(1));
    }

    function testFuzz_rekeyPreservesState(uint256 seed) public {
        RekeyHarness a = new RekeyHarness(false);
        RekeyHarness b = new RekeyHarness(true);
        a.seed(32);
        b.seed(32);
        for (uint256 i; i < 32; ++i) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            uint256 id = 1 + seed % 32;
            uint64 fee = uint64(1_000_000 + i);
            a.rekey(id, fee);
            b.rekey(id, fee);
            assertEq(a.digest(32), b.digest(32));
        }
    }
}
