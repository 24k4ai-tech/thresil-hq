// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FullMath} from "v4-core/libraries/FullMath.sol";
import {FTMonsterArcadeToken} from "../FTMonsterArcadeToken.sol";
import {FTMonsterLastBuyerPotFast} from "./FTMonsterLastBuyerPotFast.sol";
import {FTMonsterPenaltyDrawFast} from "./FTMonsterPenaltyDrawFast.sol";
import {FTMonsterArcadeLPClub} from "../FTMonsterArcadeLPClub.sol";

interface IFTMonsterLaunchReceiver {
    function launchFromLauncher(uint256 launchTimestamp) external;
}

interface IExternalBalanceToken {
    function balanceOf(address account) external view returns (uint256);
}

/// @title FTMonsterArcadeLauncherFast
/// @notice Testnet fast launcher with the same mechanics but compressed timers.
contract FTMonsterArcadeLauncherFast {
    using FullMath for uint256;

    struct SellQuote {
        uint256 ethOut;
        uint256 apiFee;
        uint256 jackpotFee;
        uint256 drawFee;
        uint256 fuseFee;
        uint256 nextCurveEth;
        uint256 reserveDebit;
        uint256 grossEthOut;
        uint256 fuseFeeBps;
    }

    string public constant website = "https://www.777x.space/";
    string public constant description =
        "Oracle777 keeps the SATO reserve rail first, runs a last-buyer pot on every valid buy, gives SOTO holders a free mint lane, and routes panic taxes into the penalty draw.";
    string public constant aiIdentity =
        "Oracle777 is a football arcade curve: buy 777X, hold the last-buyer spot, add official LP, or burn to enter the penalty draw.";
    string public constant projectWebsite = "https://www.777x.space/";
    string public constant projectGithub = "https://github.com/24k4ai-tech/thresil-hq";
    string public constant projectImage = "https://www.777x.space/assets/oracle777-og-card-wide.jpg";

    uint256 public constant TOTAL_SUPPLY = 210_000_000_000 * 1e18;
    uint256 public constant CLAIM_ALLOCATION = (TOTAL_SUPPLY * 3) / 100;
    uint256 public constant CLAIM_MAX_WALLETS = 7_777;
    uint256 public constant CLAIM_SHARE = CLAIM_ALLOCATION / CLAIM_MAX_WALLETS;
    uint256 public constant CURVE_ALLOCATION = TOTAL_SUPPLY - CLAIM_ALLOCATION;
    uint256 public constant CURVE_CLOSE_GROSS_ETH = 0.17 ether;
    uint256 public constant CURVE_CLOSE_NET_ETH = 167_161_000_000_000_000;
    uint256 public constant API_FEE_BPS_EARLY = 100;
    uint256 public constant MAX_POST_WINDOW_API_FEE_BPS = 13;
    uint256 public constant DEFAULT_POST_WINDOW_API_FEE_BPS = 13;
    uint256 public constant JACKPOT_FEE_BPS = 17;
    uint256 public constant LP_CLUB_FEE_BPS = 17;
    uint256 public constant PENALTY_DRAW_FEE_BPS = 33;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant FIXED_API_WINDOW = 77 seconds;
    uint256 public constant RAPID_FUSE_PHASE = 90 seconds;
    uint256 public constant RAPID_FUSE_WINDOW = 30 seconds;
    uint256 public constant SLOW_FUSE_WINDOW = 45 seconds;
    uint256 public constant FUSE_TIER_ONE_BPS = 500;
    uint256 public constant FUSE_TIER_TWO_BPS = 1_000;
    uint256 public constant FUSE_TIER_THREE_BPS = 1_500;
    uint256 public constant FUSE_LP_SHARE_BPS = 2_000;
    address public constant claimSourceToken = 0x829f4B62EEBE12Af653b4dD4fFc480966F7d7f09;

    uint256 private constant WAD = 1e18;
    uint256 private constant LN2_WAD = 693_147_180_559_945_309;
    uint256 private constant LN100_WAD = 4_605_170_185_988_091_368;
    uint256 private constant NORMALIZATION_WAD = 990_000_000_000_000_000;

    FTMonsterArcadeToken public immutable token;
    address public immutable apiFeeWallet;
    uint256 public immutable genesisBlock;
    bytes32 public immutable genesisHash;

    address public owner;
    FTMonsterLastBuyerPotFast public jackpot;
    FTMonsterPenaltyDrawFast public penaltyDraw;
    FTMonsterArcadeLPClub public lpClub;
    address public v4Hook;

    uint256 public launchBlock;
    uint256 public launchTimestamp;
    bool public launched;
    bool public launchFilled;
    uint256 public curveEth;
    uint256 public curveReserve;
    uint256 public postWindowApiFeeBps = DEFAULT_POST_WINDOW_API_FEE_BPS;
    bool public controlsFrozen;
    uint256 public claimedWalletCount;
    uint256 public claimTokensDistributed;
    uint256 public fuseWindowStart;
    uint256 public fuseWindowHighPrice;

    mapping(address account => bool) public hasClaimed;
    bool private locked;

    event OwnerTransferred(address indexed oldOwner, address indexed newOwner);
    event JackpotSet(address indexed jackpot);
    event PenaltyDrawSet(address indexed penaltyDraw);
    event LPClubSet(address indexed lpClub);
    event V4HookSet(address indexed v4Hook);
    event Launched(uint256 indexed launchBlock, uint256 indexed launchTimestamp);
    event GenesisBuy(address indexed buyer, uint256 ethIn, uint256 tokenOut, uint256 ethCost);
    event GenesisSell(
        address indexed seller,
        uint256 tokenIn,
        uint256 ethOut,
        uint256 grossEthOut,
        uint256 fuseFee,
        uint256 fuseFeeBps
    );
    event ApiFeePaid(uint256 amount);
    event JackpotFeePaid(uint256 amount);
    event PenaltyDrawFeePaid(uint256 amount);
    event LPClubFeePaid(uint256 amount);
    event FreeClaimed(address indexed account, uint256 amount, uint256 indexed claimNumber);
    event PostWindowApiFeeUpdated(uint256 previousBps, uint256 newBps);
    event ControlsFrozen(uint256 finalApiFeeBps);
    event FuseWindowSynced(uint256 windowStart, uint256 highPrice, uint256 windowSeconds);

    error NotOwner();
    error ZeroAddress();
    error AlreadyLaunched();
    error LaunchNotReady();
    error HookAlreadySet();
    error JackpotAlreadySet();
    error PenaltyDrawAlreadySet();
    error LPClubAlreadySet();
    error NoEth();
    error NoToken();
    error GenesisSoldOut();
    error InsufficientCurveLiquidity();
    error InsufficientEthOut();
    error RefundFailed();
    error PayoutFailed();
    error AlreadyClaimed();
    error ClaimClosed();
    error NotEligible();
    error TooEarly();
    error FeeTooHigh();
    error Frozen();
    error Reentrancy();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier nonReentrant() {
        if (locked) revert Reentrancy();
        locked = true;
        _;
        locked = false;
    }

    constructor(address apiFeeWallet_) {
        if (apiFeeWallet_ == address(0)) revert ZeroAddress();
        owner = msg.sender;
        apiFeeWallet = apiFeeWallet_;
        genesisBlock = block.number;
        genesisHash = blockhash(block.number - 1);
        token = new FTMonsterArcadeToken(address(this));
        emit OwnerTransferred(address(0), msg.sender);
    }

    function setJackpot(address jackpot_) external onlyOwner {
        if (address(jackpot) != address(0)) revert JackpotAlreadySet();
        if (jackpot_ == address(0)) revert ZeroAddress();
        jackpot = FTMonsterLastBuyerPotFast(payable(jackpot_));
        emit JackpotSet(jackpot_);
    }

    function setPenaltyDraw(address penaltyDraw_) external onlyOwner {
        if (address(penaltyDraw) != address(0)) revert PenaltyDrawAlreadySet();
        if (penaltyDraw_ == address(0)) revert ZeroAddress();
        penaltyDraw = FTMonsterPenaltyDrawFast(payable(penaltyDraw_));
        emit PenaltyDrawSet(penaltyDraw_);
    }

    function setLPClub(address lpClub_) external onlyOwner {
        if (address(lpClub) != address(0)) revert LPClubAlreadySet();
        if (lpClub_ == address(0)) revert ZeroAddress();
        lpClub = FTMonsterArcadeLPClub(payable(lpClub_));
        emit LPClubSet(lpClub_);
    }

    function setV4Hook(address v4Hook_) external onlyOwner {
        if (v4Hook != address(0)) revert HookAlreadySet();
        if (v4Hook_ == address(0)) revert ZeroAddress();
        v4Hook = v4Hook_;
        emit V4HookSet(v4Hook_);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnerTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setPostWindowApiFeeBps(uint256 newBps) external onlyOwner {
        if (controlsFrozen) revert Frozen();
        if (!launched || block.timestamp < launchTimestamp + FIXED_API_WINDOW) revert TooEarly();
        if (newBps > MAX_POST_WINDOW_API_FEE_BPS) revert FeeTooHigh();
        uint256 previous = postWindowApiFeeBps;
        postWindowApiFeeBps = newBps;
        emit PostWindowApiFeeUpdated(previous, newBps);
    }

    function freezeAndRenounce(uint256 finalApiFeeBps) external onlyOwner {
        if (!launched || block.timestamp < launchTimestamp + FIXED_API_WINDOW) revert TooEarly();
        if (finalApiFeeBps > MAX_POST_WINDOW_API_FEE_BPS) revert FeeTooHigh();
        uint256 previous = postWindowApiFeeBps;
        postWindowApiFeeBps = finalApiFeeBps;
        controlsFrozen = true;
        emit PostWindowApiFeeUpdated(previous, finalApiFeeBps);
        emit ControlsFrozen(finalApiFeeBps);
        emit OwnerTransferred(owner, address(0));
        owner = address(0);
    }

    function launch() external onlyOwner {
        if (launched) revert AlreadyLaunched();
        if (
            address(jackpot) == address(0) || address(penaltyDraw) == address(0) || address(lpClub) == address(0)
                || v4Hook == address(0) || jackpot.launcher() != address(this) || jackpot.hook() != v4Hook
                || penaltyDraw.launcher() != address(this) || penaltyDraw.hook() != v4Hook
                || address(penaltyDraw.lpClub()) != address(lpClub) || lpClub.hook() != v4Hook
        ) {
            revert LaunchNotReady();
        }
        launched = true;
        launchBlock = block.number;
        launchTimestamp = block.timestamp;
        fuseWindowStart = launchTimestamp;
        fuseWindowHighPrice = _spotPrice(0);
        IFTMonsterLaunchReceiver(v4Hook).launchFromLauncher(launchTimestamp);
        emit FuseWindowSynced(fuseWindowStart, fuseWindowHighPrice, currentFuseWindowSeconds());
        emit Launched(launchBlock, launchTimestamp);
    }

    function claim() external returns (uint256 amount) {
        if (hasClaimed[msg.sender]) revert AlreadyClaimed();
        if (claimedWalletCount >= CLAIM_MAX_WALLETS) revert ClaimClosed();
        if (IExternalBalanceToken(claimSourceToken).balanceOf(msg.sender) == 0) revert NotEligible();

        uint256 remainingClaims = CLAIM_MAX_WALLETS - claimedWalletCount;
        amount = remainingClaims == 1 ? CLAIM_ALLOCATION - claimTokensDistributed : CLAIM_SHARE;

        hasClaimed[msg.sender] = true;
        claimTokensDistributed += amount;
        unchecked {
            ++claimedWalletCount;
        }

        require(token.transfer(msg.sender, amount), "claim");
        emit FreeClaimed(msg.sender, amount, claimedWalletCount);
    }

    function buyGenesis(address to) external payable nonReentrant returns (uint256 tokenOut) {
        if (!launched) revert LaunchNotReady();
        if (msg.value == 0) revert NoEth();
        if (to == address(0)) revert ZeroAddress();

        uint256 userTokenOut;
        uint256 ethCost;
        uint256 netCost;
        (, userTokenOut, ethCost,, netCost) = _quoteBuy(msg.value, currentBaseTotalFeeBps());
        if (userTokenOut == 0) revert GenesisSoldOut();

        _touchGames();

        tokenOut = userTokenOut;
        curveEth += netCost;
        if (curveEth >= CURVE_CLOSE_NET_ETH) {
            curveEth = CURVE_CLOSE_NET_ETH;
            launchFilled = true;
        }
        curveReserve += netCost;

        require(token.transfer(to, userTokenOut), "sale");
        _routeBaseFees(ethCost);
        jackpot.recordEffectiveBuy(to, ethCost);
        _syncFuseWindow(_spotPrice(curveEth), _spotPrice(curveEth));

        uint256 refund = msg.value - ethCost;
        if (refund > 0) {
            (bool refundOk,) = msg.sender.call{value: refund}("");
            if (!refundOk) revert RefundFailed();
        }

        emit GenesisBuy(to, msg.value, tokenOut, ethCost);
    }

    function sellGenesis(uint256 tokenAmount, uint256 minEthOut) external nonReentrant returns (uint256 ethOut) {
        if (!launched) revert LaunchNotReady();
        if (tokenAmount == 0) revert NoToken();

        SellQuote memory quote = _quoteSellDetailed(curveEth, tokenAmount);
        ethOut = quote.ethOut;
        if (quote.ethOut == 0) revert NoEth();
        if (quote.ethOut < minEthOut) revert InsufficientEthOut();
        if (curveReserve < quote.reserveDebit) revert InsufficientCurveLiquidity();

        _touchGames();

        uint256 previousCurveEth = curveEth;
        curveEth = quote.nextCurveEth;
        curveReserve -= quote.reserveDebit;

        require(token.transferFrom(msg.sender, address(this), tokenAmount), "sell");
        if (launchFilled) {
            token.burn(tokenAmount);
        }

        _payEth(apiFeeWallet, quote.apiFee);
        uint256 lpBaseFee = _fee(quote.grossEthOut, LP_CLUB_FEE_BPS);
        uint256 lpBasePaid = _routeLpClubFee(lpBaseFee);
        _payEth(address(jackpot), quote.jackpotFee + (lpBaseFee - lpBasePaid));
        (uint256 lpFuseReward, uint256 drawFuseReward) = _splitFuseFee(quote.fuseFee);
        if (lpFuseReward > 0 && address(lpClub) != address(0)) {
            _payEth(address(lpClub), lpFuseReward);
        } else {
            drawFuseReward += lpFuseReward;
        }
        _payEth(address(penaltyDraw), quote.drawFee + drawFuseReward);
        _payEth(msg.sender, quote.ethOut);
        _syncFuseWindow(_spotPrice(previousCurveEth), _spotPrice(quote.nextCurveEth));

        if (quote.apiFee > 0) emit ApiFeePaid(quote.apiFee);
        if (quote.jackpotFee + (lpBaseFee - lpBasePaid) > 0) {
            emit JackpotFeePaid(quote.jackpotFee + (lpBaseFee - lpBasePaid));
        }
        if (lpBasePaid > 0) emit LPClubFeePaid(lpBasePaid);
        if (lpFuseReward > 0 && address(lpClub) != address(0)) emit LPClubFeePaid(lpFuseReward);
        if (quote.drawFee + drawFuseReward > 0) emit PenaltyDrawFeePaid(quote.drawFee + drawFuseReward);
        emit GenesisSell(msg.sender, tokenAmount, quote.ethOut, quote.grossEthOut, quote.fuseFee, quote.fuseFeeBps);
    }

    function quoteBuy(uint256 ethIn) external view returns (uint256 tokenOut, uint256 ethCost) {
        (, tokenOut, ethCost,,) = _quoteBuy(ethIn, currentBaseTotalFeeBps());
    }

    function quoteSell(uint256 tokenAmount) external view returns (uint256 ethOut) {
        ethOut = _quoteSellDetailed(curveEth, tokenAmount).ethOut;
    }

    function quoteSellDetailed(uint256 tokenAmount)
        external
        view
        returns (
            uint256 ethOut,
            uint256 apiFee,
            uint256 jackpotFee,
            uint256 drawFee,
            uint256 fuseFee,
            uint256 grossEthOut,
            uint256 fuseFeeBps
        )
    {
        SellQuote memory quote = _quoteSellDetailed(curveEth, tokenAmount);
        ethOut = quote.ethOut;
        apiFee = quote.apiFee;
        jackpotFee = quote.jackpotFee;
        drawFee = quote.drawFee;
        fuseFee = quote.fuseFee;
        grossEthOut = quote.grossEthOut;
        fuseFeeBps = quote.fuseFeeBps;
    }

    function currentPrice() external view returns (uint256) {
        return _spotPrice(curveEth);
    }

    function genesisMinted() external view returns (uint256) {
        return _supplyAtEth(curveEth);
    }

    function claimTokensRemaining() external view returns (uint256) {
        return CLAIM_ALLOCATION - claimTokensDistributed;
    }

    function curveTokensRemaining() external view returns (uint256) {
        if (launchFilled) return 0;
        uint256 sold = _supplyAtEth(curveEth);
        return sold >= CURVE_ALLOCATION ? 0 : CURVE_ALLOCATION - sold;
    }

    function currentApiFeeBps() public view returns (uint256) {
        if (!launched || block.timestamp < launchTimestamp + FIXED_API_WINDOW) return API_FEE_BPS_EARLY;
        return postWindowApiFeeBps;
    }

    function currentJackpotFeeBps() public pure returns (uint256) {
        return JACKPOT_FEE_BPS;
    }

    function currentPenaltyDrawFeeBps() public pure returns (uint256) {
        return PENALTY_DRAW_FEE_BPS;
    }

    function currentLpClubFeeBps() public pure returns (uint256) {
        return LP_CLUB_FEE_BPS;
    }

    function currentBaseTotalFeeBps() public view returns (uint256) {
        return currentApiFeeBps() + JACKPOT_FEE_BPS + LP_CLUB_FEE_BPS + PENALTY_DRAW_FEE_BPS;
    }

    function currentTotalFeeBps() public view returns (uint256) {
        return currentBaseTotalFeeBps();
    }

    function currentFuseWindowSeconds() public view returns (uint256) {
        if (!launched || block.timestamp < launchTimestamp + RAPID_FUSE_PHASE) return RAPID_FUSE_WINDOW;
        return SLOW_FUSE_WINDOW;
    }

    function currentFuseHighPrice() public view returns (uint256) {
        if (!launched) return 0;
        (, uint256 highPrice) = _effectiveFuseWindow(_spotPrice(curveEth));
        return highPrice;
    }

    function currentSellFuseFeeBps() public view returns (uint256) {
        if (!launched) return 0;
        (, uint256 highPrice) = _effectiveFuseWindow(_spotPrice(curveEth));
        return _fuseSurchargeBps(highPrice, _spotPrice(curveEth));
    }

    function fuseLpShareBps() external pure returns (uint256) {
        return FUSE_LP_SHARE_BPS;
    }

    function touchArcadeRounds() external nonReentrant {
        _touchGames();
    }

    function _quoteBuy(uint256 ethIn, uint256 totalFeeBps)
        internal
        view
        returns (uint256 rawTokenOut, uint256 userTokenOut, uint256 ethCost, uint256 ethFee, uint256 netCost)
    {
        if (ethIn == 0 || launchFilled || curveEth >= CURVE_CLOSE_NET_ETH) {
            return (0, 0, 0, 0, 0);
        }

        uint256 remainingNetCost = CURVE_CLOSE_NET_ETH - curveEth;
        uint256 remainingGrossCost = _grossCostForNetEth(remainingNetCost, totalFeeBps);
        if (ethIn >= remainingGrossCost) {
            netCost = remainingNetCost;
            ethCost = remainingGrossCost;
        } else {
            netCost = _netEthFromGross(ethIn, totalFeeBps);
            ethCost = ethIn;
        }

        rawTokenOut = _supplyAtEth(curveEth + netCost) - _supplyAtEth(curveEth);
        if (rawTokenOut == 0) return (0, 0, 0, 0, 0);
        ethFee = ethCost - netCost;
        userTokenOut = rawTokenOut;
    }

    function _quoteSellDetailed(uint256 currentCurveEth, uint256 tokenIn)
        internal
        view
        returns (SellQuote memory quote)
    {
        if (tokenIn == 0) return quote;

        uint256 currentSupply = _supplyAtEth(currentCurveEth);
        if (currentSupply < tokenIn) revert InsufficientCurveLiquidity();

        uint256 nextSupply = currentSupply - tokenIn;
        quote.nextCurveEth = _ethForSupply(nextSupply);
        quote.grossEthOut = currentCurveEth - quote.nextCurveEth;
        quote.reserveDebit = quote.grossEthOut;

        uint256 currentPriceBefore = _spotPrice(currentCurveEth);
        (, uint256 fuseHighPrice) = _effectiveFuseWindow(currentPriceBefore);
        quote.fuseFeeBps = _fuseSurchargeBps(fuseHighPrice, _spotPrice(quote.nextCurveEth));

        quote.apiFee = _fee(quote.grossEthOut, currentApiFeeBps());
        quote.jackpotFee = _fee(quote.grossEthOut, JACKPOT_FEE_BPS);
        quote.drawFee = _fee(quote.grossEthOut, PENALTY_DRAW_FEE_BPS);
        uint256 lpClubFee = _fee(quote.grossEthOut, LP_CLUB_FEE_BPS);
        quote.fuseFee = _fee(quote.grossEthOut, quote.fuseFeeBps);
        quote.ethOut = quote.grossEthOut - quote.apiFee - quote.jackpotFee - lpClubFee - quote.drawFee - quote.fuseFee;
    }

    function _routeBaseFees(uint256 ethCost) internal {
        uint256 apiFee = _fee(ethCost, currentApiFeeBps());
        uint256 jackpotFee = _fee(ethCost, JACKPOT_FEE_BPS);
        uint256 lpClubFee = _fee(ethCost, LP_CLUB_FEE_BPS);
        uint256 drawFee = _fee(ethCost, PENALTY_DRAW_FEE_BPS);
        uint256 lpClubPaid = _routeLpClubFee(lpClubFee);

        _payEth(apiFeeWallet, apiFee);
        _payEth(address(jackpot), jackpotFee + (lpClubFee - lpClubPaid));
        _payEth(address(penaltyDraw), drawFee);

        if (apiFee > 0) emit ApiFeePaid(apiFee);
        if (jackpotFee + (lpClubFee - lpClubPaid) > 0) emit JackpotFeePaid(jackpotFee + (lpClubFee - lpClubPaid));
        if (lpClubPaid > 0) emit LPClubFeePaid(lpClubPaid);
        if (drawFee > 0) emit PenaltyDrawFeePaid(drawFee);
    }

    function _touchGames() internal {
        jackpot.settleIfReady();
        penaltyDraw.settleIfReady();
    }

    function _payEth(address to, uint256 amount) internal {
        if (amount == 0) return;
        (bool ok,) = payable(to).call{value: amount}("");
        if (!ok) revert PayoutFailed();
    }

    function _routeLpClubFee(uint256 amount) internal returns (uint256 paid) {
        if (amount == 0 || address(lpClub) == address(0)) return 0;
        _payEth(address(lpClub), amount);
        return amount;
    }

    function _syncFuseWindow(uint256 referencePrice, uint256 postTradePrice) internal {
        if (!launched) return;
        (uint256 nextStart, uint256 nextHigh) = _effectiveFuseWindow(referencePrice);
        if (postTradePrice > nextHigh) nextHigh = postTradePrice;
        if (nextStart != fuseWindowStart || nextHigh != fuseWindowHighPrice) {
            fuseWindowStart = nextStart;
            fuseWindowHighPrice = nextHigh;
            emit FuseWindowSynced(nextStart, nextHigh, currentFuseWindowSeconds());
        }
    }

    function _effectiveFuseWindow(uint256 referencePrice)
        internal
        view
        returns (uint256 windowStart, uint256 highPrice)
    {
        uint256 activeWindow = currentFuseWindowSeconds();
        if (!launched) return (0, referencePrice);

        windowStart = fuseWindowStart;
        highPrice = fuseWindowHighPrice;
        if (windowStart == 0 || highPrice == 0) {
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

    function _fuseSurchargeBps(uint256 highPrice, uint256 priceToCheck) internal pure returns (uint256) {
        if (highPrice == 0 || priceToCheck == 0) return 0;
        uint256 ratioBps = FullMath.mulDiv(priceToCheck, BPS_DENOMINATOR, highPrice);
        if (ratioBps >= 9_000) return 0;
        if (ratioBps >= 8_000) return FUSE_TIER_ONE_BPS;
        if (ratioBps >= 4_000) return FUSE_TIER_TWO_BPS;
        return FUSE_TIER_THREE_BPS;
    }

    function _spotPrice(uint256 currentCurveEth) internal pure returns (uint256) {
        uint256 x = FullMath.mulDiv(currentCurveEth, LN100_WAD, CURVE_CLOSE_NET_ETH);
        uint256 expNeg = _expNegWad(x);
        uint256 expPos = FullMath.mulDiv(WAD, WAD, expNeg);
        uint256 shape = FullMath.mulDiv(CURVE_CLOSE_NET_ETH, WAD, LN100_WAD);
        uint256 normalizedShape = FullMath.mulDiv(shape, NORMALIZATION_WAD, WAD);
        return FullMath.mulDiv(normalizedShape, expPos, CURVE_ALLOCATION);
    }

    function _fee(uint256 amount, uint256 bps) internal pure returns (uint256) {
        return (amount * bps) / BPS_DENOMINATOR;
    }

    function _splitFuseFee(uint256 fuseFee) internal pure returns (uint256 lpReward, uint256 drawReward) {
        if (fuseFee == 0) return (0, 0);
        lpReward = (fuseFee * FUSE_LP_SHARE_BPS) / BPS_DENOMINATOR;
        drawReward = fuseFee - lpReward;
    }

    function _netEthFromGross(uint256 grossEth, uint256 feeBps) internal pure returns (uint256) {
        return grossEth - _fee(grossEth, feeBps);
    }

    function _grossCostForNetEth(uint256 netEth, uint256 feeBps) internal pure returns (uint256) {
        if (netEth == 0) return 0;
        uint256 netBps = BPS_DENOMINATOR - feeBps;
        return (netEth * BPS_DENOMINATOR + netBps - 1) / netBps;
    }

    function _supplyAtEth(uint256 netEth) internal pure returns (uint256 supply) {
        if (netEth >= CURVE_CLOSE_NET_ETH) return CURVE_ALLOCATION;
        if (netEth == 0) return 0;
        uint256 x = FullMath.mulDiv(netEth, LN100_WAD, CURVE_CLOSE_NET_ETH);
        uint256 expNeg = _expNegWad(x);
        supply = FullMath.mulDiv(CURVE_ALLOCATION, WAD - expNeg, NORMALIZATION_WAD);
    }

    function _ethForSupply(uint256 supply) internal pure returns (uint256 netEth) {
        if (supply >= CURVE_ALLOCATION) return CURVE_CLOSE_NET_ETH;
        if (supply == 0) return 0;
        uint256 remainingWad = WAD - FullMath.mulDiv(supply, NORMALIZATION_WAD, CURVE_ALLOCATION);
        uint256 x = _negLnWad(remainingWad);
        netEth = FullMath.mulDiv(x, CURVE_CLOSE_NET_ETH, LN100_WAD);
    }

    function _expNegWad(uint256 x) internal pure returns (uint256) {
        uint256 halves = x / LN2_WAD;
        uint256 r = x - (halves * LN2_WAD);
        uint256 term = WAD;
        uint256 sum = WAD;

        for (uint256 i = 1; i <= 24; ++i) {
            term = FullMath.mulDiv(term, r, WAD * i);
            if (term == 0) break;
            if (i & 1 == 1) {
                sum -= term;
            } else {
                sum += term;
            }
        }

        return sum >> halves;
    }

    function _negLnWad(uint256 a) internal pure returns (uint256) {
        if (a == 0 || a > WAD) revert InsufficientCurveLiquidity();
        uint256 shifts;
        while (a < WAD / 2) {
            a *= 2;
            ++shifts;
        }

        uint256 numerator = WAD - a;
        if (numerator == 0) return shifts * LN2_WAD;

        uint256 z = FullMath.mulDiv(numerator, WAD, WAD + a);
        uint256 z2 = FullMath.mulDiv(z, z, WAD);
        uint256 term = z;
        uint256 sum = term;

        for (uint256 denominator = 3; denominator <= 39; denominator += 2) {
            term = FullMath.mulDiv(term, z2, WAD);
            if (term == 0) break;
            sum += term / denominator;
        }

        return (shifts * LN2_WAD) + (2 * sum);
    }

    receive() external payable {}
}
