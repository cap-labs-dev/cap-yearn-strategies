// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/Script.sol";
import {MorphoCompounderFactory} from "../src/strategies/morpho/MorphoCompounderFactory.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast();

        address management = 0xb8FC49402dF3ee4f8587268FB89fda4d621a8793;
        address performanceFeeRecipient = 0xb8FC49402dF3ee4f8587268FB89fda4d621a8793;
        address keeper = 0xBF664De63168720b57f1c93581512E9580E3E6f8;
        address sms = 0xc1ab5a9593E6e1662A9a44F84Df4F31Fc8A76B52;
        address claimer = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;
        address swapper = 0xb20956D156B5cFf367D062AC44E72e24d7716004;

        address morphoUsdc = 0xdd0f28e19C1780eb6396170735D45153D261490d;
        address usdcVault = 0x3Ed6aa32c930253fc990dE58fF882B9186cd0072;

        MorphoCompounderFactory factory = new MorphoCompounderFactory(
            management,
            performanceFeeRecipient,
            keeper,
            sms,
            claimer,
            swapper
        );

        console.log("Factory deployed at", address(factory));

        address usdcCompounder = factory.newMorphoCompounder(
            morphoUsdc,
            usdcVault
        );
        console.log("Morpho USDC Compounder deployed at", usdcCompounder);

        vm.stopBroadcast();
    }
}
