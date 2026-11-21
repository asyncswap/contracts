// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {MatchingHandler} from "./MatchingInvariant.t.sol";
import {AsyncSwap} from "src/AsyncSwap.sol";
import {Router} from "src/Router.sol";
import {AsyncOrder} from "src/types/AsyncOrder.sol";
import {IAsyncSwapCallback} from "src/interfaces/IAsyncSwapCallback.sol";
import {IAsyncSwapFlashFiller} from "src/interfaces/IAsyncSwapFlashFiller.sol";
import {ISignatureTransfer} from "src/interfaces/ISignatureTransfer.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolIdLibrary, PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";
import {ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";

/// @notice A funded flash filler: it fills the outer order and, optionally, a second order inside its callback,
///         paying each one's live minimum from its own ETH and USDC, minted as claims.
contract InvariantFlashFiller is IAsyncSwapFlashFiller {
    using PoolIdLibrary for PoolKey;

    IPoolManager immutable manager;
    IAsyncSwapCallback immutable router;
    AsyncSwap immutable hook;

    constructor(IPoolManager _manager, IAsyncSwapCallback _router, AsyncSwap _hook) {
        manager = _manager;
        router = _router;
        hook = _hook;
    }

    function fill(AsyncOrder calldata outer, bool withInner, AsyncOrder calldata inner) external {
        router.fillOrderWithCallback(outer, type(uint256).max, abi.encode(withInner, inner));
    }

    function asyncSwapFlashFill(AsyncOrder calldata order, uint256, uint256 amountOwed, bytes calldata data) external {
        require(msg.sender == address(router), "only router");
        (bool withInner, AsyncOrder memory inner) = abi.decode(data, (bool, AsyncOrder));
        if (withInner) {
            bytes32 id =
                keccak256(abi.encode(block.chainid, inner.key.toId(), inner.owner, inner.zeroForOne, inner.salt));
            (, uint256 minimum) = hook.asyncOrderInfo(inner.key.toId(), id);
            uint256 owed = minimum;
            Currency innerOut = inner.zeroForOne ? inner.key.currency1 : inner.key.currency0;
            _fund(innerOut, owed);
            manager.approve(address(router), innerOut.toId(), owed);
            router.fillOrderInCallback(inner, type(uint256).max);
        }
        Currency output = order.zeroForOne ? order.key.currency1 : order.key.currency0;
        _fund(output, amountOwed);
        manager.approve(address(router), output.toId(), amountOwed);
    }

    /// @dev Turns `amount` of this contract's own ETH or tokens into claims inside the unlock.
    function _fund(Currency currency, uint256 amount) private {
        if (amount == 0) return;
        manager.sync(currency);
        if (currency.isAddressZero()) {
            manager.settle{value: amount}();
        } else {
            MockERC20(Currency.unwrap(currency)).transfer(address(manager), amount);
            manager.settle();
        }
        manager.mint(address(this), currency.toId(), amount);
    }

    receive() external payable {}
}

/// @notice The matching campaign plus flash fills (with an in-callback fill), block time passing, and identical
///         orders re-placed in the same block (a reused order id).
contract FlashFillHandler is MatchingHandler {
    using PoolIdLibrary for PoolKey;

    InvariantFlashFiller public filler;
    mapping(bytes32 => bool) internal seen;
    uint256 public flashFills;
    uint256 public innerFills;
    uint256 public replacements;

    constructor(AsyncSwap h, Router r, MockERC20 u, PoolKey memory k, bool p) MatchingHandler(h, r, u, k, p) {
        filler = new InvariantFlashFiller(h.poolManager(), IAsyncSwapCallback(address(r)), h);
        vm.deal(address(filler), 1_000 ether);
        u.mint(address(filler), 10_000_000e6);
    }

    function passBlocks(uint256 blocks) external {
        vm.roll(vm.getBlockNumber() + bound(blocks, 1, 150));
    }

    function flash(uint256 outerIndex, uint256 innerIndex, bool withInner) external {
        if (orders.length == 0) return;
        AsyncOrder memory outer = orders[outerIndex % orders.length];
        AsyncOrder memory inner = orders[innerIndex % orders.length];
        if (hook.asyncOrder(key.toId(), id(outer)) == 0) return;
        withInner = withInner && id(inner) != id(outer) && hook.asyncOrder(key.toId(), id(inner)) != 0;
        try filler.fill(outer, withInner, inner) {
            ++flashFills;
            if (withInner) ++innerFills;
        } catch {}
    }

    /// @dev Cancel a live order and place an identical one in the same block: the hook hands it the same id.
    function replace(uint256 index) external {
        if (orders.length == 0) return;
        AsyncOrder memory order = orders[index % orders.length];
        bytes32 orderId = id(order);
        (uint256 amountIn, uint256 minimum) = hook.asyncOrderInfo(key.toId(), orderId);
        // Only an untouched order re-creates the same salt (it hashes the original amounts).
        if (amountIn != order.amountIn || minimum != order.amountOutMin) return;
        if (order.salt != _salt(order)) return;
        vm.startPrank(order.owner);
        router.cancelOrder(order);
        router.swap{value: order.zeroForOne ? order.amountIn : 0}(
            order, abi.encode(AsyncSwap.UserParams(order.owner, address(router), order.amountOutMin, order.priorityFee))
        );
        vm.stopPrank();
        ++replacements;
    }

    function _salt(AsyncOrder memory order) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                block.timestamp,
                block.number,
                address(hook.poolManager()),
                order.owner,
                order.amountIn,
                order.amountOutMin,
                order.priorityFee
            )
        );
    }

    function _record(AsyncOrder memory order) internal override {
        bytes32 orderId = id(order);
        if (seen[orderId]) return;
        seen[orderId] = true;
        super._record(order);
    }
}

