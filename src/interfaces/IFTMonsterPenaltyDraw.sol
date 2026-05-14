// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IFTMonsterPenaltyDraw {
    function settleIfReady() external returns (bool settled, uint256 payout, address winner);
}
