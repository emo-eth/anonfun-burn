// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {SignatureValidator} from "src/SignatureValidator.sol";

import {DeterministicUpgradeableFactory, SimpleUpgradeableProxy} from "src/proxy/DeterministicUpgradeableFactory.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {IERC1271} from "openzeppelin-contracts/interfaces/IERC1271.sol";

contract SignatureValidatorTest is Test {
    uint256 mainnetFork;
    uint256 constant FORK_BLOCK_NUMBER = 21360869;

    DeterministicUpgradeableFactory factory;

    SignatureValidator validator;
    SignatureValidator implementation;

    Account signer;

    function setUp() public {
        // Setup mainnet fork
        mainnetFork = vm.createSelectFork(getChain("mainnet").rpcUrl, FORK_BLOCK_NUMBER);

        // Rest of the setup
        factory = new DeterministicUpgradeableFactory();
        implementation = new SignatureValidator();
        signer = makeAccount("signer");

        SimpleUpgradeableProxy proxy = SimpleUpgradeableProxy(factory.deployDeterministicUUPS(0, address(this)));

        proxy.upgradeToAndCall(
            address(implementation), abi.encodeCall(implementation.reinitialize, (2, address(this), signer.addr))
        );
        validator = SignatureValidator(address(proxy));
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

    function testIsValidSignature() public {
        // Use real block data from mainnet
        uint256 blockNum = FORK_BLOCK_NUMBER - 1; // Previous block
        bytes32 blockHash = blockhash(blockNum);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                validator.domainSeparator(),
                keccak256(abi.encode(validator.RECENT_BLOCK_HASH_TYPEHASH(), blockNum, blockHash))
            )
        );

        bytes memory signature = signDigest(signer.key, digest);

        SignatureValidator.RecentBlockHashBundle memory bundle =
            SignatureValidator.RecentBlockHashBundle({number: blockNum, hash: blockHash, signature: signature});

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
                keccak256(abi.encode(validator.RECENT_BLOCK_HASH_TYPEHASH(), blockNum, wrongHash))
            )
        );

        bytes memory signature = signDigest(signer.key, digest);

        SignatureValidator.RecentBlockHashBundle memory bundle =
            SignatureValidator.RecentBlockHashBundle({number: blockNum, hash: wrongHash, signature: signature});

        vm.expectRevert(SignatureValidator.InvalidBlockHash.selector);
        validator.isValidSignature(digest, abi.encode(bundle));
    }

    function testIsValidSignature_BlockTooOld() public {
        uint256 oldBlockNum = FORK_BLOCK_NUMBER - 257;
        vm.roll(FORK_BLOCK_NUMBER + 257); // Move forward so the block is too old
        bytes32 blockHash = blockhash(oldBlockNum);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                validator.domainSeparator(),
                keccak256(abi.encode(validator.RECENT_BLOCK_HASH_TYPEHASH(), oldBlockNum, blockHash))
            )
        );

        bytes memory signature = signDigest(signer.key, digest);

        SignatureValidator.RecentBlockHashBundle memory bundle =
            SignatureValidator.RecentBlockHashBundle({number: oldBlockNum, hash: blockHash, signature: signature});

        vm.expectRevert(SignatureValidator.BlockTooOld.selector);
        validator.isValidSignature(digest, abi.encode(bundle));
    }

    function testIsValidSignature_BlockFromFuture() public {
        uint256 futureBlockNum = FORK_BLOCK_NUMBER + 1;
        bytes32 blockHash = bytes32(0);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                validator.domainSeparator(),
                keccak256(abi.encode(validator.RECENT_BLOCK_HASH_TYPEHASH(), futureBlockNum, blockHash))
            )
        );

        bytes memory signature = signDigest(signer.key, digest);

        SignatureValidator.RecentBlockHashBundle memory bundle =
            SignatureValidator.RecentBlockHashBundle({number: futureBlockNum, hash: blockHash, signature: signature});

        vm.expectRevert(SignatureValidator.BlockFromFuture.selector);
        validator.isValidSignature(digest, abi.encode(bundle));
    }

    function testIsValidSignature_DigestMismatch() public {
        uint256 blockNum = FORK_BLOCK_NUMBER - 1;
        bytes32 blockHash = blockhash(blockNum);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                validator.domainSeparator(),
                keccak256(abi.encode(validator.RECENT_BLOCK_HASH_TYPEHASH(), blockNum, blockHash))
            )
        );

        bytes memory signature = signDigest(signer.key, digest);

        SignatureValidator.RecentBlockHashBundle memory bundle =
            SignatureValidator.RecentBlockHashBundle({number: blockNum, hash: blockHash, signature: signature});

        bytes32 wrongDigest = keccak256("wrong digest");

        vm.expectRevert(SignatureValidator.DigestMismatch.selector);
        validator.isValidSignature(wrongDigest, abi.encode(bundle));
    }

    function testIsValidSignature_InvalidSigner() public {
        uint256 blockNum = FORK_BLOCK_NUMBER - 1;
        bytes32 blockHash = blockhash(blockNum);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                validator.domainSeparator(),
                keccak256(abi.encode(validator.RECENT_BLOCK_HASH_TYPEHASH(), blockNum, blockHash))
            )
        );

        Account memory wrongSigner = makeAccount("wrongSigner");
        bytes memory signature = signDigest(wrongSigner.key, digest);

        SignatureValidator.RecentBlockHashBundle memory bundle =
            SignatureValidator.RecentBlockHashBundle({number: blockNum, hash: blockHash, signature: signature});

        vm.expectRevert(SignatureValidator.InvalidSigner.selector);
        validator.isValidSignature(digest, abi.encode(bundle));
    }

    function testIsValidSignature_BlockNumberUnderflow() public {
        // Try with block.number = 0 and blockNum = 1
        vm.roll(0);
        uint256 blockNum = 1;
        bytes32 blockHash = bytes32(0);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                validator.domainSeparator(),
                keccak256(abi.encode(validator.RECENT_BLOCK_HASH_TYPEHASH(), blockNum, blockHash))
            )
        );

        bytes memory signature = signDigest(signer.key, digest);

        SignatureValidator.RecentBlockHashBundle memory bundle =
            SignatureValidator.RecentBlockHashBundle({number: blockNum, hash: blockHash, signature: signature});

        vm.expectRevert(SignatureValidator.BlockFromFuture.selector);
        validator.isValidSignature(digest, abi.encode(bundle));
    }

    function testIsValidSignature_BlockNumberOverflow() public {
        // Try with block.number = type(uint256).max
        vm.roll(type(uint256).max);
        uint256 blockNum = block.number - 1;
        bytes32 blockHash = blockhash(blockNum);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                validator.domainSeparator(),
                keccak256(abi.encode(validator.RECENT_BLOCK_HASH_TYPEHASH(), blockNum, blockHash))
            )
        );

        bytes memory signature = signDigest(signer.key, digest);

        SignatureValidator.RecentBlockHashBundle memory bundle =
            SignatureValidator.RecentBlockHashBundle({number: blockNum, hash: blockHash, signature: signature});

        // Should still work since blockNum is valid
        bytes4 result = validator.isValidSignature(digest, abi.encode(bundle));
        assertEq(result, IERC1271.isValidSignature.selector);
    }

    function testIsValidSignature_BlockDiffOverflow() public {
        // Set current block to a high number
        vm.roll(type(uint256).max);
        // Try with a very low block number to cause potential overflow in block difference calculation
        uint256 blockNum = 0;
        bytes32 blockHash = bytes32(0);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                validator.domainSeparator(),
                keccak256(abi.encode(validator.RECENT_BLOCK_HASH_TYPEHASH(), blockNum, blockHash))
            )
        );

        bytes memory signature = signDigest(signer.key, digest);

        SignatureValidator.RecentBlockHashBundle memory bundle =
            SignatureValidator.RecentBlockHashBundle({number: blockNum, hash: blockHash, signature: signature});

        vm.expectRevert(SignatureValidator.BlockTooOld.selector);
        validator.isValidSignature(digest, abi.encode(bundle));
    }

    // Helper function to sign digests
    function signDigest(uint256 privateKey, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
