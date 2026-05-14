// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title FTMonsterLastBuyerPotFast
/// @notice Last effective buyer game with lazy auto-settlement.
contract FTMonsterLastBuyerPotFast {
    uint256 public constant WINNER_PAYOUT_BPS = 3_000;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant MIN_EFFECTIVE_BUY_ETH = 0.015 ether;
    uint256 public constant ROUND_DURATION = 45 seconds;

    address public hook;
    address public launcher;
    address public immutable deployer;
    uint256 public immutable genesisBlock;
    bytes32 public immutable genesisHash;

    address public lastBuyer;
    uint256 public deadlineTimestamp;
    uint256 public round;
    uint256 public totalPaid;
    address public lastWinner;
    uint256 public lastPayout;

    event FeeReceived(address indexed payer, uint256 amount);
    event HookSet(address indexed hook);
    event LauncherSet(address indexed launcher);
    event EffectiveBuy(address indexed buyer, uint256 ethIn, uint256 deadlineTimestamp, uint256 indexed round);
    event JackpotPaid(address indexed winner, uint256 amount, uint256 indexed round);
    event JackpotRolledOver(address indexed failedWinner, uint256 amount, uint256 indexed round);

    error NotRecorder();
    error NotDeployer();
    error HookAlreadySet();
    error LauncherAlreadySet();
    error ZeroAddress();

    modifier onlyRecorder() {
        if (msg.sender != hook && msg.sender != launcher) revert NotRecorder();
        _;
    }

    constructor(address hook_) {
        deployer = msg.sender;
        hook = hook_;
        genesisBlock = block.number;
        genesisHash = blockhash(block.number - 1);
        if (hook_ != address(0)) emit HookSet(hook_);
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

    function recordEffectiveBuy(address buyer, uint256 ethIn) external onlyRecorder {
        settleIfReady();
        if (buyer == address(0) || ethIn < MIN_EFFECTIVE_BUY_ETH) return;
        lastBuyer = buyer;
        deadlineTimestamp = block.timestamp + ROUND_DURATION;
        emit EffectiveBuy(buyer, ethIn, deadlineTimestamp, round);
    }

    function settleIfReady() public returns (bool settled, uint256 payout, address winner) {
        if (lastBuyer == address(0) || block.timestamp < deadlineTimestamp) {
            return (false, 0, address(0));
        }

        winner = lastBuyer;
        payout = (address(this).balance * WINNER_PAYOUT_BPS) / BPS_DENOMINATOR;
        lastBuyer = address(0);
        deadlineTimestamp = 0;

        uint256 settlingRound = round;
        unchecked {
            ++round;
        }

        if (payout > 0) {
            (bool ok,) = winner.call{value: payout}("");
            if (!ok) {
                emit JackpotRolledOver(winner, payout, settlingRound);
                return (true, payout, winner);
            }
            totalPaid += payout;
            lastWinner = winner;
            lastPayout = payout;
        }

        emit JackpotPaid(winner, payout, settlingRound);
        return (true, payout, winner);
    }

    receive() external payable {
        emit FeeReceived(msg.sender, msg.value);
    }
}
