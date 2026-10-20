// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @notice Factory for deploying and managing ERC1967 proxy contracts.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/ERC1967Factory.sol)
/// @author jtriley-eth (https://github.com/jtriley-eth/minimum-viable-proxy)
/// @dev The checked port keeps upstream's admin slots, the proxy's exact initialization code,
/// the calldata that sets a proxy's implementation, and every check, error and event, in
/// upstream's order. Trusted helpers read and write an admin slot, which Solidity cannot name,
/// create the proxy from its code, bubble up a failed call's revert data, and turn the code's
/// buffer into the pointer `_initCode` returns, with the code 0x13 bytes after it, as upstream
/// lays it out. Upstream pads the code of the shorter proxy, for a factory whose address has six
/// leading zero bytes, to 0x88 bytes with memory past the free memory pointer, which is zero in
/// all of its own entry points; the port pads it with zeros. `predictDeterministicAddress`
/// returns a clean address, where upstream leaves its upper 96 bits for inline assembly to
/// clean. Private functions carry the contract's name, so that the contract combines with other
/// mixins.
/// @custom:solar-safe memory arithmetic
contract ERC1967Factory {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The caller is not authorized to call the function.
    error Unauthorized();

    /// @dev The proxy deployment failed.
    error DeploymentFailed();

    /// @dev The upgrade failed.
    error UpgradeFailed();

    /// @dev The salt does not start with the caller.
    error SaltDoesNotStartWithCaller();

    /// @dev `bytes4(keccak256(bytes("Unauthorized()")))`.
    uint256 internal constant _UNAUTHORIZED_ERROR_SELECTOR = 0x82b42900;

    /// @dev `bytes4(keccak256(bytes("DeploymentFailed()")))`.
    uint256 internal constant _DEPLOYMENT_FAILED_ERROR_SELECTOR = 0x30116425;

    /// @dev `bytes4(keccak256(bytes("UpgradeFailed()")))`.
    uint256 internal constant _UPGRADE_FAILED_ERROR_SELECTOR = 0x55299b49;

    /// @dev `bytes4(keccak256(bytes("SaltDoesNotStartWithCaller()")))`.
    uint256 internal constant _SALT_DOES_NOT_START_WITH_CALLER_ERROR_SELECTOR = 0x2f634836;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The admin of a proxy contract has been changed.
    event AdminChanged(address indexed proxy, address indexed admin);

    /// @dev The implementation for a proxy has been upgraded.
    event Upgraded(address indexed proxy, address indexed implementation);

    /// @dev A proxy has been deployed.
    event Deployed(address indexed proxy, address indexed implementation, address indexed admin);

    /// @dev `keccak256(bytes("AdminChanged(address,address)"))`.
    uint256 internal constant _ADMIN_CHANGED_EVENT_SIGNATURE =
        0x7e644d79422f17c01e4894b5f4f588d331ebfa28653d42ae832dc59e38c9798f;

    /// @dev `keccak256(bytes("Upgraded(address,address)"))`.
    uint256 internal constant _UPGRADED_EVENT_SIGNATURE =
        0x5d611f318680d00598bb735d61bacf0c514c6b50e1e5ad30040a4df2b12791c7;

    /// @dev `keccak256(bytes("Deployed(address,address,address)"))`.
    uint256 internal constant _DEPLOYED_EVENT_SIGNATURE =
        0xc95935a66d15e0da5e412aca0ad27ae891d20b2fb91cf3994b6a3bf2b8178082;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // The admin slot for a `proxy` is `shl(96, proxy)`.

    /// @dev The ERC-1967 storage slot for the implementation in the proxy.
    /// `uint256(keccak256("eip1967.proxy.implementation")) - 1`.
    uint256 internal constant _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      ADMIN FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns the admin of the proxy.
    function adminOf(address proxy) public view returns (address admin) {
        admin = address(uint160(_erc1967FactorySload(uint256(uint160(proxy)) << 96)));
    }

    /// @dev Sets the admin of the proxy.
    /// The caller of this function must be the admin of the proxy on this factory.
    function changeAdmin(address proxy, address admin) public {
        uint256 adminSlot = uint256(uint160(proxy)) << 96;
        // Check if the caller is the admin of the proxy.
        if (_erc1967FactorySload(adminSlot) != uint256(uint160(msg.sender))) revert Unauthorized();
        // Store the admin for the proxy.
        _erc1967FactorySstore(adminSlot, uint256(uint160(admin)));
        // Emit the {AdminChanged} event.
        emit AdminChanged(proxy, admin);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     UPGRADE FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Upgrades the proxy to point to `implementation`.
    /// The caller of this function must be the admin of the proxy on this factory.
    function upgrade(address proxy, address implementation) public payable {
        upgradeAndCall(proxy, implementation, _emptyData());
    }

    /// @dev Upgrades the proxy to point to `implementation`.
    /// Then, calls the proxy with abi encoded `data`.
    /// The caller of this function must be the admin of the proxy on this factory.
    function upgradeAndCall(address proxy, address implementation, bytes calldata data)
        public
        payable
    {
        // Check if the caller is the admin of the proxy.
        if (_erc1967FactorySload(uint256(uint160(proxy)) << 96) != uint256(uint160(msg.sender))) {
            revert Unauthorized();
        }
        // Try upgrading the proxy and revert upon failure.
        (bool success, bytes memory returned) = proxy.call{value: msg.value}(
            abi.encodePacked(uint256(uint160(implementation)), _IMPLEMENTATION_SLOT, data)
        );
        if (!success) {
            // Revert with the `UpgradeFailed` selector if there is no error returndata.
            if (returned.length == 0) revert UpgradeFailed();
            // Otherwise, bubble up the returned error.
            _erc1967FactoryRevertRaw(returned);
        }
        // Emit the {Upgraded} event.
        emit Upgraded(proxy, implementation);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      DEPLOY FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Deploys a proxy for `implementation`, with `admin`,
    /// and returns its address.
    /// The value passed into this function will be forwarded to the proxy.
    function deploy(address implementation, address admin) public payable returns (address proxy) {
        proxy = deployAndCall(implementation, admin, _emptyData());
    }

    /// @dev Deploys a proxy for `implementation`, with `admin`,
    /// and returns its address.
    /// The value passed into this function will be forwarded to the proxy.
    /// Then, calls the proxy with abi encoded `data`.
    function deployAndCall(address implementation, address admin, bytes calldata data)
        public
        payable
        returns (address proxy)
    {
        proxy = _deploy(implementation, admin, bytes32(0), false, data);
    }

    /// @dev Deploys a proxy for `implementation`, with `admin`, `salt`,
    /// and returns its deterministic address.
    /// The value passed into this function will be forwarded to the proxy.
    function deployDeterministic(address implementation, address admin, bytes32 salt)
        public
        payable
        returns (address proxy)
    {
        proxy = deployDeterministicAndCall(implementation, admin, salt, _emptyData());
    }

    /// @dev Deploys a proxy for `implementation`, with `admin`, `salt`,
    /// and returns its deterministic address.
    /// The value passed into this function will be forwarded to the proxy.
    /// Then, calls the proxy with abi encoded `data`.
    function deployDeterministicAndCall(
        address implementation,
        address admin,
        bytes32 salt,
        bytes calldata data
    ) public payable returns (address proxy) {
        // If the salt does not start with the zero address or the caller.
        uint256 saltPrefix = uint256(salt) >> 96;
        if (saltPrefix != 0 && saltPrefix != uint256(uint160(msg.sender))) {
            revert SaltDoesNotStartWithCaller();
        }
        proxy = _deploy(implementation, admin, salt, true, data);
    }

    /// @dev Deploys the proxy, with optionality to deploy deterministically with a `salt`.
    function _deploy(
        address implementation,
        address admin,
        bytes32 salt,
        bool useSalt,
        bytes calldata data
    ) internal returns (address proxy) {
        bytes memory initCode = _erc1967FactoryInitCode();
        // Create the proxy, reverting if the creation fails.
        proxy = useSalt ? _erc1967FactoryCreate2(initCode, salt) : _erc1967FactoryCreate(initCode);
        // Try setting the implementation on the proxy and revert upon failure.
        (bool success, bytes memory returned) = proxy.call{value: msg.value}(
            abi.encodePacked(uint256(uint160(implementation)), _IMPLEMENTATION_SLOT, data)
        );
        if (!success) {
            // Revert with the `DeploymentFailed` selector if there is no error returndata.
            if (returned.length == 0) revert DeploymentFailed();
            // Otherwise, bubble up the returned error.
            _erc1967FactoryRevertRaw(returned);
        }
        // Store the admin for the proxy.
        _erc1967FactorySstore(uint256(uint160(proxy)) << 96, uint256(uint160(admin)));
        // Emit the {Deployed} event.
        emit Deployed(proxy, implementation, admin);
    }

    /// @dev Returns the address of the proxy deployed with `salt`.
    function predictDeterministicAddress(bytes32 salt) public view returns (address predicted) {
        bytes32 hash = initCodeHash();
        // Compute the address from the prefix, this factory, `salt` and the bytecode hash.
        predicted = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, hash))))
        );
    }

    /// @dev Returns the initialization code hash of the proxy.
    /// Used for mining vanity addresses with create2crunch.
    function initCodeHash() public view returns (bytes32 result) {
        result = keccak256(_erc1967FactoryInitCode());
    }

    /// @dev Returns a pointer to the initialization code of a proxy created via this factory.
    function _initCode() internal view returns (bytes32 m) {
        /**
         * -------------------------------------------------------------------------------------+
         * CREATION (9 bytes)                                                                   |
         * -------------------------------------------------------------------------------------|
         * Opcode     | Mnemonic        | Stack               | Memory                          |
         * -------------------------------------------------------------------------------------|
         * 60 runSize | PUSH1 runSize   | r                   |                                 |
         * 3d         | RETURNDATASIZE  | 0 r                 |                                 |
         * 81         | DUP2            | r 0 r               |                                 |
         * 60 offset  | PUSH1 offset    | o r 0 r             |                                 |
         * 3d         | RETURNDATASIZE  | 0 o r 0 r           |                                 |
         * 39         | CODECOPY        | 0 r                 | [0..runSize): runtime code      |
         * f3         | RETURN          |                     | [0..runSize): runtime code      |
         * -------------------------------------------------------------------------------------|
         * RUNTIME (127 bytes)                                                                  |
         * -------------------------------------------------------------------------------------|
         * Opcode      | Mnemonic       | Stack               | Memory                          |
         * -------------------------------------------------------------------------------------|
         *                                                                                      |
         * ::: keep some values in stack :::::::::::::::::::::::::::::::::::::::::::::::::::::: |
         * 3d          | RETURNDATASIZE | 0                   |                                 |
         * 3d          | RETURNDATASIZE | 0 0                 |                                 |
         *                                                                                      |
         * ::: check if caller is factory ::::::::::::::::::::::::::::::::::::::::::::::::::::: |
         * 33          | CALLER         | c 0 0               |                                 |
         * 73 factory  | PUSH20 factory | f c 0 0             |                                 |
         * 14          | EQ             | isf 0 0             |                                 |
         * 60 0x57     | PUSH1 0x57     | dest isf 0 0        |                                 |
         * 57          | JUMPI          | 0 0                 |                                 |
         *                                                                                      |
         * ::: copy calldata to memory :::::::::::::::::::::::::::::::::::::::::::::::::::::::: |
         * 36          | CALLDATASIZE   | cds 0 0             |                                 |
         * 3d          | RETURNDATASIZE | 0 cds 0 0           |                                 |
         * 3d          | RETURNDATASIZE | 0 0 cds 0 0         |                                 |
         * 37          | CALLDATACOPY   | 0 0                 | [0..calldatasize): calldata     |
         *                                                                                      |
         * ::: delegatecall to implementation ::::::::::::::::::::::::::::::::::::::::::::::::: |
         * 36          | CALLDATASIZE   | cds 0 0             | [0..calldatasize): calldata     |
         * 3d          | RETURNDATASIZE | 0 cds 0 0           | [0..calldatasize): calldata     |
         * 7f slot     | PUSH32 slot    | s 0 cds 0 0         | [0..calldatasize): calldata     |
         * 54          | SLOAD          | i 0 cds 0 0         | [0..calldatasize): calldata     |
         * 5a          | GAS            | g i 0 cds 0 0       | [0..calldatasize): calldata     |
         * f4          | DELEGATECALL   | succ                | [0..calldatasize): calldata     |
         *                                                                                      |
         * ::: copy returndata to memory :::::::::::::::::::::::::::::::::::::::::::::::::::::: |
         * 3d          | RETURNDATASIZE | rds succ            | [0..calldatasize): calldata     |
         * 60 0x00     | PUSH1 0x00     | 0 rds succ          | [0..calldatasize): calldata     |
         * 80          | DUP1           | 0 0 rds succ        | [0..calldatasize): calldata     |
         * 3e          | RETURNDATACOPY | succ                | [0..returndatasize): returndata |
         *                                                                                      |
         * ::: branch on delegatecall status :::::::::::::::::::::::::::::::::::::::::::::::::: |
         * 60 0x52     | PUSH1 0x52     | dest succ           | [0..returndatasize): returndata |
         * 57          | JUMPI          |                     | [0..returndatasize): returndata |
         *                                                                                      |
         * ::: delegatecall failed, revert :::::::::::::::::::::::::::::::::::::::::::::::::::: |
         * 3d          | RETURNDATASIZE | rds                 | [0..returndatasize): returndata |
         * 60 0x00     | PUSH1 0x00     | 0 rds               | [0..returndatasize): returndata |
         * fd          | REVERT         |                     | [0..returndatasize): returndata |
         *                                                                                      |
         * ::: delegatecall succeeded, return ::::::::::::::::::::::::::::::::::::::::::::::::: |
         * 5b          | JUMPDEST       |                     | [0..returndatasize): returndata |
         * 3d          | RETURNDATASIZE | rds                 | [0..returndatasize): returndata |
         * 60 0x00     | PUSH1 0x00     | 0 rds               | [0..returndatasize): returndata |
         * f3          | RETURN         |                     | [0..returndatasize): returndata |
         *                                                                                      |
         * ::: set new implementation (caller is factory) ::::::::::::::::::::::::::::::::::::: |
         * 5b          | JUMPDEST       | 0 0                 |                                 |
         * 3d          | RETURNDATASIZE | 0 0 0               |                                 |
         * 35          | CALLDATALOAD   | impl 0 0            |                                 |
         * 60 0x20     | PUSH1 0x20     | w impl 0 0          |                                 |
         * 35          | CALLDATALOAD   | slot impl 0 0       |                                 |
         * 55          | SSTORE         | 0 0                 |                                 |
         *                                                                                      |
         * ::: no extra calldata, return :::::::::::::::::::::::::::::::::::::::::::::::::::::: |
         * 60 0x40     | PUSH1 0x40     | 2w 0 0              |                                 |
         * 80          | DUP1           | 2w 2w 0 0           |                                 |
         * 36          | CALLDATASIZE   | cds 2w 2w 0 0       |                                 |
         * 11          | GT             | gt 2w 0 0           |                                 |
         * 15          | ISZERO         | lte 2w 0 0          |                                 |
         * 60 0x52     | PUSH1 0x52     | dest lte 2w 0 0     |                                 |
         * 57          | JUMPI          | 2w 0 0              |                                 |
         *                                                                                      |
         * ::: copy extra calldata to memory :::::::::::::::::::::::::::::::::::::::::::::::::: |
         * 36          | CALLDATASIZE   | cds 2w 0 0          |                                 |
         * 03          | SUB            | t 0 0               |                                 |
         * 80          | DUP1           | t t 0 0             |                                 |
         * 60 0x40     | PUSH1 0x40     | 2w t t 0 0          |                                 |
         * 3d          | RETURNDATASIZE | 0 2w t t 0 0        |                                 |
         * 37          | CALLDATACOPY   | t 0 0               | [0..t): extra calldata          |
         *                                                                                      |
         * ::: delegatecall to implementation ::::::::::::::::::::::::::::::::::::::::::::::::: |
         * 3d          | RETURNDATASIZE | 0 t 0 0             | [0..t): extra calldata          |
         * 3d          | RETURNDATASIZE | 0 0 t 0 0           | [0..t): extra calldata          |
         * 35          | CALLDATALOAD   | i 0 t 0 0           | [0..t): extra calldata          |
         * 5a          | GAS            | g i 0 t 0 0         | [0..t): extra calldata          |
         * f4          | DELEGATECALL   | succ                | [0..t): extra calldata          |
         *                                                                                      |
         * ::: copy returndata to memory :::::::::::::::::::::::::::::::::::::::::::::::::::::: |
         * 3d          | RETURNDATASIZE | rds succ            | [0..t): extra calldata          |
         * 60 0x00     | PUSH1 0x00     | 0 rds succ          | [0..t): extra calldata          |
         * 80          | DUP1           | 0 0 rds succ        | [0..t): extra calldata          |
         * 3e          | RETURNDATACOPY | succ                | [0..returndatasize): returndata |
         *                                                                                      |
         * ::: branch on delegatecall status :::::::::::::::::::::::::::::::::::::::::::::::::: |
         * 60 0x52     | PUSH1 0x52     | dest succ           | [0..returndatasize): returndata |
         * 57          | JUMPI          |                     | [0..returndatasize): returndata |
         *                                                                                      |
         * ::: delegatecall failed, revert :::::::::::::::::::::::::::::::::::::::::::::::::::: |
         * 3d          | RETURNDATASIZE | rds                 | [0..returndatasize): returndata |
         * 60 0x00     | PUSH1 0x00     | 0 rds               | [0..returndatasize): returndata |
         * fd          | REVERT         |                     | [0..returndatasize): returndata |
         * -------------------------------------------------------------------------------------+
         */
        // The code starts 0x13 bytes after `m`, after zero bytes, as upstream lays it out.
        m = _erc1967FactoryDataPointer(abi.encodePacked(bytes19(0), _erc1967FactoryInitCode()));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          HELPERS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Helper function to return an empty bytes calldata.
    function _emptyData() internal pure returns (bytes calldata data) {
        data = msg.data[:0];
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PRIVATE HELPERS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The initialization code of a proxy created via this factory, which `_initCode`
    /// documents: 0x88 bytes, the creation code and the runtime code with this factory's address.
    function _erc1967FactoryInitCode() private view returns (bytes memory) {
        // If the factory's address has six or more leading zero bytes.
        if (uint160(address(this)) >> 112 == 0) {
            return abi.encodePacked(
                hex"60793d8160093d39f33d3d336d", // 9 + 4
                uint112(uint160(address(this))), // 14
                hex"14605157363d3d37363d7f360894a13ba1a3210667c828492db98dca3e2076cc", // 32
                hex"3735a920a3ca505d382bbc545af43d6000803e604c573d6000fd5b3d6000f35b", // 32
                hex"3d3560203555604080361115604c5736038060403d373d3d355af43d6000803e", // 32
                hex"604c573d6000fd", // 7
                bytes6(0) // 6, which the creation code does not copy.
            );
        }
        return abi.encodePacked(
            hex"607f3d8160093d39f33d3d3373", // 9 + 4
            address(this), // 20
            hex"14605757363d3d37363d7f360894a13ba1a3210667c828492db98dca3e2076cc", // 32
            hex"3735a920a3ca505d382bbc545af43d6000803e6052573d6000fd5b3d6000f35b", // 32
            hex"3d356020355560408036111560525736038060403d373d3d355af43d6000803e", // 32
            hex"6052573d6000fd" // 7
        );
    }

    /// @dev The word in storage slot `slot`. Solidity cannot name a slot it did not allocate.
    /// @custom:solar-trusted
    function _erc1967FactorySload(uint256 slot) private view returns (uint256 value) {
        /// @solidity memory-safe-assembly
        assembly {
            value := sload(slot)
        }
    }

    /// @dev Stores `value` in storage slot `slot`.
    /// @custom:solar-trusted
    function _erc1967FactorySstore(uint256 slot, uint256 value) private {
        /// @solidity memory-safe-assembly
        assembly {
            sstore(slot, value)
        }
    }

    /// @dev Deploys `initcode` and returns the new address. Solidity creates contracts only
    /// from their source.
    /// @custom:solar-trusted
    function _erc1967FactoryCreate(bytes memory initcode) private returns (address deployed) {
        /// @solidity memory-safe-assembly
        assembly {
            deployed := create(0, add(initcode, 0x20), mload(initcode))
        }
        if (deployed == address(0)) revert DeploymentFailed();
    }

    /// @dev Deploys `initcode` at the address `salt` selects.
    /// @custom:solar-trusted
    function _erc1967FactoryCreate2(bytes memory initcode, bytes32 salt)
        private
        returns (address deployed)
    {
        /// @solidity memory-safe-assembly
        assembly {
            deployed := create2(0, add(initcode, 0x20), mload(initcode), salt)
        }
        if (deployed == address(0)) revert DeploymentFailed();
    }

    /// @dev Reverts with exactly `data`. Solidity reverts only with an error it encodes.
    /// @custom:solar-trusted
    function _erc1967FactoryRevertRaw(bytes memory data) private pure {
        /// @solidity memory-safe-assembly
        assembly {
            revert(add(data, 0x20), mload(data))
        }
    }

    /// @dev The memory address of the first byte of `b`'s contents. Solidity cannot convert a
    /// memory reference to a value.
    /// @custom:solar-trusted
    function _erc1967FactoryDataPointer(bytes memory b) private pure returns (bytes32 m) {
        /// @solidity memory-safe-assembly
        assembly {
            m := add(b, 0x20)
        }
    }
}
