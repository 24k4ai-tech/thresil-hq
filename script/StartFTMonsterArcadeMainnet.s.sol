// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {FTMonsterArcadeLauncher} from "../src/FTMonsterArcadeLauncher.sol";
import {FTMonsterArcadeToken} from "../src/FTMonsterArcadeToken.sol";
import {FTMonsterArcadeV4Hook} from "../src/FTMonsterArcadeV4Hook.sol";
import {FTMonsterLaunchMath} from "../src/libraries/FTMonsterLaunchMath.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

interface IMainnetPositionManager {
    function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable;
}

interface IPermit2Mainnet {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

contract StartFTMonsterArcadeMainnet is Script {
    address private constant LAUNCHER = 0x828318182b294E9AFf2437e7Dc4810Aa955Bb764;
    address private constant TOKEN = 0xcB16cA9d5c6F9090A1b56D29ACb31D764bc2ed7c;
    address private constant HOOK = 0xfBaFDa29fc1Ec863C10481270E24FEB1853CC5cc;
    address private constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address private constant POSITION_MANAGER = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
    address private constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address private constant BLACKHOLE = 0x000000000000000000000000000000000000dEaD;

    uint256 private constant SEED_BUY_ETH = 0.001 ether;
    uint256 private constant SEED_LP_ETH = 0.001 ether;
    uint24 private constant V4_POOL_FEE = 3000;
    int24 private constant V4_TICK_SPACING = 60;
    uint256 private constant LP_SAFETY_BPS = 9_950;
    uint256 private constant BPS_DENOMINATOR = 10_000;

    error WrongWiring();
    error NoSeedTokens();
    error TokenAmountTooLarge();
    error LiquidityTooSmall();

    function run() external {
        uint256 privateKey = vm.envUint("MAINNETPRIVATE_KEY");
        address deployer = vm.addr(privateKey);

        FTMonsterArcadeLauncher launcher = FTMonsterArcadeLauncher(payable(LAUNCHER));
        FTMonsterArcadeToken token = FTMonsterArcadeToken(TOKEN);
        FTMonsterArcadeV4Hook hook = FTMonsterArcadeV4Hook(HOOK);
        IPoolManager poolManager = IPoolManager(POOL_MANAGER);

        if (address(launcher.token()) != TOKEN || launcher.v4Hook() != HOOK || address(hook.token()) != TOKEN) {
            revert WrongWiring();
        }

        vm.startBroadcast(privateKey);

        if (!launcher.launched()) {
            launcher.launch();
        }

        uint256 seedTokenOut;
        if (token.balanceOf(deployer) == 0) {
            seedTokenOut = launcher.buyGenesis{value: SEED_BUY_ETH}(deployer);
        }

        uint256 tokenBudget = token.balanceOf(deployer);
        if (tokenBudget == 0) revert NoSeedTokens();

        PoolKey memory poolKey = _poolKey();
        uint160 sqrtPriceX96 = FTMonsterLaunchMath.initialSqrtPriceX96(SEED_LP_ETH, tokenBudget);
        try poolManager.initialize(poolKey, sqrtPriceX96) returns (int24 tick) {
            console2.log("POOL_INITIALIZED_TICK", tick);
        } catch {
            console2.log("POOL_INITIALIZE_SKIPPED_OR_ALREADY_DONE");
        }

        uint128 liquidity =
            FTMonsterLaunchMath.fullRangeLiquidity(sqrtPriceX96, V4_TICK_SPACING, SEED_LP_ETH, tokenBudget);
        liquidity = uint128((uint256(liquidity) * LP_SAFETY_BPS) / BPS_DENOMINATOR);
        if (liquidity == 0) revert LiquidityTooSmall();
        if (tokenBudget > type(uint160).max || tokenBudget > type(uint128).max) revert TokenAmountTooLarge();

        token.approve(PERMIT2, tokenBudget);
        IPermit2Mainnet(PERMIT2).approve(TOKEN, POSITION_MANAGER, uint160(tokenBudget), type(uint48).max);

        bytes memory unlockData = _mintBurnedLpUnlockData(poolKey, liquidity, uint128(tokenBudget), deployer);
        IMainnetPositionManager(POSITION_MANAGER).modifyLiquidities{value: SEED_LP_ETH}(
            unlockData, block.timestamp + 20 minutes
        );

        vm.stopBroadcast();

        console2.log("ARCADE_STARTED_DEPLOYER", deployer);
        console2.log("ARCADE_STARTED_LAUNCHER", LAUNCHER);
        console2.log("ARCADE_STARTED_TOKEN", TOKEN);
        console2.log("ARCADE_STARTED_HOOK", HOOK);
        console2.log("ARCADE_SEED_BUY_ETH_WEI", SEED_BUY_ETH);
        console2.log("ARCADE_SEED_TOKEN_OUT", seedTokenOut);
        console2.log("ARCADE_LP_ETH_WEI", SEED_LP_ETH);
        console2.log("ARCADE_LP_TOKEN_MAX", tokenBudget);
        console2.log("ARCADE_LP_LIQUIDITY", uint256(liquidity));
        console2.log("ARCADE_LP_NFT_RECIPIENT", BLACKHOLE);
    }

    function _poolKey() private pure returns (PoolKey memory poolKey) {
        poolKey = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(TOKEN),
            fee: V4_POOL_FEE,
            tickSpacing: V4_TICK_SPACING,
            hooks: IHooks(HOOK)
        });
    }

    function _mintBurnedLpUnlockData(
        PoolKey memory poolKey,
        uint128 liquidity,
        uint128 tokenMax,
        address refundRecipient
    ) private view returns (bytes memory) {
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            poolKey,
            TickMath.minUsableTick(poolKey.tickSpacing),
            TickMath.maxUsableTick(poolKey.tickSpacing),
            uint256(liquidity),
            uint128(SEED_LP_ETH),
            tokenMax,
            BLACKHOLE,
            abi.encode(FTMonsterArcadeV4Hook(HOOK).NO_LP_CLUB_HOOK_DATA())
        );
        params[1] = abi.encode(address(0), TOKEN);
        params[2] = abi.encode(address(0), refundRecipient);
        return abi.encode(hex"020d14", params);
    }
}
