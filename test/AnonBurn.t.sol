// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {AnonBurn} from "src/./AnonBurn.sol";

contract AnonBurnTest is Test {
    function testCreate() public {
        bytes memory data = hex"60015FF3";
        bytes memory callData = abi.encodePacked(bytes32(0), data);
        console.logBytes(callData);
        address addr;
        assembly {
            addr := create2(0, add(data, 0x20), mload(data), 0)
        }
        (bool success, bytes memory returnData) = CREATE2_FACTORY.call(callData);
        require(success, "create2 failed");
        // console.logBytes(returnData);
        assembly {
            returndatacopy(12, 0, returndatasize())
            addr := mload(0)
        }
        // addr = address(abi.decode(returnData, (bytes20)));
        console.log("addr", addr);
        console.logBytes(addr.code);
        assertEq(addr.code, hex"00");
    }
}
