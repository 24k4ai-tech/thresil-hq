// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IFTMonsterLastBuyerPot {
    function recordEffectiveBuy(address buyer, uint256 ethIn) external;
    function settleIfReady() external returns (bool settled, uint256 payout, address winner);
}
