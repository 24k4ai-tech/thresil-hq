// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FTMonsterArcadeToken} from "./FTMonsterArcadeToken.sol";
import {IFTMonsterArcadeLauncher} from "./interfaces/IFTMonsterArcadeLauncher.sol";
import {IFTMonsterLastBuyerPot} from "./interfaces/IFTMonsterLastBuyerPot.sol";
import {IFTMonsterPenaltyDraw} from "./interfaces/IFTMonsterPenaltyDraw.sol";
import {IFTMonsterArcadeLPClub} from "./interfaces/IFTMonsterArcadeLPClub.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {FullMath} from "v4-core/libraries/FullMath.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";

/// @title FTMonsterArcadeV4Hook
/// @notice V4 hook for the canonical WETH-native / Oracle777 pool.
contract FTMonsterArcadeV4Hook {
    using BalanceDeltaLibrary for BalanceDelta;

    struct Config {
        IPoolManager poolManager;
        FTMonsterArcadeToken token;
        address jackpot;
        address penaltyDraw;
        address launcher;
    }

    uint160 public constant ALL_HOOK_MASK = uint160((1 << 14) - 1);
    uint160 public constant AFTER_ADD_LIQUIDITY_FLAG = 1 << 10;
    uint160 public constant AFTER_REMOVE_LIQUIDITY_FLAG = 1 << 8;
    uint160 public constant BEFORE_SWAP_FLAG = 1 << 7;
    uint160 public constant AFTER_SWAP_FLAG = 1 << 6;
    uint160 public constant BEFORE_SWAP_RETURNS_DELTA_FLAG = 1 << 3;
    uint160 public constant AFTER_SWAP_RETURNS_DELTA_FLAG = 1 << 2;
    uint160 public constant REQUIRED_HOOK_FLAGS = AFTER_ADD_LIQUIDITY_FLAG | AFTER_REMOVE_LIQUIDITY_FLAG
        | BEFORE_SWAP_FLAG | AFTER_SWAP_FLAG | BEFORE_SWAP_RETURNS_DELTA_FLAG | AFTER_SWAP_RETURNS_DELTA_FLAG;

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint24 public constant POOL_FEE = 3000;
    int24 public constant TICK_SPACING = 60;
    uint256 public constant RAPID_FUSE_PHASE = 6 hours;
    uint256 public constant RAPID_FUSE_WINDOW = 30 minutes;
    uint256 public constant SLOW_FUSE_WINDOW = 3 hours;
    uint256 public constant FUSE_TIER_ONE_BPS = 500;
    uint256 public constant FUSE_TIER_TWO_BPS = 1_000;
    uint256 public constant FUSE_TIER_THREE_BPS = 1_500;
    bytes32 public constant NO_LP_CLUB_HOOK_DATA = bytes32(type(uint256).max);
    uint256 private constant WAD = 1e18;

    IPoolManager public immutable poolManager;
    FTMonsterArcadeToken public immutable token;
    IFTMonsterLastBuyerPot public immutable jackpot;
    IFTMonsterPenaltyDraw public immutable penaltyDraw;
    IFTMonsterArcadeLauncher public immutable launcher;

    uint256 public immutable genesisBlock;
    bytes32 public immutable genesisHash;

    uint256 public launchTimestamp;
    bool public launched;
    uint256 public trackedLiquidityEth;
    uint256 public poolFuseWindowStart;
    uint256 public poolFuseWindowHighPrice;

    mapping(bytes32 positionId => address beneficiary) public positionBeneficiary;
    mapping(bytes32 positionId => uint256 trackedEth) public positionTrackedEth;
    mapping(bytes32 positionId => uint256 liquidity) public positionLiquidity;

    event ApiFee(uint256 ethFee);
    event JackpotFee(uint256 ethFee);
    event PenaltyDrawFee(uint256 ethFee);
    event LPClubFee(uint256 ethFee);
    event TrackedLiquidityChanged(uint256 previousValue, uint256 newValue);
    event HookLaunched(uint256 indexed launchTimestamp);
    event PoolFuseWindowSynced(uint256 windowStart, uint256 highPrice, uint256 windowSeconds);

    error NotPoolManager();
    error NotLauncher();
    error InvalidPool();
    error InvalidHookAddress();
    error ExactOutputUnsupported();
    error ZeroAddress();
    error LaunchNotActive();
    error AlreadyLaunched();

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    constructor(Config memory config) {
        if ((uint160(address(this)) & ALL_HOOK_MASK) != REQUIRED_HOOK_FLAGS) {
            revert InvalidHookAddress();
        }
        if (config.jackpot == address(0) || config.penaltyDraw == address(0) || config.launcher == address(0)) {
            revert ZeroAddress();
        }
        poolManager = config.poolManager;
        token = config.token;
        jackpot = IFTMonsterLastBuyerPot(config.jackpot);
        penaltyDraw = IFTMonsterPenaltyDraw(config.penaltyDraw);
        launcher = IFTMonsterArcadeLauncher(config.launcher);
        genesisBlock = block.number;
        genesisHash = blockhash(block.number - 1);
    }

    function getHookPermissions() external pure returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: true,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function launchFromLauncher(uint256 launchTimestamp_) external {
        if (msg.sender != address(launcher)) revert NotLauncher();
        if (launched) revert AlreadyLaunched();
        if (launchTimestamp_ == 0) revert ZeroAddress();
        launched = true;
        launchTimestamp = launchTimestamp_;
        poolFuseWindowStart = launchTimestamp_;
        emit HookLaunched(launchTimestamp_);
    }

    function afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta feesAccrued,
        bytes calldata data
    ) external onlyPoolManager returns (bytes4, BalanceDelta) {
        _validatePool(key);
        _requireLaunched();

        _trackLiquidityAdded(sender, params, delta - feesAccrued, data);
        return (this.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    function afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta feesAccrued,
        bytes calldata
    ) external onlyPoolManager returns (bytes4, BalanceDelta) {
        _validatePool(key);
        _requireLaunched();

        _trackLiquidityRemoved(sender, params, delta - feesAccrued);
        return (this.afterRemoveLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    function _trackLiquidityAdded(
        address sender,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta principalDelta,
        bytes calldata data
    ) internal {
        uint256 ethAdded = _owedAmount(principalDelta.amount0());
        if (ethAdded > 0) {
            uint256 previous = trackedLiquidityEth;
            trackedLiquidityEth = previous + ethAdded;
            emit TrackedLiquidityChanged(previous, trackedLiquidityEth);
            uint256 tokenAdded = _owedAmount(principalDelta.amount1());
            uint256 eligibleEth = tokenAdded == 0 ? 0 : ethAdded;
            _syncLPClubPosition(
                _liquidityBeneficiary(sender, params.salt, data),
                _positionId(sender, params),
                _positiveInt(params.liquidityDelta),
                eligibleEth,
                true
            );
        }
    }

    function _trackLiquidityRemoved(
        address sender,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta principalDelta
    ) internal {
        uint256 ethRemoved = _receivedAmount(principalDelta.amount0());
        if (ethRemoved > 0) {
            uint256 previous = trackedLiquidityEth;
            trackedLiquidityEth = ethRemoved >= previous ? 0 : previous - ethRemoved;
            emit TrackedLiquidityChanged(previous, trackedLiquidityEth);
            _syncLPClubPosition(address(0), _positionId(sender, params), _negativeInt(params.liquidityDelta), 0, false);
        }
    }

    function beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) external onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24) {
        _validatePool(key);
        _requireLaunched();
        if (params.amountSpecified >= 0) revert ExactOutputUnsupported();

        if (!params.zeroForOne) {
            return (this.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);
        }

        uint256 ethIn = _absNegativeInt(params.amountSpecified);
        jackpot.settleIfReady();
        penaltyDraw.settleIfReady();

        uint256 apiFee = _fee(ethIn, launcher.currentApiFeeBps());
        uint256 jackpotFee = _fee(ethIn, launcher.currentJackpotFeeBps());
        uint256 lpClubFee = _fee(ethIn, launcher.currentLpClubFeeBps());
        uint256 drawFee = _fee(ethIn, launcher.currentPenaltyDrawFeeBps());
        uint256 lpClubPaid = _routeLpClubFee(lpClubFee);

        if (apiFee > 0) {
            poolManager.take(Currency.wrap(address(0)), launcher.apiFeeWallet(), apiFee);
            emit ApiFee(apiFee);
        }
        if (jackpotFee + (lpClubFee - lpClubPaid) > 0) {
            poolManager.take(Currency.wrap(address(0)), address(jackpot), jackpotFee + (lpClubFee - lpClubPaid));
            emit JackpotFee(jackpotFee + (lpClubFee - lpClubPaid));
        }
        if (lpClubPaid > 0) {
            emit LPClubFee(lpClubPaid);
        }
        if (drawFee > 0) {
            poolManager.take(Currency.wrap(address(0)), address(penaltyDraw), drawFee);
            emit PenaltyDrawFee(drawFee);
        }

        address buyer = _swapper(sender, hookData);
        jackpot.recordEffectiveBuy(buyer, ethIn);
        return (this.beforeSwap.selector, toBeforeSwapDelta(_toInt128(apiFee + jackpotFee + lpClubFee + drawFee), 0), 0);
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) external onlyPoolManager returns (bytes4, int128) {
        _validatePool(key);
        _requireLaunched();

        if (params.zeroForOne) {
            uint256 ethIn = uint256(-params.amountSpecified);
            uint256 tokenOut = _receivedAmount(delta.amount1());
            uint256 buyObservedPrice = _observedPrice(ethIn - _fee(ethIn, launcher.currentTotalFeeBps()), tokenOut);
            _syncPoolFuseWindow(buyObservedPrice, buyObservedPrice);
            return (this.afterSwap.selector, 0);
        }

        int128 ethOut = delta.amount0();
        if (ethOut <= 0) return (this.afterSwap.selector, 0);

        jackpot.settleIfReady();
        penaltyDraw.settleIfReady();

        uint256 amount = _receivedAmount(ethOut);
        uint256 tokenIn = _absNegativeInt(params.amountSpecified);
        uint256 observedPrice = _observedPrice(amount, tokenIn);
        (, uint256 windowHigh) = _effectivePoolFuseWindow(observedPrice);
        uint256 fuseFeeBps = _fuseSurchargeBps(windowHigh, observedPrice);
        uint256 apiFee = _fee(amount, launcher.currentApiFeeBps());
        uint256 jackpotFee = _fee(amount, launcher.currentJackpotFeeBps());
        uint256 lpClubFee = _fee(amount, launcher.currentLpClubFeeBps());
        uint256 drawFee = _fee(amount, launcher.currentPenaltyDrawFeeBps());
        uint256 fuseFee = _fee(amount, fuseFeeBps);
        uint256 lpClubPaid = _routeLpClubFee(lpClubFee);

        if (apiFee > 0) {
            poolManager.take(Currency.wrap(address(0)), launcher.apiFeeWallet(), apiFee);
            emit ApiFee(apiFee);
        }
        if (jackpotFee + (lpClubFee - lpClubPaid) > 0) {
            poolManager.take(Currency.wrap(address(0)), address(jackpot), jackpotFee + (lpClubFee - lpClubPaid));
            emit JackpotFee(jackpotFee + (lpClubFee - lpClubPaid));
        }
        if (lpClubPaid > 0) {
            emit LPClubFee(lpClubPaid);
        }
        if (drawFee > 0) {
            poolManager.take(Currency.wrap(address(0)), address(penaltyDraw), drawFee);
            emit PenaltyDrawFee(drawFee);
        }
        if (fuseFee > 0) {
            uint256 lpFuseReward = (fuseFee * launcher.fuseLpShareBps()) / BPS_DENOMINATOR;
            uint256 drawFuseReward = fuseFee - lpFuseReward;
            address lpClubAddress = launcher.lpClub();
            if (lpFuseReward > 0 && lpClubAddress != address(0)) {
                poolManager.take(Currency.wrap(address(0)), lpClubAddress, lpFuseReward);
            } else {
                drawFuseReward += lpFuseReward;
            }
            if (drawFuseReward > 0) {
                poolManager.take(Currency.wrap(address(0)), address(penaltyDraw), drawFuseReward);
                emit PenaltyDrawFee(drawFuseReward);
            }
        }

        _syncPoolFuseWindow(observedPrice, observedPrice);

        return (this.afterSwap.selector, _toInt128(apiFee + jackpotFee + lpClubFee + drawFee + fuseFee));
    }

    function _validatePool(PoolKey calldata key) internal view {
        if (
            Currency.unwrap(key.currency0) != address(0) || Currency.unwrap(key.currency1) != address(token)
                || key.fee != POOL_FEE || key.tickSpacing != TICK_SPACING || address(key.hooks) != address(this)
        ) {
            revert InvalidPool();
        }
    }

    function _swapper(address sender, bytes calldata hookData) internal view returns (address) {
        if (hookData.length >= 32) {
            bytes32 firstWord = _hookDataFirstWord(hookData);
            if (uint256(firstWord) >> 160 == 0) {
                address account = address(uint160(uint256(firstWord)));
                if (account != address(0)) return account;
            }
        }
        if (tx.origin != address(0)) return tx.origin;
        return sender;
    }

    function _liquidityBeneficiary(address sender, bytes32 salt, bytes calldata hookData)
        internal
        view
        returns (address account)
    {
        if (hookData.length >= 32) {
            bytes32 firstWord = _hookDataFirstWord(hookData);
            if (firstWord == NO_LP_CLUB_HOOK_DATA) return address(0);
            account = _addressFromWord(firstWord);
            if (account != address(0)) return account;
        }
        if (tx.origin != address(0)) return tx.origin;
        account = _addressFromWord(salt);
        if (account != address(0)) return account;
        return sender;
    }

    function _hookDataFirstWord(bytes calldata hookData) internal pure returns (bytes32 firstWord) {
        assembly ("memory-safe") {
            firstWord := calldataload(hookData.offset)
        }
    }

    function _addressFromWord(bytes32 word) internal pure returns (address account) {
        if (uint256(word) >> 160 != 0) return address(0);
        return address(uint160(uint256(word)));
    }

    function _positionId(address sender, IPoolManager.ModifyLiquidityParams calldata params)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(sender, params.tickLower, params.tickUpper, params.salt));
    }

    function _syncLPClubPosition(
        address account,
        bytes32 positionId,
        uint256 liquidityAmount,
        uint256 ethAmount,
        bool adding
    ) internal {
        if (liquidityAmount == 0) return;

        address lpClubAddress = launcher.lpClub();
        if (adding) {
            if (account == address(0) || ethAmount == 0 || lpClubAddress == address(0)) return;

            address creditedBeneficiary = positionBeneficiary[positionId];
            if (creditedBeneficiary == address(0)) {
                positionBeneficiary[positionId] = account;
                creditedBeneficiary = account;
            } else if (creditedBeneficiary != account) {
                _moveLPClubTrackedEth(lpClubAddress, creditedBeneficiary, account, positionTrackedEth[positionId]);
                positionBeneficiary[positionId] = account;
                creditedBeneficiary = account;
            }

            positionLiquidity[positionId] += liquidityAmount;
            positionTrackedEth[positionId] += ethAmount;
            IFTMonsterArcadeLPClub(lpClubAddress).recordLiquidityAdded(creditedBeneficiary, ethAmount);
            return;
        }

        address beneficiary = positionBeneficiary[positionId];
        uint256 oldTrackedEth = positionTrackedEth[positionId];
        uint256 oldLiquidity = positionLiquidity[positionId];
        if (beneficiary == address(0) || oldTrackedEth == 0 || oldLiquidity == 0 || lpClubAddress == address(0)) {
            return;
        }

        uint256 removedLiquidity = liquidityAmount > oldLiquidity ? oldLiquidity : liquidityAmount;
        uint256 removedEth = removedLiquidity == oldLiquidity
            ? oldTrackedEth
            : FullMath.mulDiv(oldTrackedEth, removedLiquidity, oldLiquidity);
        if (removedEth == 0) return;

        uint256 newTrackedEth = oldTrackedEth - removedEth;
        uint256 newLiquidity = oldLiquidity - removedLiquidity;
        positionTrackedEth[positionId] = newTrackedEth;
        positionLiquidity[positionId] = newLiquidity;
        if (newTrackedEth == 0 || newLiquidity == 0) {
            delete positionBeneficiary[positionId];
            delete positionTrackedEth[positionId];
            delete positionLiquidity[positionId];
        }
        IFTMonsterArcadeLPClub(lpClubAddress).recordLiquidityRemoved(beneficiary, removedEth);
    }

    function _moveLPClubTrackedEth(address lpClubAddress, address from, address to, uint256 amount) internal {
        if (amount == 0 || from == to) return;
        IFTMonsterArcadeLPClub(lpClubAddress).recordLiquidityRemoved(from, amount);
        IFTMonsterArcadeLPClub(lpClubAddress).recordLiquidityAdded(to, amount);
    }

    function _fee(uint256 amount, uint256 bps) internal pure returns (uint256) {
        return (amount * bps) / BPS_DENOMINATOR;
    }

    function _routeLpClubFee(uint256 amount) internal returns (uint256 paid) {
        address lpClubAddress = launcher.lpClub();
        if (amount == 0 || lpClubAddress == address(0)) return 0;
        poolManager.take(Currency.wrap(address(0)), lpClubAddress, amount);
        return amount;
    }

    function _observedPrice(uint256 ethAmount, uint256 tokenAmount) internal pure returns (uint256) {
        if (ethAmount == 0 || tokenAmount == 0) return 0;
        return FullMath.mulDiv(ethAmount, WAD, tokenAmount);
    }

    function _currentFuseWindowSeconds() internal view returns (uint256) {
        if (!launched || block.timestamp < launchTimestamp + RAPID_FUSE_PHASE) return RAPID_FUSE_WINDOW;
        return SLOW_FUSE_WINDOW;
    }

    function _effectivePoolFuseWindow(uint256 referencePrice)
        internal
        view
        returns (uint256 windowStart, uint256 highPrice)
    {
        uint256 activeWindow = _currentFuseWindowSeconds();
        windowStart = poolFuseWindowStart;
        highPrice = poolFuseWindowHighPrice;

        if (windowStart == 0 || highPrice == 0 || referencePrice == 0) {
            return (block.timestamp, referencePrice);
        }

        uint256 phaseBoundary = launchTimestamp + RAPID_FUSE_PHASE;
        bool crossedPhaseBoundary =
            activeWindow == SLOW_FUSE_WINDOW && windowStart < phaseBoundary && block.timestamp >= phaseBoundary;
        bool expired = block.timestamp >= windowStart + activeWindow;
        if (crossedPhaseBoundary || expired) {
            return (block.timestamp, referencePrice);
        }

        if (referencePrice > highPrice) highPrice = referencePrice;
    }

    function _syncPoolFuseWindow(uint256 referencePrice, uint256 observedPrice) internal {
        if (referencePrice == 0 && observedPrice == 0) return;
        (uint256 nextStart, uint256 nextHigh) = _effectivePoolFuseWindow(referencePrice);
        if (observedPrice > nextHigh) nextHigh = observedPrice;
        if (nextStart != poolFuseWindowStart || nextHigh != poolFuseWindowHighPrice) {
            poolFuseWindowStart = nextStart;
            poolFuseWindowHighPrice = nextHigh;
            emit PoolFuseWindowSynced(nextStart, nextHigh, _currentFuseWindowSeconds());
        }
    }

    function _fuseSurchargeBps(uint256 highPrice, uint256 priceToCheck) internal pure returns (uint256) {
        if (highPrice == 0 || priceToCheck == 0) return 0;
        uint256 ratioBps = FullMath.mulDiv(priceToCheck, BPS_DENOMINATOR, highPrice);
        if (ratioBps >= 9_000) return 0;
        if (ratioBps >= 8_000) return FUSE_TIER_ONE_BPS;
        if (ratioBps >= 4_000) return FUSE_TIER_TWO_BPS;
        return FUSE_TIER_THREE_BPS;
    }

    function _requireLaunched() internal view {
        if (!launched) revert LaunchNotActive();
    }

    function _owedAmount(int128 amount) internal pure returns (uint256) {
        if (amount >= 0) return 0;
        return _absNegativeInt128(amount);
    }

    function _receivedAmount(int128 amount) internal pure returns (uint256) {
        if (amount <= 0) return 0;
        return _positiveInt128(amount);
    }

    function _positiveInt(int256 amount) internal pure returns (uint256) {
        if (amount <= 0) return 0;
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint256(amount);
    }

    function _negativeInt(int256 amount) internal pure returns (uint256) {
        if (amount >= 0) return 0;
        return _absNegativeInt(amount);
    }

    function _toInt128(uint256 value) internal pure returns (int128 casted) {
        require(value <= uint256(uint128(type(int128).max)), "int128");
        // forge-lint: disable-next-line(unsafe-typecast)
        casted = int128(uint128(value));
    }

    function _positiveInt128(int128 amount) internal pure returns (uint256) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint256(uint128(amount));
    }

    function _absNegativeInt128(int128 amount) internal pure returns (uint256) {
        require(amount < 0, "negative");
        int128 safeNegative = -(amount + 1);
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint256(uint128(safeNegative)) + 1;
    }

    function _absNegativeInt(int256 amount) internal pure returns (uint256) {
        require(amount < 0, "negative");
        int256 safeNegative = -(amount + 1);
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint256(safeNegative) + 1;
    }
}
