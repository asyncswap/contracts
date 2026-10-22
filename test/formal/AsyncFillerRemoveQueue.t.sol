// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {AsyncFillerBookHarness} from "./AsyncFillerBookHarness.sol";
import {AsyncFiller} from "@async-swap/libraries/AsyncFiller.sol";

/// @notice Bytecode checks of `formal/Refinement/Swarm/AsyncFillerRemoveQueue.lean`: `AsyncFiller._remove`'s
///         FIFO branch (the model's `unlinkOrders` / `unlinkLevel`) and `queue_unlink`. `_remove` is
///         `internal`, so it runs in `AsyncFillerBookHarness` on the harness's own book.
///
///         The `unlink_*` / `unlinkLevel_*` theorems hold for any pointer structure, so those tests put
///         arbitrary `previous` / `next` links (including self-links, shared neighbours and dangling
///         ids) on orders 0..4 and remove one of them. `_remove` then also decrements the level's
///         `orderCount` and the book's `openOrderCount`, and deletes the level when the count reaches
///         0; that last step is outside `unlinkLevel`, so the level tests use a count >= 2.
contract AsyncFillerRemoveQueueFormalTest is Test {
    AsyncFillerBookHarness h;

    bytes32 constant PID = keccak256("formal.remove.pid");
    uint128 constant P = 1e18; // _priceKey(_, 1e18, 1e18)

    struct LinkIn {
        uint8 k; // which of orders 1..4 is removed
        bool isBuy;
        uint256 seed; // links and the other fields of orders 0..4
        uint32 count;
        uint64 open;
        bytes32 head;
        bytes32 tail;
        uint8 endsKind;
    }

    AsyncFiller.OrderInfo[5] internal before;
    bytes32 internal levelHead0;
    bytes32 internal levelTail0;
    uint32 internal levelCount0;

    function setUp() public {
        h = new AsyncFillerBookHarness();
    }

    function _u(uint256 i) internal pure returns (bytes32) {
        return bytes32(i);
    }

    /// @dev A FIFO book where `target` (one of 1..4) sits at price P (so its level and the tree leaf
    ///      exist), then orders 0..4 overwritten with arbitrary fields and links into {0..4}, the level's
    ///      head/tail/count and the book's openOrderCount set from `x`. Snapshots the pre-state, then
    ///      runs `_remove(target)` under `vm.record()`.
    function _arbitrary(LinkIn memory x, uint32 minCount) internal returns (bytes32 target) {
        target = _u(1 + x.k % 4);
        h.addOrder(
            PID,
            AsyncFiller.NewOrder({
                id: target,
                owner: address(1),
                amountIn: 1 ether,
                amountOutMin: 1 ether,
                isBuy: x.isBuy,
                zeroForOne: true,
                priorityFee: 0
            })
        );
        for (uint256 i; i < 5; ++i) {
            uint256 r = uint256(keccak256(abi.encode(x.seed, i)));
            AsyncFiller.OrderInfo memory o = AsyncFiller.OrderInfo({
                owner: address(uint160(r)),
                amountIn: r >> 3,
                amountOutMin: r >> 5,
                price: uint128(r >> 7),
                previous: _u((r >> 40) % 5),
                next: _u((r >> 48) % 5),
                isBuy: (r >> 56) & 1 == 1,
                zeroForOne: (r >> 57) & 1 == 1,
                sequence: uint64(r >> 64),
                priorityFee: uint64(r >> 128),
                priorityKey: uint128(r >> 100),
                priorityFeeEscrowed: (r >> 58) & 1 == 1
            });
            if (_u(i) == target) {
                o.isBuy = x.isBuy;
                o.price = P;
            }
            h.setOrder(PID, _u(i), o);
            before[i] = o;
        }
        uint32 count = uint32(bound(x.count, minCount, type(uint32).max));
        bytes32 head = x.endsKind % 2 == 0 ? _u(uint256(x.head) % 5) : x.head;
        bytes32 tail = x.endsKind % 3 == 0 ? _u(uint256(x.tail) % 5) : x.tail;
        h.setLevel(PID, x.isBuy, P, head, tail, count);
        h.setOpenOrderCount(PID, uint64(bound(x.open, 1, type(uint64).max)));
        (levelHead0, levelTail0, levelCount0) = (head, tail, count);
        vm.record();
        h.remove(PID, target);
    }

    function _prevOf(bytes32 target) internal view returns (bytes32) {
        return before[uint256(target)].previous;
    }

    function _nextOf(bytes32 target) internal view returns (bytes32) {
        return before[uint256(target)].next;
    }

    // ================================================================ unlinkOrders

    /// @notice formal/Refinement/Swarm/AsyncFillerRemoveQueue.lean:41 — after _remove's FIFO unlink, orders[x].next = (previous(id) != 0 and x = previous(id)) ? next(id) : old orders[x].next.
    function testFuzz_unlink_next(LinkIn memory x) public {
        bytes32 id = _arbitrary(x, 1);
        bytes32 p = _prevOf(id);
        for (uint256 i; i < 5; ++i) {
            bytes32 want = p != bytes32(0) && _u(i) == p ? _nextOf(id) : before[i].next;
            assertEq(h.order(PID, _u(i)).next, want);
        }
    }

    /// @notice formal/Refinement/Swarm/AsyncFillerRemoveQueue.lean:48 — after _remove's FIFO unlink, orders[x].previous = (next(id) != 0 and x = next(id)) ? previous(id) : old orders[x].previous.
    function testFuzz_unlink_prev(LinkIn memory x) public {
        bytes32 id = _arbitrary(x, 1);
        bytes32 n = _nextOf(id);
        for (uint256 i; i < 5; ++i) {
            bytes32 want = n != bytes32(0) && _u(i) == n ? _prevOf(id) : before[i].previous;
            assertEq(h.order(PID, _u(i)).previous, want);
        }
    }

    /// @notice formal/Refinement/Swarm/AsyncFillerRemoveQueue.lean:56 — every order other than id's two neighbours is untouched (whole record).
    function testFuzz_unlink_other(LinkIn memory x) public {
        bytes32 id = _arbitrary(x, 1);
        for (uint256 i; i < 5; ++i) {
            if (_u(i) == _prevOf(id) || _u(i) == _nextOf(id)) continue;
            assertEq(keccak256(abi.encode(h.order(PID, _u(i)))), keccak256(abi.encode(before[i])));
        }
    }

    /// @notice formal/Refinement/Swarm/AsyncFillerRemoveQueue.lean:78 — only previous/next are written: every other field of every order is kept.
    function testFuzz_unlink_linksOnly(LinkIn memory x) public {
        _arbitrary(x, 1);
        for (uint256 i; i < 5; ++i) {
            AsyncFiller.OrderInfo memory o = h.order(PID, _u(i));
            o.previous = before[i].previous;
            o.next = before[i].next;
            assertEq(keccak256(abi.encode(o)), keccak256(abi.encode(before[i])));
        }
    }

    // ================================================================ unlinkLevel

    /// @notice formal/Refinement/Swarm/AsyncFillerRemoveQueue.lean:87 — the level's head becomes next(id) when previous(id) = 0, else stays.
    function testFuzz_unlinkLevel_head(LinkIn memory x) public {
        bytes32 id = _arbitrary(x, 2);
        (bytes32 head,,) = h.level(PID, x.isBuy, P);
        assertEq(head, _prevOf(id) == bytes32(0) ? _nextOf(id) : levelHead0);
    }

    /// @notice formal/Refinement/Swarm/AsyncFillerRemoveQueue.lean:90 — the level's tail becomes previous(id) when next(id) = 0, else stays.
    function testFuzz_unlinkLevel_tail(LinkIn memory x) public {
        bytes32 id = _arbitrary(x, 2);
        (, bytes32 tail,) = h.level(PID, x.isBuy, P);
        assertEq(tail, _nextOf(id) == bytes32(0) ? _prevOf(id) : levelTail0);
    }

    /// @notice formal/Refinement/Swarm/AsyncFillerRemoveQueue.lean:93 — the pointer surgery keeps orderCount (the only change is _remove's own decrement by 1).
    function testFuzz_unlinkLevel_orderCount(LinkIn memory x) public {
        _arbitrary(x, 2);
        (,, uint32 count) = h.level(PID, x.isBuy, P);
        assertEq(count, levelCount0 - 1);
    }

    /// @dev The FIFO unlink's whole write set: orders[previous].next, orders[next].previous, the level's
    ///      head/tail/orderCount word and the book word. Nothing in the level's priority tree or id map.
    function _assertFifoWriteSet(bytes32 id, bool isBuy) internal {
        (, bytes32[] memory w) = vm.accesses(address(h));
        bytes32 ls = h.levelSlot(PID, isBuy, P);
        bytes32 p = _prevOf(id);
        bytes32 n = _nextOf(id);
        for (uint256 i; i < w.length; ++i) {
            bool ok = w[i] == bytes32(uint256(ls) + 2) || w[i] == h.bookSlot(PID);
            if (p == bytes32(0)) ok = ok || w[i] == ls;
            else ok = ok || w[i] == bytes32(uint256(h.orderSlot(PID, p)) + 5);
            if (n == bytes32(0)) ok = ok || w[i] == bytes32(uint256(ls) + 1);
            else ok = ok || w[i] == bytes32(uint256(h.orderSlot(PID, n)) + 4);
            assertTrue(ok, "write outside the FIFO unlink");
        }
    }

    /// @notice formal/Refinement/Swarm/AsyncFillerRemoveQueue.lean:96 — the FIFO unlink leaves the level's priorityOrders tree untouched.
    function testFuzz_unlinkLevel_priorityOrders(LinkIn memory x) public {
        bytes32 id = _arbitrary(x, 2);
        _assertFifoWriteSet(id, x.isBuy);
    }

    /// @notice formal/Refinement/Swarm/AsyncFillerRemoveQueue.lean:99 — the FIFO unlink leaves the level's priorityOrderIds map untouched.
    function testFuzz_unlinkLevel_priorityOrderIds(LinkIn memory x, uint128 k, bytes32 v) public {
        h.setPriorityOrderId(PID, x.isBuy, P, k, v);
        bytes32 id = _arbitrary(x, 2);
        _assertFifoWriteSet(id, x.isBuy);
        // the map entry is still there
        assertEq(h.priorityOrderId(PID, x.isBuy, P, k), v);
    }

    // ================================================================ queue_unlink

    /// @notice formal/Refinement/Swarm/AsyncFillerRemoveQueue.lean:149 — on a well-formed FIFO level holding queue xs with id in xs, _remove(id) leaves exactly the queue xs.erase id (head, tail, count, links, 0 at both ends).
    function testFuzz_queue_unlink(uint256 seed, uint8 n, uint8 pick, uint8 pre, bool isBuy) public {
        uint256 len = 1 + n % 8;
        bytes32[] memory xs = new bytes32[](len);
        for (uint256 i; i < len; ++i) {
            xs[i] = keccak256(abi.encode(seed, i));
            _add(xs[i], isBuy, 1 ether);
            if (i == 1) {
                // other levels in the same book: same side another price, and the other side
                _add(keccak256(abi.encode(seed, "other", i)), isBuy, 2 ether);
                _add(keccak256(abi.encode(seed, "side", i)), !isBuy, 1 ether);
            }
        }
        if (pre % 3 == 1 && len > 1) {
            // a non-trivial queue: one earlier removal
            uint256 j = uint256(keccak256(abi.encode(seed, "pre"))) % len;
            h.remove(PID, xs[j]);
            xs = _erase(xs, xs[j]);
        }
        bytes32 id = xs[pick % xs.length];
        h.remove(PID, id);
        bytes32[] memory want = _erase(xs, id);

        (bytes32 head, bytes32 tail, uint32 count) = h.level(PID, isBuy, P);
        assertEq(count, want.length, "orderCount = length");
        assertEq(head, want.length == 0 ? bytes32(0) : want[0], "head");
        assertEq(tail, want.length == 0 ? bytes32(0) : want[want.length - 1], "tail");
        bytes32 prev;
        bytes32 cur = head;
        for (uint256 i; i < want.length; ++i) {
            assertEq(cur, want[i], "queue order");
            AsyncFiller.OrderInfo memory o = h.order(PID, cur);
            assertEq(o.previous, prev, "previous link");
            prev = cur;
            cur = o.next;
        }
        assertEq(cur, bytes32(0), "last next = 0");
    }

    function _add(bytes32 id, bool isBuy, uint256 amountIn) internal {
        // isBuy: price = amountIn * 1e18 / amountOutMin; sell: amountOutMin * 1e18 / amountIn
        h.addOrder(
            PID,
            AsyncFiller.NewOrder({
                id: id,
                owner: address(uint160(uint256(id))),
                amountIn: isBuy ? amountIn : 1 ether,
                amountOutMin: isBuy ? 1 ether : amountIn,
                isBuy: isBuy,
                zeroForOne: !isBuy,
                priorityFee: 0
            })
        );
    }

    function _erase(bytes32[] memory xs, bytes32 id) internal pure returns (bytes32[] memory out) {
        out = new bytes32[](xs.length - 1);
        uint256 k;
        bool skipped;
        for (uint256 i; i < xs.length; ++i) {
            if (!skipped && xs[i] == id) {
                skipped = true;
                continue;
            }
            out[k++] = xs[i];
        }
    }
}
