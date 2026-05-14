// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IFTMonsterArcadeLPClub {
    function currentBoostBps(address account) external view returns (uint256);
    function recordLiquidityAdded(address account, uint256 ethAmount) external;
    function recordLiquidityRemoved(address account, uint256 ethAmount) external;
}
