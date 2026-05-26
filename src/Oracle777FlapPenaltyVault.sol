// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IOracle777FlapERC20 {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

library Oracle777VRFV2PlusClient {
    bytes4 internal constant EXTRA_ARGS_V1_TAG = bytes4(keccak256("VRF ExtraArgsV1"));

    struct ExtraArgsV1 {
        bool nativePayment;
    }

    struct RandomWordsRequest {
        bytes32 keyHash;
        uint256 subId;
        uint16 requestConfirmations;
        uint32 callbackGasLimit;
        uint32 numWords;
        bytes extraArgs;
    }

    function argsToBytes(ExtraArgsV1 memory extraArgs) internal pure returns (bytes memory bts) {
        return abi.encodeWithSelector(EXTRA_ARGS_V1_TAG, extraArgs);
    }
}

interface IOracle777VRFCoordinatorV2Plus {
    function requestRandomWords(Oracle777VRFV2PlusClient.RandomWordsRequest calldata req)
        external
        returns (uint256 requestId);

    function fundSubscriptionWithNative(uint256 subId) external payable;
}

struct Oracle777VrfConfig {
    address coordinator;
    uint256 subId;
    bytes32 keyHash;
    uint32 callbackGasLimit;
    uint16 requestConfirmations;
    uint256 nativeTopUpAmount;
}

struct FlapFieldDescriptor {
    string name;
    string fieldType;
    string description;
    uint8 decimals;
}

struct FlapApproveAction {
    string tokenType;
    string amountFieldName;
}

struct FlapVaultMethodSchema {
    string name;
    string description;
    FlapFieldDescriptor[] inputs;
    FlapFieldDescriptor[] outputs;
    FlapApproveAction[] approvals;
    bool isInputArray;
    bool isOutputArray;
    bool isWriteMethod;
}

struct FlapVaultUISchema {
    string vaultType;
    string description;
    FlapVaultMethodSchema[] methods;
}

struct FlapVaultDataSchema {
    string description;
    FlapFieldDescriptor[] fields;
    bool isArray;
}

