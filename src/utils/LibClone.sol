// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Create} from "solar:core/v1/Create.sol";

/// @notice Checked Solidity implementation of part of the pinned Solady
/// LibClone API: the minimal proxy (EIP-1167) clones and the address helpers.
/// @dev A clone's creation code is the same 53 bytes the assembly writes into
/// scratch space, assembled with `abi.encodePacked`, and deployed with
/// `Create`, which fails with the same `DeploymentFailed()`. The other proxy
/// families, which differ only in their bytes, are not ported.
library LibClone {
    /// @dev Unable to deploy the clone.
    error DeploymentFailed();

    /// @dev The salt must start with either the zero address or `by`.
    error SaltDoesNotStartWith();

    /// @dev Deploys a clone of `implementation`.
    function clone(address implementation) internal returns (address instance) {
        instance = clone(0, implementation);
    }

    /// @dev Deploys a clone of `implementation`.
    /// Deposits `value` ETH during deployment.
    function clone(uint256 value, address implementation) internal returns (address instance) {
        return Create.deploy(initCode(implementation), value);
    }

    /// @dev Deploys a deterministic clone of `implementation` with `salt`.
    function cloneDeterministic(address implementation, bytes32 salt)
        internal
        returns (address instance)
    {
        instance = cloneDeterministic(0, implementation, salt);
    }

    /// @dev Deploys a deterministic clone of `implementation` with `salt`.
    /// Deposits `value` ETH during deployment.
    function cloneDeterministic(uint256 value, address implementation, bytes32 salt)
        internal
        returns (address instance)
    {
        return Create.deploy2(initCode(implementation), salt, value);
    }

    /// @dev Returns the initialization code of the clone of `implementation`.
    function initCode(address implementation) internal pure returns (bytes memory c) {
        // Creation: copy the 44 runtime bytes out. Runtime: copy the calldata,
        // delegate-call `implementation` with all the gas, copy the response,
        // and return it or revert with it.
        return abi.encodePacked(
            hex"602c3d8160093d39f33d3d3d3d363d3d37363d73", implementation, hex"5af43d3d93803e602a57fd5bf3"
        );
    }

    /// @dev Returns the initialization code hash of the clone of `implementation`.
    function initCodeHash(address implementation) internal pure returns (bytes32 hash) {
        return keccak256(
            abi.encodePacked(
                hex"602c3d8160093d39f33d3d3d3d363d3d37363d73",
                implementation,
                hex"5af43d3d93803e602a57fd5bf3"
            )
        );
    }

    /// @dev Returns the address of the clone of `implementation`, with `salt` by `deployer`.
    function predictDeterministicAddress(address implementation, bytes32 salt, address deployer)
        internal
        pure
        returns (address predicted)
    {
        predicted = predictDeterministicAddress(initCodeHash(implementation), salt, deployer);
    }

    /// @dev Returns the address when a contract with initialization code hash,
    /// `hash`, is deployed with `salt`, by `deployer`.
    function predictDeterministicAddress(bytes32 hash, bytes32 salt, address deployer)
        internal
        pure
        returns (address predicted)
    {
        return Create.predict2(deployer, salt, hash);
    }

    /// @dev Requires that `salt` starts with either the zero address or `by`.
    function checkStartsWith(bytes32 salt, address by) internal pure {
        address prefix = address(bytes20(salt));
        if (prefix != address(0) && prefix != by) revert SaltDoesNotStartWith();
    }
}
