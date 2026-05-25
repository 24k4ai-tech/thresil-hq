const { ethers } = window;

const CONFIG_KEY = "oracle777.flapPenalty.config.v1";
const BNB_CHAIN_ID = 56;
const BNB_CHAIN_HEX = "0x38";
const RPC_URLS = [
  "https://bsc-dataseed.binance.org",
  "https://bsc-dataseed1.bnbchain.org",
  "https://bsc-dataseed2.bnbchain.org",
];
const COUNTDOWN_REFRESH_MS = 1000;
const CHAIN_REFRESH_MS = 12000;
const WAD = 10n ** 18n;

const DEFAULT_CONFIG = {
  vault: "",
  token: "",
};

const TOKEN_ABI = [
  "function symbol() view returns (string)",
  "function balanceOf(address account) view returns (uint256)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
];

const VAULT_ABI = [
  "function taxTokenAddress() view returns (address)",
  "function taxToken() view returns (address)",
  "function devWallet() view returns (address)",
  "function round() view returns (uint256)",
  "function roundEndsAt() view returns (uint256)",
  "function currentRoundWeight() view returns (uint256)",
  "function pendingVrfRequestId() view returns (uint256)",
  "function pendingSettlementPayout() view returns (uint256)",
  "function currentEntryCount() view returns (uint256)",
  "function availablePot() view returns (uint256)",
  "function currentPayoutQuote() view returns (uint256)",
  "function lastWinner() view returns (address)",
  "function lastPayout() view returns (uint256)",
  "function totalDeadBurned() view returns (uint256)",
  "function launchTimestamp() view returns (uint256)",
  "function DEV_WINDOW() view returns (uint256)",
  "function PAYOUT_BPS() view returns (uint256)",
  "function EARLY_DEV_SHARE_BPS() view returns (uint256)",
  "function vrfConfigured() view returns (bool)",
  "function totalVrfFunded() view returns (uint256)",
  "function shooterAgeBoostBps(address player) view returns (uint256)",
  "function shoot(uint256 tokenAmount) returns (uint256)",
  "function poke() returns (bool settled, uint256 payout, address winner)",
];

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
    "feeStatus",
    "refreshBtn",
    "connectBtn",
    "flapVaultAddress",
    "flapTokenAddress",
    "flapSaveConfigBtn",
    "flapTokenSymbol",
    "flapPot",
    "flapPayoutQuote",
    "flapRound",
    "flapCountdown",
    "flapEntries",
    "flapWeight",
    "flapLastWinner",
    "flapLastPayout",
    "flapMyBalance",
    "flapAllowance",
    "flapBoost",
    "flapBurnPercent",
    "flapBurnPercentValue",
    "flapBurnPreview",
    "flapBurnAmount",
    "flapApproveBtn",
    "flapShootBtn",
    "flapPokeBtn",
    "flapPenaltyStage",
    "flapGoalKeeper",
    "flapPenaltyBall",
    "flapShotOutcome",
    "flapShotDetail",
    "toast",
  ].map((id) => [id, document.getElementById(id)])
);

let browserProvider;
let signer;
let account = "";
let chainId = 0;
let readBlock = 0n;
let tokenSymbol = "777X";
let myTokenBalanceRaw = 0n;
let selectedBurnRaw = 0n;
let cachedRoundEndsAt = 0n;
let cachedVrfRequestId = 0n;
let refreshInFlight;
let countdownTimer = 0;
let chainRefreshTimer = 0;
let currentConfig = { ...DEFAULT_CONFIG };

function loadConfig() {
  let saved = {};
  try {
    saved = JSON.parse(localStorage.getItem(CONFIG_KEY) || "{}");
  } catch {}
  currentConfig = { ...DEFAULT_CONFIG };
  Object.keys(DEFAULT_CONFIG).forEach((key) => {
    if (isAddress(saved[key])) currentConfig[key] = saved[key];
  });
  if (el.flapVaultAddress) el.flapVaultAddress.value = currentConfig.vault || "";
  if (el.flapTokenAddress) el.flapTokenAddress.value = currentConfig.token || "";
}

function saveConfig() {
  currentConfig = {
    vault: cleanAddress(el.flapVaultAddress?.value),
    token: cleanAddress(el.flapTokenAddress?.value),
  };
  localStorage.setItem(CONFIG_KEY, JSON.stringify(currentConfig));
  showToast("Local Flap penalty config saved.");
}

