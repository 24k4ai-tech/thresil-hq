// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {
    FlapVaultDataSchema,
    FlapVaultUISchema,
    IOracle777FlapERC20,
    Oracle777VrfConfig,
    Oracle777VRFV2PlusClient,
    Oracle777FlapPenaltyVault,
    Oracle777FlapPenaltyVaultFactory
} from "../src/Oracle777FlapPenaltyVault.sol";

contract Oracle777FlapPenaltyVaultTest is Test {
    MockERC20 internal token;
    MockVRFCoordinator internal vrf;
    Oracle777FlapPenaltyVault internal vault;
    Oracle777FlapPenaltyVaultFactory internal factory;
    RejectEtherReceiver internal rejector;

    address internal dev = address(0xD00D);
    address internal creator = address(0xC0FFEE);
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        token = new MockERC20();
        vrf = new MockVRFCoordinator();
        Oracle777VrfConfig memory config = Oracle777VrfConfig({
            coordinator: address(vrf),
            subId: 1,
            keyHash: bytes32(uint256(777)),
            callbackGasLimit: 240_000,
            requestConfirmations: 3,
            nativeTopUpAmount: 0.01 ether
        });
        vault = new Oracle777FlapPenaltyVault(IOracle777FlapERC20(address(token)), dev, creator, config);
        factory = new Oracle777FlapPenaltyVaultFactory(dev, config);
        rejector = new RejectEtherReceiver(token, vault);
        token.mint(alice, 1_000_000 ether);
        token.mint(bob, 1_000_000 ether);
        token.mint(address(rejector), 1_000_000 ether);
    }

    function testReceivesTaxAndRoutesEarlyDevShare() public {
        vm.deal(address(this), 10 ether);
        uint256 devBefore = dev.balance;

        (bool ok,) = address(vault).call{value: 3 ether}("");
        assertTrue(ok);

        assertEq(dev.balance - devBefore, 0.9999 ether);
        assertEq(address(vault).balance, 2.0001 ether);
        assertEq(vault.availablePot(), 2.0001 ether);
        assertEq(vault.totalTaxReceived(), 3 ether);
        assertEq(vault.totalDevPaid(), 0.9999 ether);
    }

    function testDevShareEndsAfterSeventySevenMinutes() public {
        vm.deal(address(this), 10 ether);

        vm.warp(block.timestamp + 77 minutes);
        (bool ok,) = address(vault).call{value: 3 ether}("");
        assertTrue(ok);

        assertEq(dev.balance, 0);
        assertEq(address(vault).balance, 3 ether);
        assertEq(vault.availablePot(), 3 ether);
    }

    function testShootSendsTokensToDeadAddressAndRecordsWeight() public {
        vm.startPrank(alice);
        token.approve(address(vault), 10_000 ether);
        uint256 weight = vault.shoot(10_000 ether);
        vm.stopPrank();

        assertEq(token.balanceOf(vault.DEAD_ADDRESS()), 10_000 ether);
        assertEq(vault.totalDeadBurned(), 10_000 ether);
        assertEq(weight, 100_000_000_000);
        assertEq(vault.currentRoundWeight(), 100_000_000_000);
        assertEq(vault.firstShotAt(alice), block.timestamp);
    }

    function testShootDoesNotChargeNativeValueBeyondGas() public {
        vm.deal(alice, 5 ether);

        vm.startPrank(alice);
        token.approve(address(vault), 10_000 ether);
        uint256 nativeBefore = alice.balance;
        vault.shoot(10_000 ether);
        vm.stopPrank();

        assertEq(alice.balance, nativeBefore);
        assertEq(address(vault).balance, 0);
    }

    function testShootRejectsAttachedNativeValue() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        token.approve(address(vault), 1 ether);

        vm.prank(alice);
        (bool ok,) = address(vault).call{value: 0.1 ether}(abi.encodeWithSelector(vault.shoot.selector, 1 ether));
        assertFalse(ok);
        assertEq(address(vault).balance, 0);
        assertEq(token.balanceOf(vault.DEAD_ADDRESS()), 0);
    }

    function testRoundPaysThirtyPercentAfterSeedTouch() public {
        vm.deal(address(this), 20 ether);
        vm.warp(block.timestamp + 77 minutes);
        (bool ok,) = address(vault).call{value: 10 ether}("");
        assertTrue(ok);

        vm.startPrank(alice);
        token.approve(address(vault), 10_000 ether);
        vault.shoot(10_000 ether);
        vm.stopPrank();

        uint256 aliceBefore = alice.balance;
        vm.warp(block.timestamp + 17 minutes + 1);
        vault.poke();

        assertEq(vault.pendingSettlementPayout(), 2.997 ether);
        assertEq(vault.pendingVrfRequestId(), 1);
        assertEq(vault.availablePot(), 6.993 ether);
        assertEq(vrf.funded(), 0.01 ether);

        vrf.fulfill(address(vault), 1, 123);

        assertEq(vault.lastWinner(), alice);
        assertEq(vault.lastPayout(), 2.997 ether);
        assertEq(alice.balance - aliceBefore, 2.997 ether);
        assertEq(vault.availablePot(), 6.993 ether);
    }

    function testIncomingTaxCanArmAndSettleRound() public {
        vm.deal(address(this), 20 ether);
        vm.warp(block.timestamp + 77 minutes);
        (bool ok,) = address(vault).call{value: 10 ether}("");
        assertTrue(ok);

        vm.startPrank(alice);
        token.approve(address(vault), 10_000 ether);
        vault.shoot(10_000 ether);
        vm.stopPrank();

        uint256 aliceBefore = alice.balance;
        vm.warp(block.timestamp + 17 minutes + 1);
        (ok,) = address(vault).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(vault.pendingSettlementPayout(), 3.297 ether);

        vrf.fulfill(address(vault), 1, 123);

        assertEq(vault.lastWinner(), alice);
        assertEq(alice.balance - aliceBefore, 3.297 ether);
        assertEq(vault.availablePot(), 7.693 ether);
    }

    function testReturningShooterGetsCappedAgeBoost() public {
        vm.startPrank(alice);
        token.approve(address(vault), type(uint256).max);
        vault.shoot(10_000 ether);

        vm.warp(block.timestamp + 24 hours);
        vault.shoot(10_000 ether);
        vm.stopPrank();

        (, uint256 secondWeight,) = vault.roundEntry(1, 0);
        assertEq(secondWeight, 125_000_000_000);
        assertEq(vault.shooterAgeBoostBps(alice), 2_500);
    }

    function testReservedPayoutDoesNotBlockNextRound() public {
        vm.deal(address(this), 30 ether);
        vm.warp(block.timestamp + 77 minutes);
        (bool ok,) = address(vault).call{value: 10 ether}("");
        assertTrue(ok);

        uint256 activeRound = vault.round();
        rejector.approveVault(type(uint256).max);
        rejector.shoot(10_000 ether);

        vm.warp(block.timestamp + 17 minutes + 1);
        vault.poke();
        vrf.fulfill(address(vault), 1, 123);

        uint256 reserved = vault.pendingPayout(address(rejector));
        assertEq(reserved, 2.997 ether);
        assertEq(vault.reservedFailedPayouts(), 2.997 ether);
        assertEq(vault.pendingVrfRequestId(), 0);
        assertEq(vault.round(), activeRound + 1);

        vm.startPrank(alice);
        token.approve(address(vault), 10_000 ether);
        vault.shoot(10_000 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 17 minutes + 1);
        vault.poke();
        uint256 requestId = vault.pendingVrfRequestId();
        assertGt(requestId, 0);
        vrf.fulfill(address(vault), requestId, 456);

        assertEq(vault.lastWinner(), alice);
        assertEq(vault.pendingPayout(address(rejector)), reserved);
    }

    function testVrfRequestFailureCanRecoverOnLaterPoke() public {
        vm.startPrank(alice);
        token.approve(address(vault), 10_000 ether);
        vault.shoot(10_000 ether);
        vm.stopPrank();

        vm.deal(address(this), 5 ether);
        (bool ok,) = address(vault).call{value: 5 ether}("");
        assertTrue(ok);

        vrf.setFailRequests(true);
        vm.warp(block.timestamp + 17 minutes + 1);
        uint256 activeRound = vault.round();
        (bool settled,,) = vault.poke();
        assertFalse(settled);
        assertEq(vault.pendingVrfRequestId(), 0);
        assertEq(vault.round(), activeRound);

        vrf.setFailRequests(false);
        vault.poke();
        assertEq(vault.pendingVrfRequestId(), 1);
        assertEq(vault.round(), activeRound + 1);
    }

    function testFactoryCreatesNativeQuoteVault() public {
        address created = factory.newVault(address(token), address(0), creator, abi.encode(bob));
        Oracle777FlapPenaltyVault createdVault = Oracle777FlapPenaltyVault(payable(created));

        assertEq(address(createdVault.taxToken()), address(token));
        assertEq(createdVault.devWallet(), bob);
        assertTrue(factory.isQuoteTokenSupported(address(0)));
        assertFalse(factory.isQuoteTokenSupported(address(1)));
    }

    function testFactoryAcceptsFlapBytesWrappedAddressData() public {
        address created = factory.newVault(address(token), address(0), creator, abi.encode(abi.encode(bob)));
        Oracle777FlapPenaltyVault createdVault = Oracle777FlapPenaltyVault(payable(created));

        assertEq(address(createdVault.taxToken()), address(token));
        assertEq(createdVault.devWallet(), bob);
    }

    function testFactoryAcceptsFlapBytesWrappedPackedAddressData() public {
        address created = factory.newVault(address(token), address(0), creator, abi.encode(abi.encodePacked(bob)));
        Oracle777FlapPenaltyVault createdVault = Oracle777FlapPenaltyVault(payable(created));

        assertEq(address(createdVault.taxToken()), address(token));
        assertEq(createdVault.devWallet(), bob);
    }

    function testFlapSchemasDoNotRevert() public view {
        FlapVaultUISchema memory uiSchema = vault.vaultUISchema();
        assertEq(uiSchema.vaultType, "Oracle777PenaltyVault");
        assertEq(uiSchema.methods.length, 4);
        assertEq(uiSchema.methods[0].name, "shoot");
        assertEq(uiSchema.methods[0].approvals.length, 1);

        FlapVaultDataSchema memory dataSchema = factory.vaultDataSchema();
        assertEq(dataSchema.fields.length, 1);
        assertEq(dataSchema.fields[0].name, "devWallet");
        assertEq(dataSchema.fields[0].fieldType, "address");
    }

    function testShootRevertsWhenEndedRoundCannotRequestVrf() public {
        vm.startPrank(alice);
        token.approve(address(vault), 10_000 ether);
        vault.shoot(10_000 ether);
        vm.stopPrank();

        vrf.setFailRequests(true);
        vm.warp(block.timestamp + 17 minutes + 1);

        vm.startPrank(bob);
        token.approve(address(vault), 10_000 ether);
        vm.expectRevert(Oracle777FlapPenaltyVault.RoundNeedsSettlement.selector);
        vault.shoot(10_000 ether);
        vm.stopPrank();

        assertEq(token.balanceOf(vault.DEAD_ADDRESS()), 10_000 ether);
        assertEq(vault.roundEntryCount(0), 1);
    }

    function testRejectsMissingVrfConfig() public {
        Oracle777VrfConfig memory badConfig = Oracle777VrfConfig({
            coordinator: address(0),
            subId: 1,
            keyHash: bytes32(uint256(777)),
            callbackGasLimit: 240_000,
            requestConfirmations: 3,
            nativeTopUpAmount: 0
        });

        vm.expectRevert(Oracle777FlapPenaltyVault.VrfNotConfigured.selector);
        new Oracle777FlapPenaltyVault(IOracle777FlapERC20(address(token)), dev, creator, badConfig);

        vm.expectRevert(Oracle777FlapPenaltyVault.VrfNotConfigured.selector);
        new Oracle777FlapPenaltyVaultFactory(dev, badConfig);
    }
}

