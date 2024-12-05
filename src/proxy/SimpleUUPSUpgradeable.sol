// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {TransientSlot} from "openzeppelin-contracts/utils/TransientSlot.sol";

contract SimpleUpgradeableProxy is OwnableUpgradeable, UUPSUpgradeable {
    error SimpleUpgradeableProxyOnlyOwnerOrDeployer();

    // keccak256(abi.encode(uint256(keccak256("storage.simpleuupsupgradeable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 constant SIMPLE_UUPS_UPGRADEABLE_STORAGE_SLOT =
        0x19f8390be00a68fa9efa176a39eed4f34308c71df1c932124f1c1b641a5fb500;

    /**
     * @notice Modifier to check if the caller is the deployer or the owner. Since deployer is transient, the
     * deployer may only upgrade during the same tx as the initialization.
     */
    modifier onlyOwnerOrDeployer() {
        if (_msgSender() != TransientSlot.tload(_getTransientDeployerSlot()) && _msgSender() != owner()) {
            revert SimpleUpgradeableProxyOnlyOwnerOrDeployer();
        }
        _;
    }

    function _getTransientDeployerSlot() internal pure returns (TransientSlot.AddressSlot) {
        return TransientSlot.asAddress(SIMPLE_UUPS_UPGRADEABLE_STORAGE_SLOT);
    }

    function initialize(address _owner) public initializer {
        __Ownable_init(_owner);
        TransientSlot.tstore(_getTransientDeployerSlot(), _msgSender());
    }

    /**
     * @notice Only owner or deployer can authorize the upgrade; deployer is transient, so it can only upgrade during the
     * same tx as the initialization.
     */
    function _authorizeUpgrade(address) internal override onlyOwnerOrDeployer {}
}
