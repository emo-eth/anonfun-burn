// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EIP712} from "solady/utils/EIP712.sol";
import {IERC1271} from "openzeppelin-contracts/interfaces/IERC1271.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title ERC1271Upgradeable
 * @notice Abstract contract implementing ERC1271 signature validation with upgradeability
 * @dev Inherits from IERC1271 and EIP712 for signature validation
 */
abstract contract ERC1271Upgradeable is IERC1271, EIP712, Initializable {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event SignerChanged(address oldSigner, address newSigner);

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Storage struct for ERC1271Upgradeable
     * @dev Stored at a fixed slot to maintain upgradeability
     */
    struct ERC1271UpgradeableStorage {
        address signer; // Address authorized to sign messages
    }

    // Storage slot computed as: keccak256(abi.encode(uint256(keccak256("anonfun.storage.ERC1271Upgradeable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _STORAGE_SLOT =
        0xa4875c9777b077c6a44cbe5181097308a8f445cd01510a5b32ede0d9376ea000;

    /*//////////////////////////////////////////////////////////////
                            ABSTRACT METHODS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Validates a signature according to ERC1271
     * @param hash The hash that was signed
     * @param signature The signature to validate
     * @return bytes4 The function selector if valid, or 0 if invalid
     */
    function isValidSignature(bytes32 hash, bytes calldata signature)
        public
        view
        virtual
        returns (bytes4);

    /**
     * @notice Sets a new signer address
     * @param _signer The new signer address
     */
    function setSigner(address _signer) public virtual;

    /*//////////////////////////////////////////////////////////////
                            PUBLIC INTERFACE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the domain separator used for EIP712 signing
     * @return bytes32 The domain separator
     */
    function domainSeparator() public view returns (bytes32) {
        return _domainSeparator();
    }

    /**
     * @notice Gets the current signer address
     * @return address The current signer
     */
    function getSigner() public view returns (address) {
        return getStorage().signer;
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL METHODS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Internal function to update the signer
     * @param _signer The new signer address
     */
    function _setSigner(address _signer) internal {
        address oldSigner = getStorage().signer;
        getStorage().signer = _signer;
        emit SignerChanged(oldSigner, _signer);
    }

    /*//////////////////////////////////////////////////////////////
                        INITIALIZATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the contract with a signer
     * @param _signer The initial signer address
     */
    function __ERC1271_init_unchained(address _signer) internal onlyInitializing {
        _setSigner(_signer);
    }

    /*//////////////////////////////////////////////////////////////
                            STORAGE ACCESS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Gets the storage struct
     * @return $ The storage struct
     */
    function getStorage() private pure returns (ERC1271UpgradeableStorage storage $) {
        assembly {
            $.slot := _STORAGE_SLOT
        }
    }
}
