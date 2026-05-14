// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FTMonsterArcadeV4HookFast} from "./FTMonsterArcadeV4HookFast.sol";

/// @title FTMonsterArcadeHookDeployerFast
/// @notice CREATE2 deployer for the compressed-timer arcade hook used on testnets.
contract FTMonsterArcadeHookDeployerFast {
    event HookDeployed(address indexed hook, bytes32 indexed salt);

    function deploy(bytes32 salt, FTMonsterArcadeV4HookFast.Config memory config)
        external
        returns (FTMonsterArcadeV4HookFast hook)
    {
        hook = new FTMonsterArcadeV4HookFast{salt: salt}(config);
        emit HookDeployed(address(hook), salt);
    }

    function computeAddress(bytes32 salt, FTMonsterArcadeV4HookFast.Config memory config)
        external
        view
        returns (address predicted)
    {
        bytes32 initCodeHash =
            keccak256(abi.encodePacked(type(FTMonsterArcadeV4HookFast).creationCode, abi.encode(config)));
        predicted =
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash)))));
    }
}
