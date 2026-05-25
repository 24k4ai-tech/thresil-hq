// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {Oracle777FlapPenaltyVaultFactory, Oracle777VrfConfig} from "../src/Oracle777FlapPenaltyVault.sol";

contract DeployOracle777FlapPenaltyVaultFactory is Script {
    address internal constant FALLBACK_DEV_WALLET = 0x830EE35dC25Bfc3b9E93470c7BE1d4929F888355;
    address internal constant BNB_MAINNET_VRF_COORDINATOR = 0xd691f04bc0C9a24Edb78af9E005Cf85768F694C9;
    bytes32 internal constant BNB_MAINNET_VRF_KEY_HASH_500_GWEI =
        0xeb0f72532fed5c94b4caf7b49caf454b35a729608a441101b9269efb7efe2c6c;

    function run() external returns (Oracle777FlapPenaltyVaultFactory factory) {
        uint256 deployerKey = _broadcastKey();
        address devWallet = vm.envOr("DEV_WALLET", FALLBACK_DEV_WALLET);
        Oracle777VrfConfig memory vrfConfig = Oracle777VrfConfig({
            coordinator: _vrfCoordinator(),
            subId: vm.envUint("VRF_SUB_ID"),
            keyHash: _vrfKeyHash(),
            callbackGasLimit: uint32(vm.envOr("VRF_CALLBACK_GAS_LIMIT", uint256(240_000))),
            requestConfirmations: uint16(vm.envOr("VRF_REQUEST_CONFIRMATIONS", uint256(3))),
            nativeTopUpAmount: vm.envOr("VRF_NATIVE_TOP_UP_AMOUNT", uint256(0))
        });

        vm.startBroadcast(deployerKey);
        factory = new Oracle777FlapPenaltyVaultFactory(devWallet, vrfConfig);
        vm.stopBroadcast();

        console2.log("Oracle777FlapPenaltyVaultFactory:", address(factory));
        console2.log("Default dev wallet:", devWallet);
        console2.log("VRF coordinator:", vrfConfig.coordinator);
        console2.log("VRF sub id:", vrfConfig.subId);
        console2.log("VRF native top-up:", vrfConfig.nativeTopUpAmount);
    }

    function _vrfCoordinator() internal view returns (address coordinator) {
        coordinator = vm.envOr("VRF_COORDINATOR", address(0));
        if (coordinator != address(0)) return coordinator;
        if (block.chainid == 56) return BNB_MAINNET_VRF_COORDINATOR;
        revert("VRF_COORDINATOR required for this chain");
    }

    function _vrfKeyHash() internal view returns (bytes32 keyHash) {
        keyHash = vm.envOr("VRF_KEY_HASH", bytes32(0));
        if (keyHash != bytes32(0)) return keyHash;
        if (block.chainid == 56) return BNB_MAINNET_VRF_KEY_HASH_500_GWEI;
        revert("VRF_KEY_HASH required for this chain");
    }

    function _broadcastKey() internal view returns (uint256 key) {
        key = vm.envOr("MAINNETPRIVATE_KEY", uint256(0));
        if (key != 0) return key;
        return vm.envUint("PRIVATE_KEY");
    }
}
