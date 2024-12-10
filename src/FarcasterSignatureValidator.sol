// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ECDSA} from "solady/utils/ECDSA.sol";
import {ERC1271Upgradeable} from "./lib/ERC1271Upgradeable.sol";
import {Initializable} from "openzeppelin-contracts/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "openzeppelin-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts/proxy/utils/UUPSUpgradeable.sol";
import {IERC1271} from "openzeppelin-contracts/interfaces/IERC1271.sol";

/**
 * @title SignatureValidator2
 * @notice Contract for validating Farcaster verification signatures
 * @dev Implements ERC1271 signature validation with Farcaster's EIP-712 domain
 * @dev Uses network 10 (Optimism) and FID 883713
 */
contract FarcasterSignatureValidator is
    Ownable2StepUpgradeable,
    ERC1271Upgradeable,
    UUPSUpgradeable
{
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice TypeHash for the VerificationClaim struct used in EIP-712 domain
     */
    bytes32 public constant VERIFICATION_CLAIM_TYPEHASH =
        keccak256("VerificationClaim(uint256 fid,address address,bytes32 blockHash,uint8 network)");

    /**
     * @notice Salt used in the EIP-712 domain separator
     */
    bytes32 public constant FARCASTER_SALT =
        0xf2d857f4a3edcb9b78b4d503bfe733db1e3f6cdc2b7971ee739626c97e86a558;

    /**
     * @notice Farcaster ID for this validator
     */
    uint256 public constant FID = 883713;

    /**
     * @notice Network MAINNET
     */
    uint8 public constant NETWORK = 1;

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Bundle containing verification data and signature
     * @param blockNumber The block number to use
     * @param blockHash The block hash to verify
     * @param signature The ECDSA signature of the EIP712 digest
     */
    struct VerificationBundle {
        uint256 blockNumber;
        bytes32 blockHash;
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
     * @param _signature The encoded VerificationClaimBundle
     * @return bytes4 The function selector if valid, or reverts if invalid
     */
    function isValidSignature(bytes32 _hash, bytes calldata _signature)
        public
        view
        override
        returns (bytes4)
    {
        VerificationBundle memory bundle = abi.decode(_signature, (VerificationBundle));

        _validateBlockHash(bundle);

        bytes32 digest = _calculateDigest(bundle);

        if (_hash != digest) {
            revert DigestMismatch();
        }

        address recoveredSigner = ECDSA.recover(digest, bundle.signature);
        if (recoveredSigner != getSigner()) {
            revert InvalidSigner();
        }

        return IERC1271.isValidSignature.selector;
    }

    /**
     * @notice Validates block hash for externally provided bundles
     * @param bundle The verification bundle to validate
     */
    function _validateBlockHash(VerificationBundle memory bundle) internal view {
        if (bundle.blockHash != blockhash(bundle.blockNumber)) {
            revert InvalidBlockHash();
        }
        if (bundle.blockNumber > block.number) {
            revert BlockFromFuture();
        }
    }

    /**
     * @notice Calculates the EIP-712 digest for a verification bundle
     * @param bundle The verification bundle to calculate digest for
     * @return The calculated digest
     */
    function _calculateDigest(VerificationBundle memory bundle) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                _domainSeparator(),
                keccak256(
                    abi.encode(
                        VERIFICATION_CLAIM_TYPEHASH, FID, address(this), bundle.blockHash, NETWORK
                    )
                )
            )
        );
    }

    /**
     * @notice Gets the current digest using the previous block's hash
     * @return The calculated digest for the current block
     */
    function getCurrentDigest() external view returns (bytes32) {
        uint256 blockNumber = block.number - 1;

        if (blockNumber > block.number) {
            revert BlockFromFuture();
        }

        bytes32 blockHash = blockhash(blockNumber);
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                _domainSeparator(),
                keccak256(
                    abi.encode(VERIFICATION_CLAIM_TYPEHASH, FID, address(this), blockHash, NETWORK)
                )
            )
        );
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
        name = "Farcaster Verify Ethereum Address";
        version = "2.0.0";
    }

    /**
     * @notice Returns whether the domain name and version may change
     * @return True if the domain name and version may change
     */
    function _domainNameAndVersionMayChange() internal pure override returns (bool) {
        return true;
    }

    /**
     * @notice Calculates the EIP-712 domain separator
     * @return The domain separator hash
     */
    function _domainSeparator() internal view virtual override returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,bytes32 salt)"),
                keccak256("Farcaster Verify Ethereum Address"),
                keccak256("2.0.0"),
                block.chainid,
                bytes32(0xf2d857f4a3edcb9b78b4d503bfe733db1e3f6cdc2b7971ee739626c97e86a558)
            )
        );
    }
}
