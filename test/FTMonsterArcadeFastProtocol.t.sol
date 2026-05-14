// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {FTMonsterArcadeToken} from "../src/FTMonsterArcadeToken.sol";
import {FTMonsterArcadeLPClub} from "../src/FTMonsterArcadeLPClub.sol";
import {FTMonsterLastBuyerPotFast} from "../src/testnet/FTMonsterLastBuyerPotFast.sol";
import {FTMonsterPenaltyDrawFast} from "../src/testnet/FTMonsterPenaltyDrawFast.sol";
import {FTMonsterArcadeLauncherFast} from "../src/testnet/FTMonsterArcadeLauncherFast.sol";

contract FTMonsterArcadeFastProtocolTest is Test {
    FTMonsterArcadeLauncherFast internal launcher;
    FTMonsterArcadeToken internal token;
    FTMonsterLastBuyerPotFast internal jackpot;
    FTMonsterPenaltyDrawFast internal penaltyDraw;
    FTMonsterArcadeLPClub internal lpClub;
    MockFastLaunchReceiver internal hookReceiver;

    address internal taxWallet = address(0xD37);
    address internal alice = address(0xA11CE);

    function setUp() public {
        launcher = new FTMonsterArcadeLauncherFast(taxWallet);
        token = launcher.token();
        jackpot = new FTMonsterLastBuyerPotFast(address(0));
        penaltyDraw = new FTMonsterPenaltyDrawFast(token);
        hookReceiver = new MockFastLaunchReceiver();
        lpClub = new FTMonsterArcadeLPClub(address(hookReceiver));

        launcher.setJackpot(address(jackpot));
        launcher.setPenaltyDraw(address(penaltyDraw));
        launcher.setLPClub(address(lpClub));
        launcher.setV4Hook(address(hookReceiver));
        jackpot.setHook(address(hookReceiver));
        jackpot.setLauncher(address(launcher));
        penaltyDraw.setHook(address(hookReceiver));
        penaltyDraw.setLauncher(address(launcher));
        penaltyDraw.setLPClub(address(lpClub));
        launcher.launch();

        vm.deal(alice, 10 ether);
    }

    function testAllTimedFeaturesFinishInsideTwoMinutes() public {
        uint256 launchTs = launcher.launchTimestamp();

        vm.prank(alice);
        launcher.buyGenesis{value: 0.02 ether}(alice);

        vm.warp(launchTs + 46);
        vm.prank(alice);
        launcher.buyGenesis{value: 0.02 ether}(alice);
        assertEq(jackpot.lastWinner(), alice);
        assertGt(jackpot.lastPayout(), 0);

        vm.startPrank(alice);
        uint256 burnAmount = token.balanceOf(alice) / 20;
        token.approve(address(penaltyDraw), type(uint256).max);
        penaltyDraw.enter(burnAmount);
        vm.stopPrank();

        vm.warp(launchTs + 64);
        vm.prank(alice);
        launcher.buyGenesis{value: 0.03 ether}(alice);
        assertEq(penaltyDraw.lastWinner(), address(0));
        assertGt(penaltyDraw.pendingSettlementPayout(), 0);

        uint256 seedBlock = penaltyDraw.settlementBlock();
        vm.roll(seedBlock + 1);
        launcher.touchArcadeRounds();

        assertEq(penaltyDraw.round(), 2);
        assertEq(penaltyDraw.lastWinner(), alice);
        assertGt(penaltyDraw.lastPayout(), 0);

        vm.warp(launchTs + 78);
        launcher.setPostWindowApiFeeBps(50);
        assertEq(launcher.currentApiFeeBps(), 50);
        launcher.freezeAndRenounce(80);
        assertEq(launcher.owner(), address(0));
        assertTrue(launcher.controlsFrozen());

        assertLe(block.timestamp - launchTs, 120);
    }

    function testFastFuseWindowShiftsInsideTwoMinutes() public {
        uint256 launchTs = launcher.launchTimestamp();
        assertEq(launcher.currentFuseWindowSeconds(), 30 seconds);

        vm.warp(launchTs + 91);
        assertEq(launcher.currentFuseWindowSeconds(), 45 seconds);
    }
}

contract MockFastLaunchReceiver {
    uint256 public launchTimestamp;

    function launchFromLauncher(uint256 launchTimestamp_) external {
        launchTimestamp = launchTimestamp_;
    }
}
