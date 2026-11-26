// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Script, console} from "forge-std/Script.sol";
import {SimpleVault} from "../src/SimpleVault.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";

contract Deploy is Script {
    function run() external returns (MockERC20 token, SimpleVault vault) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(pk);
        uint256 cap = vm.envOr("DEPOSIT_CAP", uint256(1_000_000e6)); // 1M mUSD
        uint256 delay = vm.envOr("WITHDRAWAL_DELAY", uint256(5 minutes)); // short, for demos

        vm.startBroadcast(pk);
        token = new MockERC20(6); // 6 decimals like USDC, so the frontend must handle decimals properly
        vault = new SimpleVault(token, "Simple Vault Share", "svUSD", owner, cap, delay);
        vm.stopBroadcast();

        console.log("TOKEN_ADDRESS", address(token));
        console.log("VAULT_ADDRESS", address(vault));
    }
}
