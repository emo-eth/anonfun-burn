// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ILpLockerV2 {
    function collectRewards(uint256 _tokenId) external;
}