contract FlashFillInvariantTest is StdInvariant, Test {
    using PoolIdLibrary for PoolKey;

    PoolManager manager;
    AsyncSwap hook;
    MockERC20 usdc;
    FlashFillHandler handler;
    PoolKey key;

    /// @dev Pool reserves seeded by LPs, which sit in the PoolManager beside the claims.
    uint256 seededEth;
    uint256 seededUsdc;

    function _initialSqrtPrice() internal pure virtual returns (uint160) {
        return 2 ** 96;
    }

    function _seedLiquidity() internal virtual {}

    function _selectors() internal pure virtual returns (bytes4[] memory selectors) {
        selectors = new bytes4[](9);
        selectors[0] = MatchingHandler.submit.selector;
        selectors[1] = MatchingHandler.cancel.selector;
        selectors[2] = MatchingHandler.reprice.selector;
        selectors[3] = MatchingHandler.clear.selector;
        selectors[4] = MatchingHandler.redeem.selector;
        selectors[5] = MatchingHandler.topUpFee.selector;
        selectors[6] = FlashFillHandler.passBlocks.selector;
        selectors[7] = FlashFillHandler.flash.selector;
        selectors[8] = FlashFillHandler.replace.selector;
    }

    function setUp() public {
        manager = new PoolManager(address(this));
        usdc = new MockERC20("USD Coin", "USDC", 6);
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );
        Router router = new Router(manager, AsyncSwap(payable(address(flags))), ISignatureTransfer(address(0)), 0);
        deployCodeTo(
            "AsyncSwap.sol",
            abi.encode(
                manager, Currency.wrap(address(usdc)), address(this), address(router), uint256(0), type(uint8).max
            ),
            address(flags)
        );
        hook = AsyncSwap(payable(address(flags)));
        key = PoolKey(Currency.wrap(address(0)), Currency.wrap(address(usdc)), LPFeeLibrary.DYNAMIC_FEE_FLAG, 1, hook);
        manager.initialize(key, _initialSqrtPrice());
        _seedLiquidity();
        handler = new FlashFillHandler(hook, router, usdc, key, true);
        targetSelector(FuzzSelector(address(handler), _selectors()));
        targetContract(address(handler));
    }

    /// @notice The hook's claims are exactly what its open orders are owed: no fill path pays from another order.
    function invariant_escrowEqualsOutstandingObligations() public view {
        uint256 ethOwed;
        uint256 usdcOwed;
        (bytes32[] memory ids, bool[] memory sells) = handler.book();
        for (uint256 i; i < ids.length; ++i) {
            uint256 remaining = hook.asyncOrder(key.toId(), ids[i]);
            if (sells[i]) ethOwed += remaining;
            else usdcOwed += remaining;
            usdcOwed += hook.asyncOrderPriorityFee(key.toId(), ids[i]);
        }
        assertEq(manager.balanceOf(address(hook), 0), ethOwed, "native escrow obligations");
        assertEq(manager.balanceOf(address(hook), uint160(address(usdc))), usdcOwed, "USDC escrow obligations");
    }

    /// @notice Nothing is created or lost across makers, the filler, the vault and the PoolManager.
    function invariant_assetsConserved() public view {
        address filler = address(handler.filler());
        uint256 ethTotal = address(manager).balance + filler.balance;
        uint256 usdcTotal = usdc.balanceOf(address(manager)) + usdc.balanceOf(filler);
        uint256 nativeClaims = manager.balanceOf(address(hook), 0) + manager.balanceOf(address(hook.feeVault()), 0)
            + manager.balanceOf(filler, 0);
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            ethTotal += actor.balance;
            usdcTotal += usdc.balanceOf(actor);
            nativeClaims += manager.balanceOf(actor, 0);
        }
        if (seededEth == 0) assertEq(address(manager).balance, nativeClaims, "all native claims backed exactly");
        else assertGe(address(manager).balance, nativeClaims, "every native claim is backed");
        assertEq(ethTotal, 5_000 ether + seededEth, "ETH conserved");
        assertEq(usdcTotal, 50_000_000e6 + seededUsdc, "USDC conserved");
        assertEq(address(hook).balance, 0, "hook holds no plain ETH");
        assertEq(address(hook.router()).balance, 0, "router holds no plain ETH");
    }

    /// @dev Each new action does real work, so the campaign exercises it rather than returning early.
    function test_campaignReachesNewPaths() public virtual {
        handler.submit(0, true, 1 ether, 3_000e6, 0); // ask: 1 ETH for 3000 USDC
        handler.submit(1, false, 1 ether, 1_000e6, 0); // bid: 1000 USDC for 1 ETH, below the ask
        handler.submit(2, true, 0.5 ether, 3_500e6, 0);
        assertEq(handler.orderCount(), 3);

        handler.replace(2);
        assertEq(handler.replacements(), 1, "identical order re-placed under the same id");
        assertGt(hook.asyncOrder(key.toId(), handler.id(handler.orderAt(2))), 0);

        handler.passBlocks(10);
        handler.flash(0, 1, true); // outer: the ask; inner: the bid
        assertEq(handler.flashFills(), 1, "flash fill succeeded");
        assertEq(handler.innerFills(), 1, "in-callback fill succeeded");
        assertEq(hook.asyncOrder(key.toId(), handler.id(handler.orderAt(0))), 0);
        assertEq(hook.asyncOrder(key.toId(), handler.id(handler.orderAt(1))), 0);
        invariant_escrowEqualsOutstandingObligations();
        invariant_assetsConserved();
    }

    function afterInvariant() external view {
        // The campaign must actually exercise the new paths.
        if (handler.submissions() > 20) {
            assertGt(handler.flashFills() + handler.replacements(), 0, "new paths reached");
        }
    }
}

