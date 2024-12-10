// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {FarcasterSignatureValidator} from "src/FarcasterSignatureValidator.sol";

import {
    DeterministicUpgradeableFactory,
    SimpleUpgradeableProxy
} from "src/proxy/DeterministicUpgradeableFactory.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {IERC1271} from "openzeppelin-contracts/interfaces/IERC1271.sol";
import {ECDSA} from "openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import {UniversalSigValidator} from "./helpers/UniversalSigValidator.sol";
import {stdStorage, StdStorage} from "forge-std/StdStorage.sol";

contract FarcasterSignatureValidatorTest is Test {
    using stdStorage for StdStorage;

    uint256 constant FORK_BLOCK_NUMBER = 21360869;

    DeterministicUpgradeableFactory factory;

    FarcasterSignatureValidator validator;
    FarcasterSignatureValidator implementation;

    uint64 version = 10;

    bool initialized;

    Account signer;

    function setUp() public {
        // Setup mainnet fork
        _initOnFork(getChain("mainnet").rpcUrl, FORK_BLOCK_NUMBER);
    }

    function _initOnFork(string memory rpcUrl, uint256 blockNumber) internal {
        vm.createSelectFork(rpcUrl, blockNumber);
        // Rest of the setup
        factory = new DeterministicUpgradeableFactory();
        implementation = new FarcasterSignatureValidator();
        signer = makeAccount("signer");

        SimpleUpgradeableProxy proxy =
            SimpleUpgradeableProxy(factory.deployDeterministicUUPS(0, address(this)));
        address owner = proxy.owner();

        address _dest = vm.envAddress("VERIFYING_CONTRACT");
        vm.etch(_dest, address(proxy).code);
        // force write owner to the dest
        if (!initialized) {
            vm.store(
                address(_dest),
                bytes32(uint256(0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc)),
                bytes32(uint256(uint160(address(factory.implementation()))))
            );
            proxy = SimpleUpgradeableProxy(_dest);
            proxy.initialize(owner);
            initialized = true;
        }
        stdstore.target(address(_dest)).sig("owner()").checked_write(owner);
        proxy = SimpleUpgradeableProxy(_dest);
        validator = FarcasterSignatureValidator(address(proxy));

        proxy.upgradeToAndCall(
            address(implementation),
            abi.encodeCall(implementation.reinitialize, (version++, address(this), signer.addr))
        );
    }

    function testGetSigner() public view {
        assertEq(validator.getSigner(), signer.addr);
    }

    function testSetSigner() public {
        validator.setSigner(address(0));
        assertEq(validator.getSigner(), address(0));
    }

    function testSetSigner_OnlyOwner() public {
        address user = makeAddr("user");
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        validator.setSigner(address(0));
    }

    function testIsValidSignature() public view {
        // Use real block data from mainnet
        uint256 blockNum = FORK_BLOCK_NUMBER - 1; // Previous block
        bytes32 blockHash = blockhash(blockNum);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                validator.domainSeparator(),
                keccak256(
                    abi.encode(
                        validator.VERIFICATION_CLAIM_TYPEHASH(),
                        validator.FID(),
                        address(validator),
                        blockHash,
                        validator.NETWORK()
                    )
                )
            )
        );

        bytes memory signature = signDigest(signer.key, digest);

        FarcasterSignatureValidator.VerificationBundle memory bundle = FarcasterSignatureValidator
            .VerificationBundle({blockNumber: blockNum, blockHash: blockHash, signature: signature});

        bytes4 result = validator.isValidSignature(digest, abi.encode(bundle));
        assertEq(result, IERC1271.isValidSignature.selector);
    }

    function testIsValidSignature_InvalidBlockHash() public {
        uint256 blockNum = FORK_BLOCK_NUMBER - 1;
        bytes32 wrongHash = bytes32(uint256(1));

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                validator.domainSeparator(),
                keccak256(
                    abi.encode(
                        validator.VERIFICATION_CLAIM_TYPEHASH(),
                        validator.FID(),
                        address(validator),
                        wrongHash,
                        validator.NETWORK()
                    )
                )
            )
        );

        bytes memory signature = signDigest(signer.key, digest);

        FarcasterSignatureValidator.VerificationBundle memory bundle = FarcasterSignatureValidator
            .VerificationBundle({blockNumber: blockNum, blockHash: wrongHash, signature: signature});

        vm.expectRevert(FarcasterSignatureValidator.InvalidBlockHash.selector);
        validator.isValidSignature(digest, abi.encode(bundle));
    }

    function testIsValidSignature_BlockFromFuture() public {
        uint256 futureBlockNum = FORK_BLOCK_NUMBER + 1;
        bytes32 blockHash = bytes32(0);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                validator.domainSeparator(),
                keccak256(
                    abi.encode(
                        validator.VERIFICATION_CLAIM_TYPEHASH(),
                        validator.FID(),
                        address(validator),
                        blockHash,
                        validator.NETWORK()
                    )
                )
            )
        );

        bytes memory signature = signDigest(signer.key, digest);

        FarcasterSignatureValidator.VerificationBundle memory bundle = FarcasterSignatureValidator
            .VerificationBundle({
            blockNumber: futureBlockNum,
            blockHash: blockHash,
            signature: signature
        });

        vm.expectRevert(FarcasterSignatureValidator.BlockFromFuture.selector);
        validator.isValidSignature(digest, abi.encode(bundle));
    }

    function testIsValidSignature_DigestMismatch() public {
        uint256 blockNum = FORK_BLOCK_NUMBER - 1;
        bytes32 blockHash = blockhash(blockNum);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                validator.domainSeparator(),
                keccak256(
                    abi.encode(
                        validator.VERIFICATION_CLAIM_TYPEHASH(),
                        validator.FID(),
                        address(validator),
                        blockHash,
                        validator.NETWORK()
                    )
                )
            )
        );

        bytes memory signature = signDigest(signer.key, digest);

        FarcasterSignatureValidator.VerificationBundle memory bundle = FarcasterSignatureValidator
            .VerificationBundle({blockNumber: blockNum, blockHash: blockHash, signature: signature});

        bytes32 wrongDigest = keccak256("wrong digest");

        vm.expectRevert(FarcasterSignatureValidator.DigestMismatch.selector);
        validator.isValidSignature(wrongDigest, abi.encode(bundle));
    }

    function testIsValidSignature_InvalidSigner() public {
        uint256 blockNum = FORK_BLOCK_NUMBER - 1;
        bytes32 blockHash = blockhash(blockNum);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                validator.domainSeparator(),
                keccak256(
                    abi.encode(
                        validator.VERIFICATION_CLAIM_TYPEHASH(),
                        validator.FID(),
                        address(validator),
                        blockHash,
                        validator.NETWORK()
                    )
                )
            )
        );

        Account memory wrongSigner = makeAccount("wrongSigner");
        bytes memory signature = signDigest(wrongSigner.key, digest);

        FarcasterSignatureValidator.VerificationBundle memory bundle = FarcasterSignatureValidator
            .VerificationBundle({blockNumber: blockNum, blockHash: blockHash, signature: signature});

        vm.expectRevert(FarcasterSignatureValidator.InvalidSigner.selector);
        validator.isValidSignature(digest, abi.encode(bundle));
    }

    function testGetCurrentDigest() public {
        bytes32 digest = validator.getCurrentDigest();
        assertEq(
            digest,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    validator.domainSeparator(),
                    keccak256(
                        abi.encode(
                            validator.VERIFICATION_CLAIM_TYPEHASH(),
                            validator.FID(),
                            address(validator),
                            blockhash(block.number - 1),
                            validator.NETWORK()
                        )
                    )
                )
            )
        );
    }

    function testIsValidSignature_ExternalSigner() public {
        // Fork OP Mainnet at specific block (blockNumber + 1)

        // This signature was generated externally
        bytes memory externalSignature =
            hex"00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000007b1f715af72d71c2047b50c07996223bcded35758977269702d4770dd1bb91e4508504800000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000041619a3596cdb65c098be266aae269c9280b8f2d069f67a5d75da3279b7c6c40ba31d6cc7563e69319eef1903742d1da4fbf1895c5427bcb366e5e0e7290191dbb1b00000000000000000000000000000000000000000000000000000000000000";
        bytes32 digest = 0x868e4de68d2ec9e7f48cd5b356dc19185458732c6761813dc307c209fbbc6e2c;

        // Decode the bundle to get block number and hash
        FarcasterSignatureValidator.VerificationBundle memory bundle =
            abi.decode(externalSignature, (FarcasterSignatureValidator.VerificationBundle));

        // Fork at block number + 1 to have access to the block hash
        _initOnFork(getChain("optimism").rpcUrl, bundle.blockNumber + 1);

        validator.setSigner(0x3ba80D07Edd55cEee8137b82338c569d85F6d06b);

        // Now getCurrentDigest() should match
        assertEq(digest, validator.getCurrentDigest());

        bytes4 result = validator.isValidSignature(digest, externalSignature);
        assertEq(result, IERC1271.isValidSignature.selector);
    }

    function testIsValidSignature_WithUniversalValidator() public {
        // Fork OP Mainnet at specific block (blockNumber + 1)
        // This signature was generated externally
        bytes memory externalSignature =
            hex"00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000007b1f715af72d71c2047b50c07996223bcded35758977269702d4770dd1bb91e4508504800000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000041619a3596cdb65c098be266aae269c9280b8f2d069f67a5d75da3279b7c6c40ba31d6cc7563e69319eef1903742d1da4fbf1895c5427bcb366e5e0e7290191dbb1b00000000000000000000000000000000000000000000000000000000000000";
        bytes32 digest = 0x868e4de68d2ec9e7f48cd5b356dc19185458732c6761813dc307c209fbbc6e2c;
        // Decode the bundle to get block number and hash
        FarcasterSignatureValidator.VerificationBundle memory bundle =
            abi.decode(externalSignature, (FarcasterSignatureValidator.VerificationBundle));

        // Roll to the block number from the bundle

        _initOnFork(getChain("optimism").rpcUrl, bundle.blockNumber + 1);
        validator.setSigner(0x3ba80D07Edd55cEee8137b82338c569d85F6d06b);

        // Create and use the Universal Signature Validator
        UniversalSigValidator universalValidator = new UniversalSigValidator();
        bool isValid = universalValidator.isValidSig(address(validator), digest, externalSignature);

        assertTrue(isValid, "Universal signature validation failed");
    }

    // Helper function to sign digests
    function signDigest(uint256 privateKey, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
