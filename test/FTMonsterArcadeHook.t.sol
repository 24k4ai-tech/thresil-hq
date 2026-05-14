// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {FTMonsterArcadeLauncher} from "../src/FTMonsterArcadeLauncher.sol";
import {FTMonsterArcadeToken} from "../src/FTMonsterArcadeToken.sol";
import {FTMonsterLastBuyerPot} from "../src/FTMonsterLastBuyerPot.sol";
import {FTMonsterPenaltyDraw} from "../src/FTMonsterPenaltyDraw.sol";
import {FTMonsterArcadeLPClub} from "../src/FTMonsterArcadeLPClub.sol";
import {FTMonsterArcadeV4Hook} from "../src/FTMonsterArcadeV4Hook.sol";
import {FTMonsterArcadeHookDeployer} from "../src/FTMonsterArcadeHookDeployer.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "v4-core/types/BalanceDelta.sol";

contract FTMonsterArcadeHookTest is Test {
    address internal constant TAX_WALLET = address(0xD37);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant POSITION_MANAGER = address(0x4444);
    uint160 internal constant HOOK_MASK = uint160((1 << 14) - 1);
    uint160 internal constant REQUIRED_HOOK_BITS = 0x05CC;

    FTMonsterArcadeLauncher internal launcher;
    FTMonsterArcadeToken internal token;
    FTMonsterLastBuyerPot internal jackpot;
    FTMonsterPenaltyDraw internal penaltyDraw;
    FTMonsterArcadeLPClub internal lpClub;
    FTMonsterArcadeV4Hook internal hook;
    MockArcadePoolManager internal poolManager;

    function setUp() public {
        launcher = new FTMonsterArcadeLauncher(TAX_WALLET);
        token = launcher.token();
        jackpot = new FTMonsterLastBuyerPot(address(0));
        penaltyDraw = new FTMonsterPenaltyDraw(token);
        poolManager = new MockArcadePoolManager();
        vm.deal(address(poolManager), 100 ether);

        FTMonsterArcadeV4Hook.Config memory config = FTMonsterArcadeV4Hook.Config({
            poolManager: IPoolManager(address(poolManager)),
            token: token,
            jackpot: address(jackpot),
            penaltyDraw: address(penaltyDraw),
            launcher: address(launcher)
        });
        FTMonsterArcadeHookDeployer hookDeployer = new FTMonsterArcadeHookDeployer();
        hook = hookDeployer.deploy(_findHookSalt(hookDeployer, config), config);
        lpClub = new FTMonsterArcadeLPClub(address(hook));

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
    }

    function testOfficialLpHookDataTracksAndUntracksOwner() public {
        bytes memory hookData = abi.encode(ALICE);

        vm.prank(address(poolManager));
        hook.afterAddLiquidity(
            ALICE,
            _poolKey(),
            _liquidityParams(1, 1000),
            toBalanceDelta(-_toInt128(1 ether), -_toInt128(1000e18)),
            BalanceDeltaLibrary.ZERO_DELTA,
            hookData
        );

        assertEq(hook.trackedLiquidityEth(), 1 ether);
        assertEq(lpClub.totalTrackedEth(), 1 ether);
        assertEq(lpClub.trackedEthByAccount(ALICE), 1 ether);

        vm.prank(address(poolManager));
        hook.afterRemoveLiquidity(
            ALICE,
            _poolKey(),
            _liquidityParams(1, -400),
            toBalanceDelta(_toInt128(0.4 ether), 0),
            BalanceDeltaLibrary.ZERO_DELTA,
            hookData
        );

        assertEq(hook.trackedLiquidityEth(), 0.6 ether);
        assertEq(lpClub.totalTrackedEth(), 0.6 ether);
        assertEq(lpClub.trackedEthByAccount(ALICE), 0.6 ether);
    }

    function testRemoveUsesRecordedPositionBeneficiaryNotSpoofedHookData() public {
        bytes memory aliceHookData = abi.encode(ALICE);
        bytes memory bobHookData = abi.encode(BOB);

        vm.prank(address(poolManager));
        hook.afterAddLiquidity(
            POSITION_MANAGER,
            _poolKey(),
            _liquidityParams(2, 1000),
            toBalanceDelta(-_toInt128(1 ether), -_toInt128(1000e18)),
            BalanceDeltaLibrary.ZERO_DELTA,
            aliceHookData
        );

        vm.prank(address(poolManager));
        hook.afterRemoveLiquidity(
            POSITION_MANAGER,
            _poolKey(),
            _liquidityParams(2, -400),
            toBalanceDelta(_toInt128(0.4 ether), 0),
            BalanceDeltaLibrary.ZERO_DELTA,
            bobHookData
        );

        assertEq(lpClub.trackedEthByAccount(ALICE), 0.6 ether);
        assertEq(lpClub.trackedEthByAccount(BOB), 0);
        assertEq(lpClub.totalTrackedEth(), 0.6 ether);
    }

    function testDevBurnedSeedLpCanOptOutOfLPClubRewards() public {
        bytes32 noLpClubAccounting = hook.NO_LP_CLUB_HOOK_DATA();

        vm.prank(address(poolManager));
        hook.afterAddLiquidity(
            POSITION_MANAGER,
            _poolKey(),
            _liquidityParams(3, 1000),
            toBalanceDelta(-_toInt128(0.001 ether), -_toInt128(1000e18)),
            BalanceDeltaLibrary.ZERO_DELTA,
            abi.encode(noLpClubAccounting)
        );

        assertEq(hook.trackedLiquidityEth(), 0.001 ether);
        assertEq(lpClub.totalTrackedEth(), 0);
        assertEq(lpClub.trackedEthByAccount(ALICE), 0);
    }

    function testSingleSidedEthLiquidityDoesNotEarnLPClubRewards() public {
        vm.prank(address(poolManager));
        hook.afterAddLiquidity(
            POSITION_MANAGER,
            _poolKey(),
            _liquidityParams(4, 1000),
            toBalanceDelta(-_toInt128(1 ether), 0),
            BalanceDeltaLibrary.ZERO_DELTA,
            abi.encode(ALICE)
        );

        assertEq(hook.trackedLiquidityEth(), 1 ether);
        assertEq(lpClub.totalTrackedEth(), 0);
        assertEq(lpClub.trackedEthByAccount(ALICE), 0);
    }

    function testSellFuseShareSplitsBetweenLpClubAndDraw() public {
        vm.prank(address(poolManager));
        hook.afterSwap(
            ALICE,
            _poolKey(),
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -int256(1 ether), sqrtPriceLimitX96: 0}),
            toBalanceDelta(-_toInt128(1 ether), _toInt128(1e18)),
            abi.encode(ALICE)
        );

        uint256 taxBefore = TAX_WALLET.balance;
        uint256 jackpotBefore = address(jackpot).balance;
        uint256 drawBefore = address(penaltyDraw).balance;
        uint256 lpClubBefore = address(lpClub).balance;

        vm.prank(address(poolManager));
        (bytes4 selector, int128 hookDelta) = hook.afterSwap(
            ALICE,
            _poolKey(),
            IPoolManager.SwapParams({zeroForOne: false, amountSpecified: -int256(1e18), sqrtPriceLimitX96: 0}),
            toBalanceDelta(_toInt128(0.3 ether), -_toInt128(1e18)),
            abi.encode(ALICE)
        );

        uint256 amount = 0.3 ether;
        uint256 apiFee = (amount * launcher.currentApiFeeBps()) / 10_000;
        uint256 jackpotFee = (amount * launcher.currentJackpotFeeBps()) / 10_000;
        uint256 lpClubFee = (amount * launcher.currentLpClubFeeBps()) / 10_000;
        uint256 drawFee = (amount * launcher.currentPenaltyDrawFeeBps()) / 10_000;
        uint256 fuseFee = (amount * launcher.FUSE_TIER_THREE_BPS()) / 10_000;
        uint256 lpFuseShare = (fuseFee * launcher.fuseLpShareBps()) / 10_000;
        uint256 drawFuseShare = fuseFee - lpFuseShare;

        assertEq(selector, hook.afterSwap.selector);
        assertEq(int256(hookDelta), int256(apiFee + jackpotFee + lpClubFee + drawFee + fuseFee));
        assertEq(TAX_WALLET.balance - taxBefore, apiFee);
        assertEq(address(jackpot).balance - jackpotBefore, jackpotFee);
        assertEq(address(lpClub).balance - lpClubBefore, lpClubFee + lpFuseShare);
        assertEq(address(penaltyDraw).balance - drawBefore, drawFee + drawFuseShare);
    }

    function _poolKey() internal view returns (PoolKey memory key) {
        key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(token)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
    }

    function _liquidityParams(uint256 salt, int256 liquidityDelta)
        internal
        pure
        returns (IPoolManager.ModifyLiquidityParams memory params)
    {
        params = IPoolManager.ModifyLiquidityParams({
            tickLower: -887220, tickUpper: 887220, liquidityDelta: liquidityDelta, salt: bytes32(salt)
        });
    }

    function _findHookSalt(FTMonsterArcadeHookDeployer hookDeployer, FTMonsterArcadeV4Hook.Config memory config)
        internal
        view
        returns (bytes32 salt)
    {
        bytes32 initCodeHash = keccak256(abi.encodePacked(type(FTMonsterArcadeV4Hook).creationCode, abi.encode(config)));
        for (uint256 i = 0; i < 1_000_000; ++i) {
            salt = bytes32(i);
            address predicted = address(
                uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(hookDeployer), salt, initCodeHash))))
            );
            if ((uint160(predicted) & HOOK_MASK) == REQUIRED_HOOK_BITS) return salt;
        }
        revert("hook salt not found");
    }

    function _toInt128(uint256 amount) internal pure returns (int128) {
        return int128(int256(amount));
    }
}

contract MockArcadePoolManager {
    function take(Currency currency, address to, uint256 amount) external {
        if (Currency.unwrap(currency) == address(0)) {
            (bool ok,) = payable(to).call{value: amount}("");
            require(ok, "take");
        } else {
            revert("token-take-disabled");
        }
    }

    receive() external payable {}
}
