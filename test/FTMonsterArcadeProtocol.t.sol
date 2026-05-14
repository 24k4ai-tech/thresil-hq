// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {FTMonsterArcadeLauncher} from "../src/FTMonsterArcadeLauncher.sol";
import {FTMonsterArcadeToken} from "../src/FTMonsterArcadeToken.sol";
import {FTMonsterLastBuyerPot} from "../src/FTMonsterLastBuyerPot.sol";
import {FTMonsterPenaltyDraw} from "../src/FTMonsterPenaltyDraw.sol";
import {FTMonsterArcadeLPClub} from "../src/FTMonsterArcadeLPClub.sol";

contract FTMonsterArcadeProtocolTest is Test {
    FTMonsterArcadeLauncher internal launcher;
    FTMonsterArcadeToken internal token;
    FTMonsterLastBuyerPot internal jackpot;
    FTMonsterPenaltyDraw internal penaltyDraw;
    FTMonsterArcadeLPClub internal lpClub;
    MockLaunchReceiver internal hookReceiver;

    address internal taxWallet = address(0xD37);
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        launcher = new FTMonsterArcadeLauncher(taxWallet);
        token = launcher.token();
        jackpot = new FTMonsterLastBuyerPot(address(0));
        penaltyDraw = new FTMonsterPenaltyDraw(token);
        hookReceiver = new MockLaunchReceiver();
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

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    function testInitialMetadataAndFeeSchedule() public view {
        assertEq(token.name(), "Oracle777");
        assertEq(token.symbol(), "777X");
        assertEq(token.website(), "https://www.777x.space/");
        assertEq(address(launcher.jackpot()), address(jackpot));
        assertEq(address(launcher.penaltyDraw()), address(penaltyDraw));
        assertEq(launcher.CURVE_CLOSE_GROSS_ETH(), 17 ether);
        assertEq(launcher.CURVE_CLOSE_NET_ETH(), 15_980_000_000_000_000_000);
        assertEq(launcher.currentApiFeeBps(), 200);
        assertEq(launcher.currentJackpotFeeBps(), 100);
        assertEq(launcher.currentLpClubFeeBps(), 100);
        assertEq(launcher.currentPenaltyDrawFeeBps(), 200);
        assertEq(launcher.currentBaseTotalFeeBps(), 600);
        assertEq(launcher.currentTotalFeeBps(), 600);
        assertEq(launcher.currentFuseWindowSeconds(), 30 minutes);
        assertEq(launcher.FUSE_TIER_ONE_BPS(), 500);
        assertEq(launcher.FUSE_TIER_TWO_BPS(), 1_000);
        assertEq(launcher.FUSE_TIER_THREE_BPS(), 1_500);
        assertEq(launcher.claimSourceToken(), 0x829f4B62EEBE12Af653b4dD4fFc480966F7d7f09);
    }

    function testLaunchRequiresLPClubBeforeOpening() public {
        FTMonsterArcadeLauncher fresh = new FTMonsterArcadeLauncher(taxWallet);
        FTMonsterLastBuyerPot freshJackpot = new FTMonsterLastBuyerPot(address(0));
        FTMonsterPenaltyDraw freshDraw = new FTMonsterPenaltyDraw(fresh.token());
        MockLaunchReceiver freshHook = new MockLaunchReceiver();

        fresh.setJackpot(address(freshJackpot));
        fresh.setPenaltyDraw(address(freshDraw));
        fresh.setV4Hook(address(freshHook));
        freshJackpot.setHook(address(freshHook));
        freshJackpot.setLauncher(address(fresh));
        freshDraw.setHook(address(freshHook));
        freshDraw.setLauncher(address(fresh));

        vm.expectRevert(FTMonsterArcadeLauncher.LaunchNotReady.selector);
        fresh.launch();
    }

    function testEarlyBuyRoutesSixPercent() public {
        uint256 taxBefore = taxWallet.balance;
        uint256 jackpotBefore = address(jackpot).balance;
        uint256 drawBefore = address(penaltyDraw).balance;

        vm.prank(alice);
        launcher.buyGenesis{value: 1 ether}(alice);

        assertEq(taxWallet.balance - taxBefore, 0.02 ether);
        assertEq(address(jackpot).balance - jackpotBefore, 0.01 ether);
        assertEq(address(lpClub).balance, 0.01 ether);
        assertEq(address(penaltyDraw).balance - drawBefore, 0.02 ether);
        assertGt(token.balanceOf(alice), 0);
    }

    function testLpClubReceivesBaseLpTaxAndFuseShareAndLpCanClaimIt() public {
        vm.prank(address(hookReceiver));
        lpClub.recordLiquidityAdded(alice, 1 ether);

        vm.prank(alice);
        launcher.buyGenesis{value: 5 ether}(alice);

        uint256 balance = token.balanceOf(alice);
        (,,, uint256 drawFee, uint256 fuseFee,,) = launcher.quoteSellDetailed(balance);
        uint256 expectedBaseLpReward = (5 ether * launcher.currentLpClubFeeBps()) / 10_000;
        uint256 quotedBaseLpReward = (grossEthOutFor(balance) * launcher.currentLpClubFeeBps()) / 10_000;
        uint256 expectedLpReward = (fuseFee * launcher.fuseLpShareBps()) / 10_000;
        uint256 expectedDrawSide = drawFee + fuseFee - expectedLpReward;

        uint256 drawBefore = address(penaltyDraw).balance;
        vm.startPrank(alice);
        token.approve(address(launcher), type(uint256).max);
        launcher.sellGenesis(balance, 0);
        vm.stopPrank();

        assertApproxEqAbs(address(lpClub).balance, expectedBaseLpReward + quotedBaseLpReward + expectedLpReward, 1);
        assertEq(address(penaltyDraw).balance - drawBefore, expectedDrawSide);

        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        uint256 claimed = lpClub.claim();
        assertApproxEqAbs(claimed, expectedBaseLpReward + quotedBaseLpReward + expectedLpReward, 1);
        assertApproxEqAbs(alice.balance - aliceBefore, expectedBaseLpReward + quotedBaseLpReward + expectedLpReward, 1);
    }

    function testLpTaxAccumulatesUntilOfficialLpIsTracked() public {
        vm.prank(alice);
        launcher.buyGenesis{value: 1 ether}(alice);

        assertEq(address(lpClub).balance, 0.01 ether);
        assertEq(lpClub.undistributedRewards(), 0);

        vm.prank(address(hookReceiver));
        lpClub.recordLiquidityAdded(bob, 1 ether);
        assertEq(lpClub.undistributedRewards(), 0.01 ether);

        vm.prank(alice);
        launcher.buyGenesis{value: 1 ether}(alice);

        uint256 bobBefore = bob.balance;
        vm.prank(bob);
        uint256 claimed = lpClub.claim();

        assertApproxEqAbs(claimed, 0.02 ether, 1);
        assertApproxEqAbs(bob.balance - bobBefore, 0.02 ether, 1);
    }

    function grossEthOutFor(uint256 tokenAmount) internal view returns (uint256 grossEthOut) {
        (,,,,, grossEthOut,) = launcher.quoteSellDetailed(tokenAmount);
    }

    function testLpTrackingBoostsDrawWeight() public {
        vm.prank(address(hookReceiver));
        lpClub.recordLiquidityAdded(alice, 1 ether);

        vm.startPrank(alice);
        launcher.buyGenesis{value: 2 ether}(alice);
        uint256 aliceBalance = token.balanceOf(alice);
        token.approve(address(penaltyDraw), type(uint256).max);
        penaltyDraw.enter(aliceBalance / 10);
        vm.stopPrank();

        vm.startPrank(bob);
        launcher.buyGenesis{value: 2 ether}(bob);
        uint256 bobBalance = token.balanceOf(bob);
        token.approve(address(penaltyDraw), type(uint256).max);
        penaltyDraw.enter(bobBalance / 10);
        vm.stopPrank();

        (, uint256 aliceWeight,) = penaltyDraw.roundEntry(0, 0);
        (, uint256 bobWeight,) = penaltyDraw.roundEntry(0, 1);
        assertGt(aliceWeight, bobWeight);
    }

    function testPostWindowApiCanBeAdjustedAndFrozen() public {
        vm.warp(block.timestamp + 77 minutes + 1);

        assertEq(launcher.currentApiFeeBps(), 80);

        launcher.setPostWindowApiFeeBps(50);
        assertEq(launcher.currentApiFeeBps(), 50);
        assertEq(launcher.currentBaseTotalFeeBps(), 450);

        launcher.freezeAndRenounce(80);
        assertEq(launcher.owner(), address(0));
        assertTrue(launcher.controlsFrozen());
        assertEq(launcher.currentApiFeeBps(), 80);

        vm.expectRevert(FTMonsterArcadeLauncher.NotOwner.selector);
        launcher.setPostWindowApiFeeBps(30);
    }

    function testClaimLaneLetsSotoHolderFreeMintOnce() public {
        address source = launcher.claimSourceToken();
        vm.mockCall(source, abi.encodeWithSignature("balanceOf(address)", alice), abi.encode(uint256(1 ether)));

        vm.prank(alice);
        uint256 claimed = launcher.claim();

        assertEq(claimed, launcher.CLAIM_SHARE());
        assertEq(token.balanceOf(alice), claimed);
        assertEq(launcher.claimedWalletCount(), 1);
        assertEq(launcher.claimTokensRemaining(), launcher.CLAIM_ALLOCATION() - claimed);

        vm.prank(alice);
        vm.expectRevert(FTMonsterArcadeLauncher.AlreadyClaimed.selector);
        launcher.claim();
    }

    function testLastBuyerSettlesBeforeNextBuyerFeeArrives() public {
        vm.prank(alice);
        launcher.buyGenesis{value: 1 ether}(alice);

        uint256 aliceBefore = alice.balance;
        vm.warp(block.timestamp + 46 minutes);

        vm.prank(bob);
        launcher.buyGenesis{value: 1 ether}(bob);

        assertEq(alice.balance - aliceBefore, 0.003 ether);
        assertEq(jackpot.lastWinner(), alice);
        assertEq(jackpot.lastPayout(), 0.003 ether);
        assertEq(address(jackpot).balance, 0.017 ether);
        assertEq(jackpot.lastBuyer(), bob);
    }

    function testPenaltyDrawPaysThirtyPercentWhenTouchedAfterTimer() public {
        vm.startPrank(alice);
        launcher.buyGenesis{value: 2 ether}(alice);
        uint256 balance = token.balanceOf(alice);
        token.approve(address(penaltyDraw), type(uint256).max);
        penaltyDraw.enter(balance / 10);
        vm.stopPrank();

        vm.startPrank(bob);
        launcher.buyGenesis{value: 1 ether}(bob);
        uint256 bobBalance = token.balanceOf(bob);
        token.approve(address(penaltyDraw), type(uint256).max);
        penaltyDraw.enter(bobBalance / 20);
        vm.stopPrank();

        uint256 potBefore = address(penaltyDraw).balance;
        vm.warp(block.timestamp + 18 minutes);

        vm.prank(bob);
        launcher.buyGenesis{value: 1 ether}(bob);

        assertEq(penaltyDraw.lastPayout(), 0);
        assertEq(penaltyDraw.pendingSettlementPayout(), (potBefore * 3_000) / 10_000);
        assertEq(penaltyDraw.pendingSettlementRound(), 0);
        assertGt(penaltyDraw.settlementBlock(), block.number);
        assertEq(penaltyDraw.round(), 1);
        assertEq(penaltyDraw.currentRoundWeight(), 0);

        _settleArmedDraw();

        assertEq(penaltyDraw.lastPayout(), (potBefore * 3_000) / 10_000);
        assertEq(penaltyDraw.round(), 1);
        assertEq(penaltyDraw.currentRoundWeight(), 0);
        assertTrue(penaltyDraw.lastWinner() == alice || penaltyDraw.lastWinner() == bob);
    }

    function testFuseWindowsShiftAndSellQuoteAddsFuseTax() public {
        vm.prank(alice);
        launcher.buyGenesis{value: 5 ether}(alice);

        uint256 balance = token.balanceOf(alice);
        (uint256 ethOut, uint256 apiFee, uint256 jackpotFee, uint256 drawFee, uint256 fuseFee,, uint256 fuseFeeBps) =
            launcher.quoteSellDetailed(balance);

        assertGt(ethOut, 0);
        assertEq(apiFee > 0, true);
        assertEq(jackpotFee > 0, true);
        assertEq(drawFee > 0, true);
        assertGt(fuseFee, 0);
        assertTrue(
            fuseFeeBps == launcher.FUSE_TIER_ONE_BPS() || fuseFeeBps == launcher.FUSE_TIER_TWO_BPS()
                || fuseFeeBps == launcher.FUSE_TIER_THREE_BPS()
        );
        assertEq(launcher.currentFuseWindowSeconds(), 30 minutes);

        vm.warp(block.timestamp + 6 hours + 1);
        assertEq(launcher.currentFuseWindowSeconds(), 3 hours);
        assertEq(launcher.currentSellFuseFeeBps(), 0);
    }

    function testFuseTierThresholdsUseMilderLateBands() public {
        FTMonsterArcadeLauncherHarness harness = new FTMonsterArcadeLauncherHarness(taxWallet);

        assertEq(harness.exposedFuseSurchargeBps(100, 90), 0);
        assertEq(harness.exposedFuseSurchargeBps(100, 80), launcher.FUSE_TIER_ONE_BPS());
        assertEq(harness.exposedFuseSurchargeBps(100, 70), launcher.FUSE_TIER_TWO_BPS());
        assertEq(harness.exposedFuseSurchargeBps(100, 40), launcher.FUSE_TIER_TWO_BPS());
        assertEq(harness.exposedFuseSurchargeBps(100, 39), launcher.FUSE_TIER_THREE_BPS());
    }

    function testFullExitStaysInLateFuseBandButStillExecutes() public {
        vm.prank(alice);
        launcher.buyGenesis{value: 5 ether}(alice);

        uint256 balance = token.balanceOf(alice);
        (
            uint256 quotedEthOut,
            uint256 apiFee,
            uint256 jackpotFee,
            uint256 drawFee,
            uint256 fuseFee,
            uint256 grossEthOut,
            uint256 fuseFeeBps
        ) = launcher.quoteSellDetailed(balance);

        assertTrue(fuseFeeBps == launcher.FUSE_TIER_TWO_BPS() || fuseFeeBps == launcher.FUSE_TIER_THREE_BPS());
        assertGt(grossEthOut, quotedEthOut);
        uint256 lpClubFee = (grossEthOut * launcher.currentLpClubFeeBps()) / 10_000;
        assertEq(grossEthOut - quotedEthOut, apiFee + jackpotFee + lpClubFee + drawFee + fuseFee);

        uint256 reserveBefore = launcher.curveReserve();
        uint256 ethBefore = alice.balance;

        vm.startPrank(alice);
        token.approve(address(launcher), type(uint256).max);
        uint256 ethOut = launcher.sellGenesis(balance, 0);
        vm.stopPrank();

        assertEq(ethOut, quotedEthOut);
        assertEq(alice.balance - ethBefore, quotedEthOut);
        assertLt(launcher.curveReserve(), reserveBefore);
        assertEq(token.totalSupply(), token.TOTAL_SUPPLY());
    }

    function testSeventeenGrossEthFillsCurveOnOpeningRail() public {
        (uint256 quotedOut, uint256 quotedCost) = launcher.quoteBuy(17 ether);
        assertEq(quotedCost, launcher.CURVE_CLOSE_GROSS_ETH());
        assertGt(quotedOut, 0);

        uint256 taxBefore = taxWallet.balance;
        uint256 jackpotBefore = address(jackpot).balance;
        uint256 drawBefore = address(penaltyDraw).balance;

        vm.prank(alice);
        launcher.buyGenesis{value: 17 ether}(alice);

        assertTrue(launcher.launchFilled());
        assertEq(launcher.curveEth(), launcher.CURVE_CLOSE_NET_ETH());
        assertEq(launcher.curveReserve(), launcher.CURVE_CLOSE_NET_ETH());
        assertEq(launcher.curveTokensRemaining(), 0);
        assertEq(taxWallet.balance - taxBefore, 0.34 ether);
        assertEq(address(jackpot).balance - jackpotBefore, 0.17 ether);
        assertEq(address(lpClub).balance, 0.17 ether);
        assertEq(address(penaltyDraw).balance - drawBefore, 0.34 ether);
    }

    function testSellAfterSeventeenFillBurnsTokensAndDoesNotReopenCurve() public {
        vm.prank(alice);
        launcher.buyGenesis{value: 17 ether}(alice);

        uint256 sellAmount = token.balanceOf(alice) / 10;
        uint256 supplyBefore = token.totalSupply();
        uint256 launcherBalanceBefore = token.balanceOf(address(launcher));
        uint256 reserveBefore = launcher.curveReserve();

        vm.startPrank(alice);
        token.approve(address(launcher), sellAmount);
        uint256 ethOut = launcher.sellGenesis(sellAmount, 0);
        vm.stopPrank();

        assertGt(ethOut, 0);
        assertEq(token.totalSupply(), supplyBefore - sellAmount);
        assertEq(token.balanceOf(address(launcher)), launcherBalanceBefore);
        assertLt(launcher.curveReserve(), reserveBefore);
        assertEq(launcher.curveTokensRemaining(), 0);

        vm.prank(bob);
        vm.expectRevert();
        launcher.buyGenesis{value: 1 ether}(bob);
    }

    function testRepeatedBuySellAndRoundSettlementDoNotDeadlock() public {
        vm.startPrank(alice);
        launcher.buyGenesis{value: 3 ether}(alice);
        launcher.buyGenesis{value: 0.5 ether}(alice);
        vm.stopPrank();

        vm.startPrank(bob);
        launcher.buyGenesis{value: 2 ether}(bob);
        vm.stopPrank();

        uint256 aliceBalance = token.balanceOf(alice);
        uint256 bobBalance = token.balanceOf(bob);

        vm.startPrank(alice);
        token.approve(address(launcher), type(uint256).max);
        launcher.sellGenesis(aliceBalance / 5, 0);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(launcher), type(uint256).max);
        launcher.sellGenesis(bobBalance / 6, 0);
        vm.stopPrank();

        vm.warp(block.timestamp + 46 minutes);

        vm.startPrank(alice);
        token.approve(address(penaltyDraw), type(uint256).max);
        penaltyDraw.enter(token.balanceOf(alice) / 20);
        vm.stopPrank();

        assertGt(penaltyDraw.roundEndsAt(), block.timestamp);
        assertEq(jackpot.lastBuyer(), address(0));
        assertEq(jackpot.lastWinner(), bob);
        assertGt(jackpot.lastPayout(), 0);
        assertGt(penaltyDraw.currentRoundWeight(), 0);
    }

    function testSellStillExecutesWhenLastBuyerAndDrawBothNeedSettlement() public {
        vm.prank(alice);
        launcher.buyGenesis{value: 3 ether}(alice);

        vm.prank(bob);
        launcher.buyGenesis{value: 2 ether}(bob);

        vm.startPrank(alice);
        uint256 aliceBalance = token.balanceOf(alice);
        token.approve(address(penaltyDraw), type(uint256).max);
        penaltyDraw.enter(aliceBalance / 10);
        token.approve(address(launcher), type(uint256).max);
        vm.stopPrank();

        vm.warp(block.timestamp + 46 minutes);

        uint256 sellAmount = token.balanceOf(alice) / 8;
        (uint256 quotedEthOut,,,,,,) = launcher.quoteSellDetailed(sellAmount);
        uint256 aliceEthBefore = alice.balance;

        vm.prank(alice);
        uint256 ethOut = launcher.sellGenesis(sellAmount, 0);

        assertEq(ethOut, quotedEthOut);
        assertEq(alice.balance - aliceEthBefore, quotedEthOut);
        assertEq(jackpot.lastWinner(), bob);
        assertEq(jackpot.lastBuyer(), address(0));
        assertGt(jackpot.lastPayout(), 0);
        assertEq(penaltyDraw.round(), 1);
        assertEq(penaltyDraw.lastWinner(), address(0));
        assertGt(penaltyDraw.pendingSettlementPayout(), 0);

        _settleArmedDraw();

        assertEq(alice.balance - aliceEthBefore, quotedEthOut + penaltyDraw.lastPayout());
        assertEq(penaltyDraw.lastWinner(), alice);
        assertGt(penaltyDraw.lastPayout(), 0);
    }

    function testLastBuyerPayoutCannotReenterLauncher() public {
        ReentrantRoundTouchAttacker attacker = new ReentrantRoundTouchAttacker(launcher, token, penaltyDraw);
        vm.deal(address(attacker), 3 ether);

        attacker.buySelf{value: 1 ether}();
        vm.warp(block.timestamp + 46 minutes);

        vm.prank(bob);
        launcher.buyGenesis{value: 1 ether}(bob);

        assertEq(jackpot.lastWinner(), address(attacker));
        assertTrue(attacker.reentryAttempted());
        assertTrue(attacker.reentryBlocked());
        assertFalse(attacker.reentrySucceeded());
    }

    function testPenaltyDrawPayoutCannotReenterLauncher() public {
        ReentrantRoundTouchAttacker attacker = new ReentrantRoundTouchAttacker(launcher, token, penaltyDraw);
        vm.deal(address(attacker), 4 ether);

        attacker.buySelf{value: 2 ether}();
        attacker.approveDrawMax();
        attacker.enterDraw(token.balanceOf(address(attacker)) / 8);

        vm.warp(block.timestamp + 18 minutes);

        vm.prank(bob);
        launcher.buyGenesis{value: 1 ether}(bob);

        assertEq(penaltyDraw.lastWinner(), address(0));
        assertGt(penaltyDraw.pendingSettlementPayout(), 0);

        _settleArmedDraw();

        assertEq(penaltyDraw.lastWinner(), address(attacker));
        assertTrue(attacker.reentryAttempted());
        assertTrue(attacker.reentryBlocked());
        assertFalse(attacker.reentrySucceeded());
    }

    function testPenaltyDrawWaitsForFutureSeedBlockBeforePayout() public {
        vm.startPrank(alice);
        launcher.buyGenesis{value: 2 ether}(alice);
        uint256 balance = token.balanceOf(alice);
        token.approve(address(penaltyDraw), type(uint256).max);
        penaltyDraw.enter(balance / 10);
        vm.stopPrank();

        uint256 potBefore = address(penaltyDraw).balance;
        vm.warp(block.timestamp + 18 minutes);

        launcher.touchArcadeRounds();
        uint256 seedBlock = penaltyDraw.settlementBlock();
        assertEq(penaltyDraw.lastPayout(), 0);
        assertEq(penaltyDraw.pendingSettlementPayout(), (potBefore * 3_000) / 10_000);
        assertEq(seedBlock, block.number + 1);

        launcher.touchArcadeRounds();
        assertEq(penaltyDraw.lastPayout(), 0);

        vm.roll(seedBlock);
        launcher.touchArcadeRounds();
        assertEq(penaltyDraw.lastPayout(), 0);

        vm.roll(seedBlock + 1);
        launcher.touchArcadeRounds();

        assertEq(penaltyDraw.settlementBlock(), 0);
        assertEq(penaltyDraw.lastWinner(), alice);
        assertEq(penaltyDraw.lastPayout(), (potBefore * 3_000) / 10_000);
    }

    function _settleArmedDraw() internal {
        uint256 seedBlock = penaltyDraw.settlementBlock();
        assertGt(seedBlock, 0);
        vm.roll(seedBlock + 1);
        launcher.touchArcadeRounds();
        assertEq(penaltyDraw.settlementBlock(), 0);
    }
}

