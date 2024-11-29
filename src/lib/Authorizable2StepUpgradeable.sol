// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (access/Authorizable2Step.sol)

pragma solidity ^0.8.20;

import {AuthorizableUpgradeable} from "./AuthorizableUpgradeable.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";

/**
 * @dev Contract module which provides access control mechanism, where
 * there is an account (an authorized) that can be granted exclusive access to
 * specific functions.
 *
 * This extension of the {Authorizable} contract includes a two-step mechanism to transfer
 * authorization, where the new authorized must call {acceptAuthorization} in order to replace the
 * old one. This can help prevent common mistakes, such as transfers of authorization to
 * incorrect accounts, or to contracts that are unable to interact with the
 * permission system.
 *
 * The initial authorized is specified at deployment time in the constructor for `Authorizable`. This
 * can later be changed with {transferAuthorization} and {acceptAuthorization}.
 *
 * This module is used through inheritance. It will make available all functions
 * from parent (Authorizable).
 */
abstract contract Authorizable2StepUpgradeable is Initializable, AuthorizableUpgradeable {
    /// @custom:storage-location erc7201:openzeppelin.storage.Authorizable2Step
    struct Authorizable2StepStorage {
        address _pendingAuthorized;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Authorizable2Step")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant Authorizable2StepStorageLocation =
        0x923c2052f54dbd4cb25ef11be761ebcf0a90469cd5f1dc8402b8492e9e045600;

    function _getAuthorizable2StepStorage() private pure returns (Authorizable2StepStorage storage $) {
        assembly {
            $.slot := Authorizable2StepStorageLocation
        }
    }

    event AuthorizationTransferStarted(address indexed previousAuthorized, address indexed newAuthorized);

    function __Authorizable2Step_init() internal onlyInitializing {}

    function __Authorizable2Step_init_unchained() internal onlyInitializing {}
    /**
     * @dev Returns the address of the pending authorized.
     */

    function pendingAuthorized() public view virtual returns (address) {
        Authorizable2StepStorage storage $ = _getAuthorizable2StepStorage();
        return $._pendingAuthorized;
    }

    /**
     * @dev Starts the authorization transfer of the contract to a new account. Replaces the pending transfer if there is one.
     * Can only be called by the current authorized.
     *
     * Setting `newAuthorized` to the zero address is allowed; this can be used to cancel an initiated authorization transfer.
     */
    function transferAuthorization(address newAuthorized) public virtual override onlyAuthorized {
        Authorizable2StepStorage storage $ = _getAuthorizable2StepStorage();
        $._pendingAuthorized = newAuthorized;
        emit AuthorizationTransferStarted(authorized(), newAuthorized);
    }

    /**
     * @dev Transfers authorization of the contract to a new account (`newAuthorized`) and deletes any pending authorized.
     * Internal function without access restriction.
     */
    function _transferAuthorization(address newAuthorized) internal virtual override {
        Authorizable2StepStorage storage $ = _getAuthorizable2StepStorage();
        delete $._pendingAuthorized;
        super._transferAuthorization(newAuthorized);
    }

    /**
     * @dev The new authorized accepts the authorization transfer.
     */
    function acceptAuthorization() public virtual {
        address sender = _msgSender();
        if (pendingAuthorized() != sender) {
            revert AuthorizableUnauthorizedAccount(sender);
        }
        _transferAuthorization(sender);
    }
}
