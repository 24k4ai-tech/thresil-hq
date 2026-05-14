// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FTMonsterArcadeV4Hook} from "./FTMonsterArcadeV4Hook.sol";

/// @title FTMonsterArcadeHookDeployer
/// @notice CREATE2 deployer for the Oracle777 arcade hook address bit grind.
contract FTMonsterArcadeHookDeployer {
    event HookDeployed(address indexed hook, bytes32 indexed salt);

    function deploy(bytes32 salt, FTMonsterArcadeV4Hook.Config memory config)
        external
        returns (FTMonsterArcadeV4Hook hook)
    {
        hook = new FTMonsterArcadeV4Hook{salt: salt}(config);
        emit HookDeployed(address(hook), salt);
    }

    function computeAddress(bytes32 salt, FTMonsterArcadeV4Hook.Config memory config)
        external
        view
        returns (address predicted)
    {
        bytes32 initCodeHash = keccak256(abi.encodePacked(type(FTMonsterArcadeV4Hook).creationCode, abi.encode(config)));
        predicted =
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash)))));
    }
}
