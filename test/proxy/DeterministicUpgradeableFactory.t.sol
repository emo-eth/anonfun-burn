// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {DeterministicUpgradeableFactory} from "src/proxy/DeterministicUpgradeableFactory.sol";
import {SimpleUpgradeableProxy} from "src/proxy/SimpleUpgradeableProxy.sol";
import {UUPSUpgradeable} from "openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {HelloWorld} from "test/helpers/HelloWorld.sol";

contract DeterministicUpgradeableFactoryTest is Test {
    DeterministicUpgradeableFactory factory;
    HelloWorld implementation;

    function setUp() public {
        factory = new DeterministicUpgradeableFactory();
        implementation = new HelloWorld();
    }

    function test_deployDeterministicUUPS() public {
        address proxy = factory.deployDeterministicUUPS(keccak256("salt"), address(this));
        SimpleUpgradeableProxy proxyContract = SimpleUpgradeableProxy(payable(proxy));
        assertEq(proxyContract.owner(), address(this));
    }

    function test_deployDeterministicUUPSAndUpgradeTo() public {
        address proxy = factory.deployDeterministicUUPS(keccak256("salt"), address(this));
        SimpleUpgradeableProxy(payable(proxy)).upgradeToAndCall(
            address(implementation),
            abi.encodeWithSelector(HelloWorld.initialize.selector, "Hello World")
        );
        HelloWorld proxyContract = HelloWorld(payable(proxy));
        assertEq(proxyContract.message(), "Hello World");
    }

    function test_predictDeterministicUUPSAddress() public {
        address proxy = factory.predictDeterministicUUPSAddress(keccak256("salt"), address(this));
        assertEq(proxy, factory.deployDeterministicUUPS(keccak256("salt"), address(this)));
    }

    function test_sameSaltDifferentOwnerDifferentDeployAddress() public {
        address proxy1 = factory.deployDeterministicUUPS(keccak256("salt"), address(this));
        address proxy2 =
            factory.deployDeterministicUUPS(keccak256("salt"), address(makeAddr("owner2")));
        assertNotEq(proxy1, proxy2);
    }
}
