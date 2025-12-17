// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/Script.sol";
import {Holder} from "../src/strategies/holder/Holder.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast();

        Holder holder = new Holder(
            0x434558CB1EBe9950e8A66f1ef8A15A473Dce7D8c,
            "Holder wWTGXX"
        );

        console.log("Holder deployed at", address(holder));

        vm.stopBroadcast();
    }
}
