// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {DeterministicUpgradeableFactory} from "src/proxy/DeterministicUpgradeableFactory.sol";

contract Deploy is Script {
    function run() public {
        vm.createSelectFork(getChain("optimism").rpcUrl);
        vm.startBroadcast();
        address factory = deployFactory();
        vm.stopBroadcast();
        console2.log("Factory deployed at", factory);
        vm.createSelectFork(getChain("base").rpcUrl);
        vm.startBroadcast();
        factory = deployFactory();
        vm.stopBroadcast();
        console2.log("Factory deployed at", factory);
    }

    function deployFactory() public returns (address) {
        DeterministicUpgradeableFactory factory = new DeterministicUpgradeableFactory{salt: bytes32(0)}();
        return address(factory);
    }
}
