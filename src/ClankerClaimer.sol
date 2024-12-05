// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LpLockerV2} from "./lib/LpLockerV2.sol";
import {IV3SwapRouter} from "./lib/IV3SwapRouter.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

contract ClankerClaimer {
    error OnlyExternal();

    /// @notice Router for token swaps
    IV3SwapRouter constant router = IV3SwapRouter(0xE592427a0AECE92f77E2f978d7b47f8E788E479E);

    /// @notice Clanker's LpLocker for collecting fees
    LpLockerV2 public immutable lpLocker;

    /// @notice Target token that will be bought and burned
    ERC20 public immutable target = ERC20(0x0Db510e79909666d6dEc7f5e49370838c16D950f);

    /// @notice Pair token that will be used to buy target
    ERC20 public immutable pair;

    /// @notice LP token ID that generates fees
    uint256 public immutable lpTokenId;

    /// @notice Percentage of `target` tokens given as incentive
    uint256 public immutable incentivePercent;

    /// @notice Fee for the `target` and `pair` pool
    uint24 public immutable poolFee;

    /// @notice Emitted when caller receives their incentive payment
    /// @param caller The address receiving the incentive
    /// @param burned Amount of tokens burned
    /// @param incentive Amount of tokens given as incentive
    event Spent(address indexed caller, uint256 burned, uint256 incentive);

    function claimFees(address _lpLocker, uint256 _lpTokenId) external {
        LpLockerV2 locker = LpLockerV2(payable(_lpLocker));
        locker.collectFees(msg.sender, 0);

        // Avoid flashloan class of attacks
        // @dev It is still possible to have inter-block or multi-block
        //      attacks.
        //
        if (msg.sender != tx.origin) revert OnlyExternal();

        // Collect all fees
        //
        lpLocker.collectFees(address(this), lpTokenId);

        // Make the swap
        //
        router.exactInputSingle(
            IV3SwapRouter.ExactInputSingleParams({
                tokenIn: address(pair),
                tokenOut: address(target),
                fee: poolFee,
                recipient: address(this),
                amountIn: pair.balanceOf(address(this)),
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        // Pay incentive & burn the rest
        // @dev Using 0xdead as the burn address as Clanker ERC20s are
        //      not burnable and cannot be sent to address(0).
        //
        uint256 balance = target.balanceOf(address(this));
        uint256 incentive = (balance * incentivePercent) / 100;
        uint256 burn = balance - incentive;

        target.transfer(address(0xdead), burn);
        target.transfer(msg.sender, incentive);

        emit Spent({caller: msg.sender, burned: burn, incentive: incentive});
    }
}
