// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (access/Authorizable.sol)

pragma solidity ^0.8.20;

import {ContextUpgradeable} from "openzeppelin-upgradeable/utils/ContextUpgradeable.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an authorized) that can be granted exclusive access to
 * specific functions.
 *
 * The initial authorized is set to the address provided by the deployer. This can
 * later be changed with {transferAuthorization}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyAuthorized`, which can be applied to your functions to restrict their use to
 * the authorized.
 */
abstract contract AuthorizableUpgradeable is Initializable, ContextUpgradeable {
    /// @custom:storage-location erc7201:openzeppelin.storage.Authorizable
    struct AuthorizableStorage {
        address _authorized;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Authorizable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant AuthorizableStorageLocation =
        0x6c54ebbbc1522a6425d9747665bfa4309ceb7affca5ce621db7f2224765dab00;

    function _getAuthorizableStorage() private pure returns (AuthorizableStorage storage $) {
        assembly {
            $.slot := AuthorizableStorageLocation
        }
    }

    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error AuthorizableUnauthorizedAccount(address account);

    /**
     * @dev The authorized is not a valid authorized account. (eg. `address(0)`)
     */
    error AuthorizableInvalidAuthorized(address authorized);

    event AuthorizationTransferred(address indexed previousAuthorized, address indexed newAuthorized);

    /**
     * @dev Initializes the contract setting the address provided by the deployer as the initial authorized.
     */
    function __Authorizable_init(address initialAuthorized) internal onlyInitializing {
        __Authorizable_init_unchained(initialAuthorized);
    }

    function __Authorizable_init_unchained(address initialAuthorized) internal onlyInitializing {
        if (initialAuthorized == address(0)) {
            revert AuthorizableInvalidAuthorized(address(0));
        }
        _transferAuthorization(initialAuthorized);
    }

    /**
     * @dev Throws if called by any account other than the authorized.
     */
    modifier onlyAuthorized() {
        _checkAuthorized();
        _;
    }

    /**
     * @dev Returns the address of the current authorized.
     */
    function authorized() public view virtual returns (address) {
        AuthorizableStorage storage $ = _getAuthorizableStorage();
        return $._authorized;
    }

    /**
     * @dev Throws if the sender is not the authorized.
     */
    function _checkAuthorized() internal view virtual {
        if (authorized() != _msgSender()) {
            revert AuthorizableUnauthorizedAccount(_msgSender());
        }
    }

    /**
     * @dev Leaves the contract without authorized. It will not be possible to call
     * `onlyAuthorized` functions. Can only be called by the current authorized.
     *
     * NOTE: Renouncing authorization will leave the contract without an authorized,
     * thereby disabling any functionality that is only available to the authorized.
     */
    function renounceAuthorization() public virtual onlyAuthorized {
        _transferAuthorization(address(0));
    }

    /**
     * @dev Transfers authorization of the contract to a new account (`newAuthorized`).
     * Can only be called by the current authorized.
     */
    function transferAuthorization(address newAuthorized) public virtual onlyAuthorized {
        if (newAuthorized == address(0)) {
            revert AuthorizableInvalidAuthorized(address(0));
        }
        _transferAuthorization(newAuthorized);
    }

    /**
     * @dev Transfers authorization of the contract to a new account (`newAuthorized`).
     * Internal function without access restriction.
     */
    function _transferAuthorization(address newAuthorized) internal virtual {
        AuthorizableStorage storage $ = _getAuthorizableStorage();
        address oldAuthorized = $._authorized;
        $._authorized = newAuthorized;
        emit AuthorizationTransferred(oldAuthorized, newAuthorized);
    }
}
