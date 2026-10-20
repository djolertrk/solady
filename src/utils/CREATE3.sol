// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @notice Deterministic deployments agnostic to the initialization code.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/CREATE3.sol)
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/utils/CREATE3.sol)
/// @author Modified from 0xSequence (https://github.com/0xSequence/create3/blob/master/contracts/Create3.sol)
/// @dev The checked port creates the proxy from the sixteen bytes of `_PROXY_INITCODE` with
/// the trusted `_createDeploy2`, which fails with `DeploymentFailed()` as the assembly does,
/// and calls it with `initCode` and `value` through a plain call. Both addresses are derived in
/// Solidity, as hashes of `abi.encodePacked` bytes: the proxy's from the CREATE2 preimage, and
/// the deployment's from the RLP encoding of the proxy's address and its nonce, one. The
/// returned addresses are clean, where upstream leaves their upper 96 bits dirty.
/// @custom:solar-safe memory arithmetic
library CREATE3 {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CUSTOM ERRORS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Unable to deploy the contract.
    error DeploymentFailed();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      BYTECODE CONSTANTS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * -------------------------------------------------------------------+
     * Opcode      | Mnemonic         | Stack        | Memory             |
     * -------------------------------------------------------------------|
     * 36          | CALLDATASIZE     | cds          |                    |
     * 3d          | RETURNDATASIZE   | 0 cds        |                    |
     * 3d          | RETURNDATASIZE   | 0 0 cds      |                    |
     * 37          | CALLDATACOPY     |              | [0..cds): calldata |
     * 36          | CALLDATASIZE     | cds          | [0..cds): calldata |
     * 3d          | RETURNDATASIZE   | 0 cds        | [0..cds): calldata |
     * 34          | CALLVALUE        | value 0 cds  | [0..cds): calldata |
     * f0          | CREATE           | newContract  | [0..cds): calldata |
     * -------------------------------------------------------------------|
     * Opcode      | Mnemonic         | Stack        | Memory             |
     * -------------------------------------------------------------------|
     * 67 bytecode | PUSH8 bytecode   | bytecode     |                    |
     * 3d          | RETURNDATASIZE   | 0 bytecode   |                    |
     * 52          | MSTORE           |              | [0..8): bytecode   |
     * 60 0x08     | PUSH1 0x08       | 0x08         | [0..8): bytecode   |
     * 60 0x18     | PUSH1 0x18       | 0x18 0x08    | [0..8): bytecode   |
     * f3          | RETURN           |              | [0..8): bytecode   |
     * -------------------------------------------------------------------+
     */

    /// @dev The proxy initialization code.
    uint256 private constant _PROXY_INITCODE = 0x67363d3d37363d34f03d5260086018f3;

    /// @dev Hash of the `_PROXY_INITCODE`.
    /// Equivalent to `keccak256(abi.encodePacked(hex"67363d3d37363d34f03d5260086018f3"))`.
    bytes32 internal constant PROXY_INITCODE_HASH =
        0x21c35dbe1b344a2488cf3321d6ce542f8e9f305544ff09e4993a62319a497c1f;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      CREATE3 OPERATIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Deploys `initCode` deterministically with a `salt`.
    /// Returns the deterministic address of the deployed contract,
    /// which solely depends on `salt`.
    function deployDeterministic(bytes memory initCode, bytes32 salt)
        internal
        returns (address deployed)
    {
        deployed = deployDeterministic(0, initCode, salt);
    }

    /// @dev Deploys `initCode` deterministically with a `salt`.
    /// The deployed contract is funded with `value` (in wei) ETH.
    /// Returns the deterministic address of the deployed contract,
    /// which solely depends on `salt`.
    function deployDeterministic(uint256 value, bytes memory initCode, bytes32 salt)
        internal
        returns (address deployed)
    {
        // The proxy's initialization code is the low sixteen bytes of `_PROXY_INITCODE`.
        address proxy = _createDeploy2(abi.encodePacked(uint128(_PROXY_INITCODE)), salt, 0);
        deployed = _proxyDeployment(proxy);
        // The proxy creates a contract from its calldata and returns nothing.
        (bool success,) = proxy.call{value: value}(initCode);
        if (!success || deployed.code.length == 0) revert DeploymentFailed();
    }

    /// @dev Returns the deterministic address for `salt`.
    function predictDeterministicAddress(bytes32 salt) internal view returns (address deployed) {
        deployed = predictDeterministicAddress(salt, address(this));
    }

    /// @dev Returns the deterministic address for `salt` with `deployer`.
    function predictDeterministicAddress(bytes32 salt, address deployer)
        internal
        pure
        returns (address deployed)
    {
        deployed = _proxyDeployment(_createPredict2(deployer, salt, PROXY_INITCODE_HASH));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PRIVATE HELPERS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The address a CREATE3 proxy's one deployment gets: its first
    /// CREATE, at nonce one.
    function _proxyDeployment(address proxy) private pure returns (address) {
        // 0xd6 = 0xc0 (short RLP prefix) + 0x16 (length of: 0x94 ++ proxy ++ 0x01).
        // 0x94 = 0x80 + 0x14 (0x14 = the length of an address, 20 bytes, in hex).
        return address(uint160(uint256(keccak256(abi.encodePacked(hex"d694", proxy, hex"01")))));
    }

    /// @dev The address `deploy2` gives `deployer` for `salt` and initcode
    /// hashing to `initcodeHash`. Computes only; deploys nothing.
    function _createPredict2(address deployer, bytes32 salt, bytes32 initcodeHash)
        private
        pure
        returns (address)
    {
        return address(
            uint160(
                uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initcodeHash)))
            )
        );
    }

    /// @dev Deploys `initcode` with `value` wei at the address `salt` selects.
    /// Solidity creates contracts only from their source.
    /// @custom:solar-trusted
    function _createDeploy2(bytes memory initcode, bytes32 salt, uint256 value)
        private
        returns (address deployed)
    {
        /// @solidity memory-safe-assembly
        assembly {
            deployed := create2(value, add(initcode, 0x20), mload(initcode), salt)
        }
        if (deployed == address(0)) revert DeploymentFailed();
    }
}
