// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable2StepUpgradeable} from "openzeppelin-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title SimpleUpgradeableProxy
 * @author emo.eth
 * @notice A simple UUPSUpgradeable proxy that implements Ownable2StepUpgradeable
 */
contract SimpleUpgradeableProxy is Ownable2StepUpgradeable, UUPSUpgradeable {
    function initialize(address _owner) public initializer {
        __Ownable_init(_owner);
    }

    /**
     * @notice Only owner can authorize the upgrade
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
