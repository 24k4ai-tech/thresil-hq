// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {FTMonsterArcadeToken} from "../src/FTMonsterArcadeToken.sol";
import {FTMonsterArcadeLPClub} from "../src/FTMonsterArcadeLPClub.sol";
import {FTMonsterLastBuyerPotFast} from "../src/testnet/FTMonsterLastBuyerPotFast.sol";
import {FTMonsterPenaltyDrawFast} from "../src/testnet/FTMonsterPenaltyDrawFast.sol";
import {FTMonsterArcadeLauncherFast} from "../src/testnet/FTMonsterArcadeLauncherFast.sol";

contract DeployAndSmokeFTMonsterArcadeFastLight is Script {
    uint256 private constant BUY_SIZE = 0.001 ether;
    uint256 private constant TRACKED_LP_ETH = 0.001 ether;

    address private deployer;
    address private taxWallet;
    FTMonsterArcadeLauncherFast private launcher;
    FTMonsterArcadeToken private token;
    FTMonsterLastBuyerPotFast private jackpot;
    FTMonsterPenaltyDrawFast private penaltyDraw;
    FTMonsterArcadeLPClub private lpClub;
    FastLightMockHook private mockHook;

    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(privateKey);
        taxWallet = vm.envOr("ARCADE_FAST_TAX_WALLET", address(0x0000000000000000000000000000000000000d37));

        vm.startBroadcast(privateKey);
        _deploy();
        _wire();
        launcher.launch();
        (uint256 claimed, uint256 ethOut, uint256 burnAmount) = _smoke();
        vm.stopBroadcast();

        _log(claimed, ethOut, burnAmount);
    }

    function _deploy() private {
        launcher = new FTMonsterArcadeLauncherFast(taxWallet);
        token = launcher.token();
        jackpot = new FTMonsterLastBuyerPotFast(address(0));
        penaltyDraw = new FTMonsterPenaltyDrawFast(token);
        mockHook = new FastLightMockHook();
        lpClub = new FTMonsterArcadeLPClub(address(mockHook));
    }

    function _wire() private {
        launcher.setJackpot(address(jackpot));
        launcher.setPenaltyDraw(address(penaltyDraw));
        launcher.setLPClub(address(lpClub));
        launcher.setV4Hook(address(mockHook));
        jackpot.setHook(address(mockHook));
        jackpot.setLauncher(address(launcher));
        penaltyDraw.setHook(address(mockHook));
        penaltyDraw.setLauncher(address(launcher));
        penaltyDraw.setLPClub(address(lpClub));
    }

    function _log(uint256 claimed, uint256 ethOut, uint256 burnAmount) private view {
        console2.log("FAST_LIGHT_DEPLOYER", deployer);
        console2.log("FAST_LIGHT_LAUNCHER", address(launcher));
        console2.log("FAST_LIGHT_TOKEN", address(token));
        console2.log("FAST_LIGHT_JACKPOT", address(jackpot));
        console2.log("FAST_LIGHT_PENALTY_DRAW", address(penaltyDraw));
        console2.log("FAST_LIGHT_LP_CLUB", address(lpClub));
        console2.log("FAST_LIGHT_MOCK_HOOK", address(mockHook));
        console2.log("FAST_LIGHT_TAX_WALLET", taxWallet);
        console2.log("FAST_LIGHT_CLAIMED_LP_WEI", claimed);
        console2.log("FAST_LIGHT_SELL_ETH_OUT_WEI", ethOut);
        console2.log("FAST_LIGHT_BURN_AMOUNT", burnAmount);
    }

    function _fee(uint256 amount, uint256 bps) private pure returns (uint256) {
        return (amount * bps) / 10_000;
    }

    function _smoke() private returns (uint256 claimed, uint256 ethOut, uint256 burnAmount) {
        require(launcher.currentBaseTotalFeeBps() == 600, "base fee");
        require(launcher.currentLpClubFeeBps() == 100, "lp fee");

        uint256 firstBuy = launcher.buyGenesis{value: BUY_SIZE}(deployer);
        require(firstBuy > 0, "first buy");
        require(address(lpClub).balance == _fee(BUY_SIZE, launcher.currentLpClubFeeBps()), "lp first fee");
        require(lpClub.totalTrackedEth() == 0, "lp should be empty");

        mockHook.recordLiquidityAdded(payable(address(lpClub)), deployer, TRACKED_LP_ETH);
        require(lpClub.totalTrackedEth() == TRACKED_LP_ETH, "lp tracked");

        uint256 secondBuy = launcher.buyGenesis{value: BUY_SIZE}(deployer);
        require(secondBuy > 0, "second buy");
        claimed = lpClub.claim();
        uint256 expectedClaim = _fee(BUY_SIZE * 2, launcher.currentLpClubFeeBps());
        require(claimed + 1 >= expectedClaim && claimed <= expectedClaim, "lp claim");

        uint256 sellAmount = token.balanceOf(deployer) / 5;
        token.approve(address(launcher), sellAmount);
        ethOut = launcher.sellGenesis(sellAmount, 0);
        require(ethOut > 0, "sell out");
        require(address(lpClub).balance > 0, "sell lp fee");

        burnAmount = token.balanceOf(deployer) / 100;
        token.approve(address(penaltyDraw), burnAmount);
        uint256 weight = penaltyDraw.enter(burnAmount);
        require(weight > 0, "burn entry");
        require(penaltyDraw.currentRoundWeight() > 0, "draw weight");
    }
}

contract FastLightMockHook {
    uint256 public launchTimestamp;

    function launchFromLauncher(uint256 launchTimestamp_) external {
        launchTimestamp = launchTimestamp_;
    }

    function recordLiquidityAdded(address payable lpClub, address account, uint256 ethAmount) external {
        FTMonsterArcadeLPClub(lpClub).recordLiquidityAdded(account, ethAmount);
    }
}
