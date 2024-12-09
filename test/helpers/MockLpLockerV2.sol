// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ILpLockerV2} from "src/lib/ILpLockerV2.sol";

contract MockLpLockerV2 is ILpLockerV2 {
    event FeesCollected(uint256 indexed tokenId);

    function collectFees(uint256 _tokenId) external override {
        emit FeesCollected(_tokenId);
    }
}