/// @title Oracle777FlapPenaltyVault
/// @notice Flap-compatible BNB tax vault plus voluntary dead-address penalty game.
contract Oracle777FlapPenaltyVault {
    struct Entry {
        address player;
        uint256 cumulativeWeight;
        uint256 burnedAmount;
        uint256 weight;
    }

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant PAYOUT_BPS = 3_000;
    uint256 public constant ROUND_DURATION = 17 minutes;
    uint256 public constant DEV_WINDOW = 77 minutes;
    uint256 public constant EARLY_DEV_SHARE_BPS = 3_333;
    uint256 public constant MIN_AUTO_TOUCH_GAS = 350_000;
    uint32 public constant VRF_NUM_WORDS = 1;
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    IOracle777FlapERC20 public immutable taxToken;
    address public immutable devWallet;
    address public immutable creator;
    uint256 public immutable launchTimestamp;
    IOracle777VRFCoordinatorV2Plus public immutable vrfCoordinator;
    uint256 public immutable vrfSubId;
    bytes32 public immutable vrfKeyHash;
    uint32 public immutable vrfCallbackGasLimit;
    uint16 public immutable vrfRequestConfirmations;
    uint256 public immutable vrfNativeTopUpAmount;

    uint256 public round;
    uint256 public roundEndsAt;
    uint256 public currentRoundWeight;
    uint256 public pendingVrfRequestId;
    uint256 public pendingSettlementRound;
    uint256 public pendingSettlementWeight;
    uint256 public pendingSettlementPayout;
    uint256 public reservedFailedPayouts;
    uint256 public pendingDevPayout;
    uint256 public totalDeadBurned;
    uint256 public totalTaxReceived;
    uint256 public totalDevPaid;
    uint256 public totalVrfFunded;
    uint256 public totalPaid;
    address public lastWinner;
    uint256 public lastPayout;
    uint256 public lastWinningWeight;
    uint256 public lastVrfTopUpRound = type(uint256).max;

    mapping(uint256 roundId => Entry[]) private roundEntries;
    mapping(address player => uint256) public firstShotAt;
    mapping(address player => uint256) public pendingPayout;

    bool private locked;

    event TaxReceived(address indexed payer, uint256 amount, uint256 devAmount, uint256 potAmount);
    event Shot(
        uint256 indexed round,
        address indexed player,
        uint256 burnedAmount,
        uint256 weight,
        uint256 cumulativeWeight,
        uint256 roundEndsAt
    );
    event RoundSettlementArmed(uint256 indexed round, uint256 seedBlock, uint256 totalWeight, uint256 payout);
    event VrfRequested(uint256 indexed round, uint256 indexed requestId, uint256 totalWeight, uint256 payout);
    event VrfRequestFailed(uint256 indexed round, bytes reason);
    event VrfSubscriptionFunded(uint256 indexed round, uint256 amount);
    event RoundSettled(
        uint256 indexed round, address indexed winner, uint256 payout, uint256 winningWeight, uint256 totalWeight
    );
    event RoundCarried(uint256 indexed round);
    event PayoutReserved(address indexed winner, uint256 amount);
    event PendingPayoutClaimed(address indexed winner, uint256 amount);
    event DevPaid(address indexed devWallet, uint256 amount);
    event DevPayoutReserved(uint256 amount);

    error ReentrantCall();
    error OnlyVrfCoordinator();
    error ZeroAddress();
    error ZeroAmount();
    error TransferFailed();
    error NothingToClaim();
    error UnsupportedQuoteToken();
    error VrfNotConfigured();
    error RoundNeedsSettlement();

    modifier nonReentrant() {
        if (locked) revert ReentrantCall();
        locked = true;
        _;
        locked = false;
    }

    constructor(IOracle777FlapERC20 taxToken_, address devWallet_, address creator_, Oracle777VrfConfig memory vrfConfig) {
        if (address(taxToken_) == address(0) || devWallet_ == address(0) || creator_ == address(0)) {
            revert ZeroAddress();
        }
        if (vrfConfig.coordinator == address(0) || vrfConfig.subId == 0 || vrfConfig.keyHash == bytes32(0)) {
            revert VrfNotConfigured();
        }
        taxToken = taxToken_;
        devWallet = devWallet_;
        creator = creator_;
        launchTimestamp = block.timestamp;
        roundEndsAt = block.timestamp + ROUND_DURATION;
        vrfCoordinator = IOracle777VRFCoordinatorV2Plus(vrfConfig.coordinator);
        vrfSubId = vrfConfig.subId;
        vrfKeyHash = vrfConfig.keyHash;
        vrfCallbackGasLimit = vrfConfig.callbackGasLimit == 0 ? 240_000 : vrfConfig.callbackGasLimit;
        vrfRequestConfirmations = vrfConfig.requestConfirmations == 0 ? 3 : vrfConfig.requestConfirmations;
        vrfNativeTopUpAmount = vrfConfig.nativeTopUpAmount;
    }

    function description() public pure returns (string memory) {
        return
            "Oracle777 Flap Penalty Vault: receives BNB tax, sends early dev share for 77 minutes, keeps the rest in a 17-minute penalty pot, requests Chainlink VRF, and pays 30% of available pot per settled round.";
    }

    function taxTokenAddress() external view returns (address) {
        return address(taxToken);
    }

    function currentEntryCount() external view returns (uint256) {
        return roundEntries[round].length;
    }

    function roundEntryCount(uint256 roundId) external view returns (uint256) {
        return roundEntries[roundId].length;
    }

    function roundEntry(uint256 roundId, uint256 index)
        external
        view
        returns (address player, uint256 weight, uint256 burnedAmount)
    {
        Entry storage entry = roundEntries[roundId][index];
        return (entry.player, entry.weight, entry.burnedAmount);
    }

    function availablePot() public view returns (uint256) {
        uint256 reserved = reservedFailedPayouts + pendingSettlementPayout + pendingDevPayout;
        uint256 balance = address(this).balance;
        return balance > reserved ? balance - reserved : 0;
    }

    function currentPayoutQuote() external view returns (uint256) {
        return (availablePot() * PAYOUT_BPS) / BPS_DENOMINATOR;
    }

    function vrfConfigured() public view returns (bool) {
        return address(vrfCoordinator) != address(0) && vrfSubId != 0 && vrfKeyHash != bytes32(0);
    }

    function shooterAgeBoostBps(address player) public view returns (uint256) {
        uint256 first = firstShotAt[player];
        if (first == 0 || block.timestamp <= first) return 0;
        uint256 age = block.timestamp - first;
        if (age >= 24 hours) return 2_500;
        if (age >= 6 hours) return 1_700;
        if (age >= 77 minutes) return 1_000;
        if (age >= 17 minutes) return 500;
        return 0;
    }

    function shoot(uint256 tokenAmount) external nonReentrant returns (uint256 weight) {
        if (tokenAmount == 0) revert ZeroAmount();
        _touch();
        if (block.timestamp >= roundEndsAt) revert RoundNeedsSettlement();

        if (!taxToken.transferFrom(msg.sender, DEAD_ADDRESS, tokenAmount)) revert TransferFailed();
        totalDeadBurned += tokenAmount;

        weight = _sqrt(tokenAmount);
        if (weight == 0) weight = 1;

        uint256 first = firstShotAt[msg.sender];
        if (first == 0) {
            firstShotAt[msg.sender] = block.timestamp;
        } else {
            uint256 boostBps = shooterAgeBoostBps(msg.sender);
            if (boostBps > 0) {
                weight += (weight * boostBps) / BPS_DENOMINATOR;
            }
        }

        uint256 cumulative = currentRoundWeight + weight;
        roundEntries[round].push(Entry(msg.sender, cumulative, tokenAmount, weight));
        currentRoundWeight = cumulative;

        emit Shot(round, msg.sender, tokenAmount, weight, cumulative, roundEndsAt);
    }

    function poke() external nonReentrant returns (bool settled, uint256 payout, address winner) {
        return _touch();
    }

    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external nonReentrant {
        if (msg.sender != address(vrfCoordinator)) revert OnlyVrfCoordinator();
        if (requestId != pendingVrfRequestId || randomWords.length == 0) return;
        _settleVrfRound(randomWords[0]);
    }

    function claimPendingPayout() external nonReentrant returns (uint256 amount) {
        amount = pendingPayout[msg.sender];
        if (amount == 0) revert NothingToClaim();
        pendingPayout[msg.sender] = 0;
        reservedFailedPayouts -= amount;
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) {
            pendingPayout[msg.sender] = amount;
            reservedFailedPayouts += amount;
            revert TransferFailed();
        }
        emit PendingPayoutClaimed(msg.sender, amount);
    }

    function claimPendingDev() external nonReentrant returns (uint256 amount) {
        if (msg.sender != devWallet) revert NothingToClaim();
        amount = pendingDevPayout;
        if (amount == 0) revert NothingToClaim();
        pendingDevPayout = 0;
        (bool ok,) = devWallet.call{value: amount}("");
        if (!ok) {
            pendingDevPayout = amount;
            revert TransferFailed();
        }
        totalDevPaid += amount;
        emit DevPaid(devWallet, amount);
    }

    function vaultUISchema() public pure returns (FlapVaultUISchema memory schema) {
        schema.vaultType = "Oracle777PenaltyVault";
        schema.description = "Voluntary dead-address burn penalty draw. One 17-minute round requests Chainlink VRF and pays 30% of the available BNB pot.";
        schema.methods = new FlapVaultMethodSchema[](4);

        schema.methods[0].name = "shoot";
        schema.methods[0].description = "Send 777X to the dead address and enter the active penalty round.";
        schema.methods[0].inputs = new FlapFieldDescriptor[](1);
        schema.methods[0].inputs[0] = FlapFieldDescriptor("tokenAmount", "uint256", "777X amount to dead-burn", 18);
        schema.methods[0].approvals = new FlapApproveAction[](1);
        schema.methods[0].approvals[0] = FlapApproveAction("taxToken", "tokenAmount");
        schema.methods[0].isWriteMethod = true;

        schema.methods[1].name = "poke";
        schema.methods[1].description = "Request VRF for a ready round. VRF callback pays the winner automatically.";
        schema.methods[1].isWriteMethod = true;

        schema.methods[2].name = "availablePot";
        schema.methods[2].description = "BNB available for future penalty payouts.";
        schema.methods[2].outputs = new FlapFieldDescriptor[](1);
        schema.methods[2].outputs[0] = FlapFieldDescriptor("pot", "uint256", "Available BNB pot", 18);

        schema.methods[3].name = "currentPayoutQuote";
        schema.methods[3].description = "Current 30% payout quote if the round arms now.";
        schema.methods[3].outputs = new FlapFieldDescriptor[](1);
        schema.methods[3].outputs[0] = FlapFieldDescriptor("payout", "uint256", "30% payout quote", 18);
    }

    receive() external payable nonReentrant {
        _handleIncomingTax(msg.value);
        if (gasleft() >= MIN_AUTO_TOUCH_GAS) {
            _touch();
        }
    }

    function _handleIncomingTax(uint256 amount) internal {
        if (amount == 0) return;
        totalTaxReceived += amount;
        uint256 devAmount;
        if (block.timestamp < launchTimestamp + DEV_WINDOW) {
            devAmount = (amount * EARLY_DEV_SHARE_BPS) / BPS_DENOMINATOR;
            _payDev(devAmount);
        }
        emit TaxReceived(msg.sender, amount, devAmount, amount - devAmount);
    }

    function _payDev(uint256 amount) internal {
        if (amount == 0) return;
        (bool ok,) = devWallet.call{value: amount}("");
        if (ok) {
            totalDevPaid += amount;
            emit DevPaid(devWallet, amount);
        } else {
            pendingDevPayout += amount;
            emit DevPayoutReserved(amount);
        }
    }

    function _touch() internal returns (bool settled, uint256 payout, address winner) {
        if (pendingVrfRequestId != 0) return (false, pendingSettlementPayout, address(0));

        _rollEmptyRoundsIfNeeded();
        if (block.timestamp < roundEndsAt || currentRoundWeight == 0) {
            return (settled, payout, winner);
        }

        if (!vrfConfigured()) return (false, 0, address(0));

        uint256 settledRound = round;
        uint256 totalWeight = currentRoundWeight;
        _fundVrfSubscriptionIfNeeded(settledRound);

        uint256 roundPayout = (availablePot() * PAYOUT_BPS) / BPS_DENOMINATOR;

        Oracle777VRFV2PlusClient.RandomWordsRequest memory request = Oracle777VRFV2PlusClient.RandomWordsRequest({
            keyHash: vrfKeyHash,
            subId: vrfSubId,
            requestConfirmations: vrfRequestConfirmations,
            callbackGasLimit: vrfCallbackGasLimit,
            numWords: VRF_NUM_WORDS,
            extraArgs: Oracle777VRFV2PlusClient.argsToBytes(
                Oracle777VRFV2PlusClient.ExtraArgsV1({nativePayment: true})
            )
        });

        try vrfCoordinator.requestRandomWords(request) returns (uint256 requestId) {
            pendingSettlementRound = settledRound;
            pendingSettlementWeight = totalWeight;
            pendingSettlementPayout = roundPayout;
            pendingVrfRequestId = requestId;

            round = settledRound + 1;
            currentRoundWeight = 0;
            roundEndsAt = block.timestamp + ROUND_DURATION;

            emit VrfRequested(settledRound, requestId, totalWeight, roundPayout);
            return (false, roundPayout, address(0));
        } catch (bytes memory reason) {
            emit VrfRequestFailed(settledRound, reason);
            return (false, 0, address(0));
        }
    }

    function _settleVrfRound(uint256 randomWord) internal returns (bool settled, uint256 payout, address winner) {
        uint256 totalWeight = pendingSettlementWeight;
        if (totalWeight == 0) return (false, 0, address(0));
        uint256 winningWeight = (uint256(keccak256(abi.encode(randomWord, address(this), pendingSettlementRound))) % totalWeight) + 1;

        uint256 settledRound = pendingSettlementRound;
        payout = pendingSettlementPayout;
        winner = _pickWinner(settledRound, winningWeight);

        pendingVrfRequestId = 0;
        pendingSettlementRound = 0;
        pendingSettlementWeight = 0;
        pendingSettlementPayout = 0;

        if (payout > 0) {
            uint256 payableAmount = payout > address(this).balance ? address(this).balance : payout;
            (bool ok,) = winner.call{value: payableAmount}("");
            if (ok) {
                totalPaid += payableAmount;
            } else {
                pendingPayout[winner] += payableAmount;
                reservedFailedPayouts += payableAmount;
                emit PayoutReserved(winner, payableAmount);
            }
        }

        lastWinner = winner;
        lastPayout = payout;
        lastWinningWeight = winningWeight;
        emit RoundSettled(settledRound, winner, payout, winningWeight, totalWeight);
        return (true, payout, winner);
    }

    function _fundVrfSubscriptionIfNeeded(uint256 settledRound) internal {
        uint256 amount = vrfNativeTopUpAmount;
        if (amount == 0 || lastVrfTopUpRound == settledRound || availablePot() <= amount) return;
        lastVrfTopUpRound = settledRound;
        try vrfCoordinator.fundSubscriptionWithNative{value: amount}(vrfSubId) {
            totalVrfFunded += amount;
            emit VrfSubscriptionFunded(settledRound, amount);
        } catch {
            emit VrfRequestFailed(settledRound, "VRF_SUBSCRIPTION_FUNDING_FAILED");
        }
    }

    function _rollEmptyRoundsIfNeeded() internal {
        if (block.timestamp < roundEndsAt || currentRoundWeight != 0) return;
        uint256 missed = ((block.timestamp - roundEndsAt) / ROUND_DURATION) + 1;
        round += missed;
        roundEndsAt += missed * ROUND_DURATION;
        emit RoundCarried(round);
    }

    function _pickWinner(uint256 roundId, uint256 winningWeight) internal view returns (address) {
        Entry[] storage entries = roundEntries[roundId];
        uint256 low;
        uint256 high = entries.length;

        while (low < high) {
            uint256 mid = (low + high) >> 1;
            if (entries[mid].cumulativeWeight < winningWeight) low = mid + 1;
            else high = mid;
        }

        return entries[low].player;
    }

    function _sqrt(uint256 value) internal pure returns (uint256 result) {
        if (value == 0) return 0;
        uint256 x = value;
        result = 1;
        if (x >> 128 > 0) {
            x >>= 128;
            result <<= 64;
        }
        if (x >> 64 > 0) {
            x >>= 64;
            result <<= 32;
        }
        if (x >> 32 > 0) {
            x >>= 32;
            result <<= 16;
        }
        if (x >> 16 > 0) {
            x >>= 16;
            result <<= 8;
        }
        if (x >> 8 > 0) {
            x >>= 8;
            result <<= 4;
        }
        if (x >> 4 > 0) {
            x >>= 4;
            result <<= 2;
        }
        if (x >> 2 > 0) result <<= 1;

        unchecked {
            for (uint256 i = 0; i < 7; ++i) {
                result = (result + value / result) >> 1;
            }
            uint256 roundedDown = value / result;
            return result < roundedDown ? result : roundedDown;
        }
    }
}

