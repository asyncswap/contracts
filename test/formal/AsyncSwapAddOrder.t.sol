// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {FormalSlotsB} from "./FormalSlotsB.sol";
import {AsyncFillerBookHarness} from "./AsyncFillerBookHarness.sol";
import {AsyncFiller} from "@async-swap/libraries/AsyncFiller.sol";

/// @notice Bytecode checks of `formal/Refinement/Swarm/AsyncSwapAddOrder.lean`.
///
///         `AsyncFiller.addOrder` is `internal` and `AsyncMatching.addOrder` is a linked `public` library
///         function, so both run in `AsyncFillerBookHarness` on its own `pid → State` / `pid → Book`
///         storage (the same code the hook runs on `asyncOrders[pid]` / `priceBooks[pid]`). The model
///         leaves `_append` opaque: the theorems describe the storage `addOrder` hands to `_append`.
///         On the bytecode `_append` runs too, so the tests compare against a second harness that
///         writes exactly the theorem's `addState` and then runs the real `_append`
///         (`writeThenAppend`): both must end with identical storage. Fields `_append` never writes are
///         also checked directly.
contract AsyncSwapAddOrderFormalTest is FormalSlotsB {
    AsyncFillerBookHarness a; // runs the function under test
    AsyncFillerBookHarness b; // the theorem's expected state, then `_append`

    bytes32 constant PID = keccak256("formal.addOrder.pid");
    bytes32 constant OTHER = keccak256("formal.addOrder.other");
    uint256 constant MIN_FEE = 100_000; // AsyncFiller.MIN_PRIORITY_FEE
    uint256 constant MAX_FEE = type(uint64).max; // AsyncFiller.MAX_PRIORITY_FEE

    /// @dev Fuzzed inputs and pre-state. The `*Kind` fields steer the raw values towards the guards'
    ///      boundaries; every kind also leaves some runs fully raw.
    struct In {
        bytes32 id;
        address owner;
        uint256 amountIn;
        uint256 amountOutMin;
        bool isBuy;
        bool zeroForOne;
        uint256 fee;
        uint8 idKind;
        uint8 feeKind;
        uint8 amtKind;
        uint8 mode;
        uint64 seq;
        uint8 seqKind;
        uint256 seed;
        uint8 nPre;
    }

    function setUp() public override {
        super.setUp();
        a = new AsyncFillerBookHarness();
        b = new AsyncFillerBookHarness();
    }

    // ================================================================ fixture helpers

    function _preId(uint256 seed, uint256 i) internal pure returns (bytes32) {
        return keccak256(abi.encode(seed, i));
    }

    function _fee(uint8 kind, uint256 raw) internal pure returns (uint256) {
        kind %= 5;
        if (kind == 0) return 0;
        if (kind == 1) return 1 + raw % (MIN_FEE - 1); // [1, MIN)
        if (kind == 2) return MIN_FEE + raw % (MAX_FEE - MIN_FEE + 1); // [MIN, MAX]
        if (kind == 3) return MAX_FEE + 1 + raw % (type(uint256).max - MAX_FEE); // > MAX
        return raw;
    }

    function _seq(uint8 kind, uint64 raw) internal pure returns (uint64) {
        kind %= 4;
        if (kind == 0) return raw;
        if (kind == 1) return type(uint64).max - 1; // seq + 1 = 2^64 - 1 still fits
        if (kind == 2) return type(uint64).max; // seq + 1 overflows
        return raw % 1000;
    }

    /// @dev The order `addOrder` is called with. `amtKind` mixes raw amounts (zero divisors, mulDiv
    ///      overflow) with ones at the pre-placed orders' price (1e18), so levels are shared.
    function _shape(In memory x) internal pure returns (AsyncFiller.NewOrder memory o) {
        o.id = x.idKind % 4 == 3 && x.nPre % 4 != 0 ? _preId(x.seed, 0) : x.id;
        o.owner = x.owner;
        uint8 k = x.amtKind % 3;
        o.amountIn = k == 0 ? x.amountIn : k == 1 ? 1 ether : 1 + x.amountIn % 1e30;
        o.amountOutMin = k == 0 ? x.amountOutMin : k == 1 ? 1 ether : 1 + x.amountOutMin % 1e30;
        o.isBuy = x.isBuy;
        o.zeroForOne = x.zeroForOne;
        o.priorityFee = _fee(x.feeKind, x.fee);
    }

    /// @dev Same pre-state in `h`: mode, up to 3 resting orders on PID (valid fee for the mode), a pool
    ///      record, an executor grant, an order with the target id in OTHER, then `nextSequence`.
    function _prep(AsyncFillerBookHarness h, In memory x, uint8 mode, bytes32 targetId) internal {
        h.setMode(PID, mode);
        uint256 n = x.nPre % 4;
        for (uint256 i; i < n; ++i) {
            uint256 r = uint256(keccak256(abi.encode(x.seed, i, "r")));
            h.addOrder(
                PID,
                AsyncFiller.NewOrder({
                    id: _preId(x.seed, i),
                    owner: address(uint160(r)),
                    amountIn: r % 3 == 0 ? 2 ether : 1 ether,
                    amountOutMin: 1 ether,
                    isBuy: (r >> 8) & 1 == 1,
                    zeroForOne: (r >> 9) & 1 == 1,
                    priorityFee: mode == 1 ? MIN_FEE + (r >> 16) % 1000 : 0
                })
            );
        }
        h.setPoolFields(PID, address(uint160(x.seed)), address(uint160(x.seed >> 8)), address(uint160(x.seed >> 16)));
        h.setExecutor(PID, x.owner, address(uint160(x.seed >> 24)), true);
        h.addOrder(
            OTHER,
            AsyncFiller.NewOrder({
                id: targetId,
                owner: address(0xBEEF),
                amountIn: 1 ether,
                amountOutMin: 1 ether,
                isBuy: x.isBuy,
                zeroForOne: x.zeroForOne,
                priorityFee: 0
            })
        );
        h.setNextSequence(PID, _seq(x.seqKind, x.seq));
    }

    function _setup(In memory x, uint8 mode) internal returns (AsyncFiller.NewOrder memory o) {
        o = _shape(x);
        _prep(a, x, mode, o.id);
        _prep(b, x, mode, o.id);
    }

    function _bookWordOf(AsyncFillerBookHarness h) internal view returns (uint256) {
        return uint256(vm.load(address(h), h.bookSlot(PID)));
    }

    function _modeOf(AsyncFillerBookHarness h) internal view returns (uint8) {
        return uint8(_bookWordOf(h) >> 128);
    }

    function _nextSeqOf(AsyncFillerBookHarness h) internal view returns (uint64) {
        return uint64(_bookWordOf(h));
    }

    function _panic(uint256 code) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("Panic(uint256)", code);
    }

    /// @dev `addOrder_run`'s case split on the pre-state of `a`: the revert data it predicts, or
    ///      `ok = true`. `_priceKey`'s outcome is its `Math.mulDiv` call's (run in the harness).
    function _predict(AsyncFiller.NewOrder memory o) internal view returns (bool ok, bytes memory err) {
        uint8 mode = _modeOf(a);
        uint256 fee = o.priorityFee;
        if (mode == 0 && fee != 0) {
            return (false, abi.encodeWithSelector(AsyncFiller.InvalidOrderingModeChange.selector));
        }
        if (mode == 1 && fee < MIN_FEE) {
            return (false, abi.encodeWithSelector(AsyncFiller.PriorityFeeTooSmall.selector));
        }
        if (fee > MAX_FEE) return (false, abi.encodeWithSelector(AsyncFiller.PriorityFeeTooLarge.selector));
        try a.priceKeyMulDiv(o.isBuy, o.amountIn, o.amountOutMin) {}
        catch (bytes memory e) {
            return (false, e);
        }
        if (uint256(_nextSeqOf(a)) + 1 >= 2 ** 64) return (false, _panic(0x11));
        return (true, "");
    }

    function _call(AsyncFillerBookHarness h, bool viaMatching, AsyncFiller.NewOrder memory o)
        internal
        returns (bool s, bytes memory ret)
    {
        (s, ret) = viaMatching
            ? address(h).call(abi.encodeCall(AsyncFillerBookHarness.matchingAddOrder, (PID, o)))
            : address(h).call(abi.encodeCall(AsyncFillerBookHarness.addOrder, (PID, o)));
    }

    /// @dev The theorem's `newOrder owner aIn aOut isBuy zfo fee p seq`.
    function _newOrder(AsyncFiller.NewOrder memory o, uint128 p, uint64 seq)
        internal
        pure
        returns (AsyncFiller.OrderInfo memory)
    {
        return AsyncFiller.OrderInfo({
            owner: o.owner,
            amountIn: o.amountIn,
            amountOutMin: o.amountOutMin,
            price: p,
            previous: bytes32(0),
            next: bytes32(0),
            isBuy: o.isBuy,
            zeroForOne: o.zeroForOne,
            sequence: seq,
            priorityFee: uint64(o.priorityFee % 2 ** 64),
            priorityKey: uint128(2 ** 64 - 1 - uint256(seq)),
            priorityFeeEscrowed: o.priorityFee == 0
        });
    }

    /// @dev Every slot either harness wrote since `vm.record()` holds the same word in both. The two
    ///      start from identical storage, so this is equality of their whole storage.
    function _assertSameStorage() internal {
        (, bytes32[] memory wa) = vm.accesses(address(a));
        (, bytes32[] memory wb) = vm.accesses(address(b));
        for (uint256 i; i < wa.length; ++i) {
            assertEq(vm.load(address(a), wa[i]), vm.load(address(b), wa[i]), "slot written by addOrder differs");
        }
        for (uint256 i; i < wb.length; ++i) {
            assertEq(vm.load(address(a), wb[i]), vm.load(address(b), wb[i]), "slot written by addState+_append differs");
        }
    }

    /// @dev After a successful call on `a` (pre-state `seq0`): the price key is in [1, 2^128), and `a`'s
    ///      storage equals `_append(addState(...))` built in `b`. Call under `vm.record()`.
    function _assertAddState(AsyncFiller.NewOrder memory o, uint64 seq0) internal returns (uint128 p, uint64 seq) {
        p = a.order(PID, o.id).price;
        assertGe(p, 1, "price key >= 1");
        seq = seq0 + 1;
        b.writeThenAppend(PID, o.id, _newOrder(o, p, seq), seq);
        _assertSameStorage();
    }

    // ================================================================ AsyncFiller.addOrder

    /// @notice formal/Refinement/Swarm/AsyncSwapAddOrder.lean:68 — _priorityKey(0, seq) = 2^64 - 1 - seq (observed as the stored key of a fresh, unpaid order).
    function testFuzz_priorityKey_zero(In memory x) public {
        uint8 mode = x.mode % 2;
        x.feeKind = mode == 0 ? 0 : 2;
        x.amtKind = 1;
        AsyncFiller.NewOrder memory o = _setup(x, mode);
        vm.assume(_nextSeqOf(a) < type(uint64).max);
        uint64 seq = _nextSeqOf(a) + 1;
        a.addOrder(PID, o);
        AsyncFiller.OrderInfo memory s = a.order(PID, o.id);
        assertEq(s.sequence, seq);
        assertEq(uint256(s.priorityKey), 2 ** 64 - 1 - uint256(seq));
    }

    function _checkRun(In memory x, bool viaMatching) internal {
        AsyncFiller.NewOrder memory o = _setup(x, x.mode % 2);
        (bool ok, bytes memory err) = _predict(o);
        uint64 seq0 = _nextSeqOf(a);
        vm.record();
        (bool s, bytes memory ret) = _call(a, viaMatching, o);
        if (!ok) {
            assertFalse(s, "predicted a revert");
            assertEq(ret, err, "revert data");
            (, bytes32[] memory wa) = vm.accesses(address(a));
            assertEq(wa.length, 0);
            return;
        }
        assertTrue(s, "predicted success");
        _assertAddState(o, seq0);
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapAddOrder.lean:76 — addOrder = InvalidOrderingModeChange | PriorityFeeTooSmall | PriorityFeeTooLarge | _priceKey's error | panic 0x11 on the uint64 bump | _append(addWrite(newOrder…)).
    function testFuzz_addOrder_run(In memory x) public {
        _checkRun(x, false);
    }

    function _checkInvalidMode(In memory x, bool viaMatching) internal {
        AsyncFiller.NewOrder memory o = _setup(x, 0);
        vm.assume(o.priorityFee != 0);
        (bool s, bytes memory ret) = _call(a, viaMatching, o);
        assertFalse(s);
        assertEq(ret, abi.encodeWithSelector(AsyncFiller.InvalidOrderingModeChange.selector));
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapAddOrder.lean:118 — orderingMode = FIFO and priorityFee != 0 reverts InvalidOrderingModeChange (any amounts, sequence).
    function testFuzz_addOrder_invalidMode(In memory x) public {
        _checkInvalidMode(x, false);
    }

    function _checkFeeTooSmall(In memory x, bool viaMatching) internal {
        x.feeKind = x.feeKind % 2 == 0 ? 0 : 1; // [0, MIN)
        AsyncFiller.NewOrder memory o = _setup(x, 1);
        (bool s, bytes memory ret) = _call(a, viaMatching, o);
        assertFalse(s);
        assertEq(ret, abi.encodeWithSelector(AsyncFiller.PriorityFeeTooSmall.selector));
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapAddOrder.lean:125 — orderingMode = PriorityFee and priorityFee < MIN_PRIORITY_FEE reverts PriorityFeeTooSmall.
    function testFuzz_addOrder_feeTooSmall(In memory x) public {
        _checkFeeTooSmall(x, false);
    }

    function _checkFeeTooLarge(In memory x, bool viaMatching) internal {
        // ¬guard1 ∧ fee > MAX forces orderingMode != FIFO; ¬guard2 then holds for mode PriorityFee.
        x.feeKind = 3;
        AsyncFiller.NewOrder memory o = _setup(x, 1);
        (bool s, bytes memory ret) = _call(a, viaMatching, o);
        assertFalse(s);
        assertEq(ret, abi.encodeWithSelector(AsyncFiller.PriorityFeeTooLarge.selector));
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapAddOrder.lean:133 — past guards 1-2, priorityFee > 2^64 - 1 reverts PriorityFeeTooLarge.
    function testFuzz_addOrder_feeTooLarge(In memory x) public {
        _checkFeeTooLarge(x, false);
    }

    function _checkSeqOverflow(In memory x, bool viaMatching) internal {
        uint8 mode = x.mode % 2;
        x.feeKind = mode == 0 ? 0 : 2;
        x.seqKind = 2;
        AsyncFiller.NewOrder memory o = _setup(x, mode);
        try a.priceKeyMulDiv(o.isBuy, o.amountIn, o.amountOutMin) {}
        catch {
            vm.assume(false); // hypothesis: _priceKey succeeds
        }
        (bool s, bytes memory ret) = _call(a, viaMatching, o);
        assertFalse(s);
        assertEq(ret, _panic(0x11));
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapAddOrder.lean:144 — guards passing and _priceKey succeeding, nextSequence = 2^64 - 1 panics 0x11.
    function testFuzz_addOrder_seqOverflow(In memory x) public {
        _checkSeqOverflow(x, false);
    }

    function _checkOk(In memory x, bool viaMatching) internal {
        uint8 mode = x.mode % 2;
        AsyncFiller.NewOrder memory o = _setup(x, mode);
        uint64 seq0 = _nextSeqOf(a);
        vm.record();
        (bool s,) = _call(a, viaMatching, o);
        if (!s) return;
        uint256 fee = o.priorityFee;
        assertFalse(mode == 0 && fee != 0, "guard 1 passed");
        assertFalse(mode == 1 && fee < MIN_FEE, "guard 2 passed");
        assertLe(fee, MAX_FEE, "guard 3 passed");
        assertLt(uint256(seq0) + 1, 2 ** 64, "seq fits uint64");
        // _priceKey succeeded (and is pure, so it left storage alone)
        a.priceKeyMulDiv(o.isBuy, o.amountIn, o.amountOutMin);
        _assertAddState(o, seq0);
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapAddOrder.lean:167 — success implies the guards passed, _priceKey gave p in [1, 2^128), seq fits uint64, and the final state is _append(addState(...newOrder(p, seq), seq)).
    function testFuzz_addOrder_ok(In memory x) public {
        _checkOk(x, false);
    }

    /// @dev A successful `addOrder` in `mode` (fee valid for it, amounts that price), run on `a` under
    ///      `vm.record()`. `b` is left in the pre-state, so it serves as the "before" snapshot.
    function _succeed(In memory x, uint8 mode) internal returns (AsyncFiller.NewOrder memory o, uint64 seq0) {
        x.feeKind = mode == 0 ? 0 : 2;
        x.amtKind = x.amtKind % 2 == 0 ? 1 : 2;
        x.seqKind = x.seqKind % 2 == 0 ? 0 : 3;
        o = _setup(x, mode);
        vm.assume(_nextSeqOf(a) < type(uint64).max);
        seq0 = _nextSeqOf(a);
        vm.record();
        a.addOrder(PID, o);
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapAddOrder.lean:208 — the stored order is newOrder(...): owner, amounts, side, direction, price p, unlinked, sequence = seq, fee mod 2^64, key 2^64 - 1 - seq, escrowed iff fee = 0.
    function testFuzz_addState_order(In memory x) public {
        uint8 mode = x.mode % 2;
        (AsyncFiller.NewOrder memory o, uint64 seq0) = _succeed(x, mode);
        AsyncFiller.OrderInfo memory s = a.order(PID, o.id);
        (, bytes32 tailBefore,) = b.level(PID, o.isBuy, s.price);
        uint64 seq = seq0 + 1;
        assertEq(s.owner, o.owner);
        assertEq(s.amountIn, o.amountIn);
        assertEq(s.amountOutMin, o.amountOutMin);
        assertGe(s.price, 1);
        assertEq(s.isBuy, o.isBuy);
        assertEq(s.zeroForOne, o.zeroForOne);
        assertEq(s.sequence, seq);
        assertEq(uint256(s.priorityFee), o.priorityFee % 2 ** 64);
        assertEq(uint256(s.priorityKey), 2 ** 64 - 1 - uint256(seq)); // _append re-keys with the paid fee, 0 here
        assertEq(s.priorityFeeEscrowed, o.priorityFee == 0);
        // next = 0 is what addOrder writes; _append keeps it, except that in FIFO mode it sets the old
        // tail's next to id, which is the order itself when id was already that level's tail.
        if (mode == 1 || tailBefore != o.id) assertEq(s.next, bytes32(0));
        // previous = 0 is what addOrder writes; in FIFO mode _append then links the order behind the
        // level's old tail, so previous = 0 is visible when the level was empty or the book is priority.
        if (mode == 1 || tailBefore == bytes32(0)) assertEq(s.previous, bytes32(0));
        _assertAddState(o, seq0);
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapAddOrder.lean:218 — the book's nextSequence becomes seq; openOrderCount, orderingMode, trees and levels are as addOrder found them (until _append).
    function testFuzz_addState_book(In memory x) public {
        (AsyncFiller.NewOrder memory o, uint64 seq0) = _succeed(x, x.mode % 2);
        uint256 wordBefore = _bookWordOf(b);
        assertEq(_nextSeqOf(a), seq0 + 1, "nextSequence = seq");
        assertEq(_modeOf(a), uint8(wordBefore >> 128), "orderingMode unchanged");
        // openOrderCount, bids, asks and the levels: equal to `_append` run on the unchanged book.
        _assertAddState(o, seq0);
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapAddOrder.lean:227 — every other order of the pool, and its poolManager, numeraire, feeVault and isExecutor, are untouched (before _append).
    function testFuzz_addState_other_order(In memory x) public {
        (AsyncFiller.NewOrder memory o, uint64 seq0) = _succeed(x, x.mode % 2);
        for (uint256 i; i < x.nPre % 4; ++i) {
            bytes32 j = _preId(x.seed, i);
            if (j == o.id) continue;
            AsyncFiller.OrderInfo memory now_ = a.order(PID, j);
            AsyncFiller.OrderInfo memory was = b.order(PID, j);
            // `_append` (FIFO) sets the old tail's `next` to `id`; every other field is as addOrder left it.
            if (now_.next != was.next) {
                assertEq(now_.next, o.id, "only _append's tail link");
                now_.next = was.next;
            }
            assertEq(keccak256(abi.encode(now_)), keccak256(abi.encode(was)), "other order");
        }
        (address pm, address num, address fv) = a.poolFields(PID);
        (address pm0, address num0, address fv0) = b.poolFields(PID);
        assertEq(pm, pm0);
        assertEq(num, num0);
        assertEq(fv, fv0);
        assertTrue(a.isExecutor(PID, x.owner, address(uint160(x.seed >> 24))));
        _assertAddState(o, seq0);
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapAddOrder.lean:237 — every other pool (orders and book) is untouched.
    function testFuzz_addState_other_pool(In memory x) public {
        (AsyncFiller.NewOrder memory o,) = _succeed(x, x.mode % 2);
        AsyncFiller.OrderInfo memory was = b.order(OTHER, o.id);
        assertEq(keccak256(abi.encode(a.order(OTHER, o.id))), keccak256(abi.encode(was)), "other pool's order");
        assertEq(vm.load(address(a), a.bookSlot(OTHER)), vm.load(address(b), b.bookSlot(OTHER)), "other book word");
        (bytes32 h, bytes32 t, uint32 c) = a.level(OTHER, was.isBuy, was.price);
        (bytes32 h0, bytes32 t0, uint32 c0) = b.level(OTHER, was.isBuy, was.price);
        assertEq(h, h0);
        assertEq(t, t0);
        assertEq(c, c0);
        // no write lands in OTHER's order record, book word or that level
        (, bytes32[] memory wa) = vm.accesses(address(a));
        uint256 os = uint256(a.orderSlot(OTHER, o.id));
        uint256 ls = uint256(a.levelSlot(OTHER, was.isBuy, was.price));
        for (uint256 i; i < wa.length; ++i) {
            uint256 w = uint256(wa[i]);
            assertTrue(w < os || w > os + 7, "write to OTHER's order");
            assertTrue(w < ls || w > ls + 2, "write to OTHER's level");
            assertTrue(wa[i] != a.bookSlot(OTHER), "write to OTHER's book");
        }
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapAddOrder.lean:244 — owner, pendingOwner, nonceUsed and the EIP-712 name/version fallbacks are untouched (on the hook, through a real order placement).
    function testFuzz_addState_frame(
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOutMin,
        address maker,
        uint256 nonce
    ) public {
        bytes32 nonceSlot = _nonceSlot(maker, nonce);
        bytes32[5] memory slots =
            [bytes32(0), bytes32(uint256(1)), bytes32(OWNER_SLOT), bytes32(PENDING_OWNER_SLOT), nonceSlot];
        bytes32[5] memory was;
        for (uint256 i; i < 5; ++i) {
            was[i] = _loadHook(slots[i]);
        }
        vm.record();
        _placeOrder(alice, zeroForOne, bound(amountIn, 1, 50 ether), bound(amountOutMin, 1, 1e30));
        bytes32[] memory w = _hookWrites();
        for (uint256 i; i < 5; ++i) {
            assertEq(_loadHook(slots[i]), was[i]);
            for (uint256 j; j < w.length; ++j) {
                assertTrue(w[j] != slots[i], "frame slot written");
            }
        }
    }

    // ================================================================ AsyncMatching.addOrder

    /// @notice formal/Refinement/Swarm/AsyncSwapAddOrder.lean:255 — AsyncMatching.addOrder(order) behaves exactly as AsyncFiller.addOrder on the NewOrder's fields (same revert data, or same storage).
    function testFuzz_matching_addOrder_eq(In memory x) public {
        AsyncFiller.NewOrder memory o = _setup(x, x.mode % 2);
        vm.record();
        (bool sa, bytes memory ra) = _call(a, false, o);
        (bool sb, bytes memory rb) = _call(b, true, o);
        assertEq(sa, sb, "same outcome");
        assertEq(ra, rb, "same return / revert data");
        _assertSameStorage();
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapAddOrder.lean:263 — AsyncMatching.addOrder has addOrder_run's full case split on the NewOrder's fields.
    function testFuzz_matching_addOrder_run(In memory x) public {
        _checkRun(x, true);
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapAddOrder.lean:284 — AsyncMatching.addOrder: FIFO mode with order.priorityFee != 0 reverts InvalidOrderingModeChange.
    function testFuzz_matching_addOrder_invalidMode(In memory x) public {
        _checkInvalidMode(x, true);
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapAddOrder.lean:291 — AsyncMatching.addOrder: PriorityFee mode with order.priorityFee < MIN_PRIORITY_FEE reverts PriorityFeeTooSmall.
    function testFuzz_matching_addOrder_feeTooSmall(In memory x) public {
        _checkFeeTooSmall(x, true);
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapAddOrder.lean:299 — AsyncMatching.addOrder: past guards 1-2, order.priorityFee > MAX_PRIORITY_FEE reverts PriorityFeeTooLarge.
    function testFuzz_matching_addOrder_feeTooLarge(In memory x) public {
        _checkFeeTooLarge(x, true);
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapAddOrder.lean:309 — AsyncMatching.addOrder: guards passing and _priceKey succeeding, nextSequence = 2^64 - 1 panics 0x11.
    function testFuzz_matching_addOrder_seqOverflow(In memory x) public {
        _checkSeqOverflow(x, true);
    }

    /// @notice formal/Refinement/Swarm/AsyncSwapAddOrder.lean:324 — AsyncMatching.addOrder success implies the guards passed, p in [1, 2^128), seq fits, final state = _append(addState(...)).
    function testFuzz_matching_addOrder_ok(In memory x) public {
        _checkOk(x, true);
    }

    // ================================================================ notes

    /// @notice Note (not a theorem): the model's orderingMode is an unbounded Nat, so for a stored mode byte
    ///         >= 2 addOrder_run (lean:76), addOrder_feeTooLarge (lean:133), addOrder_seqOverflow (lean:144)
    ///         and their AsyncMatching versions predict PriorityFeeTooLarge / _priceKey's error / panic 0x11 /
    ///         success. The bytecode decodes the enum on its first read of `book.orderingMode` and panics
    ///         0x21 for every input. Unreachable: the mode byte is only ever written from a decoded enum.
    function testFuzz_note_addOrder_modeOutOfRange(In memory x, uint8 rawMode, bool viaMatching) public {
        uint8 mode = uint8(bound(rawMode, 2, 255));
        x.nPre = 0; // pre-placing would itself run addOrder in the out-of-range mode
        AsyncFiller.NewOrder memory o = _setup(x, mode);
        (, bytes memory modelErr) = _predict(o);
        (bool s, bytes memory ret) = _call(a, viaMatching, o);
        assertFalse(s);
        assertEq(ret, _panic(0x21), "enum decoding panic");
        assertTrue(keccak256(modelErr) != keccak256(_panic(0x21)), "the model predicts something else");
    }
}
