// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";

interface IOracle777VRFSubscriptionManager {
    function addConsumer(uint256 subId, address consumer) external;
}

contract AddOracle777VrfConsumer is Script {
    address internal constant BNB_MAINNET_VRF_COORDINATOR = 0xd691f04bc0C9a24Edb78af9E005Cf85768F694C9;

    function run() external {
        uint256 ownerKey = _broadcastKey();
        address coordinator = _vrfCoordinator();
        uint256 subId = vm.envUint("VRF_SUB_ID");
        address vault = vm.envAddress("FLAP_PENALTY_VAULT");

        vm.startBroadcast(ownerKey);
        IOracle777VRFSubscriptionManager(coordinator).addConsumer(subId, vault);
        vm.stopBroadcast();

        console2.log("Added VRF consumer:", vault);
        console2.log("VRF coordinator:", coordinator);
        console2.log("VRF sub id:", subId);
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
