// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title SimpleUpgradeableProxy
 * @author emo.eth
 * @notice A simple UUPSUpgradeable proxy that implements OwnableUpgradeable
 */
contract SimpleUpgradeableProxy is OwnableUpgradeable, UUPSUpgradeable {
    function initialize(address _owner) public initializer {
        __Ownable_init(_owner);
    }

    /**
     * @notice Only owner can authorize the upgrade
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
