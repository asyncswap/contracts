// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {ISignatureTransfer} from "@async-swap/interfaces/ISignatureTransfer.sol";
import {IAsyncSwapFlashFiller} from "@async-swap/interfaces/IAsyncSwapFlashFiller.sol";
import {Permit2Bytecode} from "./utils/Permit2Bytecode.sol";
import {AsyncSwap} from "@async-swap/AsyncSwap.sol";
import {AsyncFiller} from "@async-swap/libraries/AsyncFiller.sol";
import {AsyncMatching} from "@async-swap/libraries/AsyncMatching.sol";
import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";
import {Router} from "@async-swap/Router.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {Test, Vm} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {PoolIdLibrary, PoolKey} from "v4-core/types/PoolKey.sol";

/// @notice A flash filler that holds nothing: inside the callback it runs a list of steps (each optionally approving
///         the Router for some claims first), then approves the Router for the output it owes the maker.
contract MockFlashFiller is IAsyncSwapFlashFiller {
    struct Step {
        Currency payCurrency;
        uint256 payAmount;
        address target;
        bytes callData;
    }

    IPoolManager immutable manager;
    Router immutable router;
    uint256 public calls;

    constructor(IPoolManager _manager, Router _router) {
        manager = _manager;
        router = _router;
    }

    function run(AsyncOrder calldata order, uint256 maxPrice, Step[] calldata steps, uint256 shortBy) external payable {
        router.fillOrderWithCallback{value: msg.value}(order, maxPrice, abi.encode(steps, shortBy));
    }

    /// @dev Lets a test act as this contract outside a flash fill (setup, or calls that must fail).
    function exec(address target, bytes calldata callData) external payable returns (bytes memory) {
        (bool ok, bytes memory ret) = target.call{value: msg.value}(callData);
        if (!ok) _bubble(ret);
        return ret;
    }

    function asyncSwapFlashFill(AsyncOrder calldata order, uint256, uint256 amountOwed, bytes calldata data)
        external
        override
    {
        require(msg.sender == address(router), "only router");
        ++calls;
        (Step[] memory steps, uint256 shortBy) = abi.decode(data, (Step[], uint256));
        for (uint256 i; i < steps.length; ++i) {
            if (steps[i].payAmount != 0) {
                manager.approve(address(router), steps[i].payCurrency.toId(), steps[i].payAmount);
            }
            (bool ok, bytes memory ret) = steps[i].target.call(steps[i].callData);
            if (!ok) _bubble(ret);
        }
        Currency output = order.zeroForOne ? order.key.currency1 : order.key.currency0;
        manager.approve(address(router), output.toId(), amountOwed - shortBy);
    }

    function _bubble(bytes memory ret) private pure {
        assembly ("memory-safe") {
            revert(add(ret, 0x20), mload(ret))
        }
    }

    receive() external payable {}
}

/// @notice Calls an in-unlock entry point from an address that is not the active flash filler.
contract Bystander {
    function call(address target, bytes calldata callData) external {
        (bool ok, bytes memory ret) = target.call(callData);
        if (!ok) {
            assembly ("memory-safe") {
                revert(add(ret, 0x20), mload(ret))
            }
        }
    }
}