/// @notice Permissionless Flap-compatible factory for Oracle777FlapPenaltyVault.
contract Oracle777FlapPenaltyVaultFactory {
    address public immutable defaultDevWallet;
    Oracle777VrfConfig private defaultVrfConfig;

    event VaultCreated(address indexed taxToken, address indexed creator, address indexed vault, address devWallet);

    constructor(address defaultDevWallet_, Oracle777VrfConfig memory defaultVrfConfig_) {
        if (defaultDevWallet_ == address(0)) revert Oracle777FlapPenaltyVault.ZeroAddress();
        if (
            defaultVrfConfig_.coordinator == address(0) || defaultVrfConfig_.subId == 0
                || defaultVrfConfig_.keyHash == bytes32(0)
        ) {
            revert Oracle777FlapPenaltyVault.VrfNotConfigured();
        }
        defaultDevWallet = defaultDevWallet_;
        defaultVrfConfig = defaultVrfConfig_;
    }

    function defaultVrf()
        external
        view
        returns (
            address coordinator,
            uint256 subId,
            bytes32 keyHash,
            uint32 callbackGasLimit,
            uint16 requestConfirmations,
            uint256 nativeTopUpAmount
        )
    {
        Oracle777VrfConfig memory config = defaultVrfConfig;
        return (
            config.coordinator,
            config.subId,
            config.keyHash,
            config.callbackGasLimit,
            config.requestConfirmations,
            config.nativeTopUpAmount
        );
    }

    function newVault(address taxToken, address quoteToken, address creator, bytes calldata vaultData)
        external
        returns (address vault)
    {
        if (taxToken == address(0) || creator == address(0)) revert Oracle777FlapPenaltyVault.ZeroAddress();
        if (quoteToken != address(0)) revert Oracle777FlapPenaltyVault.UnsupportedQuoteToken();
        address devWallet = _decodeDevWallet(vaultData);
        Oracle777VrfConfig memory vrfConfig = defaultVrfConfig;
        vault = address(new Oracle777FlapPenaltyVault(IOracle777FlapERC20(taxToken), devWallet, creator, vrfConfig));
        emit VaultCreated(taxToken, creator, vault, devWallet);
    }

    function isQuoteTokenSupported(address quoteToken) external pure returns (bool supported) {
        return quoteToken == address(0);
    }

    function vaultDataSchema() public pure returns (FlapVaultDataSchema memory schema) {
        schema.description = "Dev wallet";
        schema.fields = new FlapFieldDescriptor[](1);
        schema.fields[0] = FlapFieldDescriptor("devWallet", "address", "BNB receiver for the temporary dev/API share", 0);
        schema.isArray = false;
    }

    function _decodeDevWallet(bytes calldata vaultData) internal view returns (address devWallet) {
        devWallet = defaultDevWallet;
        if (vaultData.length == 0) return devWallet;

        bytes memory data = _unwrapAbiEncodedBytes(vaultData);
        if (data.length == 0) return devWallet;

        if (data.length == 20) {
            devWallet = _addressFromPackedBytes(data);
        } else if (data.length == 32) {
            devWallet = abi.decode(data, (address));
        } else {
            revert Oracle777FlapPenaltyVault.ZeroAddress();
        }
        if (devWallet == address(0)) revert Oracle777FlapPenaltyVault.ZeroAddress();
    }

    function _unwrapAbiEncodedBytes(bytes calldata data) internal pure returns (bytes memory unwrapped) {
        if (data.length >= 64) {
            uint256 offset;
            uint256 size;
            assembly {
                offset := calldataload(data.offset)
                size := calldataload(add(data.offset, 32))
            }
            uint256 paddedSize = ((size + 31) / 32) * 32;
            if (offset == 32 && data.length == 64 + paddedSize) {
                return abi.decode(data, (bytes));
            }
        }
        return data;
    }

    function _addressFromPackedBytes(bytes memory data) internal pure returns (address value) {
        assembly {
            value := shr(96, mload(add(data, 32)))
        }
    }
}
