// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {FTMonsterArcadeToken} from "../src/FTMonsterArcadeToken.sol";
import {FTMonsterArcadeLPClub} from "../src/FTMonsterArcadeLPClub.sol";
import {FTMonsterLaunchMath} from "../src/libraries/FTMonsterLaunchMath.sol";
import {FTMonsterLastBuyerPotFast} from "../src/testnet/FTMonsterLastBuyerPotFast.sol";
import {FTMonsterPenaltyDrawFast} from "../src/testnet/FTMonsterPenaltyDrawFast.sol";
import {FTMonsterArcadeLauncherFast} from "../src/testnet/FTMonsterArcadeLauncherFast.sol";
import {FTMonsterArcadeV4HookFast} from "../src/testnet/FTMonsterArcadeV4HookFast.sol";
import {FTMonsterArcadeHookDeployerFast} from "../src/testnet/FTMonsterArcadeHookDeployerFast.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";

contract DeployFTMonsterArcadeFast is Script {
    uint160 private constant HOOK_MASK = uint160((1 << 14) - 1);
    uint160 private constant REQUIRED_HOOK_BITS = 0x05CC;
    address private constant DEFAULT_SEPOLIA_V4_POOL_MANAGER = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
    address private constant DEFAULT_SEPOLIA_POSITION_MANAGER = 0x4b8CBEdC19B0cecA9bbFbd61A62DCB3BfEe1aBac;

    error HookSaltNotFound(uint256 start, uint256 limit);
    error InvalidHookSalt(bytes32 salt, address predicted);

    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        IPoolManager poolManager = IPoolManager(vm.envOr("SEPOLIA_V4_POOL_MANAGER", DEFAULT_SEPOLIA_V4_POOL_MANAGER));
        address taxWallet = vm.envOr("ARCADE_FAST_TAX_WALLET", vm.addr(privateKey));
        uint256 referenceEth = vm.envOr("ARCADE_FAST_REFERENCE_ETH", uint256(0.1 ether));
        uint256 referenceTokenBudget = vm.envOr("ARCADE_FAST_REFERENCE_TOKEN_BUDGET", uint256(1_000_000_000 * 1e18));

        vm.startBroadcast(privateKey);

        FTMonsterArcadeLauncherFast launcher = new FTMonsterArcadeLauncherFast(taxWallet);
        FTMonsterArcadeToken token = launcher.token();
        FTMonsterLastBuyerPotFast jackpot = new FTMonsterLastBuyerPotFast(address(0));
        FTMonsterPenaltyDrawFast penaltyDraw = new FTMonsterPenaltyDrawFast(token);
        FTMonsterArcadeV4HookFast hook = _deployHook(poolManager, token, jackpot, penaltyDraw, launcher);
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

        launcher.launch();

        PoolKey memory poolKey = _poolKey(token, hook);
        uint160 initialSqrtPriceX96 = FTMonsterLaunchMath.initialSqrtPriceX96(referenceEth, referenceTokenBudget);
        if (vm.envOr("INITIALIZE_FAST_POOL", true)) {
            poolManager.initialize(poolKey, initialSqrtPriceX96);
        }

        vm.stopBroadcast();

        console2.log("FAST_LAUNCHER", address(launcher));
        console2.log("FAST_TOKEN", address(token));
        console2.log("FAST_JACKPOT", address(jackpot));
        console2.log("FAST_PENALTY_DRAW", address(penaltyDraw));
        console2.log("FAST_LP_CLUB", address(lpClub));
        console2.log("FAST_HOOK", address(hook));
        console2.log("FAST_POOL_MANAGER", address(poolManager));
        console2.log("OFFICIAL_SEPOLIA_POSITION_MANAGER", DEFAULT_SEPOLIA_POSITION_MANAGER);
    }

    function _deployHook(
        IPoolManager poolManager,
        FTMonsterArcadeToken token,
        FTMonsterLastBuyerPotFast jackpot,
        FTMonsterPenaltyDrawFast penaltyDraw,
        FTMonsterArcadeLauncherFast launcher
    ) internal returns (FTMonsterArcadeV4HookFast hook) {
        FTMonsterArcadeHookDeployerFast hookDeployer = new FTMonsterArcadeHookDeployerFast();
        FTMonsterArcadeV4HookFast.Config memory config = FTMonsterArcadeV4HookFast.Config({
            poolManager: poolManager,
            token: token,
            jackpot: address(jackpot),
            penaltyDraw: address(penaltyDraw),
            launcher: address(launcher)
        });
        bytes32 initCodeHash =
            keccak256(abi.encodePacked(type(FTMonsterArcadeV4HookFast).creationCode, abi.encode(config)));
        bytes32 hookSalt = _hookSalt(hookDeployer, initCodeHash);
        hook = hookDeployer.deploy(hookSalt, config);
    }

    function _hookSalt(FTMonsterArcadeHookDeployerFast hookDeployer, bytes32 initCodeHash)
        internal
        view
        returns (bytes32)
    {
        uint256 saltOverride = vm.envOr("ARCADE_FAST_HOOK_SALT", type(uint256).max);
        if (saltOverride != type(uint256).max) {
            bytes32 hookSalt = bytes32(saltOverride);
            address predicted = _computeHookAddress(hookDeployer, hookSalt, initCodeHash);
            if ((uint160(predicted) & HOOK_MASK) != REQUIRED_HOOK_BITS) revert InvalidHookSalt(hookSalt, predicted);
            return hookSalt;
        }

        return _findHookSalt(
            hookDeployer,
            initCodeHash,
            vm.envOr("ARCADE_FAST_HOOK_SALT_START", uint256(0)),
            vm.envOr("ARCADE_FAST_HOOK_SALT_SEARCH_LIMIT", uint256(1_000_000))
        );
    }

    function _findHookSalt(
        FTMonsterArcadeHookDeployerFast hookDeployer,
        bytes32 initCodeHash,
        uint256 start,
        uint256 limit
    ) internal pure returns (bytes32 salt) {
        uint256 end = start + limit;
        for (uint256 i = start; i < end; ++i) {
            salt = bytes32(i);
            address predicted = _computeHookAddress(hookDeployer, salt, initCodeHash);
            if ((uint160(predicted) & HOOK_MASK) == REQUIRED_HOOK_BITS) return salt;
        }
        revert HookSaltNotFound(start, limit);
    }

    function _poolKey(FTMonsterArcadeToken token, FTMonsterArcadeV4HookFast hook)
        internal
        pure
        returns (PoolKey memory poolKey)
    {
        poolKey = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(token)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
    }

    function _computeHookAddress(FTMonsterArcadeHookDeployerFast hookDeployer, bytes32 salt, bytes32 initCodeHash)
        internal
        pure
        returns (address predicted)
    {
        predicted = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(hookDeployer), salt, initCodeHash))))
        );
    }
}
