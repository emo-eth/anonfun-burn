// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface LpLockerV1 {
    error OwnableInvalidOwner(address owner);
    error OwnableUnauthorizedAccount(address account);

    event ClaimedFees(
        address indexed claimer,
        address indexed token0,
        address indexed token1,
        uint256 amount0,
        uint256 amount1,
        uint256 totalAmount1,
        uint256 totalAmount0
    );
    event ERC721Released(address indexed token, uint256 amount);
    event LockDuration(uint256 _time);
    event LockId(uint256 _id);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Received(address indexed from, uint256 tokenId);

    receive() external payable;

    function _erc721Released(address) external view returns (uint256);
    function _fee() external view returns (uint256);
    function _feeRecipient() external view returns (address);
    function collectFees(address _recipient, uint256 _tokenId) external;
    function duration() external view returns (uint256);
    function end() external view returns (uint256);
    function initializer(uint256 token_id) external;
    function onERC721Received(address, address from, uint256 id, bytes memory data) external returns (bytes4);
    function owner() external view returns (address);
    function release() external;
    function released(address token) external view returns (uint256);
    function renounceOwnership() external;
    function transferOwnership(address newOwner) external;
    function version() external view returns (string memory);
    function vestingSchedule() external view returns (uint256);
    function withdrawERC20(address _token) external;
}
