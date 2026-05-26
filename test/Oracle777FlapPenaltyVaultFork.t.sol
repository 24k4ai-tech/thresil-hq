// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {
    IOracle777FlapERC20,
    Oracle777FlapPenaltyVault,
    Oracle777FlapPenaltyVaultFactory,
    Oracle777VRFV2PlusClient,
    Oracle777VrfConfig
} from "../src/Oracle777FlapPenaltyVault.sol";

contract Oracle777FlapPenaltyVaultForkTest is Test {
    address internal constant DEPLOYED_FACTORY = 0x16Aa0e4257C9aB1f443A03BF647397AA8b58E55d;
    address internal constant DEPLOYED_DEV_WALLET = 0x830EE35dC25Bfc3b9E93470c7BE1d4929F888355;
    string internal constant DEFAULT_BSC_RPC = "https://bsc-dataseed.binance.org";

    Oracle777FlapPenaltyVaultFactory internal deployedFactory;
    Oracle777FlapPenaltyVaultFactory internal factory;
    ForkMockERC20 internal token;
    ForkMockVRFCoordinator internal vrf;
    Oracle777FlapPenaltyVault internal vault;

    address internal creator = address(0xC0FFEE);
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        string memory rpc = vm.envOr("BSC_RPC_URL", DEFAULT_BSC_RPC);
        vm.createSelectFork(rpc);
        vm.txGasPrice(0);

        deployedFactory = Oracle777FlapPenaltyVaultFactory(DEPLOYED_FACTORY);
        token = new ForkMockERC20();
        vrf = new ForkMockVRFCoordinator();

        Oracle777VrfConfig memory config = Oracle777VrfConfig({
            coordinator: address(vrf),
            subId: 1,
            keyHash: bytes32(uint256(777)),
            callbackGasLimit: 240_000,
            requestConfirmations: 3,
            nativeTopUpAmount: 0.001 ether
        });

        factory = new Oracle777FlapPenaltyVaultFactory(DEPLOYED_DEV_WALLET, config);
        address created = factory.newVault(address(token), address(0), creator, abi.encode(DEPLOYED_DEV_WALLET));
        vault = Oracle777FlapPenaltyVault(payable(created));

        token.mint(alice, 1_000_000 ether);
        token.mint(bob, 1_000_000 ether);
    }

    function testForkFactoryReadbackMatchesDeployedConfig() public view {
        assertEq(address(deployedFactory), DEPLOYED_FACTORY);
        assertEq(deployedFactory.defaultDevWallet(), DEPLOYED_DEV_WALLET);
        assertTrue(deployedFactory.isQuoteTokenSupported(address(0)));
        assertFalse(deployedFactory.isQuoteTokenSupported(address(1)));
    }

    function testForkRehearsalShootOnlyBurnsTokenAndPaysWinner() public {
        vm.warp(block.timestamp + 77 minutes);
        vm.deal(address(this), 20 ether);
        (bool ok,) = address(vault).call{value: 10 ether}("");
        assertTrue(ok);

        vm.startPrank(alice);
        token.approve(address(vault), 10_000 ether);
        uint256 aliceNativeBefore = alice.balance;
        uint256 aliceTokenBefore = token.balanceOf(alice);
        vault.shoot(10_000 ether);
        vm.stopPrank();

        assertEq(alice.balance, aliceNativeBefore);
        assertEq(token.balanceOf(alice), aliceTokenBefore - 10_000 ether);
        assertEq(token.balanceOf(vault.DEAD_ADDRESS()), 10_000 ether);

        vm.warp(block.timestamp + 17 minutes + 1);
        vault.poke();

        uint256 requestId = vault.pendingVrfRequestId();
        assertGt(requestId, 0);
        assertEq(vrf.funded(), 0.001 ether);
        assertEq(vault.pendingSettlementPayout(), 2.9997 ether);

        vrf.fulfill(address(vault), requestId, 123456);

        assertEq(vault.lastWinner(), alice);
        assertEq(vault.lastPayout(), 2.9997 ether);
        assertEq(alice.balance - aliceNativeBefore, 2.9997 ether);
    }

    function testForkShootRejectsAttachedNativeValue() public {
        vm.deal(alice, 1 ether);
        vm.startPrank(alice);
        token.approve(address(vault), 1 ether);
        (bool ok,) = address(vault).call{value: 0.1 ether}(abi.encodeWithSelector(vault.shoot.selector, 1 ether));
        vm.stopPrank();

        assertFalse(ok);
        assertEq(address(vault).balance, 0);
        assertEq(token.balanceOf(vault.DEAD_ADDRESS()), 0);
    }
}

contract ForkMockERC20 {
    mapping(address account => uint256) public balanceOf;
    mapping(address owner => mapping(address spender => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "allowance");
            allowance[from][msg.sender] = allowed - amount;
        }
        require(balanceOf[from] >= amount, "balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract ForkMockVRFCoordinator {
    uint256 public nextRequestId = 1;
    uint256 public funded;

    function requestRandomWords(Oracle777VRFV2PlusClient.RandomWordsRequest calldata)
        external
        returns (uint256 requestId)
    {
        requestId = nextRequestId++;
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
