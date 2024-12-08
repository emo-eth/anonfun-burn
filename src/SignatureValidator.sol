// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Initializable} from "openzeppelin-contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {ERC1271Upgradeable} from "./lib/ERC1271Upgradeable.sol";

contract SignatureValidator is OwnableUpgradeable, ERC1271Upgradeable, UUPSUpgradeable {
    function initialize(address _owner, address _signer) public initializer {
        __Ownable_init(_owner);
        __ERC1271_init_unchained(_signer);
    }

    function reinitialize(uint64 version, address _owner, address _signer) public reinitializer(version) {
        __Ownable_init(_owner);
        __ERC1271_init_unchained(_signer);
    }

    function setSigner(address signer) public override onlyOwner {
        _setSigner(signer);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
        name = "AnonFun";
        version = "1";
    }
}
