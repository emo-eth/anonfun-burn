// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "openzeppelin-upgradeable/access/Ownable2StepUpgradeable.sol";
import {AuthorizableUpgradeable} from "./lib/AuthorizableUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract AnonBurn is Initializable, Ownable2StepUpgradeable, AuthorizableUpgradeable, UUPSUpgradeable {
    struct AnonBurnStorage {
        uint32 frequency;
        address token;
    }

    // keccak256(abi.encode(uint256(keccak256("anonfun.storage.AnonBurn")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant Authorizable2StepStorageLocation =
        0x2d8a54f6dfd94bf9126af7a97ae3045b23d9b0f2c8e96fa9e77db7fef1e27b00;

    function getAnonBurnStorage() private pure returns (AnonBurnStorage storage $) {
        assembly {
            $.slot := Authorizable2StepStorageLocation
        }
    }

    function initialize(uint32 frequency, address token, address _owner, address _authorized) public initializer {
        __Ownable_init(_owner);
        __Authorizable_init(_authorized);
        __AnonBurn_init_unchained(frequency, token);
    }

    function __AnonBurn_init_unchained(uint32 frequency, address token) internal onlyInitializing {
        AnonBurnStorage storage $ = getAnonBurnStorage();
        $.frequency = frequency;
        $.token = token;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
