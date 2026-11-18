// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {LaunchpadTest} from "./Launchpad.t.sol";
import {Launchpad} from "src/Launchpad.sol";
import {AsyncSwap} from "src/AsyncSwap.sol";
import {Router} from "src/Router.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {console2} from "forge-std/console2.sol";

/// @notice Opt-in fork check against live testnet deployments. No private key or broadcasts.
/// LAUNCHPAD_TESTNET_RPC=<url> forge test --match-contract LaunchpadTestnetTest -vv
contract LaunchpadTestnetTest is LaunchpadTest {
    function setUp() public override {
        string memory rpc = vm.envOr("LAUNCHPAD_TESTNET_RPC", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpc);
        require(block.chainid == 1301 || block.chainid == 46630, "Testnet only");
        address target = block.chainid == 1301
            ? 0x91B1e6C36Af74737FF82A654Fa7a1747fE186888
            : 0x91E143120F9758b875713aA5E476E8e853C86888;
        require(target.code.length > 0, "Hook not deployed");
        hook = AsyncSwap(payable(target));
        manager = hook.poolManager();
        router = Router(payable(hook.router()));
        currency1 = hook.numeraire();
        token1 = MockERC20(Currency.unwrap(currency1));
        require(address(manager).code.length > 0 && address(router).code.length > 0, "Missing dependency");
        console2.log("Testnet chain", block.chainid);
        console2.log("Fork block", block.number);
        pad = new Launchpad(hook);
    }

    function _fundBuyer() internal override {
        // Test-only funding in the local fork, never a mint transaction on the remote testnet.
        deal(address(token1), buyer, 100e6);
    }
}
