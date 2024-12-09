// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SimpleUpgradeableProxy} from "./SimpleUpgradeableProxy.sol";

/**
 * @title DeterministicUpgradeableFactory
 * @author emo.eth
 * @notice This factory deploys Openzeppelin ERC1967 UUPSUpgradeable proxies to deterministic
 * addresses on any chain using CREATE2. The initial proxy implementation is a simple
 * UUPSUpgradeable proxy that implements Ownable2StepUpgradeable, which the factory initializes with
 * a provided owner.
 */
contract DeterministicUpgradeableFactory {
    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    SimpleUpgradeableProxy internal immutable _implementation;

    constructor() {
        _implementation = new SimpleUpgradeableProxy();
    }

    /*//////////////////////////////////////////////////////////////
                            CORE LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploy a deterministic ERC1967 proxy with an initial Ownable UUPSUpgradeable
     * implementation, initialized with the provided owner
     * @param salt The salt to use for the deterministic deployment
     * @param owner The owner to initialize the proxy with
     * @return The address of the deployed proxy
     */
    function deployDeterministicUUPS(bytes32 salt, address owner) public returns (address) {
        // Since owner is part of the initialization code, the same salt with different owners will
        // result in different addresses
        address proxy = address(
            new ERC1967Proxy{salt: salt}(
                address(_implementation),
                abi.encodeWithSelector(_implementation.initialize.selector, owner)
            )
        );
        return proxy;
    }

    /**
     * @notice Predict the address of a deterministic ERC1967 proxy with an initial Ownable
     * UUPSUpgradeable implementation
     * @param salt The salt to use for the deterministic deployment
     * @param owner The owner to initialize the proxy with
     * @return The address of the deployed proxy
     */
    function predictDeterministicUUPSAddress(bytes32 salt, address owner)
        public
        view
        returns (address)
    {
        bytes32 initCodeHash = getInitCodeHashForOwner(owner);

        // Use initcodehash and salt to derive CREATE2 address
        // CREATE2 address = keccak256(0xff ++ deployerAddress ++ salt ++ initCodeHash)[12:]
        return address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash))
                )
            )
        );
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
                abi.encode(
                    address(_implementation),
                    abi.encodeWithSelector(_implementation.initialize.selector, owner)
                )
            )
        );
    }
}
