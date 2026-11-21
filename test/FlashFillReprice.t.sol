// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {FlashFillTest, MockFlashFiller} from "./FlashFill.t.sol";
import {AsyncSwap} from "@async-swap/AsyncSwap.sol";
import {AsyncOrder} from "@async-swap/types/AsyncOrder.sol";
import {IAsyncSwapCallback} from "@async-swap/interfaces/IAsyncSwapCallback.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolIdLibrary, PoolKey} from "v4-core/types/PoolKey.sol";

/// @notice An ERC20 that calls `onTokenReceived` on a recipient with code, like ERC-777 or ERC-1363 style tokens.
///         Anyone may open a numeraire pool for such a token.
contract CallbackToken {
    string public name = "Callback";
    string public symbol = "CBT";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _move(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        _move(from, to, amount);
        return true;
    }

    function _move(address from, address to, uint256 amount) private {
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        if (to.code.length != 0) {
            (bool ok,) = to.call(abi.encodeWithSignature("onTokenReceived()"));
            ok;
        }
    }
}

/// @notice A maker that raises its own order's minimum output when it is paid, i.e. while the Router is between
///         paying the hook and the hook paying the maker.
contract RepricingMaker {
    AsyncSwap public hook;
    AsyncOrder public order;
    uint256 public newMin;
    bool public armed;

    function arm(AsyncSwap _hook, AsyncOrder calldata _order, uint256 _newMin) external {
        hook = _hook;
        order = _order;
        newMin = _newMin;
        armed = true;
    }

    function onTokenReceived() external {
        _reprice();
    }

    receive() external payable {
        _reprice();
    }

    function _reprice() private {
        if (!armed) return;
        armed = false;
        hook.updatePrice(order, newMin);
    }
}

/// @notice Pays native ETH into the PoolManager on someone else's account, so a test filler can mint ETH claims.
contract EthCredit {
    function credit(IPoolManager manager, address to, uint256 amount) external {
        manager.sync(Currency.wrap(address(0)));
        manager.settleFor{value: amount}(to);
    }

    receive() external payable {}
}

