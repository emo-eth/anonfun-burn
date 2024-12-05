// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {DeterministicUpgradeableFactory} from "src/proxy/DeterministicUpgradeableFactory.sol";
import {SimpleUpgradeableProxy} from "src/proxy/SimpleUUPSUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract HelloWorldooooor is UUPSUpgradeable {
    string public message;

    function initialize(string memory _message) public {
        message = _message;
    }

    function _authorizeUpgrade(address newImplementation) internal override {
        // TODO: Implement authorization logic
    }
}

contract DeterministicUpgradeableFactoryTest is Test {
    DeterministicUpgradeableFactory factory;
    HelloWorldooooor implementation;

    function setUp() public {
        factory = new DeterministicUpgradeableFactory();
        implementation = new HelloWorldooooor();
    }

    function test_deployDeterministicUUPS() public {
        address proxy = factory.deployDeterministicUUPS(keccak256("salt"), address(this));
        SimpleUpgradeableProxy proxyContract = SimpleUpgradeableProxy(payable(proxy));
        assertEq(proxyContract.owner(), address(this));
    }

    function test_deployDeterministicUUPSAndUpgradeTo() public {
        address proxy = factory.deployDeterministicUUPSAndUpgradeTo(
            keccak256("salt"),
            address(this),
            address(implementation),
            abi.encodeWithSelector(HelloWorldooooor.initialize.selector, "Hello World")
        );
        HelloWorldooooor proxyContract = HelloWorldooooor(payable(proxy));
        assertEq(proxyContract.message(), "Hello World");
    }

    function test_predictDeterministicUUPSAddress() public {
        address proxy = factory.predictDeterministicUUPSAddress(keccak256("salt"), address(this));
        assertEq(proxy, factory.deployDeterministicUUPS(keccak256("salt"), address(this)));
    }
}
