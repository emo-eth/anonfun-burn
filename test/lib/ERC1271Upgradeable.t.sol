// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1271Upgradeable, ERC1271} from "src/lib/ERC1271Upgradeable.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";

contract MockERC1271Upgradeable is ERC1271Upgradeable {
    function initialize(address _signer) external initializer {
        __ERC1271_init_unchained(_signer);
    }

    function setSigner(address _signer) public override {
        address oldSigner = getSigner();
        _setSigner(_signer);
        emit SignerChanged(oldSigner, _signer);
    }

    function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
        name = "BlockHashValidator";
        version = "1";
    }

    function isValidSignature(bytes32 hash, bytes calldata signature) public view override returns (bytes4) {
        if (ECDSA.recover(hash, signature) == getSigner()) {
            return ERC1271.isValidSignature.selector;
        }
        return bytes4(0xffffffff);
    }
}

contract ERC1271UpgradeableTest is Test {
    MockERC1271Upgradeable public erc1271;

    // Test accounts
    Account signer;
    Account newSigner;
    Account unauthorized;

    // Test message
    string constant TEST_CONTENTS = "Hello World";

    function setUp() public {
        // Create test accounts
        signer = makeAccount("signer");
        newSigner = makeAccount("newSigner");
        unauthorized = makeAccount("unauthorized");

        // Deploy and initialize contract
        erc1271 = new MockERC1271Upgradeable();
        erc1271.initialize(signer.addr);

        vm.txGasPrice(11);
    }

    function test_initialize() public {
        assertEq(erc1271.getSigner(), signer.addr);
    }

    function test_setSigner() public {
        vm.expectEmit(true, true, false, true);
        emit ERC1271Upgradeable.SignerChanged(signer.addr, newSigner.addr);

        erc1271.setSigner(newSigner.addr);
        assertEq(erc1271.getSigner(), newSigner.addr);
    }

    function test_isValidSignature_validSigner() public {
        // Create signature
        bytes32 structHash = _getStructHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.key, structHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Verify signature
        bytes4 returnValue = erc1271.isValidSignature(structHash, signature);
        assertEq(returnValue, ERC1271.isValidSignature.selector);
    }

    function test_isValidSignature_invalidSigner() public {
        // Create signature with unauthorized account
        bytes32 structHash = _getStructHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(unauthorized.key, structHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Verify signature should fail
        bytes4 returnValue = erc1271.isValidSignature(structHash, signature);
        assertEq(returnValue, bytes4(0xffffffff));
    }

    function test_isValidSignature_invalidSignature() public {
        // Create signature with wrong message
        bytes32 wrongHash = keccak256(bytes("Wrong message"));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.key, wrongHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Verify signature should fail with correct hash but wrong signature
        bytes32 structHash = _getStructHash();
        bytes4 returnValue = erc1271.isValidSignature(structHash, signature);
        assertEq(returnValue, bytes4(0xffffffff));
    }

    function test_isValidSignature_invalidSignatureLength() public {
        // Create invalid signature (wrong length)
        bytes memory invalidSignature = abi.encodePacked(bytes32(0), bytes32(0)); // Only 64 bytes instead of 65
        bytes32 structHash = _getStructHash();

        // Verify signature should fail
        vm.expectRevert(abi.encodeWithSignature("InvalidSignature()"));
        bytes4 returnValue = erc1271.isValidSignature(structHash, invalidSignature);
    }

    function test_isValidSignature_afterSignerChange() public {
        // Create signature with original signer
        bytes32 structHash = _getStructHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.key, structHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Change signer
        erc1271.setSigner(newSigner.addr);

        // Original signature should now be invalid
        bytes4 returnValue = erc1271.isValidSignature(structHash, signature);
        assertEq(returnValue, bytes4(0xffffffff));

        // Create and verify signature with new signer
        (v, r, s) = vm.sign(newSigner.key, structHash);
        signature = abi.encodePacked(r, s, v);

        returnValue = erc1271.isValidSignature(structHash, signature);
        assertEq(returnValue, ERC1271.isValidSignature.selector);
    }

    function test_cannotReinitialize() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        erc1271.initialize(newSigner.addr);
    }

    function _getStructHash() internal pure returns (bytes32) {
        // Using EIP-712 Personal Sign format from ERC1271
        return keccak256(abi.encode(keccak256("PersonalSign(string contents)"), keccak256(bytes(TEST_CONTENTS))));
    }
}