contract MockERC20 {
    string public constant name = "Mock777";
    string public constant symbol = "777X";
    uint8 public constant decimals = 18;

    mapping(address account => uint256) public balanceOf;
    mapping(address owner => mapping(address spender => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "allowance");
            allowance[from][msg.sender] = allowed - amount;
            emit Approval(from, msg.sender, allowance[from][msg.sender]);
        }
        require(balanceOf[from] >= amount, "balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

contract MockVRFCoordinator {
    uint256 public nextRequestId = 1;
    uint256 public funded;
    bool public failRequests;

    event Requested(uint256 indexed requestId);

    function setFailRequests(bool value) external {
        failRequests = value;
    }

    function requestRandomWords(Oracle777VRFV2PlusClient.RandomWordsRequest calldata)
        external
        returns (uint256 requestId)
    {
        require(!failRequests, "VRF_REQUEST_FAILED");
        requestId = nextRequestId++;
        emit Requested(requestId);
    }

    function fundSubscriptionWithNative(uint256) external payable {
        funded += msg.value;
    }

    function fulfill(address consumer, uint256 requestId, uint256 randomWord) external {
        uint256[] memory words = new uint256[](1);
        words[0] = randomWord;
        Oracle777FlapPenaltyVault(payable(consumer)).rawFulfillRandomWords(requestId, words);
    }
}

contract RejectEtherReceiver {
    MockERC20 internal immutable token;
    Oracle777FlapPenaltyVault internal immutable vault;

    constructor(MockERC20 token_, Oracle777FlapPenaltyVault vault_) {
        token = token_;
        vault = vault_;
    }

    function approveVault(uint256 amount) external {
        token.approve(address(vault), amount);
    }

    function shoot(uint256 amount) external {
        vault.shoot(amount);
    }

    receive() external payable {
        revert("NO_ETH");
    }
}
