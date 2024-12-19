// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ILpLockerV2} from "src/lib/ILpLockerV2.sol";

contract MockLpLockerV2 is ILpLockerV2 {
    event RewardsCollected(uint256 indexed tokenId);

    function collectRewards(uint256 _tokenId) external override {
        emit RewardsCollected(_tokenId);
    }
}
