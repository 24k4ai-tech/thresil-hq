const { ethers } = window;

const CONFIG_KEY = "thresil.arcade.config.v2";
const RPC_URLS = [
  "https://ethereum.publicnode.com",
  "https://eth.llamarpc.com",
  "https://ethereum-rpc.publicnode.com",
];
const COUNTDOWN_REFRESH_MS = 1000;
const CHAIN_REFRESH_MS = 12000;

const DEFAULT_CONFIG = {
  launcher: "0x828318182b294E9AFf2437e7Dc4810Aa955Bb764",
  token: "0xcB16cA9d5c6F9090A1b56D29ACb31D764bc2ed7c",
  jackpot: "0x107E0b771877e560B846AEcA0cE3b15D83592091",
  draw: "0x350E881320d890B5EdD83be5c24CE0EDEf185f55",
};

const ERC20_BALANCE_ABI = ["function balanceOf(address account) view returns (uint256)"];

const LAUNCHER_ABI = [
  "function owner() view returns (address)",
  "function token() view returns (address)",
  "function jackpot() view returns (address)",
  "function penaltyDraw() view returns (address)",
  "function lpClub() view returns (address)",
  "function v4Hook() view returns (address)",
  "function fuseLpShareBps() view returns (uint256)",
  "function CURVE_CLOSE_GROSS_ETH() view returns (uint256)",
  "function launched() view returns (bool)",
  "function launchTimestamp() view returns (uint256)",
  "function curveReserve() view returns (uint256)",
  "function currentPrice() view returns (uint256)",
  "function genesisMinted() view returns (uint256)",
  "function curveTokensRemaining() view returns (uint256)",
  "function claimSourceToken() view returns (address)",
  "function claimTokensRemaining() view returns (uint256)",
  "function claimedWalletCount() view returns (uint256)",
  "function CLAIM_MAX_WALLETS() view returns (uint256)",
  "function CLAIM_SHARE() view returns (uint256)",
  "function currentApiFeeBps() view returns (uint256)",
  "function currentJackpotFeeBps() view returns (uint256)",
  "function currentPenaltyDrawFeeBps() view returns (uint256)",
  "function currentLpClubFeeBps() view returns (uint256)",
  "function currentBaseTotalFeeBps() view returns (uint256)",
  "function currentTotalFeeBps() view returns (uint256)",
  "function currentFuseWindowSeconds() view returns (uint256)",
  "function currentFuseHighPrice() view returns (uint256)",
  "function currentSellFuseFeeBps() view returns (uint256)",
  "function quoteBuy(uint256 ethIn) view returns (uint256 tokenOut, uint256 ethCost)",
  "function quoteSell(uint256 tokenAmount) view returns (uint256 ethOut)",
  "function quoteSellDetailed(uint256 tokenAmount) view returns (uint256 ethOut, uint256 apiFee, uint256 jackpotFee, uint256 drawFee, uint256 fuseFee, uint256 grossEthOut, uint256 fuseFeeBps)",
  "function buyGenesis(address to) payable returns (uint256)",
  "function sellGenesis(uint256 tokenAmount, uint256 minEthOut) returns (uint256)",
  "function claim() returns (uint256)",
];

const TOKEN_ABI = [
  "function name() view returns (string)",
  "function symbol() view returns (string)",
  "function totalSupply() view returns (uint256)",
  "function balanceOf(address account) view returns (uint256)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
];

const JACKPOT_ABI = [
  "function lastBuyer() view returns (address)",
  "function deadlineTimestamp() view returns (uint256)",
  "function round() view returns (uint256)",
  "function totalPaid() view returns (uint256)",
  "function lastWinner() view returns (address)",
  "function lastPayout() view returns (uint256)",
];

const DRAW_ABI = [
  "function round() view returns (uint256)",
  "function roundEndsAt() view returns (uint256)",
  "function currentRoundWeight() view returns (uint256)",
  "function currentEntryCount() view returns (uint256)",
  "function settlementBlock() view returns (uint256)",
  "function pendingSettlementPayout() view returns (uint256)",
  "function lastWinner() view returns (address)",
  "function lastPayout() view returns (uint256)",
  "function totalBurned() view returns (uint256)",
  "function enter(uint256 tokenAmount) returns (uint256)",
];

const LP_CLUB_ABI = [
  "function trackedEthByAccount(address account) view returns (uint256)",
  "function pendingRewards(address account) view returns (uint256)",
  "function currentBoostBps(address account) view returns (uint256)",
  "function claim() returns (uint256)",
];

const HOOK_ABI = ["function poolManager() view returns (address)"];
const STATE_VIEW_ABI = [
  "function getSlot0(bytes32 poolId) view returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee)",
];
const POSITION_MANAGER_ABI = ["function modifyLiquidities(bytes unlockData, uint256 deadline) payable"];
const PERMIT2_ABI = [
  "function allowance(address user, address token, address spender) view returns (uint160 amount, uint48 expiration, uint48 nonce)",
  "function approve(address token, address spender, uint160 amount, uint48 expiration)",
];

const OFFICIAL_V4_POSITION_MANAGER = "0xbd216513d74c8cf14cf4747e6aaa6420ff64ee9e";
const OFFICIAL_V4_STATE_VIEW = "0x7ffe42c4a5deea5b0fec41c94c136cf115597227";
const PERMIT2_ADDRESS = "0x000000000022D473030F116dDEE9F6B43aC78BA3";
const V4_POOL_FEE = 3000;
const V4_TICK_SPACING = 60;
const FULL_RANGE_TICK_LOWER = -887220;
const FULL_RANGE_TICK_UPPER = 887220;
const MIN_SQRT_RATIO = 4295128739n;
const MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342n;
const Q96 = 2n ** 96n;
const Q192 = Q96 * Q96;
const WAD = 10n ** 18n;
const LP_SAFETY_BPS = 9950n;
const LP_TOKEN_BUFFER_BPS = 10100n;
const BPS_DENOMINATOR = 10000n;
const MAX_UINT160 = (1n << 160n) - 1n;
const MAX_UINT48 = (1n << 48n) - 1n;
const PENALTY_STARS = [
  { key: "cr7", name: "CR7", tag: "POWER 7" },
  { key: "messi", name: "Messi", tag: "LEFT 10" },
  { key: "mbappe", name: "Mbappe", tag: "SPEED 9" },
  { key: "haaland", name: "Haaland", tag: "HAMMER" },
  { key: "neymar", name: "Neymar", tag: "FLAIR" },
];

