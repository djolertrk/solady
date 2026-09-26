// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Code} from "solar:core/v1/Code.sol";
import {Create} from "solar:core/v1/Create.sol";

/// @notice Checked Solidity implementation of the pinned Solady SSTORE2 API.
/// @dev A data contract holds `data` as its code after one STOP byte, so it
/// cannot be called. Writing deploys it with `Create`; reading copies a range of
/// it with `Code`, checked against the code's size, where the assembly copies
/// past the end and trims. Two deliberate differences from the assembly: data
/// too long for the two-byte length the creation code pushes fails with
/// `DeploymentFailed()` instead of running out of gas, and reading an account
/// without code fails with `Panic(0x11)` instead of running out of gas.
library SSTORE2 {
    /// @dev The creation code of the CREATE3 proxy.
    bytes internal constant _CREATE3_PROXY_INITCODE = hex"67363d3d37363d34f03d5260086018f3";

    /// @dev Hash of the `_CREATE3_PROXY_INITCODE`.
    bytes32 internal constant CREATE3_PROXY_INITCODE_HASH =
        0x21c35dbe1b344a2488cf3321d6ce542f8e9f305544ff09e4993a62319a497c1f;

    /// @dev Unable to deploy the storage contract.
    error DeploymentFailed();

    /// @dev Writes `data` into the bytecode of a storage contract and returns its address.
    function write(bytes memory data) internal returns (address pointer) {
        return Create.deploy(_initCode(data), 0);
    }

    /// @dev Writes `data` into the bytecode of a storage contract with `salt`
    /// and returns its normal CREATE2 deterministic address.
    function writeCounterfactual(bytes memory data, bytes32 salt)
        internal
        returns (address pointer)
    {
        return Create.deploy2(_initCode(data), salt, 0);
    }

    /// @dev Writes `data` into the bytecode of a storage contract and returns its address.
    /// This uses the so-called "CREATE3" workflow, which means that `pointer`
    /// is agnostic to `data`, and only depends on `salt`.
    function writeDeterministic(bytes memory data, bytes32 salt)
        internal
        returns (address pointer)
    {
        address proxy = Create.deploy2(_CREATE3_PROXY_INITCODE, salt, 0);
        pointer = _proxyDeployment(proxy);
        (bool success,) = proxy.call(_initCode(data));
        if (!success || pointer.code.length == 0) revert DeploymentFailed();
    }

    /// @dev Returns the initialization code hash of the storage contract for `data`.
    /// Used for mining vanity addresses with create2crunch.
    function initCodeHash(bytes memory data) internal pure returns (bytes32 hash) {
        return keccak256(_initCode(data));
    }

    /// @dev Equivalent to `predictCounterfactualAddress(data, salt, address(this))`
    function predictCounterfactualAddress(bytes memory data, bytes32 salt)
        internal
        view
        returns (address pointer)
    {
        pointer = predictCounterfactualAddress(data, salt, address(this));
    }

    /// @dev Returns the CREATE2 address of the storage contract for `data`
    /// deployed with `salt` by `deployer`.
    function predictCounterfactualAddress(bytes memory data, bytes32 salt, address deployer)
        internal
        pure
        returns (address predicted)
    {
        return Create.predict2(deployer, salt, initCodeHash(data));
    }

    /// @dev Equivalent to `predictDeterministicAddress(salt, address(this))`.
    function predictDeterministicAddress(bytes32 salt) internal view returns (address pointer) {
        pointer = predictDeterministicAddress(salt, address(this));
    }

    /// @dev Returns the "CREATE3" deterministic address for `salt` with `deployer`.
    function predictDeterministicAddress(bytes32 salt, address deployer)
        internal
        pure
        returns (address pointer)
    {
        return _proxyDeployment(Create.predict2(deployer, salt, CREATE3_PROXY_INITCODE_HASH));
    }

    /// @dev Equivalent to `read(pointer, 0, 2 ** 256 - 1)`.
    function read(address pointer) internal view returns (bytes memory data) {
        return read(pointer, 0, type(uint256).max);
    }

    /// @dev Equivalent to `read(pointer, start, 2 ** 256 - 1)`.
    function read(address pointer, uint256 start) internal view returns (bytes memory data) {
        return read(pointer, start, type(uint256).max);
    }

    /// @dev Returns a slice of the data on `pointer` from `start` to `end`.
    /// `start` and `end` will be clamped to the range `[0, args.length]`.
    /// The `pointer` MUST be deployed via the SSTORE2 write functions.
    function read(address pointer, uint256 start, uint256 end)
        internal
        view
        returns (bytes memory data)
    {
        // The data is the code after the STOP byte. The read checks its range
        // against the code size this line already took.
        uint256 n = pointer.code.length - 1;
        if (end > n) end = n;
        if (start >= end) return "";
        return Code.read(pointer, start + 1, end - start);
    }

    /// @dev The creation code of the storage contract for `data`: it copies the
    /// STOP byte and `data` that follow it out as the deployed code.
    function _initCode(bytes memory data) private pure returns (bytes memory) {
        // The two-byte length the creation code pushes covers the STOP byte too.
        if (data.length > 0xfffe) revert DeploymentFailed();
        // PUSH2 l, DUP1, PUSH1 0x0a, RETURNDATASIZE, CODECOPY, RETURNDATASIZE, RETURN, STOP
        return abi.encodePacked(hex"61", uint16(data.length + 1), hex"80600a3d393df300", data);
    }

    /// @dev The address a CREATE3 proxy's one deployment gets: its first
    /// CREATE, at nonce one.
    function _proxyDeployment(address proxy) private pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(hex"d694", proxy, hex"01")))));
    }
}