/// @notice A fill inside a flash fill (`fillOrderInCallback`) must pay the maker exactly what the filler paid in. A
///         maker that tries to reprice while it is being paid must not draw on other makers' escrow: the hook closes
///         the order and burns exactly what was paid before any payout runs the maker's code.
contract FlashFillRepriceTest is FlashFillTest {
    using PoolIdLibrary for PoolKey;

    CallbackToken cbt;
    Currency CBT;
    PoolKey cbtUsdc;
    address victim = makeAddr("victim");
    address attacker = makeAddr("attacker");

    function _setUpCallbackPool() internal {
        cbt = new CallbackToken();
        CBT = Currency.wrap(address(cbt));
        cbtUsdc = _key(CBT, USDC);
        manager.initialize(cbtUsdc, 2 ** 96);
        address[2] memory makers = [victim, attacker];
        for (uint256 i; i < 2; ++i) {
            cbt.mint(makers[i], 1_000_000 ether);
            usdc.mint(makers[i], 1_000_000 ether);
            vm.startPrank(makers[i]);
            cbt.approve(address(router), type(uint256).max);
            usdc.approve(address(router), type(uint256).max);
            hook.setExecutor(cbtUsdc.toId(), address(router), true);
            vm.stopPrank();
        }
    }

    function _step(address target, bytes memory callData) internal pure returns (MockFlashFiller.Step memory s) {
        s.target = target;
        s.callData = callData;
    }

    function test_inCallbackFill_makerRepriceWhilePaidCannotDrainEscrow() public {
        _setUpCallbackPool();
        // The pot: the victim escrows 1000 CBT selling for USDC.
        _place(victim, cbtUsdc, CBT, 1000 ether, 100_000 ether); // 100 USDC per CBT, above the attacker's bid
        // The attacker sells 200 USDC for at least 10 CBT, and tries to raise that to 900 CBT while being paid.
        AsyncOrder memory evil = _place(attacker, cbtUsdc, USDC, 200 ether, 10 ether);
        uint256 owed = 10 ether;
        vm.etch(attacker, address(new RepricingMaker()).code);
        RepricingMaker(payable(attacker)).arm(hook, evil, 900 ether);

        // The outer flash fill: Bob sells 1 TOKEN for 100 USDC, paid from the USDC the in-callback fill releases.
        AsyncOrder memory outer = _place(bob, tokenUsdc, TOKEN, 1 ether, 100 ether);

        // The filler brings 10 CBT as claims and fills the attacker's order at its minimum.
        cbt.mint(address(filler), owed);
        MockFlashFiller.Step[] memory steps = new MockFlashFiller.Step[](5);
        steps[0] = _step(address(manager), abi.encodeCall(IPoolManager.sync, (CBT)));
        steps[1] = _step(address(cbt), abi.encodeCall(CallbackToken.transfer, (address(manager), owed)));
        steps[2] = _step(address(manager), abi.encodeWithSignature("settle()"));
        steps[3] = _step(address(manager), abi.encodeCall(IPoolManager.mint, (address(filler), CBT.toId(), owed)));
        steps[4] = MockFlashFiller.Step({
            payCurrency: CBT,
            payAmount: owed,
            target: address(router),
            callData: abi.encodeCall(IAsyncSwapCallback.fillOrderInCallback, (evil, owed))
        });

        uint256 attackerBefore = cbt.balanceOf(attacker);
        filler.run(outer, 100 ether, steps, 0);
        emit log_named_uint("attacker CBT gain", cbt.balanceOf(attacker) - attackerBefore);

        // Whatever happened, the attacker got at most what the filler paid, and the victim's escrow is whole.
        assertLe(cbt.balanceOf(attacker) - attackerBefore, owed, "attacker paid more than the filler paid");
        assertGe(manager.balanceOf(address(hook), CBT.toId()), 1000 ether, "victim escrow drained");
    }

    /// @notice The same attempt with native ETH output: the payout is claims, so the maker's `receive` never runs.
    function test_inCallbackFill_nativeMakerRepriceWhilePaidCannotDrainEscrow() public {
        address victimEth = makeAddr("victimEth");
        address attackerEth = makeAddr("attackerEth");
        vm.deal(victimEth, 100 ether);
        usdc.mint(attackerEth, 1_000_000 ether);
        vm.prank(victimEth);
        hook.setExecutor(ethUsdc.toId(), address(router), true);
        vm.startPrank(attackerEth);
        usdc.approve(address(router), type(uint256).max);
        hook.setExecutor(ethUsdc.toId(), address(router), true);
        vm.stopPrank();

        // The pot: 50 ETH escrowed, asking far above the attacker's bid.
        _place(victimEth, ethUsdc, ETH, 50 ether, 1_000_000 ether);
        // The attacker buys ETH with 200 USDC for at least 0.1 ETH.
        AsyncOrder memory evil = _place(attackerEth, ethUsdc, USDC, 200 ether, 0.1 ether);
        uint256 owed = 0.1 ether;
        vm.etch(attackerEth, address(new RepricingMaker()).code);
        RepricingMaker(payable(attackerEth)).arm(hook, evil, 40 ether);

        AsyncOrder memory outer = _place(bob, tokenUsdc, TOKEN, 1 ether, 100 ether);
        EthCredit credit = new EthCredit();
        vm.deal(address(credit), owed);
        MockFlashFiller.Step[] memory steps = new MockFlashFiller.Step[](3);
        steps[0] = _step(address(credit), abi.encodeCall(EthCredit.credit, (manager, address(filler), owed)));
        steps[1] = _step(address(manager), abi.encodeCall(IPoolManager.mint, (address(filler), ETH.toId(), owed)));
        steps[2] = MockFlashFiller.Step({
            payCurrency: ETH,
            payAmount: owed,
            target: address(router),
            callData: abi.encodeCall(IAsyncSwapCallback.fillOrderInCallback, (evil, owed))
        });

        uint256 before = attackerEth.balance + manager.balanceOf(attackerEth, ETH.toId());
        filler.run(outer, 100 ether, steps, 0);
        uint256 gain = attackerEth.balance + manager.balanceOf(attackerEth, ETH.toId()) - before;
        emit log_named_uint("attacker ETH gain", gain);

        assertLe(gain, owed, "attacker paid more than the filler paid");
        assertGe(manager.balanceOf(address(hook), ETH.toId()), 50 ether, "victim ETH escrow drained");
    }
}
