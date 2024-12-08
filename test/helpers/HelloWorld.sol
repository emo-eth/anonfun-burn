// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UUPSUpgradeable} from "openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract HelloWorld is UUPSUpgradeable {
    string public message;

    function initialize(string memory _message) public reinitializer(2) {
        message = _message;
    }

    function _authorizeUpgrade(address newImplementation) internal override {}
}
