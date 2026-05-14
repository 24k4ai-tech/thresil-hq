// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IFTMonsterArcadeLauncher {
    function owner() external view returns (address);
    function apiFeeWallet() external view returns (address);
    function lpClub() external view returns (address);
    function fuseLpShareBps() external pure returns (uint256);
    function currentLpClubFeeBps() external pure returns (uint256);
    function launched() external view returns (bool);
    function launchTimestamp() external view returns (uint256);
    function currentApiFeeBps() external view returns (uint256);
    function currentJackpotFeeBps() external pure returns (uint256);
    function currentPenaltyDrawFeeBps() external pure returns (uint256);
    function currentTotalFeeBps() external view returns (uint256);
}
