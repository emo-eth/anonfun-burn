// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UUPSUpgradeable} from "openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SimpleUpgradeableProxy} from "./SimpleUUPSUpgradeable.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeterministicUpgradeableFactory {
    SimpleUpgradeableProxy immutable implementation;

    constructor() {
        implementation = new SimpleUpgradeableProxy();
    }

    function deployDeterministicUUPS(bytes32 salt, address owner) public returns (address) {
        address proxy = address(
            new ERC1967Proxy{salt: salt}(
                address(implementation), abi.encodeWithSelector(implementation.initialize.selector, owner)
            )
        );
        return proxy;
    }

    function deployDeterministicUUPSAndUpgradeTo(
        bytes32 salt,
        address owner,
        address newImplementation,
        bytes calldata initData
    ) public returns (address) {
        address proxy = address(
            new ERC1967Proxy{salt: salt}(
                address(implementation), abi.encodeWithSelector(implementation.initialize.selector, owner)
            )
        );
        SimpleUpgradeableProxy(payable(proxy)).upgradeToAndCall(newImplementation, initData);
        return proxy;
    }

    function predictDeterministicUUPSAddress(bytes32 salt, address owner) public view returns (address) {
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(ERC1967Proxy).creationCode,
                abi.encode(address(implementation), abi.encodeWithSelector(implementation.initialize.selector, owner))
            )
        );
        // use initcodehash and salt to derive create2 address
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash)))));
    }
}
