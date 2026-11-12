// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {ISignatureTransfer} from "@async-swap/interfaces/ISignatureTransfer.sol";
import {Permit2Bytecode} from "./utils/Permit2Bytecode.sol";
import {AsyncSwap} from "@async-swap/AsyncSwap.sol";
import {AsyncFiller} from "@async-swap/libraries/AsyncFiller.sol";
import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";
import {Router} from "@async-swap/Router.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {Test, Vm} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {CustomRevert} from "v4-core/libraries/CustomRevert.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolIdLibrary, PoolKey} from "v4-core/types/PoolKey.sol";

/// @notice Pools without the numeraire (approach E): opened only once both tokens have a numeraire pool on the hook,
///         `currency1` is the quote side, and the minimum order is each token's decimal floor.
contract NonNumerairePoolsTest is Test {
    using PoolIdLibrary for PoolKey;

    address owner = makeAddr("deployer");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    IPoolManager manager;
    AsyncSwap hook;
    Router router;
    MockERC20 usdc;
    MockERC20 token; // 18 decimals
    MockERC20 small; // 6 decimals
    Currency constant ETH = Currency.wrap(address(0));
    Currency USDC;
    Currency TOKEN;
    Currency SMALL;

    function setUp() public {
        manager = new PoolManager(owner);
        usdc = new MockERC20("USD Coin", "USDC", 18);
        token = new MockERC20("Token", "TKN", 18);
        small = new MockERC20("Small", "SML", 6);
        USDC = Currency.wrap(address(usdc));
        TOKEN = Currency.wrap(address(token));
        SMALL = Currency.wrap(address(small));
        vm.mockCall(address(usdc), abi.encodeWithSignature("decimals()"), abi.encode(uint8(6)));

        address hookAddress = address(
            uint160(
                Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                    | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
            )
        );
        router = new Router(manager, AsyncSwap(payable(hookAddress)), ISignatureTransfer(Permit2Bytecode.PERMIT2), 0);
        // Asset precision 4: every order trades at least 0.0001 of each token.
        deployCodeTo(
            "AsyncSwap.sol",
            abi.encode(manager, USDC, address(this), address(router), uint256(0), uint8(4)),
            hookAddress
        );
        hook = AsyncSwap(payable(hookAddress));

        address[2] memory makers = [alice, bob];
        for (uint256 i; i < 2; ++i) {
            vm.deal(makers[i], 100 ether);
            usdc.mint(makers[i], 1_000_000 ether);
            token.mint(makers[i], 1_000_000 ether);
            small.mint(makers[i], 1_000_000e6);
            vm.startPrank(makers[i]);
            usdc.approve(address(router), type(uint256).max);
            token.approve(address(router), type(uint256).max);
            small.approve(address(router), type(uint256).max);
            vm.stopPrank();
        }
    }

    /* ------------------------------------------------------------------ helpers */

    function _key(Currency a, Currency b, int24 tickSpacing) internal view returns (PoolKey memory) {
        (Currency c0, Currency c1) = Currency.unwrap(a) < Currency.unwrap(b) ? (a, b) : (b, a);
        return PoolKey({
            currency0: c0, currency1: c1, fee: LPFeeLibrary.DYNAMIC_FEE_FLAG, tickSpacing: tickSpacing, hooks: hook
        });
    }

    function _init(PoolKey memory key) internal {
        manager.initialize(key, 2 ** 96);
        address[2] memory makers = [alice, bob];
        for (uint256 i; i < 2; ++i) {
            vm.prank(makers[i]);
            hook.setExecutor(key.toId(), address(router), true);
        }
    }

    /// @dev The ETH/TOKEN pool with both numeraire pools in place.
    function _ethToken() internal returns (PoolKey memory key) {
        _init(_key(ETH, USDC, 1));
        _init(_key(TOKEN, USDC, 1));
        key = _key(ETH, TOKEN, 1);
        _init(key);
    }

    function _wrapped(bytes4 selector, bytes memory reason) internal view returns (bytes memory) {
        return abi.encodeWithSelector(
            CustomRevert.WrappedError.selector,
            address(hook),
            selector,
            reason,
            abi.encodeWithSelector(Hooks.HookCallFailed.selector)
        );
    }

    function _order(address maker, PoolKey memory key, Currency input, uint256 amountIn, uint256 amountOutMin)
        internal
        pure
        returns (AsyncOrder memory)
    {
        return AsyncOrder({
            key: key,
            owner: maker,
            zeroForOne: input == key.currency0,
            amountIn: amountIn,
            amountOutMin: amountOutMin,
            priorityFee: 0,
            sqrtPrice: 2 ** 96,
            salt: bytes32(0)
        });
    }

    function _swap(AsyncOrder memory order) internal returns (AsyncOrder memory) {
        bytes memory userData = abi.encode(
            AsyncSwap.UserParams({
                user: order.owner,
                executor: address(router),
                amountOutMin: order.amountOutMin,
                priorityFee: order.priorityFee
            })
        );
        Currency input = order.zeroForOne ? order.key.currency0 : order.key.currency1;
        vm.recordLogs();
        vm.prank(order.owner);
        router.swap{value: input.isAddressZero() ? order.amountIn : 0}(order, userData);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(hook) && logs[i].topics[0] == AsyncFiller.AsyncOrderCreated.selector) {
                (,,, bytes32 salt) = abi.decode(logs[i].data, (bool, uint256, uint256, bytes32));
                order.salt = salt;
            }
        }
        return order;
    }

    function _live(AsyncOrder memory order) internal view returns (uint256 amountIn) {
        bytes32 id = keccak256(abi.encode(block.chainid, order.key.toId(), order.owner, order.zeroForOne, order.salt));
        (amountIn,) = hook.asyncOrderInfo(order.key.toId(), id);
    }

    function _fee(uint256 x) internal pure returns (uint256) {
        return Math.mulDiv(x, 2, 10_000, Math.Rounding.Ceil);
    }

    /* ------------------------------------------------------------------ pool creation */

    function test_init_revertsWithoutNumerairePools() public {
        PoolKey memory key = _key(ETH, TOKEN, 1);
        vm.expectRevert(
            _wrapped(IHooks.beforeInitialize.selector, abi.encodeWithSelector(AsyncSwap.NumeraireRequired.selector))
        );
        manager.initialize(key, 2 ** 96);
    }

    function test_init_revertsWithOnlyOneNumerairePool() public {
        _init(_key(ETH, USDC, 1));
        PoolKey memory key = _key(ETH, TOKEN, 1);
        vm.expectRevert(
            _wrapped(IHooks.beforeInitialize.selector, abi.encodeWithSelector(AsyncSwap.NumeraireRequired.selector))
        );
        manager.initialize(key, 2 ** 96);
    }

    /// @notice The numeraire pools must have the new pool's tick spacing.
    function test_init_revertsOnOtherTickSpacing() public {
        _init(_key(ETH, USDC, 1));
        _init(_key(TOKEN, USDC, 1));
        PoolKey memory key = _key(ETH, TOKEN, 10);
        vm.expectRevert(
            _wrapped(IHooks.beforeInitialize.selector, abi.encodeWithSelector(AsyncSwap.NumeraireRequired.selector))
        );
        manager.initialize(key, 2 ** 96);
    }

    function test_init_revertsWithoutDynamicFee() public {
        _init(_key(ETH, USDC, 1));
        _init(_key(TOKEN, USDC, 1));
        PoolKey memory key = _key(ETH, TOKEN, 1);
        key.fee = 3000;
        vm.expectRevert(
            _wrapped(IHooks.beforeInitialize.selector, abi.encodeWithSelector(AsyncSwap.DynamicFeeRequired.selector))
        );
        manager.initialize(key, 2 ** 96);
    }

    /// @notice Each side's floor follows its own token's decimals: 0.0001 of an 18- and a 6-decimal token.
    function test_init_setsDecimalFloorsBothSides() public {
        _init(_key(TOKEN, USDC, 1));
        _init(_key(SMALL, USDC, 1));
        PoolKey memory key = _key(TOKEN, SMALL, 1);
        _init(key);
        uint256 floor0 = key.currency0 == TOKEN ? 1e14 : 100;
        assertEq(hook.minAssetAmount(key.toId()), floor0);
    }

    /// @notice Numeraire pools keep their own rules.
    function test_numerairePool_unchanged() public {
        PoolKey memory key = _key(TOKEN, USDC, 1);
        _init(key);
        assertEq(hook.minAssetAmount(key.toId()), 1e14);
    }

    /* ------------------------------------------------------------------ orders */

    function test_order_belowInputFloorReverts() public {
        PoolKey memory key = _ethToken();
        // ETH is currency0, the asset side: below 0.0001 ETH in.
        AsyncOrder memory order = _order(alice, key, ETH, 1e14 - 1, 1 ether);
        vm.expectRevert();
        this.swapExternal(order);
        order.amountIn = 1e14;
        _swap(order);
    }

    function test_order_belowOutputFloorReverts() public {
        PoolKey memory key = _ethToken();
        // Asks for less than 0.0001 TOKEN out.
        AsyncOrder memory order = _order(alice, key, ETH, 1 ether, 1e14 - 1);
        vm.expectRevert();
        this.swapExternal(order);
        order.amountOutMin = 1e14;
        _swap(order);
    }

    function swapExternal(AsyncOrder memory order) external {
        _swap(order);
    }

    function test_order_priorityFeeReverts() public {
        PoolKey memory key = _ethToken();
        AsyncOrder memory order = _order(alice, key, ETH, 1 ether, 90 ether);
        order.priorityFee = 100_000;
        vm.expectRevert(
            _wrapped(IHooks.beforeSwap.selector, abi.encodeWithSelector(AsyncSwap.PriorityFeeNeedsNumeraire.selector))
        );
        this.swapExternal(order);
    }

    function test_order_topUpReverts() public {
        PoolKey memory key = _ethToken();
        AsyncOrder memory order = _swap(_order(alice, key, ETH, 1 ether, 90 ether));
        vm.prank(alice);
        vm.expectRevert(AsyncSwap.PriorityFeeNeedsNumeraire.selector);
        router.topUpPriorityFee(order, 100_000);
    }

    function test_order_cancel() public {
        PoolKey memory key = _ethToken();
        AsyncOrder memory order = _swap(_order(alice, key, ETH, 1 ether, 90 ether));
        assertEq(_live(order), 1 ether);
        vm.prank(alice);
        router.cancelOrder(order);
        assertEq(_live(order), 0);
        assertEq(manager.balanceOf(alice, ETH.toId()), 1 ether);
    }

    function test_order_reprice() public {
        PoolKey memory key = _ethToken();
        AsyncOrder memory order = _swap(_order(alice, key, ETH, 1 ether, 90 ether));
        vm.prank(alice);
        hook.updatePrice(order, 80 ether);
        bytes32 id = keccak256(abi.encode(block.chainid, key.toId(), alice, true, order.salt));
        (, uint256 out) = hook.asyncOrderInfo(key.toId(), id);
        assertEq(out, 80 ether);
    }

    /// @notice A plain filler fill works as on any pool.
    function test_order_fill() public {
        PoolKey memory key = _ethToken();
        AsyncOrder memory order = _swap(_order(alice, key, ETH, 1 ether, 90 ether));
        uint256 aliceToken = token.balanceOf(alice);
        vm.prank(bob);
        router.fillOrder(order, 90 ether, "");
        assertEq(_live(order), 0);
        assertEq(token.balanceOf(alice) - aliceToken, 90 ether - _fee(90 ether));
        assertEq(manager.balanceOf(bob, ETH.toId()), 1 ether - _fee(1 ether));
    }

    /// @notice With `currency1` as the quote side, opposite orders on the pool cross and match directly.
    function test_order_oppositeOrdersMatch() public {
        PoolKey memory key = _ethToken();
        // Alice sells 1 ETH for at least 90 TOKEN; Bob sells 100 TOKEN for at least 1 ETH.
        AsyncOrder memory ask = _swap(_order(alice, key, ETH, 1 ether, 90 ether));
        AsyncOrder memory bid = _swap(_order(bob, key, TOKEN, 100 ether, 1 ether));
        assertEq(_live(ask), 0, "ask filled");
        // Bob's bid fills at Alice's resting price, 90 TOKEN for 1 ETH; 10 TOKEN stays on the book.
        assertEq(_live(bid), 10 ether, "bid remainder");
        assertEq(manager.balanceOf(bob, ETH.toId()), 1 ether - _fee(1 ether));
    }

    /// @notice Orders in the same direction rest side by side and do not match.
    function test_order_sameDirectionRests() public {
        PoolKey memory key = _ethToken();
        AsyncOrder memory a = _swap(_order(alice, key, ETH, 1 ether, 90 ether));
        AsyncOrder memory b = _swap(_order(bob, key, ETH, 1 ether, 95 ether));
        assertEq(_live(a), 1 ether);
        assertEq(_live(b), 1 ether);
    }
}