contract FlashFillTest is Test {
    using PoolIdLibrary for PoolKey;

    address owner = makeAddr("deployer");
    address alice = makeAddr("alice"); // the flash-filled maker
    address bob = makeAddr("bob"); // resting bid on ETH/USDC
    address carol = makeAddr("carol"); // resting ask on TOKEN/USDC

    IPoolManager manager;
    AsyncSwap hook;
    Router router;
    MockFlashFiller filler;
    MockERC20 usdc;
    MockERC20 token;
    Currency constant ETH = Currency.wrap(address(0));
    Currency USDC;
    Currency TOKEN;
    PoolKey ethUsdc;
    PoolKey tokenUsdc;
    PoolKey ethToken;

    function setUp() public {
        manager = new PoolManager(owner);
        usdc = new MockERC20("USD Coin", "USDC", 18);
        token = new MockERC20("Token", "TKN", 18);
        USDC = Currency.wrap(address(usdc));
        TOKEN = Currency.wrap(address(token));
        vm.mockCall(address(usdc), abi.encodeWithSignature("decimals()"), abi.encode(uint8(6)));

        address hookAddress = address(
            uint160(
                Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                    | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
            )
        );
        router = new Router(manager, AsyncSwap(payable(hookAddress)), ISignatureTransfer(Permit2Bytecode.PERMIT2), 0);
        deployCodeTo(
            "AsyncSwap.sol",
            abi.encode(manager, USDC, address(this), address(router), uint256(0), type(uint8).max),
            hookAddress
        );
        hook = AsyncSwap(payable(hookAddress));

        ethUsdc = _key(ETH, USDC);
        tokenUsdc = _key(TOKEN, USDC);
        ethToken = _key(ETH, TOKEN);
        manager.initialize(ethUsdc, 2 ** 96);
        manager.initialize(tokenUsdc, 2 ** 96);
        manager.initialize(ethToken, 2 ** 96);

        filler = new MockFlashFiller(manager, router);

        address[3] memory makers = [alice, bob, carol];
        for (uint256 i; i < 3; ++i) {
            vm.deal(makers[i], 100 ether);
            usdc.mint(makers[i], 1_000_000 ether);
            token.mint(makers[i], 1_000_000 ether);
            vm.startPrank(makers[i]);
            usdc.approve(address(router), type(uint256).max);
            token.approve(address(router), type(uint256).max);
            hook.setExecutor(ethUsdc.toId(), address(router), true);
            hook.setExecutor(tokenUsdc.toId(), address(router), true);
            hook.setExecutor(ethToken.toId(), address(router), true);
            vm.stopPrank();
        }
    }

    /* ------------------------------------------------------------------ helpers */

    function _key(Currency a, Currency b) internal view returns (PoolKey memory) {
        (Currency c0, Currency c1) = Currency.unwrap(a) < Currency.unwrap(b) ? (a, b) : (b, a);
        return PoolKey({currency0: c0, currency1: c1, fee: LPFeeLibrary.DYNAMIC_FEE_FLAG, tickSpacing: 1, hooks: hook});
    }

    function _fee(uint256 x) internal pure returns (uint256) {
        return Math.mulDiv(x, 2, 10_000, Math.Rounding.Ceil);
    }

    /// @dev Places an order selling `amountIn` of `input` for at least `amountOutMin` on `key`, and returns it with
    ///      the salt the hook assigned (read from `AsyncOrderCreated`).
    function _place(address maker, PoolKey memory key, Currency input, uint256 amountIn, uint256 amountOutMin)
        internal
        returns (AsyncOrder memory order)
    {
        order = AsyncOrder({
            key: key,
            owner: maker,
            zeroForOne: input == key.currency0,
            amountIn: amountIn,
            amountOutMin: amountOutMin,
            priorityFee: 0,
            sqrtPrice: 2 ** 96,
            salt: bytes32(0)
        });
        bytes memory userData = abi.encode(
            AsyncSwap.UserParams({user: maker, executor: address(router), amountOutMin: amountOutMin, priorityFee: 0})
        );
        vm.recordLogs();
        vm.prank(maker);
        router.swap{value: input.isAddressZero() ? amountIn : 0}(order, userData);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(hook) && logs[i].topics[0] == AsyncFiller.AsyncOrderCreated.selector) {
                (,,, bytes32 salt) = abi.decode(logs[i].data, (bool, uint256, uint256, bytes32));
                order.salt = salt;
            }
        }
        require(order.salt != bytes32(0), "no order");
    }

    function _live(AsyncOrder memory order) internal view returns (uint256 amountIn) {
        bytes32 id = keccak256(abi.encode(block.chainid, order.key.toId(), order.owner, order.zeroForOne, order.salt));
        (amountIn,) = hook.asyncOrderInfo(order.key.toId(), id);
    }

    function _output(AsyncOrder memory order) internal pure returns (Currency) {
        return order.zeroForOne ? order.key.currency1 : order.key.currency0;
    }

    function _fillStep(AsyncOrder memory order) internal pure returns (MockFlashFiller.Step memory) {
        return MockFlashFiller.Step({
            payCurrency: _output(order),
            payAmount: order.amountOutMin,
            target: address(0), // set by caller
            callData: abi.encodeCall(Router.fillOrderInCallback, (order, order.amountOutMin))
        });
    }

    function _steps1(MockFlashFiller.Step memory a) internal view returns (MockFlashFiller.Step[] memory s) {
        s = new MockFlashFiller.Step[](1);
        s[0] = a;
        if (s[0].target == address(0)) s[0].target = address(router);
    }

    function _steps2(MockFlashFiller.Step memory a, MockFlashFiller.Step memory b)
        internal
        view
        returns (MockFlashFiller.Step[] memory s)
    {
        s = new MockFlashFiller.Step[](2);
        s[0] = a;
        s[1] = b;
        for (uint256 i; i < 2; ++i) {
            if (s[i].target == address(0)) s[i].target = address(router);
        }
    }

    /// @dev The cross-book book: Bob bids 2970 USDC for 0.99 ETH, Carol asks 2000 USDC for 100 TOKEN, Alice wants at
    ///      least 90 TOKEN for 1 ETH on the ETH/TOKEN pool.
    function _crossBook() internal returns (AsyncOrder memory a, AsyncOrder memory b, AsyncOrder memory c) {
        b = _place(bob, ethUsdc, USDC, 2970 ether, 0.99 ether);
        c = _place(carol, tokenUsdc, TOKEN, 100 ether, 2000 ether);
        a = _place(alice, ethToken, ETH, 1 ether, 90 ether);
    }

    /* ------------------------------------------------------------------ cross-book fill */

    /// @notice ETH -> TOKEN filled from the books alone: the filler sells Alice's ETH into Bob's ETH/USDC bid and buys
    ///         Carol's TOKEN with that USDC, then pays Alice. It starts and ends with no tokens in its wallet.
    function test_flashFill_crossBook_noInventory() public {
        (AsyncOrder memory a, AsyncOrder memory b, AsyncOrder memory c) = _crossBook();
        uint256 aliceToken = token.balanceOf(alice);
        uint256 carolUsdc = usdc.balanceOf(carol);

        filler.run(a, 90 ether, _steps2(_fillStep(b), _fillStep(c)), 0);

        // Every maker paid its minimum less the 0.02% trade fee.
        assertEq(token.balanceOf(alice) - aliceToken, 90 ether - _fee(90 ether), "alice TOKEN");
        assertEq(manager.balanceOf(bob, ETH.toId()), 0.99 ether - _fee(0.99 ether), "bob ETH claims");
        assertEq(usdc.balanceOf(carol) - carolUsdc, 2000 ether - _fee(2000 ether), "carol USDC");
        // All three orders are closed.
        assertEq(_live(a), 0);
        assertEq(_live(b), 0);
        assertEq(_live(c), 0);
        // The filler held nothing and keeps the surplus, as claims.
        assertEq(address(filler).balance, 0);
        assertEq(usdc.balanceOf(address(filler)), 0);
        assertEq(token.balanceOf(address(filler)), 0);
        assertEq(manager.balanceOf(address(filler), ETH.toId()), (1 ether - _fee(1 ether)) - 0.99 ether, "ETH");
        assertEq(manager.balanceOf(address(filler), USDC.toId()), (2970 ether - _fee(2970 ether)) - 2000 ether);
        assertEq(manager.balanceOf(address(filler), TOKEN.toId()), (100 ether - _fee(100 ether)) - 90 ether);
        // The hook escrows nothing for the closed orders, and the router holds nothing.
        assertEq(manager.balanceOf(address(hook), ETH.toId()), 0);
        assertEq(manager.balanceOf(address(hook), USDC.toId()), 0);
        assertEq(manager.balanceOf(address(hook), TOKEN.toId()), 0);
        assertEq(manager.balanceOf(address(router), TOKEN.toId()), 0);
        assertEq(filler.calls(), 1);
    }

    /// @notice The reverse route pays native ETH out: TOKEN -> USDC through a resting TOKEN/USDC bid, USDC -> ETH
    ///         through a resting ETH/USDC ask. Alice's ETH arrives as native claims, like every native payout.
    function test_flashFill_nativeOutput_crossBook() public {
        AsyncOrder memory bid = _place(bob, tokenUsdc, USDC, 2500 ether, 99 ether);
        AsyncOrder memory ask = _place(carol, ethUsdc, ETH, 1 ether, 2400 ether);
        AsyncOrder memory a = _place(alice, ethToken, TOKEN, 100 ether, 0.9 ether);

        filler.run(a, 0.9 ether, _steps2(_fillStep(bid), _fillStep(ask)), 0);

        assertEq(manager.balanceOf(alice, ETH.toId()), 0.9 ether - _fee(0.9 ether), "alice ETH claims");
        assertEq(token.balanceOf(bob), 1_000_000 ether + 99 ether - _fee(99 ether), "bob TOKEN");
        assertEq(usdc.balanceOf(carol), 1_000_000 ether + 2400 ether - _fee(2400 ether), "carol USDC");
        assertEq(manager.balanceOf(address(filler), ETH.toId()), (1 ether - _fee(1 ether)) - 0.9 ether);
        assertEq(address(filler).balance, 0);
    }

    /// @notice A flash fill works for an order on a numeraire pool too: Carol sells ETH for USDC, and the filler routes
    ///         ETH -> TOKEN through Bob's bid on the ETH/TOKEN pool and TOKEN -> USDC through Alice's TOKEN/USDC bid.
    function test_flashFill_numerairePair() public {
        AsyncOrder memory bobBuysEth = _place(bob, ethToken, TOKEN, 300 ether, 0.99 ether);
        AsyncOrder memory aliceBuysToken = _place(alice, tokenUsdc, USDC, 1600 ether, 290 ether);
        AsyncOrder memory c = _place(carol, ethUsdc, ETH, 1 ether, 1500 ether);
        uint256 carolUsdc = usdc.balanceOf(carol);

        filler.run(c, 1500 ether, _steps2(_fillStep(bobBuysEth), _fillStep(aliceBuysToken)), 0);

        assertEq(usdc.balanceOf(carol) - carolUsdc, 1500 ether - _fee(1500 ether), "carol USDC");
        assertEq(_live(c), 0);
        assertEq(_live(bobBuysEth), 0);
        assertEq(_live(aliceBuysToken), 0);
        assertEq(usdc.balanceOf(address(filler)), 0);
        assertEq(manager.balanceOf(address(filler), USDC.toId()), (1600 ether - _fee(1600 ether)) - 1500 ether);
    }

    /// @notice Fees on a flash fill match a plain fill: 0.02% of the input and of the maker's minimum to the vault.
    function test_flashFill_feesToVault() public {
        (AsyncOrder memory a, AsyncOrder memory b, AsyncOrder memory c) = _crossBook();
        filler.run(a, 90 ether, _steps2(_fillStep(b), _fillStep(c)), 0);
        address vault = address(hook.feeVault());
        assertEq(manager.balanceOf(vault, ETH.toId()), _fee(1 ether) + _fee(0.99 ether));
        assertEq(manager.balanceOf(vault, TOKEN.toId()), _fee(90 ether) + _fee(100 ether));
        assertEq(manager.balanceOf(vault, USDC.toId()), _fee(2970 ether) + _fee(2000 ether));
    }

    /* ------------------------------------------------------------------ the maker check */

    /// @notice Paying the maker one unit short reverts the whole fill, resting orders included.
    function test_flashFill_underpayingMakerReverts() public {
        (AsyncOrder memory a, AsyncOrder memory b, AsyncOrder memory c) = _crossBook();
        vm.expectRevert();
        filler.run(a, 90 ether, _steps2(_fillStep(b), _fillStep(c)), 1);
        assertEq(_live(a), 1 ether);
        assertEq(_live(b), 2970 ether);
        assertEq(_live(c), 100 ether);
    }

    /// @notice A filler that never sources the output cannot pay: it holds no TOKEN claims at the end.
    function test_flashFill_noRouteReverts() public {
        (AsyncOrder memory a,,) = _crossBook();
        vm.expectRevert();
        filler.run(a, 90 ether, new MockFlashFiller.Step[](0), 0);
        assertEq(_live(a), 1 ether);
    }

    /// @notice A filler that spends its credited input on an open delta it never closes fails the unlock.
    function test_flashFill_unsettledDeltaReverts() public {
        (AsyncOrder memory a, AsyncOrder memory b, AsyncOrder memory c) = _crossBook();
        MockFlashFiller.Step memory burnEth = MockFlashFiller.Step({
            payCurrency: ETH,
            payAmount: 0,
            target: address(manager),
            callData: abi.encodeCall(IPoolManager.burn, (address(filler), ETH.toId(), 0.001 ether))
        });
        MockFlashFiller.Step[] memory steps = new MockFlashFiller.Step[](3);
        steps[0] = burnEth;
        steps[1] = _fillStep(b);
        steps[1].target = address(router);
        steps[2] = _fillStep(c);
        steps[2].target = address(router);
        vm.expectRevert(IPoolManager.CurrencyNotSettled.selector);
        filler.run(a, 90 ether, steps, 0);
    }

    /// @notice `maxPrice` caps the output owed, and `order.amountIn` is the least input accepted.
    function test_flashFill_boundsChecked() public {
        (AsyncOrder memory a, AsyncOrder memory b, AsyncOrder memory c) = _crossBook();
        MockFlashFiller.Step[] memory steps = _steps2(_fillStep(b), _fillStep(c));
        vm.expectRevert("Price exceeds maxPrice");
        filler.run(a, 90 ether - 1, steps, 0);
        a.amountIn = 1 ether + 1;
        vm.expectRevert("Input below order.amountIn");
        filler.run(a, 90 ether, steps, 0);
    }

    /* ------------------------------------------------------------------ the locked order */

    /// @dev Runs a flash fill of Alice's order whose only step is `step`, expecting `reason`.
    function _expectStepRevert(MockFlashFiller.Step memory step, bytes memory reason) internal {
        (AsyncOrder memory a,,) = _crossBook();
        if (step.target == address(0)) step.target = address(router);
        vm.expectRevert(reason);
        filler.run(a, 90 ether, _steps1(step), 0);
        assertEq(_live(a), 1 ether);
    }

    function _call(address target, bytes memory callData) internal pure returns (MockFlashFiller.Step memory) {
        return MockFlashFiller.Step({payCurrency: ETH, payAmount: 0, target: target, callData: callData});
    }

    function _alicesOrder() internal view returns (AsyncOrder memory a) {
        // Same fields `_crossBook` places; the salt is what the hook assigns to Alice's first ETH/TOKEN order.
        a = AsyncOrder({
            key: ethToken,
            owner: alice,
            zeroForOne: true,
            amountIn: 1 ether,
            amountOutMin: 90 ether,
            priorityFee: 0,
            sqrtPrice: 2 ** 96,
            salt: keccak256(
                abi.encode(block.timestamp, block.number, address(manager), alice, 1 ether, 90 ether, uint256(0))
            )
        });
    }

    /// @notice The order being flash-filled cannot be filled again inside its own callback.
    function test_lockedOrder_cannotBeFilledAgain() public {
        AsyncOrder memory a = _alicesOrder();
        MockFlashFiller.Step memory step = _fillStep(a);
        _expectStepRevert(step, abi.encodeWithSelector(AsyncFiller.OrderNotFound.selector));
    }

    /// @notice ...nor cancelled through the hook from the open unlock (the maker here would be the executor).
    function test_lockedOrder_cannotBeCancelledThroughHook() public {
        vm.prank(alice);
        hook.setExecutor(ethToken.toId(), address(filler), true);
        _expectStepRevert(
            _call(address(hook), abi.encodeCall(AsyncSwap.cancelOrder, (_alicesOrder()))),
            abi.encodeWithSelector(AsyncFiller.OrderNotFound.selector)
        );
    }

    /// @notice ...nor cancelled through the Router, which refuses every normal entry point during a flash fill.
    function test_lockedOrder_cannotBeCancelledThroughRouter() public {
        _expectStepRevert(
            _call(address(router), abi.encodeCall(Router.cancelOrder, (_alicesOrder()))),
            abi.encodeWithSelector(Router.FlashFillActive.selector)
        );
    }

    /// @notice ...nor repriced: the order is closed for the whole callback.
    function test_lockedOrder_cannotBeRepriced() public {
        // `updatePrice` checks the caller is the owner first, so make the filler the maker of the locked order.
        vm.deal(address(filler), 1 ether);
        filler.exec(address(hook), abi.encodeCall(AsyncSwap.setExecutor, (ethToken.toId(), address(router), true)));
        _place(bob, ethUsdc, USDC, 2970 ether, 0.99 ether);
        _place(carol, tokenUsdc, TOKEN, 100 ether, 2000 ether);
        AsyncOrder memory own = _placeAsFiller(1 ether, 90 ether);
        own.amountOutMin = 90 ether;
        MockFlashFiller.Step[] memory steps =
            _steps1(_call(address(hook), abi.encodeCall(AsyncSwap.updatePrice, (own, 80 ether))));
        vm.expectRevert(abi.encodeWithSelector(AsyncFiller.OrderNotFound.selector));
        filler.run(own, 90 ether, steps, 0);
        assertEq(_live(own), 1 ether);
    }

    function _placeAsFiller(uint256 amountIn, uint256 amountOutMin) internal returns (AsyncOrder memory order) {
        order = AsyncOrder({
            key: ethToken,
            owner: address(filler),
            zeroForOne: true,
            amountIn: amountIn,
            amountOutMin: amountOutMin,
            priorityFee: 0,
            sqrtPrice: 2 ** 96,
            salt: bytes32(0)
        });
        bytes memory userData = abi.encode(
            AsyncSwap.UserParams({
                user: address(filler), executor: address(router), amountOutMin: amountOutMin, priorityFee: 0
            })
        );
        filler.exec{value: amountIn}(address(router), abi.encodeCall(Router.swap, (order, userData)));
        order.salt = keccak256(
            abi.encode(
                block.timestamp, block.number, address(manager), address(filler), amountIn, amountOutMin, uint256(0)
            )
        );
    }

    /// @notice ...nor topped up.
    function test_lockedOrder_cannotBeToppedUp() public {
        _expectStepRevert(
            _call(address(router), abi.encodeCall(Router.topUpPriorityFee, (_alicesOrder(), 1))),
            abi.encodeWithSelector(Router.FlashFillActive.selector)
        );
    }

    /// @notice Flash fills do not nest, and the normal fill path is closed during one.
    function test_reentrancy_normalEntryPointsRefused() public {
        AsyncOrder memory a = _alicesOrder();
        _expectStepRevert(
            _call(address(router), abi.encodeCall(Router.fillOrderWithCallback, (a, 90 ether, ""))),
            abi.encodeWithSelector(Router.FlashFillActive.selector)
        );
        _expectStepRevert(
            _call(address(router), abi.encodeCall(Router.fillOrder, (a, 90 ether, ""))),
            abi.encodeWithSelector(Router.FlashFillActive.selector)
        );
        _expectStepRevert(
            _call(address(router), abi.encodeCall(Router.matchBook, (ethUsdc, 1))),
            abi.encodeWithSelector(Router.FlashFillActive.selector)
        );
    }

    /// @notice The hook's flash-fill and claims-fill entry points take only the Router.
    function test_hookEntryPoints_routerOnly() public {
        AsyncOrder memory a = _alicesOrder();
        vm.expectRevert(AsyncSwap.NotTrustedRouter.selector);
        hook.beginFlashFill(a, address(this));
        vm.expectRevert(AsyncSwap.NotTrustedRouter.selector);
        hook.settleFlashFill(a, address(this));
        vm.expectRevert(AsyncSwap.NotTrustedRouter.selector);
        hook.executeOrderWithClaims(a, address(this));
    }

    /* ------------------------------------------------------------------ in-unlock entry points */

    /// @notice Outside a flash fill nobody may use the in-unlock entry points.
    function test_inFlash_refusedWithoutActiveFlashFill() public {
        (, AsyncOrder memory b,) = _crossBook();
        vm.expectRevert(Router.NotFlashFiller.selector);
        router.fillOrderInCallback(b, type(uint256).max);
        vm.expectRevert(Router.NotFlashFiller.selector);
        router.matchBookInCallback(ethUsdc, 1);
        vm.expectRevert(Router.NotFlashFiller.selector);
        filler.exec(address(router), abi.encodeCall(Router.fillOrderInCallback, (b, type(uint256).max)));
    }

    /// @notice During a flash fill only its own filler may use them, not another contract it calls.
    function test_inFlash_refusedForOtherCaller() public {
        Bystander other = new Bystander();
        AsyncOrder memory b = _place(bob, ethUsdc, USDC, 2970 ether, 0.99 ether);
        _place(carol, tokenUsdc, TOKEN, 100 ether, 2000 ether);
        AsyncOrder memory a = _place(alice, ethToken, ETH, 1 ether, 90 ether);
        MockFlashFiller.Step[] memory steps = _steps1(
            _call(
                address(other),
                abi.encodeCall(
                    Bystander.call, (address(router), abi.encodeCall(Router.fillOrderInCallback, (b, 0.99 ether)))
                )
            )
        );
        vm.expectRevert(Router.NotFlashFiller.selector);
        filler.run(a, 90 ether, steps, 0);
    }

    /// @notice The active-filler slot is cleared when the flash fill ends.
    function test_inFlash_slotClearedAfterFill() public {
        (AsyncOrder memory a, AsyncOrder memory b, AsyncOrder memory c) = _crossBook();
        AsyncOrder memory spare = _place(bob, ethUsdc, USDC, 2970 ether, 0.98 ether);
        filler.run(a, 90 ether, _steps2(_fillStep(b), _fillStep(c)), 0);
        vm.expectRevert(Router.NotFlashFiller.selector);
        filler.exec(address(router), abi.encodeCall(Router.fillOrderInCallback, (spare, type(uint256).max)));
        // Normal entry points work again.
        router.matchBook(ethUsdc, 1);
    }

    /// @notice `matchBookInCallback` runs the book matcher from inside the callback.
    function test_inFlash_matchBook() public {
        (AsyncOrder memory a, AsyncOrder memory b, AsyncOrder memory c) = _crossBook();
        MockFlashFiller.Step[] memory steps = new MockFlashFiller.Step[](3);
        steps[0] = _call(address(router), abi.encodeCall(Router.matchBookInCallback, (ethUsdc, 1)));
        steps[1] = _fillStep(b);
        steps[1].target = address(router);
        steps[2] = _fillStep(c);
        steps[2].target = address(router);
        filler.run(a, 90 ether, steps, 0);
        assertEq(_live(a), 0);
    }

    /// @notice A resting order filled inside a flash fill keeps its own maxPrice check.
    function test_inFlash_fillRespectsMaxPrice() public {
        (AsyncOrder memory a, AsyncOrder memory b,) = _crossBook();
        MockFlashFiller.Step memory step = _fillStep(b);
        step.callData = abi.encodeCall(Router.fillOrderInCallback, (b, 0.99 ether - 1));
        step.target = address(router);
        vm.expectRevert("Price exceeds maxPrice");
        filler.run(a, 90 ether, _steps1(step), 0);
    }
}
