// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FullMath} from "v4-core/libraries/FullMath.sol";

contract FTMonsterArcadeLPClub {
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 private constant Q128 = 1 << 128;
    uint256 public constant MAX_LP_BOOST_BPS = 700;
    uint256 public constant FULL_BOOST_ETH = 1 ether;

    address public immutable hook;

    uint256 public totalTrackedEth;
    uint256 public accRewardPerEthX128;
    uint256 public accountedBalance;
    uint256 public undistributedRewards;

    mapping(address account => uint256) public trackedEthByAccount;
    mapping(address account => uint256) public rewardDebt;
    mapping(address account => uint256) public pendingRewards;

    event LiquidityTracked(address indexed account, uint256 ethAmount, uint256 nextTrackedEth);
    event LiquidityUntracked(address indexed account, uint256 ethAmount, uint256 nextTrackedEth);
    event RewardClaimed(address indexed account, uint256 amount);
    event FeeReceived(address indexed payer, uint256 amount);

    error NotHook();
    error ZeroAddress();
    error NothingToClaim();
    error EthTransferFailed();

    modifier onlyHook() {
        if (msg.sender != hook) revert NotHook();
        _;
    }

    constructor(address hook_) {
        if (hook_ == address(0)) revert ZeroAddress();
        hook = hook_;
    }

    function currentBoostBps(address account) external view returns (uint256) {
        uint256 tracked = trackedEthByAccount[account];
        if (tracked == 0) return 0;
        if (tracked >= FULL_BOOST_ETH) return MAX_LP_BOOST_BPS;
        return FullMath.mulDiv(tracked, MAX_LP_BOOST_BPS, FULL_BOOST_ETH);
    }

    function claim() external returns (uint256 amount) {
        _checkpointRewards();
        _accrue(msg.sender);
        amount = pendingRewards[msg.sender];
        if (amount == 0) revert NothingToClaim();
        pendingRewards[msg.sender] = 0;
        (bool ok,) = payable(msg.sender).call{value: amount}("");
        if (!ok) revert EthTransferFailed();
        accountedBalance = address(this).balance;
        emit RewardClaimed(msg.sender, amount);
    }

    function recordLiquidityAdded(address account, uint256 ethAmount) external onlyHook {
        if (account == address(0) || ethAmount == 0) return;
        _checkpointRewards();
        _accrue(account);
        trackedEthByAccount[account] += ethAmount;
        totalTrackedEth += ethAmount;
        rewardDebt[account] = FullMath.mulDiv(trackedEthByAccount[account], accRewardPerEthX128, Q128);
        emit LiquidityTracked(account, ethAmount, trackedEthByAccount[account]);
    }

    function recordLiquidityRemoved(address account, uint256 ethAmount) external onlyHook {
        if (account == address(0) || ethAmount == 0) return;
        _checkpointRewards();
        _accrue(account);
        uint256 tracked = trackedEthByAccount[account];
        uint256 debit = ethAmount >= tracked ? tracked : ethAmount;
        trackedEthByAccount[account] = tracked - debit;
        totalTrackedEth -= debit;
        rewardDebt[account] = FullMath.mulDiv(trackedEthByAccount[account], accRewardPerEthX128, Q128);
        emit LiquidityUntracked(account, debit, trackedEthByAccount[account]);
    }

    function _checkpointRewards() internal {
        uint256 balance = address(this).balance;
        if (balance < accountedBalance) {
            accountedBalance = balance;
            return;
        }

        uint256 incoming = balance - accountedBalance;
        if (totalTrackedEth == 0) {
            if (incoming > 0) {
                undistributedRewards += incoming;
                accountedBalance = balance;
            }
            return;
        }

        uint256 distributable = incoming + undistributedRewards;
        if (distributable == 0) return;
        undistributedRewards = 0;
        accRewardPerEthX128 += FullMath.mulDiv(distributable, Q128, totalTrackedEth);
        accountedBalance = balance;
    }

    function _accrue(address account) internal {
        uint256 tracked = trackedEthByAccount[account];
        if (tracked == 0) {
            rewardDebt[account] = 0;
            return;
        }

        uint256 grossDebt = FullMath.mulDiv(tracked, accRewardPerEthX128, Q128);
        uint256 previousDebt = rewardDebt[account];
        if (grossDebt > previousDebt) {
            pendingRewards[account] += grossDebt - previousDebt;
        }
        rewardDebt[account] = grossDebt;
    }

    receive() external payable {
        emit FeeReceived(msg.sender, msg.value);
    }
}