const el = Object.fromEntries(
  [
    "networkStatus",
    "blockNumber",
    "protocolStatus",
    "curveStatus",
    "feeStatus",
    "curveDial",
    "curveDialLabel",
    "refreshBtn",
    "connectBtn",
    "launcherAddress",
    "tokenAddress",
    "jackpotAddress",
    "drawAddress",
    "saveConfigBtn",
    "totalSupply",
    "genesisMinted",
    "curveReserve",
    "currentPrice",
    "myTokenBalance",
    "curveRemaining",
    "currentFuseTax",
    "fuseHighPrice",
    "fuseMode",
    "mintEth",
    "mintQuote",
    "mintBtn",
    "claimRemaining",
    "claimedWallets",
    "claimShare",
    "claimSourceBalance",
    "claimBtn",
    "lpEthInput",
    "lpTokenPreview",
    "lpPoolPrice",
    "lpManagerStatus",
    "lpTrackedEth",
    "lpBoostBps",
    "lpPendingReward",
    "lpFuseShare",
    "lpAddBtn",
    "lpClaimBtn",
    "sellPercent",
    "sellPercentValue",
    "sellAmountPreview",
    "sellQuote",
    "approveSellBtn",
    "sellBtn",
    "jackpotBalance",
    "lastBuyer",
    "signalCountdown",
    "jackpotLastWinner",
    "jackpotLastPayout",
    "drawBalance",
    "drawCountdown",
    "drawEntries",
    "drawLastWinner",
    "drawLastPayout",
    "drawPercent",
    "drawPercentValue",
    "drawAmountPreview",
    "drawAmount",
    "approveDrawBtn",
    "drawEnterBtn",
    "penaltyStage",
    "goalKeeper",
    "penaltyBall",
    "shotOutcome",
    "shotDetail",
    "toast",
  ].map((id) => [id, document.getElementById(id)])
);

let browserProvider;
let signer;
let account = "";
let chainId = 0;
let readBlock = 0n;
let countdownTimer = 0;
let chainRefreshTimer = 0;
let refreshInFlight;
let tokenSymbol = "777X";
let myTokenBalanceRaw = 0n;
let currentPriceRaw = 0n;
let currentPoolPriceRaw = 0n;
let currentConfig = { ...DEFAULT_CONFIG };
let cachedLaunchTimestamp = 0n;
let cachedSignalDeadline = 0n;
let cachedDrawDeadline = 0n;
let cachedDrawSettlementBlock = 0n;
const sellPresetButtons = Array.from(document.querySelectorAll("[data-sell-preset]"));

function loadConfig() {
  const saved = JSON.parse(localStorage.getItem(CONFIG_KEY) || "{}");
  currentConfig = { ...DEFAULT_CONFIG };
  Object.keys(DEFAULT_CONFIG).forEach((key) => {
    if (isAddress(saved[key])) currentConfig[key] = saved[key];
  });
  el.launcherAddress.value = currentConfig.launcher || "";
  el.tokenAddress.value = currentConfig.token || "";
  el.jackpotAddress.value = currentConfig.jackpot || "";
  el.drawAddress.value = currentConfig.draw || "";
}

function configuredAddress(key, value) {
  const cleaned = cleanAddress(value);
  if (isAddress(cleaned)) return cleaned;
  const fallback = currentConfig[key] || DEFAULT_CONFIG[key];
  return isAddress(fallback) ? fallback : "";
}

function saveConfig() {
  currentConfig = {
    launcher: cleanAddress(el.launcherAddress.value),
    token: cleanAddress(el.tokenAddress.value),
    jackpot: cleanAddress(el.jackpotAddress.value),
    draw: cleanAddress(el.drawAddress.value),
  };
  localStorage.setItem(CONFIG_KEY, JSON.stringify(currentConfig));
  showToast("Local arcade config saved.");
}

async function connectWallet() {
  if (!window.ethereum) throw new Error("No injected wallet found.");
  browserProvider = new ethers.BrowserProvider(window.ethereum);
  await browserProvider.send("eth_requestAccounts", []);
  signer = await browserProvider.getSigner();
  account = await signer.getAddress();
  const network = await browserProvider.getNetwork();
  chainId = Number(network.chainId);
  el.networkStatus.textContent =
    chainId === 1 ? `${short(account)} on mainnet` : `${short(account)} on chain ${chainId}`;
  el.connectBtn.textContent = "Wallet Connected";
  bindWalletEvents();
  await refreshLiveState({ force: true });
}

function bindWalletEvents() {
  if (!window.ethereum?.on) return;
  window.ethereum.removeListener?.("accountsChanged", onAccountsChanged);
  window.ethereum.removeListener?.("chainChanged", onChainChanged);
  window.ethereum.on("accountsChanged", onAccountsChanged);
  window.ethereum.on("chainChanged", onChainChanged);
}

function onAccountsChanged(accounts) {
  account = accounts?.[0] || "";
  if (!account) {
    signer = undefined;
    el.networkStatus.textContent = "Read mode";
    el.connectBtn.textContent = "Connect Wallet";
  }
  refreshLiveState({ force: true }).catch((error) => showToast(humanError(error)));
}

function onChainChanged() {
  window.location.reload();
}

