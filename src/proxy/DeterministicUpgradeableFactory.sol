// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UUPSUpgradeable} from "openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SimpleUpgradeableProxy} from "./SimpleUpgradeableProxy.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeterministicUpgradeableFactory
 * @author emo.eth
 * @notice This factory is used to deploy Openzeppelin ERC1967 UUPSUpgradeable proxies to deterministic addresses
 *         on any chain using the CREATE2 opcode. The initial proxy implementation is a simple UUPSUpgradeable proxy
 *         that implements OwnableUpgradeable, which the factory initializes with a provided owner.
 */
contract DeterministicUpgradeableFactory {
    SimpleUpgradeableProxy immutable implementation;

    constructor() {
        implementation = new SimpleUpgradeableProxy();
    }

    /**
     * @notice Deploy a deterministic ERC1967 proxy with an initial Ownable UUPSUpgradeable implementation, initialized
     *         with the provided owner.
     *
     * @param salt The salt to use for the deterministic deployment
     * @param owner The owner to initialize the proxy with
     * @return The address of the deployed proxy
     */
    function deployDeterministicUUPS(bytes32 salt, address owner) public returns (address) {
        // Since owner is part of the initialization code, the same salt with different owners will
        // result in different addresses
        address proxy = address(
            new ERC1967Proxy{salt: salt}(
                address(implementation), abi.encodeWithSelector(implementation.initialize.selector, owner)
            )
        );
        return proxy;
    }

    /**
     * @notice Predict the address of a deterministic ERC1967 proxy with an initial Ownable UUPSUpgradeable implementation
     * @param salt The salt to use for the deterministic deployment
     * @param owner The owner to initialize the proxy with
     * @return The address of the deployed proxy
     */
    function predictDeterministicUUPSAddress(bytes32 salt, address owner) public view returns (address) {
        bytes32 initCodeHash = getInitCodeHashForOwner(owner);
        // use initcodehash and salt to derive create2 address
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash)))));
    }

    /**
     * @notice Get the initcode hash for a given owner, for use with tools like create2crunch
     * @param owner The owner to initialize the proxy with
     * @return The init code hash
     */
    function getInitCodeHashForOwner(address owner) public view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                type(ERC1967Proxy).creationCode,
                abi.encode(address(implementation), abi.encodeWithSelector(implementation.initialize.selector, owner))
            )
        );
    }
}