contract MockLaunchReceiver {
    uint256 public launchTimestamp;

    function launchFromLauncher(uint256 launchTimestamp_) external {
        launchTimestamp = launchTimestamp_;
    }
}

contract FTMonsterArcadeLauncherHarness is FTMonsterArcadeLauncher {
    constructor(address apiFeeWallet_) FTMonsterArcadeLauncher(apiFeeWallet_) {}

    function exposedFuseSurchargeBps(uint256 highPrice, uint256 priceToCheck) external pure returns (uint256) {
        return _fuseSurchargeBps(highPrice, priceToCheck);
    }
}

contract ReentrantRoundTouchAttacker {
    FTMonsterArcadeLauncher public immutable launcher;
    FTMonsterArcadeToken public immutable token;
    FTMonsterPenaltyDraw public immutable penaltyDraw;

    bool public reentryAttempted;
    bool public reentryBlocked;
    bool public reentrySucceeded;

    constructor(FTMonsterArcadeLauncher launcher_, FTMonsterArcadeToken token_, FTMonsterPenaltyDraw penaltyDraw_) {
        launcher = launcher_;
        token = token_;
        penaltyDraw = penaltyDraw_;
    }

    function buySelf() external payable {
        launcher.buyGenesis{value: msg.value}(address(this));
    }

    function approveDrawMax() external {
        token.approve(address(penaltyDraw), type(uint256).max);
    }

    function enterDraw(uint256 amount) external {
        penaltyDraw.enter(amount);
    }

    receive() external payable {
        if (reentryAttempted || address(this).balance < 0.01 ether) return;
        reentryAttempted = true;
        try launcher.buyGenesis{value: 0.01 ether}(address(this)) {
            reentrySucceeded = true;
        } catch {
            reentryBlocked = true;
        }
    }
}
