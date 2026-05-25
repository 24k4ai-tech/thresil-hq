// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";

interface IOracle777VRFSubscriptionCreator {
    function createSubscription() external returns (uint256 subId);
    function fundSubscriptionWithNative(uint256 subId) external payable;
}

contract CreateOracle777VrfSubscription is Script {
    address internal constant BNB_MAINNET_VRF_COORDINATOR = 0xd691f04bc0C9a24Edb78af9E005Cf85768F694C9;

    function run() external returns (uint256 subId) {
        uint256 ownerKey = _broadcastKey();
        address coordinator = _vrfCoordinator();
        uint256 initialFunding = vm.envOr("VRF_INITIAL_FUNDING", uint256(0));

        vm.startBroadcast(ownerKey);
        subId = IOracle777VRFSubscriptionCreator(coordinator).createSubscription();
        if (initialFunding > 0) {
            IOracle777VRFSubscriptionCreator(coordinator).fundSubscriptionWithNative{value: initialFunding}(subId);
        }
        vm.stopBroadcast();

        console2.log("Created VRF sub id:", subId);
        console2.log("VRF coordinator:", coordinator);
        console2.log("Initial native funding:", initialFunding);
    }

    function _vrfCoordinator() internal view returns (address coordinator) {
        coordinator = vm.envOr("VRF_COORDINATOR", address(0));
        if (coordinator != address(0)) return coordinator;
        if (block.chainid == 56) return BNB_MAINNET_VRF_COORDINATOR;
        revert("VRF_COORDINATOR required for this chain");
    }

    function _broadcastKey() internal view returns (uint256 key) {
        key = vm.envOr("MAINNETPRIVATE_KEY", uint256(0));
        if (key != 0) return key;
        return vm.envUint("PRIVATE_KEY");
    }
}
