// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FullMath} from "v4-core/libraries/FullMath.sol";
import {FTMonsterArcadeToken} from "../FTMonsterArcadeToken.sol";
import {IFTMonsterArcadeLPClub} from "../interfaces/IFTMonsterArcadeLPClub.sol";

interface IArcadeRoundTouch {
    function touchArcadeRounds() external;
}

/// @title FTMonsterPenaltyDrawFast
/// @notice Burn-to-enter draw. Once the timer ends, the next touch locks a future block seed before payout.
contract FTMonsterPenaltyDrawFast {
    struct Entry {
        address player;
        uint256 cumulativeWeight;
        uint256 burnAmount;
    }

    uint256 public constant PAYOUT_BPS = 3_000;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant ROUND_DURATION = 17 seconds;

    FTMonsterArcadeToken public immutable token;
    address public hook;
    address public launcher;
    IFTMonsterArcadeLPClub public lpClub;
    address public immutable deployer;
    uint256 public immutable genesisBlock;
    bytes32 public immutable genesisHash;

    uint256 public round;
    uint256 public roundEndsAt;
    uint256 public currentRoundWeight;
    uint256 public settlementBlock;
    uint256 public pendingSettlementRound;
    uint256 public pendingSettlementWeight;
    uint256 public pendingSettlementPayout;
    address public lastWinner;
    uint256 public lastPayout;
    uint256 public lastWinningWeight;
    uint256 public totalBurned;

    mapping(uint256 roundId => Entry[]) private roundEntries;

    event HookSet(address indexed hook);
    event LauncherSet(address indexed launcher);
    event LPClubSet(address indexed lpClub);
    event Entered(
        uint256 indexed round,
        address indexed player,
        uint256 burnAmount,
        uint256 weight,
        uint256 cumulativeWeight,
        uint256 roundEndsAt
    );
    event RoundSettled(
        uint256 indexed round, address indexed winner, uint256 payout, uint256 winningWeight, uint256 totalWeight
    );
    event RoundSettlementArmed(uint256 indexed round, uint256 seedBlock, uint256 totalWeight, uint256 payout);
    event RoundCarried(uint256 indexed round, uint256 totalWeight);
    event FeeReceived(address indexed payer, uint256 amount);

    error NotDeployer();
    error HookAlreadySet();
    error LauncherAlreadySet();
    error LPClubAlreadySet();
    error ZeroAddress();
    error ZeroAmount();

    constructor(FTMonsterArcadeToken token_) {
        token = token_;
        deployer = msg.sender;
        genesisBlock = block.number;
        genesisHash = blockhash(block.number - 1);
        roundEndsAt = block.timestamp + ROUND_DURATION;
    }

    function setHook(address hook_) external {
        if (msg.sender != deployer) revert NotDeployer();
        if (hook != address(0)) revert HookAlreadySet();
        if (hook_ == address(0)) revert ZeroAddress();
        hook = hook_;
        emit HookSet(hook_);
    }

    function setLauncher(address launcher_) external {
        if (msg.sender != deployer) revert NotDeployer();
        if (launcher != address(0)) revert LauncherAlreadySet();
        if (launcher_ == address(0)) revert ZeroAddress();
        launcher = launcher_;
        emit LauncherSet(launcher_);
    }

    function setLPClub(address lpClub_) external {
        if (msg.sender != deployer) revert NotDeployer();
        if (address(lpClub) != address(0)) revert LPClubAlreadySet();
        if (lpClub_ == address(0)) revert ZeroAddress();
        lpClub = IFTMonsterArcadeLPClub(lpClub_);
        emit LPClubSet(lpClub_);
    }

    function currentEntryCount() external view returns (uint256) {
        return roundEntries[round].length;
    }

    function roundEntryCount(uint256 roundId) external view returns (uint256) {
        return roundEntries[roundId].length;
    }

    function roundEntry(uint256 roundId, uint256 index)
        external
        view
        returns (address player, uint256 weight, uint256 burnAmount)
    {
        Entry storage entry = roundEntries[roundId][index];
        uint256 previous = index == 0 ? 0 : roundEntries[roundId][index - 1].cumulativeWeight;
        return (entry.player, entry.cumulativeWeight - previous, entry.burnAmount);
    }

    function enter(uint256 tokenAmount) external returns (uint256 weight) {
        if (tokenAmount == 0) revert ZeroAmount();
        if (launcher != address(0)) {
            IArcadeRoundTouch(launcher).touchArcadeRounds();
        } else {
            _rollEmptyRoundIfNeeded();
            settleIfReady();
        }

        require(token.transferFrom(msg.sender, address(this), tokenAmount), "transfer");
        token.burn(tokenAmount);
        totalBurned += tokenAmount;

        weight = _sqrt(tokenAmount);
        if (weight == 0) weight = 1;
        if (address(lpClub) != address(0)) {
            uint256 boostBps = lpClub.currentBoostBps(msg.sender);
            if (boostBps > 0) {
                weight += FullMath.mulDiv(weight, boostBps, BPS_DENOMINATOR);
            }
        }

        uint256 cumulative = currentRoundWeight + weight;
        roundEntries[round].push(Entry({player: msg.sender, cumulativeWeight: cumulative, burnAmount: tokenAmount}));
        currentRoundWeight = cumulative;

        emit Entered(round, msg.sender, tokenAmount, weight, cumulative, roundEndsAt);
    }

    function settleIfReady() public returns (bool settled, uint256 payout, address winner) {
        if (settlementBlock != 0) {
            return _settleArmedRound();
        }

        _rollEmptyRoundIfNeeded();
        if (block.timestamp < roundEndsAt || currentRoundWeight == 0) {
            return (false, 0, address(0));
        }

        uint256 totalWeight = currentRoundWeight;
        uint256 settledRound = round;
        payout = (address(this).balance * PAYOUT_BPS) / BPS_DENOMINATOR;

        pendingSettlementRound = settledRound;
        pendingSettlementWeight = totalWeight;
        pendingSettlementPayout = payout;
        settlementBlock = block.number + 1;

        round = settledRound + 1;
        currentRoundWeight = 0;
        roundEndsAt = block.timestamp + ROUND_DURATION;

        emit RoundSettlementArmed(settledRound, settlementBlock, totalWeight, payout);
        return (false, payout, address(0));
    }

    function _settleArmedRound() internal returns (bool settled, uint256 payout, address winner) {
        uint256 seedBlock = settlementBlock;
        if (block.number <= seedBlock) {
            return (false, pendingSettlementPayout, address(0));
        }

        bytes32 seed = blockhash(seedBlock);
        if (seed == bytes32(0)) {
            settlementBlock = block.number + 1;
            emit RoundSettlementArmed(
                pendingSettlementRound, settlementBlock, pendingSettlementWeight, pendingSettlementPayout
            );
            return (false, pendingSettlementPayout, address(0));
        }

        uint256 totalWeight = pendingSettlementWeight;
        uint256 winningWeight =
            (uint256(
                        keccak256(
                            abi.encode(
                                seed, address(this), pendingSettlementRound, totalWeight, pendingSettlementPayout
                            )
                        )
                    )
                    % totalWeight) + 1;

        uint256 settledRound = pendingSettlementRound;
        payout = pendingSettlementPayout;
        winner = _pickWinner(settledRound, winningWeight);

        settlementBlock = 0;
        pendingSettlementRound = 0;
        pendingSettlementWeight = 0;
        pendingSettlementPayout = 0;

        if (payout > 0) {
            uint256 payableAmount = payout > address(this).balance ? address(this).balance : payout;
            (bool ok,) = winner.call{value: payableAmount}("");
            if (!ok) {
                emit RoundCarried(settledRound, totalWeight);
                return (true, payout, winner);
            }
        }

        lastWinner = winner;
        lastPayout = payout;
        lastWinningWeight = winningWeight;
        emit RoundSettled(settledRound, winner, payout, winningWeight, totalWeight);
        return (true, payout, winner);
    }

    function _pickWinner(uint256 roundId, uint256 winningWeight) internal view returns (address) {
        Entry[] storage entries = roundEntries[roundId];
        uint256 low = 0;
        uint256 high = entries.length;

        while (low < high) {
            uint256 mid = (low + high) >> 1;
            if (entries[mid].cumulativeWeight < winningWeight) {
                low = mid + 1;
            } else {
                high = mid;
            }
        }

        return entries[low].player;
    }

    function _rollEmptyRoundIfNeeded() internal {
        if (block.timestamp < roundEndsAt || currentRoundWeight != 0) return;
        unchecked {
            ++round;
        }
        roundEndsAt = block.timestamp + ROUND_DURATION;
    }

    function _sqrt(uint256 value) internal pure returns (uint256 result) {
        if (value == 0) return 0;
        uint256 x = value;
        result = 1;
        if (x >> 128 > 0) {
            x >>= 128;
            result <<= 64;
        }
        if (x >> 64 > 0) {
            x >>= 64;
            result <<= 32;
        }
        if (x >> 32 > 0) {
            x >>= 32;
            result <<= 16;
        }
        if (x >> 16 > 0) {
            x >>= 16;
            result <<= 8;
        }
        if (x >> 8 > 0) {
            x >>= 8;
            result <<= 4;
        }
        if (x >> 4 > 0) {
            x >>= 4;
            result <<= 2;
        }
        if (x >> 2 > 0) {
            result <<= 1;
        }

        unchecked {
            for (uint256 i = 0; i < 7; ++i) {
                result = (result + value / result) >> 1;
            }
            uint256 roundedDown = value / result;
            return result < roundedDown ? result : roundedDown;
        }
    }

    receive() external payable {
        emit FeeReceived(msg.sender, msg.value);
    }
}
