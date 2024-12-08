// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {SimpleUpgradeableProxy} from "src/proxy/SimpleUpgradeableProxy.sol";
import {HelloWorld} from "test/helpers/HelloWorld.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";

contract SimpleUpgradeableProxyTest is Test {
    address upgradeTarget;
    address proxy;
    address implementation;

    function setUp() public {
        upgradeTarget = address(new HelloWorld());
        implementation = address(new SimpleUpgradeableProxy());
        proxy = address(
            new ERC1967Proxy(
                address(implementation),
                abi.encodeWithSelector(SimpleUpgradeableProxy.initialize.selector, address(this))
            )
        );
    }

    function testUpgradeTo() public {
        SimpleUpgradeableProxy(payable(proxy)).upgradeToAndCall(
            upgradeTarget, abi.encodeWithSelector(HelloWorld.initialize.selector, "Hello World")
        );
        HelloWorld proxyContract = HelloWorld(payable(address(proxy)));
        assertEq(proxyContract.message(), "Hello World");
    }

    function testUpgradeTo_OnlyOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, makeAddr("other"))
        );
        vm.prank(makeAddr("other"));
        SimpleUpgradeableProxy(payable(proxy)).upgradeToAndCall(
            upgradeTarget, abi.encodeWithSelector(HelloWorld.initialize.selector, "Hello World")
        );
    }
}
