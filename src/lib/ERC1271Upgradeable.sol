// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC1271} from "solady/accounts/ERC1271.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";

abstract contract ERC1271Upgradeable is ERC1271, Initializable {
    struct ERC1271UpgradeableStorage {
        /// @notice The address of the signer
        address signer;
    }

    // keccak256(abi.encode(uint256(keccak256("anonfun.storage.ERC1271Upgradeable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _STORAGE_SLOT = 0xf695917c9b3214e876a160829e44ba34b727c9c364f152d05bc1066f53bcf200;

    function setSigner(address _signer) public virtual;

    function getSigner() public view returns (address) {
        return getStorage().signer;
    }

    function _setSigner(address _signer) internal {
        getStorage().signer = _signer;
    }

    function getStorage() private pure returns (ERC1271UpgradeableStorage storage $) {
        assembly {
            $.slot := _STORAGE_SLOT
        }
    }

    function __ERC1271_init_unchained(address _signer) internal onlyInitializing {
        getStorage().signer = _signer;
    }

    function _erc1271Signer() internal view override returns (address) {
        return getStorage().signer;
    }
}
