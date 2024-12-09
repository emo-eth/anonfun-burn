// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ECDSA} from "solady/utils/ECDSA.sol";
import {ERC1271Upgradeable} from "./lib/ERC1271Upgradeable.sol";
import {Initializable} from "openzeppelin-contracts/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "openzeppelin-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts/proxy/utils/UUPSUpgradeable.sol";
import {IERC1271} from "openzeppelin-contracts/interfaces/IERC1271.sol";

/**
 * @title SignatureValidator
 * @notice Contract for validating signatures against recent block hashes
 * @dev Implements ERC1271 signature validation with upgradeable proxy support
 */
contract SignatureValidator is Ownable2StepUpgradeable, ERC1271Upgradeable, UUPSUpgradeable {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    bytes32 public constant RECENT_BLOCK_HASH_TYPEHASH =
        keccak256("RecentBlockHash(uint256 number,bytes32 hash)");

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Bundle containing block data and signature for validation
     * @param number The block number
     * @param hash The block hash
     * @param signature The ECDSA signature of the EIP712 digest
     */
    struct RecentBlockHashBundle {
        uint256 number;
        bytes32 hash;
        bytes signature;
    }

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Thrown when provided block hash does not match chain state
     */
    error InvalidBlockHash();

    /**
     * @notice Thrown when block number is more than 256 blocks old
     */
    error BlockTooOld();

    /**
     * @notice Thrown when block number is greater than current block
     */
    error BlockFromFuture();

    /**
     * @notice Thrown when provided hash does not match calculated digest
     */
    error DigestMismatch();

    /**
     * @notice Thrown when recovered signer does not match stored signer
     */
    error InvalidSigner();

    /*//////////////////////////////////////////////////////////////
                             CORE LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Validates a signature according to ERC1271
     * @param _hash The hash that was signed
     * @param _signature The encoded RecentBlockHashBundle
     * @return bytes4 The function selector if valid, or reverts if invalid
     */
    function isValidSignature(bytes32 _hash, bytes calldata _signature)
        public
        view
        override
        returns (bytes4)
    {
        // Decode the signature bundle
        RecentBlockHashBundle memory bundle = abi.decode(_signature, (RecentBlockHashBundle));

        // Validate block hash and number
        _validateBlockHash(bundle);

        // Calculate EIP-712 digest
        bytes32 digest = _calculateDigest(bundle);

        // Verify hash matches digest
        if (_hash != digest) {
            revert DigestMismatch();
        }

        // Recover and validate signer
        address recoveredSigner = ECDSA.recover(digest, bundle.signature);
        if (recoveredSigner != getSigner()) {
            revert InvalidSigner();
        }

        return IERC1271.isValidSignature.selector;
    }

    /*//////////////////////////////////////////////////////////////
                            OWNER SETTINGS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets a new signer address
     * @param signer The new signer address
     */
    function setSigner(address signer) public override onlyOwner {
        address oldSigner = getSigner();
        _setSigner(signer);
        emit SignerChanged(oldSigner, signer);
    }

    /*//////////////////////////////////////////////////////////////
                            PROXY ADMIN
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the contract
     * @param _owner The owner address
     * @param _signer The initial signer address
     */
    function initialize(address _owner, address _signer) public initializer {
        __Ownable_init(_owner);
        __ERC1271_init_unchained(_signer);
    }

    /**
     * @notice Reinitializes the contract with a new version
     * @param version The new version number
     * @param _owner The owner address
     * @param _signer The signer address
     */
    function reinitialize(uint64 version, address _owner, address _signer)
        public
        reinitializer(version)
    {
        __Ownable_init(_owner);
        __ERC1271_init_unchained(_signer);
    }

    /**
     * @notice Authorizes an upgrade
     * @param newImplementation The new implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /*//////////////////////////////////////////////////////////////
                            EIP-712 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the domain name and version
     * @return name The domain name
     * @return version The domain version
     */
    function _domainNameAndVersion()
        internal
        pure
        override
        returns (string memory name, string memory version)
    {
        name = "BlockHashValidator";
        version = "1";
    }

    /**
     * @notice Returns whether the domain name and version may change
     * @return True if the domain name and version may change
     */
    function _domainNameAndVersionMayChange() internal pure override returns (bool) {
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Validates block hash and number constraints
     * @param bundle The block hash bundle to validate
     */
    function _validateBlockHash(RecentBlockHashBundle memory bundle) internal view {
        if (bundle.hash != blockhash(bundle.number)) {
            revert InvalidBlockHash();
        }
        if (bundle.number > block.number) {
            revert BlockFromFuture();
        }
        if (block.number - bundle.number > 256) {
            revert BlockTooOld();
        }
    }

    /**
     * @notice Calculates EIP-712 digest from bundle
     * @param bundle The block hash bundle
     * @return bytes32 The calculated digest
     */
    function _calculateDigest(RecentBlockHashBundle memory bundle)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                _domainSeparator(),
                keccak256(abi.encode(RECENT_BLOCK_HASH_TYPEHASH, bundle.number, bundle.hash))
            )
        );
    }
}
