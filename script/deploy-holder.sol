// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/Script.sol";
import {OndoHolder} from "../src/strategies/ondo/OndoHolder.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast();

        address USDC = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

        OndoHolder holder = new OndoHolder(
            USDC,
            "OndoHolder USDC",
            address(0x3Ed6aa32c930253fc990dE58fF882B9186cd0072),
            address(0xa42613C243b67BF6194Ac327795b926B4b491f15),
            address(0xaf37c1167910ebC994e266949387d2c7C326b879)
        );

        console.log("Holder deployed at", address(holder));

        vm.stopBroadcast();
    }
}