async function connectWallet() {
  if (!window.ethereum) throw new Error("No injected wallet found.");
  browserProvider = new ethers.BrowserProvider(window.ethereum);
  await browserProvider.send("eth_requestAccounts", []);
  signer = await browserProvider.getSigner();
  account = await signer.getAddress();
  const network = await browserProvider.getNetwork();
  chainId = Number(network.chainId);
  if (chainId !== BNB_CHAIN_ID) {
    await switchToBnbChain();
    browserProvider = new ethers.BrowserProvider(window.ethereum);
    signer = await browserProvider.getSigner();
    account = await signer.getAddress();
    chainId = Number((await browserProvider.getNetwork()).chainId);
  }
  el.networkStatus.textContent =
    chainId === BNB_CHAIN_ID ? `${short(account)} on BNB Chain` : `${short(account)} on chain ${chainId}`;
  el.connectBtn.textContent = "Wallet Connected";
  bindWalletEvents();
  await refreshLiveState({ force: true });
}

async function switchToBnbChain() {
  try {
    await window.ethereum.request({ method: "wallet_switchEthereumChain", params: [{ chainId: BNB_CHAIN_HEX }] });
  } catch (error) {
    if (error?.code !== 4902) throw error;
    await window.ethereum.request({
      method: "wallet_addEthereumChain",
      params: [
        {
          chainId: BNB_CHAIN_HEX,
          chainName: "BNB Smart Chain",
          nativeCurrency: { name: "BNB", symbol: "BNB", decimals: 18 },
          rpcUrls: [RPC_URLS[0]],
          blockExplorerUrls: ["https://bscscan.com"],
        },
      ],
    });
  }
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
      const provider = new ethers.JsonRpcProvider(url, BNB_CHAIN_ID);
      await provider.getBlockNumber();
      return provider;
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError || new Error("No BNB Chain RPC available.");
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

async function refresh() {
  const provider = await getReadProvider();
  readBlock = BigInt(await provider.getBlockNumber());
  el.blockNumber.textContent = readBlock.toString();

  const vaultAddress = cleanAddress(el.flapVaultAddress?.value) || currentConfig.vault;
  if (!isAddress(vaultAddress)) {
    setPendingState();
    return;
  }
  if (el.flapVaultAddress && !isAddress(el.flapVaultAddress.value)) el.flapVaultAddress.value = vaultAddress;

  const vault = new ethers.Contract(vaultAddress, VAULT_ABI, provider);
  let tokenAddress = cleanAddress(el.flapTokenAddress?.value) || currentConfig.token;
  if (!isAddress(tokenAddress)) {
    tokenAddress = await vault.taxTokenAddress().catch(() => vault.taxToken());
  }
  if (el.flapTokenAddress && isAddress(tokenAddress) && !isAddress(el.flapTokenAddress.value)) {
    el.flapTokenAddress.value = tokenAddress;
  }
  if (!isAddress(tokenAddress)) {
    setPendingState("Set token address or deploy a vault that exposes taxToken.");
    return;
  }

  const token = new ethers.Contract(tokenAddress, TOKEN_ABI, provider);
  const [
    symbol,
    pot,
    payoutQuote,
    round,
    roundEndsAt,
    entries,
    weight,
    vrfRequestId,
    pendingPayout,
    lastWinner,
    lastPayout,
    totalDeadBurned,
    launchTimestamp,
    devWindow,
    earlyDevShareBps,
    vrfConfigured,
    totalVrfFunded,
    myBalance,
    allowance,
    boostBps,
  ] = await Promise.all([
    token.symbol().catch(() => "777X"),
    vault.availablePot(),
    vault.currentPayoutQuote(),
    vault.round(),
    vault.roundEndsAt(),
    vault.currentEntryCount(),
    vault.currentRoundWeight(),
    vault.pendingVrfRequestId(),
    vault.pendingSettlementPayout(),
    vault.lastWinner(),
    vault.lastPayout(),
    vault.totalDeadBurned(),
    vault.launchTimestamp(),
    vault.DEV_WINDOW(),
    vault.EARLY_DEV_SHARE_BPS(),
    vault.vrfConfigured().catch(() => false),
    vault.totalVrfFunded().catch(() => 0n),
    account ? token.balanceOf(account) : 0n,
    account ? token.allowance(account, vaultAddress) : 0n,
    account ? vault.shooterAgeBoostBps(account) : 0n,
  ]);

  tokenSymbol = symbol || "777X";
  myTokenBalanceRaw = myBalance;
  cachedRoundEndsAt = roundEndsAt;
  cachedVrfRequestId = vrfRequestId;

  el.protocolStatus.textContent = "Flap penalty mode";
  el.feeStatus.textContent = formatTaxStatus(earlyDevShareBps, launchTimestamp, devWindow, vrfConfigured, totalVrfFunded);
  el.flapTokenSymbol.textContent = tokenSymbol;
  el.flapPot.textContent = `${formatBnb(pot)} BNB`;
  el.flapPayoutQuote.textContent =
    pendingPayout > 0n ? `Armed: ${formatBnb(pendingPayout)} BNB` : `${formatBnb(payoutQuote)} BNB`;
  el.flapRound.textContent = round.toString();
  el.flapEntries.textContent = entries.toString();
  el.flapWeight.textContent = formatWeight(weight);
  el.flapLastWinner.textContent = short(lastWinner);
  el.flapLastPayout.textContent = `${formatBnb(lastPayout)} BNB`;
  el.flapMyBalance.textContent = account ? `${formatToken(myBalance)} ${tokenSymbol}` : "Connect wallet";
  el.flapAllowance.textContent = account ? `${formatToken(allowance)} ${tokenSymbol}` : "Connect wallet";
  el.flapBoost.textContent = account ? formatBps(boostBps) : "Connect wallet";

  const deadBurnNote = `Total dead-burned: ${formatToken(totalDeadBurned)} ${tokenSymbol}`;
  if (el.flapShotDetail && !el.flapPenaltyStage?.classList.contains("shooting")) {
    el.flapShotDetail.textContent = deadBurnNote;
  }

  updateBurnSelection();
  updateCountdowns();
  syncPenaltyScene(entries);
}

function updateBurnSelection() {
  const exact = parseUnitsSafe(el.flapBurnAmount?.value);
  const percent = Number(el.flapBurnPercent?.value || "0");
  const sliderAmount = percentToAmount(myTokenBalanceRaw, percent);
  selectedBurnRaw = exact > 0n ? exact : sliderAmount;
  if (el.flapBurnPercentValue) el.flapBurnPercentValue.textContent = `${percent.toFixed(1)}%`;
  if (el.flapBurnPreview) {
    el.flapBurnPreview.textContent = `${formatToken(selectedBurnRaw)} ${tokenSymbol}`;
  }
}

async function approveBurn() {
  if (!signer) throw new Error("Connect wallet first.");
  const vaultAddress = cleanAddress(el.flapVaultAddress?.value);
  const tokenAddress = cleanAddress(el.flapTokenAddress?.value);
  updateBurnSelection();
  if (!isAddress(vaultAddress) || !isAddress(tokenAddress) || selectedBurnRaw <= 0n) {
    throw new Error("Set vault, token, and burn amount first.");
  }
  const token = new ethers.Contract(tokenAddress, TOKEN_ABI, signer);
  const tx = await token.approve(vaultAddress, selectedBurnRaw);
  showToast(`Approve sent: ${tx.hash}`);
  await tx.wait();
  await refreshLiveState({ force: true });
}

async function shootPenalty() {
  if (!signer) throw new Error("Connect wallet first.");
  const vaultAddress = cleanAddress(el.flapVaultAddress?.value);
  updateBurnSelection();
  if (!isAddress(vaultAddress) || selectedBurnRaw <= 0n) throw new Error("Enter a valid burn amount.");
  playPenaltyShot();
  const vault = new ethers.Contract(vaultAddress, VAULT_ABI, signer);
  const tx = await vault.shoot(selectedBurnRaw);
  showToast(`Penalty burn sent: ${tx.hash}`);
  await tx.wait();
  await refreshLiveState({ force: true });
}

async function pokeSettlement() {
  if (!signer) throw new Error("Connect wallet first.");
  const vaultAddress = cleanAddress(el.flapVaultAddress?.value);
  if (!isAddress(vaultAddress)) throw new Error("Set vault first.");
  const vault = new ethers.Contract(vaultAddress, VAULT_ABI, signer);
  const tx = await vault.poke();
  showToast(`Poke sent: ${tx.hash}`);
  await tx.wait();
  await refreshLiveState({ force: true });
}

function updateCountdowns() {
  const now = Math.floor(Date.now() / 1000);
  if (!el.flapCountdown) return;
  if (cachedVrfRequestId > 0n) {
    el.flapCountdown.textContent = `VRF pending #${cachedVrfRequestId.toString()}`;
    return;
  }
  el.flapCountdown.textContent = cachedRoundEndsAt > 0n ? formatCountdown(Number(cachedRoundEndsAt) - now) : "Waiting";
}

function syncPenaltyScene(seed = 0n) {
  if (!el.flapPenaltyStage || !el.flapGoalKeeper || !el.flapPenaltyBall) return;
  const variants = ["left", "center", "right"];
  const keeperIndex = Number(seed % 3n);
  const ballIndex = Number((seed + 1n) % 3n);
  setPenaltyStar(Number(seed % BigInt(PENALTY_STARS.length)));
  el.flapGoalKeeper.dataset.side = variants[keeperIndex];
  el.flapPenaltyBall.dataset.path = variants[ballIndex];
}

function playPenaltyShot() {
  if (!el.flapPenaltyStage || !el.flapGoalKeeper || !el.flapPenaltyBall) return;
  const variants = ["left", "center", "right"];
  const keeperSide = variants[Math.floor(Math.random() * variants.length)];
  const ballPath = variants[Math.floor(Math.random() * variants.length)];
  const starIndex = Math.floor(Math.random() * PENALTY_STARS.length);
  const goal = keeperSide !== ballPath || Math.random() > 0.55;

  el.flapPenaltyStage.classList.remove("goal", "save", "shooting", "chaseBurst");
  void el.flapPenaltyStage.offsetWidth;

  const star = setPenaltyStar(starIndex);
  el.flapGoalKeeper.dataset.side = keeperSide;
  el.flapPenaltyBall.dataset.path = ballPath;
  el.flapPenaltyStage.classList.add("shooting", "chaseBurst", goal ? "goal" : "save");
  el.flapShotOutcome.textContent = goal ? `${star.name} GOAL LOOK` : `${star.name} SAVE LOOK`;
  el.flapShotDetail.textContent = `${star.tag}: animation only. Onchain settlement picks the actual winner later.`;
}

function setPenaltyStar(index) {
  const star = PENALTY_STARS[index % PENALTY_STARS.length] || PENALTY_STARS[0];
  if (el.flapPenaltyStage) el.flapPenaltyStage.dataset.star = star.key;
  document.querySelectorAll("[data-flap-runner]").forEach((runner, runnerIndex) => {
    runner.dataset.star = PENALTY_STARS[(index + runnerIndex) % PENALTY_STARS.length].key;
  });
  return star;
}

function setPendingState(message = "Set Flap vault to read chain") {
  el.protocolStatus.textContent = "Awaiting Flap vault";
  el.feeStatus.textContent = message;
  [
    "flapPot",
    "flapPayoutQuote",
    "flapRound",
    "flapEntries",
    "flapWeight",
    "flapLastWinner",
    "flapLastPayout",
    "flapMyBalance",
    "flapAllowance",
    "flapBoost",
  ].forEach((id) => {
    if (el[id]) el[id].textContent = "-";
  });
  cachedRoundEndsAt = 0n;
  cachedVrfRequestId = 0n;
  myTokenBalanceRaw = 0n;
  updateBurnSelection();
  updateCountdowns();
}

function formatTaxStatus(earlyDevShareBps, launchTimestamp, devWindow, vrfConfigured, totalVrfFunded) {
  const earlyShare = formatBps(earlyDevShareBps);
  const end = Number(launchTimestamp + devWindow);
  const left = end - Math.floor(Date.now() / 1000);
  const devStatus = left > 0 ? `early dev share ${earlyShare} of vault inflow, ${formatCountdown(left)} left` : "early dev share ended";
  const vrfStatus = vrfConfigured ? `VRF on; funded ${formatBnb(totalVrfFunded)} BNB` : "VRF not configured";
  return `Flap target tax: 3% buy / 3% sell. Vault pays 30% pot per round; ${devStatus}; ${vrfStatus}.`;
}

function percentToAmount(balance, percent) {
  if (!balance || percent <= 0) return 0n;
  return (balance * BigInt(Math.round(percent * 10))) / 1000n;
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

function formatBnb(value) {
  return formatDecimal(ethers.formatEther(value), 4);
}

function formatToken(value, decimals = 2) {
  return formatDecimal(ethers.formatUnits(value, 18), decimals);
}

function formatWeight(value) {
  const num = Number(value);
  if (!Number.isFinite(num)) return value.toString();
  return num.toLocaleString(undefined, { maximumFractionDigits: 0 });
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

function formatCountdown(seconds) {
  if (seconds <= 0) return "Ready / next touch";
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  if (h > 0) return `${h}h ${m}m ${s}s`;
  return `${m}m ${s}s`;
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

function wire() {
  loadConfig();
  setPendingState();

  el.connectBtn?.addEventListener("click", () => connectWallet().catch((error) => showToast(humanError(error))));
  el.refreshBtn?.addEventListener("click", () =>
    refreshLiveState({ force: true }).catch((error) => showToast(humanError(error)))
  );
  el.flapSaveConfigBtn?.addEventListener("click", () => {
    saveConfig();
    refreshLiveState({ force: true }).catch((error) => showToast(humanError(error)));
  });
  el.flapApproveBtn?.addEventListener("click", () => approveBurn().catch((error) => showToast(humanError(error))));
  el.flapShootBtn?.addEventListener("click", () => shootPenalty().catch((error) => showToast(humanError(error))));
  el.flapPokeBtn?.addEventListener("click", () => pokeSettlement().catch((error) => showToast(humanError(error))));
  el.flapBurnPercent?.addEventListener("input", updateBurnSelection);
  el.flapBurnAmount?.addEventListener("input", updateBurnSelection);
  ["flapVaultAddress", "flapTokenAddress"].forEach((id) =>
    el[id]?.addEventListener("change", () => refreshLiveState({ quiet: true, force: true }).catch(() => {}))
  );

  refreshLiveState({ force: true }).catch((error) => showToast(humanError(error)));
  startLiveRefresh();
}

wire();