async function getReadProvider() {
  if (browserProvider) return browserProvider;

  let lastError;
  for (const url of RPC_URLS) {
    try {
      const provider = new ethers.JsonRpcProvider(url);
      await provider.getBlockNumber();
      return provider;
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError || new Error("No Ethereum RPC available.");
}

async function refreshLiveState({ quiet = false, force = false } = {}) {
  if (!force && document.hidden) return;
  if (refreshInFlight) {
    if (!force) return refreshInFlight;
    await refreshInFlight.catch(() => {});
  }

  refreshInFlight = refresh()
    .catch((error) => {
      if (!quiet) showToast(humanError(error));
      throw error;
    })
    .finally(() => {
      refreshInFlight = undefined;
    });

  return refreshInFlight;
}

function startLiveRefresh() {
  window.clearInterval(countdownTimer);
  window.clearInterval(chainRefreshTimer);
  document.removeEventListener("visibilitychange", onVisibilityRefresh);

  countdownTimer = window.setInterval(updateCountdowns, COUNTDOWN_REFRESH_MS);
  chainRefreshTimer = window.setInterval(() => {
    refreshLiveState({ quiet: true }).catch(() => {});
  }, CHAIN_REFRESH_MS);
  document.addEventListener("visibilitychange", onVisibilityRefresh);
}

function onVisibilityRefresh() {
  if (!document.hidden) refreshLiveState({ quiet: true, force: true }).catch(() => {});
}

async function refresh() {
  const launcherAddress = configuredAddress("launcher", el.launcherAddress.value);
  if (!isAddress(launcherAddress)) {
    setPendingState();
    return;
  }
  if (!isAddress(el.launcherAddress.value)) el.launcherAddress.value = launcherAddress;

  const provider = await getReadProvider();
  readBlock = BigInt(await provider.getBlockNumber());
  el.blockNumber.textContent = readBlock.toString();

  const launcher = new ethers.Contract(launcherAddress, LAUNCHER_ABI, provider);
  const tokenAddress = currentConfig.token || (await launcher.token());
  const jackpotAddress = currentConfig.jackpot || (await launcher.jackpot());
  const drawAddress = currentConfig.draw || (await launcher.penaltyDraw());
  const lpClubAddress = await launcher.lpClub();

  if (!isAddress(el.tokenAddress.value)) el.tokenAddress.value = tokenAddress;
  if (!isAddress(el.jackpotAddress.value)) el.jackpotAddress.value = jackpotAddress;
  if (!isAddress(el.drawAddress.value)) el.drawAddress.value = drawAddress;

  const token = new ethers.Contract(tokenAddress, TOKEN_ABI, provider);
  const jackpot = new ethers.Contract(jackpotAddress, JACKPOT_ABI, provider);
  const draw = new ethers.Contract(drawAddress, DRAW_ABI, provider);
  const lpClub = isAddress(lpClubAddress) ? new ethers.Contract(lpClubAddress, LP_CLUB_ABI, provider) : null;
  const claimSourceAddress = await launcher.claimSourceToken();
  const claimSource = new ethers.Contract(claimSourceAddress, ERC20_BALANCE_ABI, provider);
  let curveCloseGross = ethers.parseEther("17");
  try {
    curveCloseGross = await launcher.CURVE_CLOSE_GROSS_ETH();
  } catch {}

  const [
    totalSupply,
    curveMinted,
    curveReserve,
    currentPrice,
    curveRemaining,
    claimRemaining,
    claimedWallets,
    claimMaxWallets,
    claimShare,
    launched,
    launchTimestamp,
    currentApiFeeBps,
    currentJackpotFeeBps,
    currentLpClubFeeBps,
    currentPenaltyDrawFeeBps,
    currentBaseTotalFeeBps,
    currentTotalFeeBps,
    fuseLpShareBps,
    currentFuseWindowSeconds,
    currentFuseHighPrice,
    currentSellFuseFeeBps,
    jackpotBalance,
    lastBuyer,
    signalDeadline,
    jackpotLastWinner,
    jackpotLastPayout,
    drawBalance,
    drawDeadline,
    drawEntries,
    drawSettlementBlock,
    pendingDrawPayout,
    drawLastWinner,
    drawLastPayout,
    claimSourceBalance,
    myTokenBalance,
    lpTrackedEth,
    lpPendingReward,
    lpBoostBps,
  ] = await Promise.all([
    token.totalSupply(),
    launcher.genesisMinted(),
    launcher.curveReserve(),
    launcher.currentPrice(),
    launcher.curveTokensRemaining(),
    launcher.claimTokensRemaining(),
    launcher.claimedWalletCount(),
    launcher.CLAIM_MAX_WALLETS(),
    launcher.CLAIM_SHARE(),
    launcher.launched(),
    launcher.launchTimestamp(),
    launcher.currentApiFeeBps(),
    launcher.currentJackpotFeeBps(),
    launcher.currentLpClubFeeBps().catch(() => 100n),
    launcher.currentPenaltyDrawFeeBps(),
    launcher.currentBaseTotalFeeBps(),
    launcher.currentTotalFeeBps(),
    launcher.fuseLpShareBps(),
    launcher.currentFuseWindowSeconds(),
    launcher.currentFuseHighPrice(),
    launcher.currentSellFuseFeeBps(),
    provider.getBalance(jackpotAddress),
    jackpot.lastBuyer(),
    jackpot.deadlineTimestamp(),
    jackpot.lastWinner(),
    jackpot.lastPayout(),
    provider.getBalance(drawAddress),
    draw.roundEndsAt(),
    draw.currentEntryCount(),
    draw.settlementBlock().catch(() => 0n),
    draw.pendingSettlementPayout().catch(() => 0n),
    draw.lastWinner(),
    draw.lastPayout(),
    account ? claimSource.balanceOf(account) : 0n,
    account ? token.balanceOf(account) : 0n,
    account && lpClub ? lpClub.trackedEthByAccount(account) : 0n,
    account && lpClub ? lpClub.pendingRewards(account) : 0n,
    account && lpClub ? lpClub.currentBoostBps(account) : 0n,
  ]);

  tokenSymbol = (await token.symbol()) || "777X";
  myTokenBalanceRaw = myTokenBalance;
  currentPriceRaw = currentPrice;
  cachedLaunchTimestamp = launchTimestamp;
  cachedSignalDeadline = signalDeadline;
  cachedDrawDeadline = drawDeadline;
  cachedDrawSettlementBlock = drawSettlementBlock;

  el.protocolStatus.textContent = launched ? "Arcade live" : "Configured, not launched";
  el.curveStatus.textContent = launched ? "SATO reserve rail live" : "Standby";
  el.feeStatus.textContent = formatTradeSplit(
    currentBaseTotalFeeBps,
    currentApiFeeBps,
    currentJackpotFeeBps,
    currentLpClubFeeBps,
    currentPenaltyDrawFeeBps,
    currentSellFuseFeeBps,
    curveCloseGross
  );
  el.totalSupply.textContent = `${formatToken(totalSupply)} ${tokenSymbol}`;
  el.genesisMinted.textContent = `${formatToken(curveMinted)} ${tokenSymbol}`;
  el.curveReserve.textContent = `${formatEth(curveReserve)} ETH`;
  el.currentPrice.textContent = `${formatGwei(currentPrice)} gwei`;
  el.myTokenBalance.textContent = account ? `${formatToken(myTokenBalance)} ${tokenSymbol}` : "Connect wallet";
  el.curveRemaining.textContent = `${formatToken(curveRemaining)} ${tokenSymbol}`;
  el.currentFuseTax.textContent = formatFuseTax(currentSellFuseFeeBps);
  el.fuseHighPrice.textContent = `${formatGwei(currentFuseHighPrice)} gwei`;
  el.fuseMode.textContent = formatFuseWindow(currentFuseWindowSeconds);
  el.claimRemaining.textContent = `${formatToken(claimRemaining)} ${tokenSymbol}`;
  el.claimedWallets.textContent = `${claimedWallets.toString()} / ${claimMaxWallets.toString()}`;
  el.claimShare.textContent = `${formatToken(claimShare)} ${tokenSymbol}`;
  el.claimSourceBalance.textContent = account ? formatEligibility(claimSourceBalance) : "Connect wallet";
  const curveCapacity = curveMinted + curveRemaining;
  const mintedPercent = curveCapacity > 0n ? Number((curveMinted * 10000n) / curveCapacity) / 100 : 0;
  const clampedMintedPercent = Math.min(100, Math.max(0, mintedPercent));
  if (el.curveDial) {
    el.curveDial.style.background =
      `radial-gradient(circle at center, rgba(12, 7, 7, 0.98) 56%, transparent 57%), conic-gradient(var(--cyan) ${clampedMintedPercent * 3.6}deg, rgba(242, 203, 91, 0.12) 0deg)`;
  }
  if (el.curveDialLabel) {
    el.curveDialLabel.textContent = `${clampedMintedPercent.toFixed(1)}%`;
  }

  el.jackpotBalance.textContent = `${formatEth(jackpotBalance)} ETH`;
  el.lastBuyer.textContent = short(lastBuyer);
  el.jackpotLastWinner.textContent = short(jackpotLastWinner);
  el.jackpotLastPayout.textContent = `${formatEth(jackpotLastPayout)} ETH`;
  el.drawBalance.textContent = `${formatEth(drawBalance)} ETH`;
  el.drawEntries.textContent = drawEntries.toString();
  el.drawLastWinner.textContent = short(drawLastWinner);
  el.drawLastPayout.textContent =
    pendingDrawPayout > 0n ? `Armed: ${formatEth(pendingDrawPayout)} ETH` : `${formatEth(drawLastPayout)} ETH`;
  if (el.lpTrackedEth) el.lpTrackedEth.textContent = account ? `${formatEth(lpTrackedEth)} ETH` : "Connect wallet";
  if (el.lpBoostBps) el.lpBoostBps.textContent = formatBps(lpBoostBps);
  if (el.lpPendingReward) el.lpPendingReward.textContent = account ? `${formatEth(lpPendingReward)} ETH` : "Connect wallet";
  if (el.lpFuseShare) {
    el.lpFuseShare.textContent = formatLpRewardRule(currentLpClubFeeBps, fuseLpShareBps);
  }

  await updateQuotes();
  updateCountdowns();
  syncPenaltyScene(drawEntries);
}

async function updateQuotes() {
  const launcherAddress = cleanAddress(el.launcherAddress.value);
  if (!isAddress(launcherAddress)) {
    el.mintQuote.textContent = "-";
    el.sellQuote.textContent = "-";
    if (el.lpTokenPreview) el.lpTokenPreview.textContent = "-";
    if (el.lpPoolPrice) el.lpPoolPrice.textContent = "-";
    if (el.lpManagerStatus) el.lpManagerStatus.textContent = "Awaiting config";
    return;
  }

  const provider = await getReadProvider();
  const launcher = new ethers.Contract(launcherAddress, LAUNCHER_ABI, provider);

  const mintValue = parseUnitsSafe(el.mintEth.value);
  if (mintValue > 0n) {
    try {
      const [tokenOut, ethCost] = await launcher.quoteBuy(mintValue);
      el.mintQuote.textContent =
        `You receive about ${formatToken(tokenOut)} ${tokenSymbol}; wallet spends ${formatEth(ethCost)} ETH including tax.`;
    } catch {
      el.mintQuote.textContent = "-";
    }
  } else {
    el.mintQuote.textContent = "-";
  }

  syncSellInputsFromSlider();
  const sellValue = selectedSellAmountRaw();
  if (sellValue > 0n) {
    try {
      const [ethOut, , , , , , fuseFeeBps] = await launcher.quoteSellDetailed(sellValue);
      el.sellQuote.textContent =
        `You receive about ${formatEth(ethOut)} ETH after tax. ${formatFuseTax(fuseFeeBps)}.`;
    } catch {
      el.sellQuote.textContent = "-";
    }
  } else {
    el.sellQuote.textContent = "-";
  }

  syncDrawInputsFromSlider();
  await syncLpQuoteFromEth(provider);
}

function syncSellInputsFromSlider() {
  const percent = Number(el.sellPercent.value || "0");
  el.sellPercentValue.textContent = `${percent.toFixed(1)}%`;
  const amount = selectedSellAmountRaw();
  el.sellAmountPreview.textContent = amount ? `${formatToken(amount)} ${tokenSymbol}` : `0 ${tokenSymbol}`;
}

function syncDrawInputsFromSlider() {
  const percent = Number(el.drawPercent.value || "0");
  el.drawPercentValue.textContent = `${percent.toFixed(1)}%`;
  const amount = percentToAmount(myTokenBalanceRaw, percent);
  if (document.activeElement !== el.drawAmount) {
    el.drawAmount.value = amount ? formatInputToken(amount, 4) : "0";
  }
  el.drawAmountPreview.textContent = amount ? `${formatToken(amount)} ${tokenSymbol}` : `0 ${tokenSymbol}`;
}

async function getLpContext(provider) {
  const launcherAddress = configuredAddress("launcher", el.launcherAddress.value);
  const tokenAddress = configuredAddress("token", el.tokenAddress.value);
  if (!isAddress(launcherAddress) || !isAddress(tokenAddress)) throw new Error("Set launcher and token first.");

  const launcher = new ethers.Contract(launcherAddress, LAUNCHER_ABI, provider);
  const hookAddress = cleanAddress(await launcher.v4Hook());
  if (!isAddress(hookAddress)) throw new Error("Launcher hook is not set.");

  const poolKey = {
    currency0: ethers.ZeroAddress,
    currency1: tokenAddress,
    fee: V4_POOL_FEE,
    tickSpacing: V4_TICK_SPACING,
    hooks: hookAddress,
  };
  const abiCoder = ethers.AbiCoder.defaultAbiCoder();
  const poolId = ethers.keccak256(
    abiCoder.encode(
      ["address", "address", "uint24", "int24", "address"],
      [poolKey.currency0, poolKey.currency1, poolKey.fee, poolKey.tickSpacing, poolKey.hooks]
    )
  );

  const hook = new ethers.Contract(hookAddress, HOOK_ABI, provider);
  const stateView = new ethers.Contract(OFFICIAL_V4_STATE_VIEW, STATE_VIEW_ABI, provider);
  const [poolManagerAddress, slot0] = await Promise.all([hook.poolManager(), stateView.getSlot0(poolId)]);
  return {
    poolKey,
    poolId,
    hookAddress,
    poolManagerAddress,
    sqrtPriceX96: BigInt(slot0[0]),
    tick: Number(slot0[1]),
  };
}

function tokenPerEthFromSqrtPrice(sqrtPriceX96) {
  if (sqrtPriceX96 <= 0n) return 0n;
  return (sqrtPriceX96 * sqrtPriceX96 * WAD) / Q192;
}

function liquidityForAmount0(amount0, sqrtPriceX96, sqrtUpperX96) {
  const intermediate = (sqrtPriceX96 * sqrtUpperX96) / Q96;
  return (amount0 * intermediate) / (sqrtUpperX96 - sqrtPriceX96);
}

function liquidityForAmount1(amount1, sqrtLowerX96, sqrtPriceX96) {
  return (amount1 * Q96) / (sqrtPriceX96 - sqrtLowerX96);
}

function quoteLpPosition(ethAmountRaw, sqrtPriceX96) {
  if (ethAmountRaw <= 0n || sqrtPriceX96 <= 0n) {
    return { tokenQuote: 0n, tokenMax: 0n, liquidity: 0n, poolPrice: 0n };
  }

  const poolPrice = tokenPerEthFromSqrtPrice(sqrtPriceX96);
  const tokenQuote = (ethAmountRaw * poolPrice) / WAD;
  const tokenMax = (tokenQuote * LP_TOKEN_BUFFER_BPS) / BPS_DENOMINATOR;

  const liqFromEth = liquidityForAmount0(ethAmountRaw, sqrtPriceX96, MAX_SQRT_RATIO);
  const liqFromToken = liquidityForAmount1(tokenQuote, MIN_SQRT_RATIO, sqrtPriceX96);
  const liquidity = ((liqFromEth < liqFromToken ? liqFromEth : liqFromToken) * LP_SAFETY_BPS) / BPS_DENOMINATOR;
  return { tokenQuote, tokenMax, liquidity, poolPrice };
}

async function syncLpQuoteFromEth(providerOverride) {
  const ethAmount = parseUnitsSafe(el.lpEthInput?.value);
  if (!el.lpTokenPreview || !el.lpPoolPrice || !el.lpManagerStatus) return;
  if (ethAmount <= 0n) {
    currentPoolPriceRaw = 0n;
    el.lpTokenPreview.textContent = `0 ${tokenSymbol}`;
    el.lpPoolPrice.textContent = "-";
    el.lpManagerStatus.textContent = "Enter ETH";
    return;
  }

  try {
    const provider = providerOverride || (await getReadProvider());
    const { sqrtPriceX96 } = await getLpContext(provider);
    const quote = quoteLpPosition(ethAmount, sqrtPriceX96);
    currentPoolPriceRaw = quote.poolPrice;
    el.lpTokenPreview.textContent = `${formatToken(quote.tokenQuote)} ${tokenSymbol}`;
    el.lpPoolPrice.textContent = quote.poolPrice > 0n ? `${formatToken(quote.poolPrice, 4)} ${tokenSymbol} / ETH` : "-";
    el.lpManagerStatus.textContent = `PosM ${short(OFFICIAL_V4_POSITION_MANAGER)}`;
  } catch (error) {
    currentPoolPriceRaw = 0n;
    const fallbackPrice = currentPriceRaw;
    const fallbackToken = fallbackPrice > 0n ? (ethAmount * WAD) / fallbackPrice : 0n;
    const fallbackTokenPerEth = fallbackPrice > 0n ? (WAD * WAD) / fallbackPrice : 0n;
    el.lpTokenPreview.textContent = fallbackToken ? `${formatToken(fallbackToken)} ${tokenSymbol}` : `0 ${tokenSymbol}`;
    el.lpPoolPrice.textContent =
      fallbackTokenPerEth > 0n ? `${formatToken(fallbackTokenPerEth, 4)} ${tokenSymbol} / ETH curve fallback` : "Pool quote unavailable";
    el.lpManagerStatus.textContent = humanError(error);
  }
}

function buildLpUnlockData(poolKey, ownerAddress, liquidity, ethAmountRaw, tokenMaxRaw) {
  const abiCoder = ethers.AbiCoder.defaultAbiCoder();
  const params = [
    abiCoder.encode(
      [
        "(address currency0,address currency1,uint24 fee,int24 tickSpacing,address hooks)",
        "int24",
        "int24",
        "uint256",
        "uint128",
        "uint128",
        "address",
        "bytes",
      ],
      [
        poolKey,
        FULL_RANGE_TICK_LOWER,
        FULL_RANGE_TICK_UPPER,
        liquidity,
        ethAmountRaw,
        tokenMaxRaw,
        ownerAddress,
        abiCoder.encode(["address"], [ownerAddress]),
      ]
    ),
    abiCoder.encode(["address", "address"], [poolKey.currency0, poolKey.currency1]),
    abiCoder.encode(["address", "address"], [poolKey.currency0, ownerAddress]),
  ];
  return abiCoder.encode(["bytes", "bytes[]"], ["0x020d14", params]);
}

async function ensurePermit2Ready(tokenAddress, neededAmount) {
  const token = new ethers.Contract(tokenAddress, TOKEN_ABI, signer);
  const permit2 = new ethers.Contract(PERMIT2_ADDRESS, PERMIT2_ABI, signer);
  const walletAllowance = await token.allowance(account, PERMIT2_ADDRESS);
  if (BigInt(walletAllowance) < neededAmount) {
    showToast("Step 1/3: approving 777X to Permit2.");
    const approveTx = await token.approve(PERMIT2_ADDRESS, ethers.MaxUint256);
    await approveTx.wait();
  }

  const [permitAmount] = await permit2.allowance(account, tokenAddress, OFFICIAL_V4_POSITION_MANAGER);
  if (BigInt(permitAmount) < neededAmount) {
    showToast("Step 2/3: granting Permit2 allowance to the official manager.");
    const expiry = Math.min(Number(MAX_UINT48), Math.floor(Date.now() / 1000) + 60 * 60 * 24 * 3650);
    const permitTx = await permit2.approve(tokenAddress, OFFICIAL_V4_POSITION_MANAGER, MAX_UINT160, expiry);
    await permitTx.wait();
  }
}

async function addOfficialLp() {
  if (!signer) throw new Error("Connect wallet first.");
  if (chainId !== 1) throw new Error("Switch to Ethereum mainnet.");

  const ethAmount = parseUnitsSafe(el.lpEthInput?.value);
  if (ethAmount <= 0n) throw new Error("Enter a valid ETH amount.");

  const provider = browserProvider || (await getReadProvider());
  const tokenAddress = configuredAddress("token", el.tokenAddress.value);
  if (!isAddress(tokenAddress)) throw new Error("Set token first.");

  const { poolKey, sqrtPriceX96 } = await getLpContext(provider);
  const quote = quoteLpPosition(ethAmount, sqrtPriceX96);
  if (quote.tokenQuote <= 0n || quote.liquidity <= 0n) throw new Error("LP quote is empty.");
  if (myTokenBalanceRaw < quote.tokenMax) throw new Error(`Need about ${formatToken(quote.tokenMax)} ${tokenSymbol} to pair this ETH.`);

  await ensurePermit2Ready(tokenAddress, quote.tokenMax);

  showToast("Step 3/3: minting LP through the official v4 PositionManager.");
  const positionManager = new ethers.Contract(OFFICIAL_V4_POSITION_MANAGER, POSITION_MANAGER_ABI, signer);
  const deadline = BigInt(Math.floor(Date.now() / 1000) + 20 * 60);
  const unlockData = buildLpUnlockData(poolKey, account, quote.liquidity, ethAmount, quote.tokenMax);
  const tx = await positionManager.modifyLiquidities(unlockData, deadline, { value: ethAmount });
  showToast(`LP mint sent: ${tx.hash}`);
  await tx.wait();
  await refreshLiveState({ force: true });
}

async function claimLpEth() {
  if (!signer) throw new Error("Connect wallet first.");
  const launcherAddress = configuredAddress("launcher", el.launcherAddress.value);
  if (!isAddress(launcherAddress)) throw new Error("Set launcher first.");
  const provider = browserProvider || (await getReadProvider());
  const launcher = new ethers.Contract(launcherAddress, LAUNCHER_ABI, provider);
  const lpClubAddress = cleanAddress(await launcher.lpClub());
  if (!isAddress(lpClubAddress)) throw new Error("LP club is not set.");
  const lpClub = new ethers.Contract(lpClubAddress, LP_CLUB_ABI, signer);
  const tx = await lpClub.claim();
  showToast(`LP claim sent: ${tx.hash}`);
  await tx.wait();
  await refreshLiveState({ force: true });
}

async function mintTokens() {
  if (!signer) throw new Error("Connect wallet first.");
  const launcherAddress = configuredAddress("launcher", el.launcherAddress.value);
  const value = parseUnitsSafe(el.mintEth.value);
  if (!isAddress(launcherAddress) || value <= 0n) throw new Error("Enter a valid mint amount.");
  const launcher = new ethers.Contract(launcherAddress, LAUNCHER_ABI, signer);
  const tx = await launcher.buyGenesis(account, { value });
  showToast(`Mint sent: ${tx.hash}`);
  await tx.wait();
  await refreshLiveState({ force: true });
}

async function claimFreeMint() {
  if (!signer) throw new Error("Connect wallet first.");
  const launcherAddress = configuredAddress("launcher", el.launcherAddress.value);
  if (!isAddress(launcherAddress)) throw new Error("Set launcher first.");
  const launcher = new ethers.Contract(launcherAddress, LAUNCHER_ABI, signer);
  const tx = await launcher.claim();
  showToast(`Claim sent: ${tx.hash}`);
  await tx.wait();
  await refreshLiveState({ force: true });
}

async function approveSell() {
  if (!signer) throw new Error("Connect wallet first.");
  const tokenAddress = configuredAddress("token", el.tokenAddress.value);
  const launcherAddress = configuredAddress("launcher", el.launcherAddress.value);
  const amount = selectedSellAmountRaw();
  if (!isAddress(tokenAddress) || !isAddress(launcherAddress) || amount <= 0n) {
    throw new Error("Set launcher and move the sell slider first.");
  }
  const token = new ethers.Contract(tokenAddress, TOKEN_ABI, signer);
  const tx = await token.approve(launcherAddress, amount);
  showToast(`Approve sent: ${tx.hash}`);
  await tx.wait();
}

async function sellTokens() {
  if (!signer) throw new Error("Connect wallet first.");
  const launcherAddress = configuredAddress("launcher", el.launcherAddress.value);
  const amount = selectedSellAmountRaw();
  if (!isAddress(launcherAddress) || amount <= 0n) throw new Error("Move the sell slider first.");
  const launcher = new ethers.Contract(launcherAddress, LAUNCHER_ABI, signer);
  const tx = await launcher.sellGenesis(amount, 0);
  showToast(`Sell sent: ${tx.hash}`);
  await tx.wait();
  await refreshLiveState({ force: true });
}

async function approveDraw() {
  if (!signer) throw new Error("Connect wallet first.");
  const tokenAddress = configuredAddress("token", el.tokenAddress.value);
  const drawAddress = configuredAddress("draw", el.drawAddress.value);
  const amount = parseUnitsSafe(el.drawAmount.value);
  if (!isAddress(tokenAddress) || !isAddress(drawAddress) || amount <= 0n) {
    throw new Error("Enter a valid burn amount first.");
  }
  const token = new ethers.Contract(tokenAddress, TOKEN_ABI, signer);
  const tx = await token.approve(drawAddress, amount);
  showToast(`Approve sent: ${tx.hash}`);
  await tx.wait();
}

async function enterDraw() {
  if (!signer) throw new Error("Connect wallet first.");
  const drawAddress = configuredAddress("draw", el.drawAddress.value);
  const amount = parseUnitsSafe(el.drawAmount.value);
  if (!isAddress(drawAddress) || amount <= 0n) throw new Error("Enter a valid draw amount.");
  playPenaltyShot();
  const draw = new ethers.Contract(drawAddress, DRAW_ABI, signer);
  const tx = await draw.enter(amount);
  showToast(`Penalty draw sent: ${tx.hash}`);
  await tx.wait();
  await refreshLiveState({ force: true });
}

function updateCountdowns() {
  const now = Math.floor(Date.now() / 1000);
  el.signalCountdown.textContent = cachedSignalDeadline > 0n ? formatCountdown(Number(cachedSignalDeadline) - now) : "Waiting";
  el.drawCountdown.textContent =
    cachedDrawDeadline > 0n ? formatDrawCountdown(Number(cachedDrawDeadline) - now, cachedDrawSettlementBlock) : "Waiting";
}

function syncPenaltyScene(seed = 0n) {
  if (!el.penaltyStage || !el.goalKeeper || !el.penaltyBall) return;
  const variants = ["left", "center", "right"];
  const keeperIndex = Number(seed % 3n);
  const ballIndex = Number((seed + 1n) % 3n);
  setPenaltyStar(Number(seed % BigInt(PENALTY_STARS.length)));
  el.goalKeeper.dataset.side = variants[keeperIndex];
  el.penaltyBall.dataset.path = variants[ballIndex];
}

function playPenaltyShot() {
  if (!el.penaltyStage || !el.goalKeeper || !el.penaltyBall) return;
  const variants = ["left", "center", "right"];
  const keeperSide = variants[Math.floor(Math.random() * variants.length)];
  const ballPath = variants[Math.floor(Math.random() * variants.length)];
  const starIndex = Math.floor(Math.random() * PENALTY_STARS.length);
  const goal = keeperSide !== ballPath || Math.random() > 0.55;

  el.penaltyStage.classList.remove("goal", "save", "shooting", "chaseBurst");
  void el.penaltyStage.offsetWidth;

  const star = setPenaltyStar(starIndex);
  el.goalKeeper.dataset.side = keeperSide;
  el.penaltyBall.dataset.path = ballPath;
  el.penaltyStage.classList.add("shooting", "chaseBurst", goal ? "goal" : "save");

  if (el.shotOutcome) {
    el.shotOutcome.textContent = goal ? `${star.name} GOAL LOOK` : `${star.name} SAVE LOOK`;
  }
  if (el.shotDetail) {
    el.shotDetail.textContent = goal
      ? `${star.tag} breaks through. The real payout waits for the future-block seed settle.`
      : `${star.tag} gets stopped visually. Your burn still entered the weighted round.`;
  }
}

function setPenaltyStar(index) {
  const star = PENALTY_STARS[index % PENALTY_STARS.length] || PENALTY_STARS[0];
  if (el.penaltyStage) {
    el.penaltyStage.dataset.star = star.key;
  }
  document.querySelectorAll("[data-runner]").forEach((runner, runnerIndex) => {
    runner.dataset.star = PENALTY_STARS[(index + runnerIndex) % PENALTY_STARS.length].key;
  });
  return star;
}

function setPendingState() {
  currentPoolPriceRaw = 0n;
  cachedDrawSettlementBlock = 0n;
  el.protocolStatus.textContent = "Awaiting config";
  el.curveStatus.textContent = "Pending";
  el.feeStatus.textContent = "Set launcher to read chain";
  [
    "totalSupply",
    "genesisMinted",
    "curveReserve",
    "currentPrice",
    "myTokenBalance",
    "curveRemaining",
    "currentFuseTax",
    "fuseHighPrice",
    "fuseMode",
    "claimRemaining",
    "claimedWallets",
    "claimShare",
    "claimSourceBalance",
    "lpTokenPreview",
    "lpPoolPrice",
    "lpManagerStatus",
    "lpTrackedEth",
    "lpBoostBps",
    "lpPendingReward",
    "lpFuseShare",
    "jackpotBalance",
    "lastBuyer",
    "jackpotLastWinner",
    "jackpotLastPayout",
    "drawBalance",
    "drawEntries",
    "drawLastWinner",
    "drawLastPayout",
  ].forEach((id) => {
    if (el[id]) el[id].textContent = "-";
  });
  if (el.curveDialLabel) el.curveDialLabel.textContent = "-";
  el.signalCountdown.textContent = "Waiting";
  el.drawCountdown.textContent = "Waiting";
  if (el.shotOutcome) el.shotOutcome.textContent = "READY";
  if (el.shotDetail) {
    el.shotDetail.textContent = "Burn any time. Every burn logs one weighted shot into the live 17-minute round.";
  }
}

function percentToAmount(balance, percent) {
  if (!balance || percent <= 0) return 0n;
  return (balance * BigInt(Math.round(percent * 10))) / 1000n;
}

function selectedSellAmountRaw() {
  return percentToAmount(myTokenBalanceRaw, Number(el.sellPercent?.value || "0"));
}

function parseUnitsSafe(value) {
  try {
    const trimmed = String(value || "").replace(/,/g, "").trim();
    if (!trimmed) return 0n;
    return ethers.parseUnits(trimmed, 18);
  } catch {
    return 0n;
  }
}

function formatInputToken(value, decimals = 4) {
  const [whole, fraction = ""] = ethers.formatUnits(value, 18).split(".");
  const trimmedFraction = fraction.slice(0, decimals).replace(/0+$/, "");
  return trimmedFraction ? `${whole}.${trimmedFraction}` : whole;
}

function formatEth(value) {
  return formatDecimal(ethers.formatEther(value), 4);
}

function formatToken(value, decimals = 2) {
  return formatDecimal(ethers.formatUnits(value, 18), decimals);
}

function formatGwei(value) {
  return formatDecimal(ethers.formatUnits(value, "gwei"), 4);
}

function formatDecimal(value, decimals = 2) {
  const num = Number(value);
  if (!Number.isFinite(num)) return String(value);
  return num.toLocaleString(undefined, {
    minimumFractionDigits: 0,
    maximumFractionDigits: decimals,
  });
}

function formatBps(bps) {
  return `${(Number(bps) / 100).toFixed(2)}%`;
}

function formatTradeSplit(totalBps, apiBps, signalBps, lpBps, drawBps, fuseBps, grossFill) {
  return `Trade tax now ${formatBps(totalBps)}: API ${formatBps(apiBps)}, last buyer ${formatBps(signalBps)}, LP ${formatBps(lpBps)}, penalty draw ${formatBps(drawBps)}. ${formatFuseTax(fuseBps)}; curve fills at ${formatEth(grossFill)} ETH.`;
}

function formatFuseTax(bps) {
  if (BigInt(bps) === 0n) return "No extra fuse sell tax";
  return `Extra fuse sell tax ${formatBps(bps)}`;
}

function formatLpRewardRule(baseBps, fuseShareBps) {
  return `${formatBps(baseBps)} of every trade + ${formatBps(fuseShareBps)} of any fuse tax`;
}

function formatFuseWindow(seconds) {
  if (Number(seconds) <= 1800) return "Rapid window: 30 minutes";
  if (Number(seconds) <= 10800) return "Slow window: 3 hours";
  return `Window: ${Math.round(Number(seconds) / 3600)} hours`;
}

function formatEligibility(balance) {
  if (balance > 0n) return `Eligible / ${formatToken(balance, 2)}`;
  return "No SOTO balance";
}

function formatCountdown(seconds) {
  if (seconds <= 0) return "Armed / next touch";
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  if (h > 0) return `${h}h ${m}m ${s}s`;
  return `${m}m ${s}s`;
}

function formatDrawCountdown(seconds, settlementBlock) {
  if (settlementBlock > 0n) {
    if (readBlock <= settlementBlock) return `Seed block ${settlementBlock.toString()}`;
    return "Seed locked / next touch";
  }
  return formatCountdown(seconds);
}

function cleanAddress(value) {
  return String(value || "").trim();
}

function isAddress(value) {
  try {
    return !!value && ethers.isAddress(value);
  } catch {
    return false;
  }
}

function short(value) {
  if (!value || !isAddress(value) || /^0x0+$/.test(value)) return "-";
  return `${value.slice(0, 6)}...${value.slice(-4)}`;
}

function humanError(error) {
  const message =
    error?.shortMessage ||
    error?.reason ||
    error?.info?.error?.message ||
    error?.message ||
    "Unknown error.";
  return message.replace(/^execution reverted: /i, "");
}

function showToast(message) {
  if (!el.toast) return;
  el.toast.textContent = message;
  el.toast.classList.add("show");
  clearTimeout(showToast.timer);
  showToast.timer = setTimeout(() => el.toast.classList.remove("show"), 3400);
}

function wire() {
  loadConfig();
  setPendingState();

  el.saveConfigBtn?.addEventListener("click", () => {
    saveConfig();
    refreshLiveState({ force: true }).catch((error) => showToast(humanError(error)));
  });
  el.connectBtn?.addEventListener("click", () => connectWallet().catch((error) => showToast(humanError(error))));
  el.refreshBtn?.addEventListener("click", () =>
    refreshLiveState({ force: true }).catch((error) => showToast(humanError(error)))
  );
  el.mintBtn?.addEventListener("click", () => mintTokens().catch((error) => showToast(humanError(error))));
  el.claimBtn?.addEventListener("click", () => claimFreeMint().catch((error) => showToast(humanError(error))));
  el.lpAddBtn?.addEventListener("click", () => addOfficialLp().catch((error) => showToast(humanError(error))));
  el.lpClaimBtn?.addEventListener("click", () => claimLpEth().catch((error) => showToast(humanError(error))));
  el.approveSellBtn?.addEventListener("click", () => approveSell().catch((error) => showToast(humanError(error))));
  el.sellBtn?.addEventListener("click", () => sellTokens().catch((error) => showToast(humanError(error))));
  el.approveDrawBtn?.addEventListener("click", () => approveDraw().catch((error) => showToast(humanError(error))));
  el.drawEnterBtn?.addEventListener("click", () => enterDraw().catch((error) => showToast(humanError(error))));

  ["mintEth", "drawAmount", "lpEthInput"].forEach((id) =>
    el[id]?.addEventListener("input", () => updateQuotes().catch(() => {}))
  );
  el.sellPercent?.addEventListener("input", () => updateQuotes().catch(() => {}));
  el.drawPercent?.addEventListener("input", () => updateQuotes().catch(() => {}));
  sellPresetButtons.forEach((button) =>
    button.addEventListener("click", () => {
      el.sellPercent.value = button.dataset.sellPreset || "0";
      updateQuotes().catch(() => {});
    })
  );
  ["launcherAddress", "tokenAddress", "jackpotAddress", "drawAddress"].forEach((id) =>
    el[id]?.addEventListener("change", () => refreshLiveState({ quiet: true, force: true }).catch(() => {}))
  );

  refreshLiveState({ force: true }).catch((error) => showToast(humanError(error)));
  startLiveRefresh();
}

wire();