/// @notice The same campaign with Uniswap v4 liquidity in range at 2,000 USDC per ETH, so pool fills (on submit and
///         via retry) interleave with flash fills and in-callback fills.
contract LpFlashFillInvariantTest is FlashFillInvariantTest {
    // sqrt(2000e6 / 1e18) * 2^96 with ETH as currency0 and 6-decimal USDC as currency1.
    uint160 constant SQRT_PRICE_2000 = 3543191142285914327220224;
    int24 constant TICK_2000 = -200311;

    receive() external payable {}

    function _initialSqrtPrice() internal pure override returns (uint160) {
        return SQRT_PRICE_2000;
    }

    function _seedLiquidity() internal override {
        PoolModifyLiquidityTest lp = new PoolModifyLiquidityTest(manager);
        vm.deal(address(this), 20_000 ether);
        usdc.mint(address(this), 50_000_000e6);
        usdc.approve(address(lp), type(uint256).max);
        uint256 ethBefore = address(manager).balance;
        uint256 usdcBefore = usdc.balanceOf(address(manager));
        lp.modifyLiquidity{value: 20_000 ether}(
            key, ModifyLiquidityParams(TICK_2000 - 100, TICK_2000 + 100, 1e20, 0), ""
        );
        seededEth = address(manager).balance - ethBefore;
        seededUsdc = usdc.balanceOf(address(manager)) - usdcBefore;
    }

    function _selectors() internal pure override returns (bytes4[] memory selectors) {
        bytes4[] memory base = super._selectors();
        selectors = new bytes4[](base.length + 1);
        for (uint256 i; i < base.length; ++i) {
            selectors[i] = base[i];
        }
        selectors[base.length] = MatchingHandler.lpFill.selector;
    }

    /// @dev The base sanity sequence assumes an empty pool; here submits can fill from LPs instead.
    function test_campaignReachesNewPaths() public override {}
}
