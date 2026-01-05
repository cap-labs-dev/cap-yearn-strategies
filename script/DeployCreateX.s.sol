// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

contract DeployCreateX is Script {
    function run() external {
        vm.startBroadcast();

        // Get the implementation contract address that will be used with the proxy
        // Replace this with your actual implementation contract address
        address implementation = address(0x0000000000000000000000000000000000000000); // Example implementation address

        address oracle = address(0xcD7f45566bc0E7303fB92A93969BB4D3f6e662bb);

        // Generate the init code (bytecode) for ERC1967Proxy
        bytes memory initCode = type(ERC1967Proxy).creationCode;

        // Generate the initialization data for the proxy
        // First, encode the initialize function call with all parameters
        bytes memory initializeCalldata =
            abi.encodeWithSignature("initialize(address)", oracle);

        // This is the constructor arguments for ERC1967Proxy: implementation address and initialization call data
        bytes memory constructorArgs = abi.encode(implementation, initializeCalldata);

        // Combine the init code with the encoded constructor arguments
        bytes memory proxyBytecode = abi.encodePacked(initCode, constructorArgs);

        console.logBytes(proxyBytecode);

        vm.stopBroadcast();
    }
}
