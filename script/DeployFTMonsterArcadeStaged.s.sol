// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {FTMonsterArcadeToken} from "../src/FTMonsterArcadeToken.sol";
import {FTMonsterArcadeLPClub} from "../src/FTMonsterArcadeLPClub.sol";
import {FTMonsterLastBuyerPot} from "../src/FTMonsterLastBuyerPot.sol";
import {FTMonsterPenaltyDraw} from "../src/FTMonsterPenaltyDraw.sol";
import {FTMonsterArcadeLauncher} from "../src/FTMonsterArcadeLauncher.sol";
import {FTMonsterArcadeV4Hook} from "../src/FTMonsterArcadeV4Hook.sol";
import {FTMonsterArcadeHookDeployer} from "../src/FTMonsterArcadeHookDeployer.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

contract DeployFTMonsterArcadeStaged is Script {
    uint160 private constant HOOK_MASK = uint160((1 << 14) - 1);
    uint160 private constant REQUIRED_HOOK_BITS = 0x05CC;
    address private constant DEFAULT_MAINNET_V4_POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address private constant DEFAULT_MAINNET_POSITION_MANAGER = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;

    error HookSaltNotFound(uint256 start, uint256 limit);
    error InvalidHookSalt(bytes32 salt, address predicted);

    function run() external {
        uint256 privateKey = vm.envUint("MAINNETPRIVATE_KEY");
        address deployer = vm.addr(privateKey);
        IPoolManager poolManager = IPoolManager(vm.envOr("V4_POOL_MANAGER", DEFAULT_MAINNET_V4_POOL_MANAGER));
        address taxWallet = vm.envOr("ARCADE_TAX_WALLET", deployer);

        vm.startBroadcast(privateKey);

        FTMonsterArcadeLauncher launcher = new FTMonsterArcadeLauncher(taxWallet);
        FTMonsterArcadeToken token = launcher.token();
        FTMonsterLastBuyerPot jackpot = new FTMonsterLastBuyerPot(address(0));
        FTMonsterPenaltyDraw penaltyDraw = new FTMonsterPenaltyDraw(token);
        FTMonsterArcadeV4Hook hook = _deployHook(poolManager, token, jackpot, penaltyDraw, launcher);
        FTMonsterArcadeLPClub lpClub = new FTMonsterArcadeLPClub(address(hook));

        launcher.setJackpot(address(jackpot));
        launcher.setPenaltyDraw(address(penaltyDraw));
        launcher.setLPClub(address(lpClub));
        launcher.setV4Hook(address(hook));

        jackpot.setHook(address(hook));
        jackpot.setLauncher(address(launcher));
        penaltyDraw.setHook(address(hook));
        penaltyDraw.setLauncher(address(launcher));
        penaltyDraw.setLPClub(address(lpClub));

        vm.stopBroadcast();

        console2.log("ARCADE_STAGED_DEPLOYER", deployer);
        console2.log("ARCADE_STAGED_LAUNCHER", address(launcher));
        console2.log("ARCADE_STAGED_TOKEN", address(token));
        console2.log("ARCADE_STAGED_JACKPOT", address(jackpot));
        console2.log("ARCADE_STAGED_PENALTY_DRAW", address(penaltyDraw));
        console2.log("ARCADE_STAGED_LP_CLUB", address(lpClub));
        console2.log("ARCADE_STAGED_HOOK", address(hook));
        console2.log("ARCADE_STAGED_TAX_WALLET", taxWallet);
        console2.log("ARCADE_STAGED_POOL_MANAGER", address(poolManager));
        console2.log("OFFICIAL_MAINNET_POSITION_MANAGER", DEFAULT_MAINNET_POSITION_MANAGER);
    }

    function _deployHook(
        IPoolManager poolManager,
        FTMonsterArcadeToken token,
        FTMonsterLastBuyerPot jackpot,
        FTMonsterPenaltyDraw penaltyDraw,
        FTMonsterArcadeLauncher launcher
    ) internal returns (FTMonsterArcadeV4Hook hook) {
        FTMonsterArcadeHookDeployer hookDeployer = new FTMonsterArcadeHookDeployer();
        FTMonsterArcadeV4Hook.Config memory config = FTMonsterArcadeV4Hook.Config({
            poolManager: poolManager,
            token: token,
            jackpot: address(jackpot),
            penaltyDraw: address(penaltyDraw),
            launcher: address(launcher)
        });
        bytes32 initCodeHash = keccak256(abi.encodePacked(type(FTMonsterArcadeV4Hook).creationCode, abi.encode(config)));
        bytes32 hookSalt = _hookSalt(hookDeployer, initCodeHash);
        hook = hookDeployer.deploy(hookSalt, config);
    }

    function _hookSalt(FTMonsterArcadeHookDeployer hookDeployer, bytes32 initCodeHash) internal view returns (bytes32) {
        uint256 saltOverride = vm.envOr("ARCADE_HOOK_SALT", type(uint256).max);
        if (saltOverride != type(uint256).max) {
            bytes32 hookSalt = bytes32(saltOverride);
            address predicted = _computeHookAddress(hookDeployer, hookSalt, initCodeHash);
            if ((uint160(predicted) & HOOK_MASK) != REQUIRED_HOOK_BITS) revert InvalidHookSalt(hookSalt, predicted);
            return hookSalt;
        }

        return _findHookSalt(
            hookDeployer,
            initCodeHash,
            vm.envOr("ARCADE_HOOK_SALT_START", uint256(0)),
            vm.envOr("ARCADE_HOOK_SALT_SEARCH_LIMIT", uint256(1_000_000))
        );
    }

    function _findHookSalt(FTMonsterArcadeHookDeployer hookDeployer, bytes32 initCodeHash, uint256 start, uint256 limit)
        internal
        pure
        returns (bytes32 salt)
    {
        uint256 end = start + limit;
        for (uint256 i = start; i < end; ++i) {
            salt = bytes32(i);
            address predicted = _computeHookAddress(hookDeployer, salt, initCodeHash);
            if ((uint160(predicted) & HOOK_MASK) == REQUIRED_HOOK_BITS) return salt;
        }
        revert HookSaltNotFound(start, limit);
    }

    function _computeHookAddress(FTMonsterArcadeHookDeployer hookDeployer, bytes32 salt, bytes32 initCodeHash)
        internal
        pure
        returns (address predicted)
    {
        predicted = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(hookDeployer), salt, initCodeHash))))
        );
    }
}
