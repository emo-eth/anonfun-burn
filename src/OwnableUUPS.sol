// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UUPSUpgradeable} from "openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";

contract OwnableUUPS is UUPSUpgradeable, OwnableUpgradeable {
    function initialize(address _owner) public initializer {
        __Ownable_init_unchained(_owner);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
