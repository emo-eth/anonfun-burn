// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {SignatureValidator} from "src/SignatureValidator.sol";

import {DeterministicUpgradeableFactory} from "src/proxy/DeterministicUpgradeableFactory.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";

contract SignatureValidatorTest is Test {
    DeterministicUpgradeableFactory factory;

    SignatureValidator validator;
    SignatureValidator implementation;

    Account signer;

    function setUp() public {
        factory = new DeterministicUpgradeableFactory();
        implementation = new SignatureValidator();
        signer = makeAccount("signer");

        validator = SignatureValidator(
            factory.deployDeterministicUUPSAndUpgradeTo(
                bytes32(0),
                address(this),
                address(implementation),
                abi.encodeCall(implementation.reinitialize, (2, address(this), signer.addr))
            )
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
}
