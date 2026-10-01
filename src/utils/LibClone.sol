// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Bytes} from "solar:core/Bytes.sol";
import {Calls} from "solar:core/Calls.sol";
import {Code} from "solar:core/Code.sol";
import {Create} from "solar:core/Create.sol";
import {Hash} from "solar:core/Hash.sol";
import {Revert} from "solar:core/Revert.sol";

/// @notice Checked Solidity implementation of the pinned Solady LibClone API:
/// minimal proxies (plain, PUSH0 and with immutable arguments), minimal ERC1967
/// and ERC1967I proxies, ERC1967 and ERC1967I beacon proxies, each with and
/// without immutable arguments, and the ERC1967 bootstrap.
/// @dev Each proxy's creation code is the bytes the assembly writes, assembled
/// with `abi.encodePacked` around its implementation or beacon, and deployed
/// with `Create`, which fails with the same `DeploymentFailed()`. A proxy's
/// arguments follow its runtime code and are read back with `Code.read`,
/// checked against the code's size. Three deliberate differences from the
/// assembly: arguments too long for the two-byte runtime size fail with
/// `DeploymentFailed()` where the assembly runs out of gas outside a
/// deployment; reading the arguments of an account whose code is shorter than
/// the proxy's fails with `Panic(0x11)` instead of running out of gas; and
/// `argLoad` reads zeros past the end of `args`, where the assembly reads
/// whatever memory follows, which the `argsOn` functions leave zeroed.
library LibClone {
    /// @dev The keccak256 of deployed code for the clone proxy,
    /// with the implementation set to `address(0)`.
    bytes32 internal constant CLONE_CODE_HASH =
        0x48db2cfdb2853fce0b464f1f93a1996469459df3ab6c812106074c4106a1eb1f;

    /// @dev The keccak256 of deployed code for the PUSH0 proxy,
    /// with the implementation set to `address(0)`.
    bytes32 internal constant PUSH0_CLONE_CODE_HASH =
        0x67bc6bde1b84d66e267c718ba44cf3928a615d29885537955cb43d44b3e789dc;

    /// @dev The keccak256 of deployed code for the ERC-1167 CWIA proxy,
    /// with the implementation set to `address(0)`.
    bytes32 internal constant CWIA_CODE_HASH =
        0x3cf92464268225a4513da40a34d967354684c32cd0edd67b5f668dfe3550e940;

    /// @dev The keccak256 of the deployed code for the ERC1967 proxy.
    bytes32 internal constant ERC1967_CODE_HASH =
        0xaaa52c8cc8a0e3fd27ce756cc6b4e70c51423e9b597b11f32d3e49f8b1fc890d;

    /// @dev The keccak256 of the deployed code for the ERC1967I proxy.
    bytes32 internal constant ERC1967I_CODE_HASH =
        0xce700223c0d4cea4583409accfc45adac4a093b3519998a9cbbe1504dadba6f7;

    /// @dev The keccak256 of the deployed code for the ERC1967 beacon proxy.
    bytes32 internal constant ERC1967_BEACON_PROXY_CODE_HASH =
        0x14044459af17bc4f0f5aa2f658cb692add77d1302c29fe2aebab005eea9d1162;

    /// @dev The keccak256 of the deployed code for the ERC1967 beacon proxy.
    bytes32 internal constant ERC1967I_BEACON_PROXY_CODE_HASH =
        0xf8c46d2793d5aa984eb827aeaba4b63aedcab80119212fce827309788735519a;

    /// @dev Unable to deploy the clone.
    error DeploymentFailed();

    /// @dev The salt must start with either the zero address or `by`.
    error SaltDoesNotStartWith();

    /// @dev The ETH transfer has failed.
    error ETHTransferFailed();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    CREATION CODE PIECES                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The creation code of a minimal proxy up to its implementation.
    bytes private constant _CLONE_HEAD = hex"602c3d8160093d39f33d3d3d3d363d3d37363d73";

    /// @dev The runtime code after the address.
    bytes private constant _CLONE_TAIL = hex"5af43d3d93803e602a57fd5bf3";

    /// @dev The creation code of a PUSH0 minimal proxy up to its implementation.
    bytes private constant _PUSH0_CLONE_HEAD = hex"602d5f8160095f39f35f5f365f5f37365f73";

    /// @dev The runtime code after the address.
    bytes private constant _PUSH0_CLONE_TAIL = hex"5af43d5f5f3e6029573d5ffd5b3d5ff3";

    /// @dev The creation code of a minimal ERC1967 proxy up to its implementation.
    bytes private constant _ERC1967_HEAD = hex"603d3d8160223d3973";

    /// @dev The runtime code after the address.
    bytes private constant _ERC1967_TAIL =
        hex"60095155f3363d3d373d3d363d7f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc545af43d6000803e6038573d6000fd5b3d6000f3";

    /// @dev The creation code of an ERC1967I proxy up to its implementation.
    bytes private constant _ERC1967I_HEAD = hex"60523d8160223d3973";

    /// @dev The runtime code after the address.
    bytes private constant _ERC1967I_TAIL =
        hex"600f5155f3365814604357363d3d373d3d363d7f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc545af43d6000803e603e573d6000fd5b3d6000f35b6020600f3d393d51543d52593df3";

    /// @dev The creation code of an ERC1967 beacon proxy up to its beacon.
    bytes private constant _ERC1967_BEACON_PROXY_HEAD = hex"60523d8160223d3973";

    /// @dev The runtime code after the address.
    bytes private constant _ERC1967_BEACON_PROXY_TAIL =
        hex"60195155f3363d3d373d3d363d602036600436635c60da1b60e01b36527fa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50545afa5036515af43d6000803e604d573d6000fd5b3d6000f3";

    /// @dev The creation code of an ERC1967I beacon proxy up to its beacon.
    bytes private constant _ERC1967I_BEACON_PROXY_HEAD = hex"60573d8160223d3973";

    /// @dev The runtime code after the address.
    bytes private constant _ERC1967I_BEACON_PROXY_TAIL =
        hex"60195155f3363d3d373d3d363d602036600436635c60da1b60e01b36527fa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50545afa361460525736515af43d600060013e6052573d6001fd5b3d6001f3";

    /// @dev The creation code of the ERC1967 bootstrap up to its authorized
    /// upgrader.
    bytes private constant _ERC1967_BOOTSTRAP_HEAD = hex"606880600a3d393df3fe3373";

    /// @dev The runtime code after the address.
    bytes private constant _ERC1967_BOOTSTRAP_TAIL =
        hex"0338573d3560601c7f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc55601436116049575b005b363d3d373d3d6014360360143d3560601c5af46047573d6000383e3d38fd";

    /// @dev The creation code of a clone with arguments, between the runtime
    /// size it pushes and the address; its runtime is 0x2d bytes before the
    /// arguments.
    bytes private constant _CWIA_ARGS_HEAD = hex"3d81600a3d39f3363d3d373d3d3d363d73";

    /// @dev The runtime code of a clone with arguments after the address.
    bytes private constant _CWIA_TAIL = hex"5af43d82803e903d91602b57fd5bf3";

    /// @dev The creation code of an ERC1967 proxy of any kind with arguments,
    /// between the runtime size it pushes and the address. The runtime is 0x3d
    /// bytes before the arguments for a minimal proxy, 0x52 for an ERC1967I
    /// proxy or a beacon proxy, and 0x57 for an ERC1967I beacon proxy.
    bytes private constant _ERC1967_ARGS_HEAD = hex"3d8160233d3973";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  MINIMAL PROXY OPERATIONS                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    /// @dev Deploys a clone of `implementation`.
    function clone(address implementation) internal returns (address instance) {
        instance = clone(0, implementation);
    }

    /// @dev Deploys a clone of `implementation`.
    /// Deposits `value` ETH during deployment.
    function clone(uint256 value, address implementation) internal returns (address instance) {
        return Create.deploy(abi.encodePacked(_CLONE_HEAD, implementation, _CLONE_TAIL), value);
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
        return Create.deploy2(
            abi.encodePacked(_CLONE_HEAD, implementation, _CLONE_TAIL), salt, value
        );
    }

    /// @dev Returns the initialization code of the clone of `implementation`.
    function initCode(address implementation) internal pure returns (bytes memory c) {
        return abi.encodePacked(_CLONE_HEAD, implementation, _CLONE_TAIL);
    }

    /// @dev Returns the initialization code hash of the clone of `implementation`.
    function initCodeHash(address implementation) internal pure returns (bytes32 hash) {
        return keccak256(abi.encodePacked(_CLONE_HEAD, implementation, _CLONE_TAIL));
    }

    /// @dev Returns the address of the clone of `implementation`, with `salt` by `deployer`.
    function predictDeterministicAddress(address implementation, bytes32 salt, address deployer)
        internal
        pure
        returns (address predicted)
    {
        predicted = predictDeterministicAddress(initCodeHash(implementation), salt, deployer);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*          MINIMAL PROXY OPERATIONS (PUSH0 VARIANT)          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    /// @dev Deploys a PUSH0 clone of `implementation`.
    function clone_PUSH0(address implementation) internal returns (address instance) {
        instance = clone_PUSH0(0, implementation);
    }

    /// @dev Deploys a PUSH0 clone of `implementation`.
    /// Deposits `value` ETH during deployment.
    function clone_PUSH0(uint256 value, address implementation)
        internal
        returns (address instance)
    {
        return Create.deploy(
            abi.encodePacked(_PUSH0_CLONE_HEAD, implementation, _PUSH0_CLONE_TAIL), value
        );
    }

    /// @dev Deploys a deterministic PUSH0 clone of `implementation` with `salt`.
    function cloneDeterministic_PUSH0(address implementation, bytes32 salt)
        internal
        returns (address instance)
    {
        instance = cloneDeterministic_PUSH0(0, implementation, salt);
    }

    /// @dev Deploys a deterministic PUSH0 clone of `implementation` with `salt`.
    /// Deposits `value` ETH during deployment.
    function cloneDeterministic_PUSH0(uint256 value, address implementation, bytes32 salt)
        internal
        returns (address instance)
    {
        return Create.deploy2(
            abi.encodePacked(_PUSH0_CLONE_HEAD, implementation, _PUSH0_CLONE_TAIL), salt, value
        );
    }

    /// @dev Returns the initialization code of the PUSH0 clone of `implementation`.
    function initCode_PUSH0(address implementation) internal pure returns (bytes memory c) {
        return abi.encodePacked(_PUSH0_CLONE_HEAD, implementation, _PUSH0_CLONE_TAIL);
    }

    /// @dev Returns the initialization code hash of the PUSH0 clone of `implementation`.
    function initCodeHash_PUSH0(address implementation) internal pure returns (bytes32 hash) {
        return keccak256(abi.encodePacked(_PUSH0_CLONE_HEAD, implementation, _PUSH0_CLONE_TAIL));
    }

    /// @dev Returns the address of the PUSH0 clone of `implementation`, with `salt` by `deployer`.
    function predictDeterministicAddress_PUSH0(
        address implementation,
        bytes32 salt,
        address deployer
    ) internal pure returns (address predicted) {
        predicted = predictDeterministicAddress(initCodeHash_PUSH0(implementation), salt, deployer);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*           CLONES WITH IMMUTABLE ARGS OPERATIONS            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    /// @dev Deploys a clone of `implementation` with immutable arguments encoded in `args`.
    function clone(address implementation, bytes memory args) internal returns (address instance) {
        instance = clone(0, implementation, args);
    }

    /// @dev Deploys a clone of `implementation` with immutable arguments encoded in `args`.
    /// Deposits `value` ETH during deployment.
    function clone(uint256 value, address implementation, bytes memory args)
        internal
        returns (address instance)
    {
        return Create.deploy(
            abi.encodePacked(
                hex"61", _runtimeSize(0x2d, args), _CWIA_ARGS_HEAD, implementation, _CWIA_TAIL, args
            ),
            value
        );
    }

    /// @dev Deploys a deterministic clone of `implementation`
    /// with immutable arguments encoded in `args` and `salt`.
    function cloneDeterministic(address implementation, bytes memory args, bytes32 salt)
        internal
        returns (address instance)
    {
        instance = cloneDeterministic(0, implementation, args, salt);
    }

    /// @dev Deploys a deterministic clone of `implementation`
    /// with immutable arguments encoded in `args` and `salt`.
    function cloneDeterministic(
        uint256 value,
        address implementation,
        bytes memory args,
        bytes32 salt
    ) internal returns (address instance) {
        return Create.deploy2(
            abi.encodePacked(
                hex"61", _runtimeSize(0x2d, args), _CWIA_ARGS_HEAD, implementation, _CWIA_TAIL, args
            ),
            salt,
            value
        );
    }

    /// @dev Deploys a deterministic clone of `implementation`
    /// with immutable arguments encoded in `args` and `salt`.
    /// This method does not revert if the clone has already been deployed.
    function createDeterministicClone(address implementation, bytes memory args, bytes32 salt)
        internal
        returns (bool alreadyDeployed, address instance)
    {
        return createDeterministicClone(0, implementation, args, salt);
    }

    /// @dev Deploys a deterministic clone of `implementation`
    /// with immutable arguments encoded in `args` and `salt`.
    /// This method does not revert if the clone has already been deployed.
    function createDeterministicClone(
        uint256 value,
        address implementation,
        bytes memory args,
        bytes32 salt
    ) internal returns (bool alreadyDeployed, address instance) {
        return _createDeterministic(
            abi.encodePacked(
                hex"61", _runtimeSize(0x2d, args), _CWIA_ARGS_HEAD, implementation, _CWIA_TAIL, args
            ),
            salt,
            value
        );
    }

    /// @dev Returns the initialization code of the clone of `implementation`
    /// using immutable arguments encoded in `args`.
    function initCode(address implementation, bytes memory args)
        internal
        pure
        returns (bytes memory c)
    {
        return abi.encodePacked(
            hex"61", _runtimeSize(0x2d, args), _CWIA_ARGS_HEAD, implementation, _CWIA_TAIL, args
        );
    }

    /// @dev Returns the initialization code hash of the clone of `implementation`
    /// using immutable arguments encoded in `args`.
    function initCodeHash(address implementation, bytes memory args)
        internal
        pure
        returns (bytes32 hash)
    {
        return keccak256(
            abi.encodePacked(
                hex"61", _runtimeSize(0x2d, args), _CWIA_ARGS_HEAD, implementation, _CWIA_TAIL, args
            )
        );
    }

    /// @dev Returns the address of the clone of
    /// `implementation` using immutable arguments encoded in `args`, with `salt`, by `deployer`.
    function predictDeterministicAddress(
        address implementation,
        bytes memory data,
        bytes32 salt,
        address deployer
    ) internal pure returns (address predicted) {
        predicted = predictDeterministicAddress(initCodeHash(implementation, data), salt, deployer);
    }

    /// @dev Equivalent to `argsOnClone(instance, 0, 2 ** 256 - 1)`.
    function argsOnClone(address instance) internal view returns (bytes memory args) {
        return _argsOn(instance, 0x2d);
    }

    /// @dev Equivalent to `argsOnClone(instance, start, 2 ** 256 - 1)`.
    function argsOnClone(address instance, uint256 start)
        internal
        view
        returns (bytes memory args)
    {
        return _argsOn(instance, 0x2d, start);
    }

    /// @dev Returns a slice of the immutable arguments on `instance` from `start` to `end`.
    /// `start` and `end` will be clamped to the range `[0, args.length]`.
    /// The `instance` MUST be deployed via the clone with immutable args functions.
    /// Otherwise, the behavior is undefined.
    /// Out-of-gas reverts if `instance` does not have any code.
    function argsOnClone(address instance, uint256 start, uint256 end)
        internal
        view
        returns (bytes memory args)
    {
        return _argsOn(instance, 0x2d, start, end);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*              MINIMAL ERC1967 PROXY OPERATIONS              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    /// @dev Deploys a minimal ERC1967 proxy with `implementation`.
    function deployERC1967(address implementation) internal returns (address instance) {
        instance = deployERC1967(0, implementation);
    }

    /// @dev Deploys a minimal ERC1967 proxy with `implementation`.
    /// Deposits `value` ETH during deployment.
    function deployERC1967(uint256 value, address implementation)
        internal
        returns (address instance)
    {
        return Create.deploy(abi.encodePacked(_ERC1967_HEAD, implementation, _ERC1967_TAIL), value);
    }

    /// @dev Deploys a deterministic minimal ERC1967 proxy with `implementation` and `salt`.
    function deployDeterministicERC1967(address implementation, bytes32 salt)
        internal
        returns (address instance)
    {
        instance = deployDeterministicERC1967(0, implementation, salt);
    }

    /// @dev Deploys a deterministic minimal ERC1967 proxy with `implementation` and `salt`.
    /// Deposits `value` ETH during deployment.
    function deployDeterministicERC1967(uint256 value, address implementation, bytes32 salt)
        internal
        returns (address instance)
    {
        return
            Create.deploy2(
                abi.encodePacked(_ERC1967_HEAD, implementation, _ERC1967_TAIL), salt, value
            );
    }

    /// @dev Creates a deterministic minimal ERC1967 proxy with `implementation` and `salt`.
    /// Note: This method is intended for use in ERC4337 factories,
    /// which are expected to NOT revert if the proxy is already deployed.
    function createDeterministicERC1967(address implementation, bytes32 salt)
        internal
        returns (bool alreadyDeployed, address instance)
    {
        return createDeterministicERC1967(0, implementation, salt);
    }

    /// @dev Creates a deterministic minimal ERC1967 proxy with `implementation` and `salt`.
    /// Deposits `value` ETH during deployment.
    /// Note: This method is intended for use in ERC4337 factories,
    /// which are expected to NOT revert if the proxy is already deployed.
    function createDeterministicERC1967(uint256 value, address implementation, bytes32 salt)
        internal
        returns (bool alreadyDeployed, address instance)
    {
        return _createDeterministic(
            abi.encodePacked(_ERC1967_HEAD, implementation, _ERC1967_TAIL), salt, value
        );
    }

    /// @dev Returns the initialization code of the minimal ERC1967 proxy of `implementation`.
    function initCodeERC1967(address implementation) internal pure returns (bytes memory c) {
        return abi.encodePacked(_ERC1967_HEAD, implementation, _ERC1967_TAIL);
    }

    /// @dev Returns the initialization code hash of the minimal ERC1967 proxy of `implementation`.
    function initCodeHashERC1967(address implementation) internal pure returns (bytes32 hash) {
        return keccak256(abi.encodePacked(_ERC1967_HEAD, implementation, _ERC1967_TAIL));
    }

    /// @dev Returns the address of the ERC1967 proxy of `implementation`, with `salt` by `deployer`.
    function predictDeterministicAddressERC1967(
        address implementation,
        bytes32 salt,
        address deployer
    ) internal pure returns (address predicted) {
        predicted = predictDeterministicAddress(initCodeHashERC1967(implementation), salt, deployer);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*    MINIMAL ERC1967 PROXY WITH IMMUTABLE ARGS OPERATIONS    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    /// @dev Deploys a minimal ERC1967 proxy with `implementation` and `args`.
    function deployERC1967(address implementation, bytes memory args)
        internal
        returns (address instance)
    {
        instance = deployERC1967(0, implementation, args);
    }

    /// @dev Deploys a minimal ERC1967 proxy with `implementation` and `args`.
    /// Deposits `value` ETH during deployment.
    function deployERC1967(uint256 value, address implementation, bytes memory args)
        internal
        returns (address instance)
    {
        return Create.deploy(
            abi.encodePacked(
                hex"61",
                _runtimeSize(0x3d, args),
                _ERC1967_ARGS_HEAD,
                implementation,
                _ERC1967_TAIL,
                args
            ),
            value
        );
    }

    /// @dev Deploys a deterministic minimal ERC1967 proxy with `implementation`, `args` and `salt`.
    function deployDeterministicERC1967(address implementation, bytes memory args, bytes32 salt)
        internal
        returns (address instance)
    {
        instance = deployDeterministicERC1967(0, implementation, args, salt);
    }

    /// @dev Deploys a deterministic minimal ERC1967 proxy with `implementation`, `args` and `salt`.
    /// Deposits `value` ETH during deployment.
    function deployDeterministicERC1967(
        uint256 value,
        address implementation,
        bytes memory args,
        bytes32 salt
    ) internal returns (address instance) {
        return Create.deploy2(
            abi.encodePacked(
                hex"61",
                _runtimeSize(0x3d, args),
                _ERC1967_ARGS_HEAD,
                implementation,
                _ERC1967_TAIL,
                args
            ),
            salt,
            value
        );
    }

    /// @dev Creates a deterministic minimal ERC1967 proxy with `implementation`, `args` and `salt`.
    /// Note: This method is intended for use in ERC4337 factories,
    /// which are expected to NOT revert if the proxy is already deployed.
    function createDeterministicERC1967(address implementation, bytes memory args, bytes32 salt)
        internal
        returns (bool alreadyDeployed, address instance)
    {
        return createDeterministicERC1967(0, implementation, args, salt);
    }

    /// @dev Creates a deterministic minimal ERC1967 proxy with `implementation`, `args` and `salt`.
    /// Deposits `value` ETH during deployment.
    /// Note: This method is intended for use in ERC4337 factories,
    /// which are expected to NOT revert if the proxy is already deployed.
    function createDeterministicERC1967(
        uint256 value,
        address implementation,
        bytes memory args,
        bytes32 salt
    ) internal returns (bool alreadyDeployed, address instance) {
        return _createDeterministic(
            abi.encodePacked(
                hex"61",
                _runtimeSize(0x3d, args),
                _ERC1967_ARGS_HEAD,
                implementation,
                _ERC1967_TAIL,
                args
            ),
            salt,
            value
        );
    }

    /// @dev Returns the initialization code of the minimal ERC1967 proxy of `implementation` and `args`.
    function initCodeERC1967(address implementation, bytes memory args)
        internal
        pure
        returns (bytes memory c)
    {
        return abi.encodePacked(
            hex"61",
            _runtimeSize(0x3d, args),
            _ERC1967_ARGS_HEAD,
            implementation,
            _ERC1967_TAIL,
            args
        );
    }

    /// @dev Returns the initialization code hash of the minimal ERC1967 proxy of `implementation` and `args`.
    function initCodeHashERC1967(address implementation, bytes memory args)
        internal
        pure
        returns (bytes32 hash)
    {
        return keccak256(
            abi.encodePacked(
                hex"61",
                _runtimeSize(0x3d, args),
                _ERC1967_ARGS_HEAD,
                implementation,
                _ERC1967_TAIL,
                args
            )
        );
    }

    /// @dev Returns the address of the ERC1967 proxy of `implementation`, `args`, with `salt` by `deployer`.
    function predictDeterministicAddressERC1967(
        address implementation,
        bytes memory args,
        bytes32 salt,
        address deployer
    ) internal pure returns (address predicted) {
        predicted = predictDeterministicAddress(
            initCodeHashERC1967(implementation, args), salt, deployer
        );
    }

    /// @dev Equivalent to `argsOnERC1967(instance, start, 2 ** 256 - 1)`.
    function argsOnERC1967(address instance) internal view returns (bytes memory args) {
        return _argsOn(instance, 0x3d);
    }

    /// @dev Equivalent to `argsOnERC1967(instance, start, 2 ** 256 - 1)`.
    function argsOnERC1967(address instance, uint256 start)
        internal
        view
        returns (bytes memory args)
    {
        return _argsOn(instance, 0x3d, start);
    }

    /// @dev Returns a slice of the immutable arguments on `instance` from `start` to `end`.
    /// `start` and `end` will be clamped to the range `[0, args.length]`.
    /// The `instance` MUST be deployed via the ERC1967 with immutable args functions.
    /// Otherwise, the behavior is undefined.
    /// Out-of-gas reverts if `instance` does not have any code.
    function argsOnERC1967(address instance, uint256 start, uint256 end)
        internal
        view
        returns (bytes memory args)
    {
        return _argsOn(instance, 0x3d, start, end);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 ERC1967I PROXY OPERATIONS                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    /// @dev Deploys a ERC1967I proxy with `implementation`.
    function deployERC1967I(address implementation) internal returns (address instance) {
        instance = deployERC1967I(0, implementation);
    }

    /// @dev Deploys a ERC1967I proxy with `implementation`.
    /// Deposits `value` ETH during deployment.
    function deployERC1967I(uint256 value, address implementation)
        internal
        returns (address instance)
    {
        return Create.deploy(
            abi.encodePacked(_ERC1967I_HEAD, implementation, _ERC1967I_TAIL), value
        );
    }

    /// @dev Deploys a deterministic ERC1967I proxy with `implementation` and `salt`.
    function deployDeterministicERC1967I(address implementation, bytes32 salt)
        internal
        returns (address instance)
    {
        instance = deployDeterministicERC1967I(0, implementation, salt);
    }

    /// @dev Deploys a deterministic ERC1967I proxy with `implementation` and `salt`.
    /// Deposits `value` ETH during deployment.
    function deployDeterministicERC1967I(uint256 value, address implementation, bytes32 salt)
        internal
        returns (address instance)
    {
        return Create.deploy2(
            abi.encodePacked(_ERC1967I_HEAD, implementation, _ERC1967I_TAIL), salt, value
        );
    }

    /// @dev Creates a deterministic ERC1967I proxy with `implementation` and `salt`.
    /// Note: This method is intended for use in ERC4337 factories,
    /// which are expected to NOT revert if the proxy is already deployed.
    function createDeterministicERC1967I(address implementation, bytes32 salt)
        internal
        returns (bool alreadyDeployed, address instance)
    {
        return createDeterministicERC1967I(0, implementation, salt);
    }

    /// @dev Creates a deterministic ERC1967I proxy with `implementation` and `salt`.
    /// Deposits `value` ETH during deployment.
    /// Note: This method is intended for use in ERC4337 factories,
    /// which are expected to NOT revert if the proxy is already deployed.
    function createDeterministicERC1967I(uint256 value, address implementation, bytes32 salt)
        internal
        returns (bool alreadyDeployed, address instance)
    {
        return _createDeterministic(
            abi.encodePacked(_ERC1967I_HEAD, implementation, _ERC1967I_TAIL), salt, value
        );
    }

    /// @dev Returns the initialization code of the ERC1967I proxy of `implementation`.
    function initCodeERC1967I(address implementation) internal pure returns (bytes memory c) {
        return abi.encodePacked(_ERC1967I_HEAD, implementation, _ERC1967I_TAIL);
    }

    /// @dev Returns the initialization code hash of the ERC1967I proxy of `implementation`.
    function initCodeHashERC1967I(address implementation) internal pure returns (bytes32 hash) {
        return keccak256(abi.encodePacked(_ERC1967I_HEAD, implementation, _ERC1967I_TAIL));
    }

    /// @dev Returns the address of the ERC1967I proxy of `implementation`, with `salt` by `deployer`.
    function predictDeterministicAddressERC1967I(
        address implementation,
        bytes32 salt,
        address deployer
    ) internal pure returns (address predicted) {
        predicted = predictDeterministicAddress(
            initCodeHashERC1967I(implementation), salt, deployer
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*       ERC1967I PROXY WITH IMMUTABLE ARGS OPERATIONS        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    /// @dev Deploys a minimal ERC1967I proxy with `implementation` and `args`.
    function deployERC1967I(address implementation, bytes memory args) internal returns (address) {
        return deployERC1967I(0, implementation, args);
    }

    /// @dev Deploys a minimal ERC1967I proxy with `implementation` and `args`.
    /// Deposits `value` ETH during deployment.
    function deployERC1967I(uint256 value, address implementation, bytes memory args)
        internal
        returns (address instance)
    {
        return Create.deploy(
            abi.encodePacked(
                hex"61",
                _runtimeSize(0x52, args),
                _ERC1967_ARGS_HEAD,
                implementation,
                _ERC1967I_TAIL,
                args
            ),
            value
        );
    }

    /// @dev Deploys a deterministic ERC1967I proxy with `implementation`, `args`, and `salt`.
    function deployDeterministicERC1967I(address implementation, bytes memory args, bytes32 salt)
        internal
        returns (address instance)
    {
        instance = deployDeterministicERC1967I(0, implementation, args, salt);
    }

    /// @dev Deploys a deterministic ERC1967I proxy with `implementation`, `args`, and `salt`.
    /// Deposits `value` ETH during deployment.
    function deployDeterministicERC1967I(
        uint256 value,
        address implementation,
        bytes memory args,
        bytes32 salt
    ) internal returns (address instance) {
        return Create.deploy2(
            abi.encodePacked(
                hex"61",
                _runtimeSize(0x52, args),
                _ERC1967_ARGS_HEAD,
                implementation,
                _ERC1967I_TAIL,
                args
            ),
            salt,
            value
        );
    }

    /// @dev Creates a deterministic ERC1967I proxy with `implementation`, `args` and `salt`.
    /// Note: This method is intended for use in ERC4337 factories,
    /// which are expected to NOT revert if the proxy is already deployed.
    function createDeterministicERC1967I(address implementation, bytes memory args, bytes32 salt)
        internal
        returns (bool alreadyDeployed, address instance)
    {
        return createDeterministicERC1967I(0, implementation, args, salt);
    }

    /// @dev Creates a deterministic ERC1967I proxy with `implementation`, `args` and `salt`.
    /// Deposits `value` ETH during deployment.
    /// Note: This method is intended for use in ERC4337 factories,
    /// which are expected to NOT revert if the proxy is already deployed.
    function createDeterministicERC1967I(
        uint256 value,
        address implementation,
        bytes memory args,
        bytes32 salt
    ) internal returns (bool alreadyDeployed, address instance) {
        return _createDeterministic(
            abi.encodePacked(
                hex"61",
                _runtimeSize(0x52, args),
                _ERC1967_ARGS_HEAD,
                implementation,
                _ERC1967I_TAIL,
                args
            ),
            salt,
            value
        );
    }

    /// @dev Returns the initialization code of the ERC1967I proxy of `implementation` and `args`.
    function initCodeERC1967I(address implementation, bytes memory args)
        internal
        pure
        returns (bytes memory c)
    {
        return abi.encodePacked(
            hex"61",
            _runtimeSize(0x52, args),
            _ERC1967_ARGS_HEAD,
            implementation,
            _ERC1967I_TAIL,
            args
        );
    }

    /// @dev Returns the initialization code hash of the ERC1967I proxy of `implementation` and `args.
    function initCodeHashERC1967I(address implementation, bytes memory args)
        internal
        pure
        returns (bytes32 hash)
    {
        return keccak256(
            abi.encodePacked(
                hex"61",
                _runtimeSize(0x52, args),
                _ERC1967_ARGS_HEAD,
                implementation,
                _ERC1967I_TAIL,
                args
            )
        );
    }

    /// @dev Returns the address of the ERC1967I proxy of `implementation`, `args` with `salt` by `deployer`.
    function predictDeterministicAddressERC1967I(
        address implementation,
        bytes memory args,
        bytes32 salt,
        address deployer
    ) internal pure returns (address predicted) {
        predicted = predictDeterministicAddress(
            initCodeHashERC1967I(implementation, args), salt, deployer
        );
    }

    /// @dev Equivalent to `argsOnERC1967I(instance, start, 2 ** 256 - 1)`.
    function argsOnERC1967I(address instance) internal view returns (bytes memory args) {
        return _argsOn(instance, 0x52);
    }

    /// @dev Equivalent to `argsOnERC1967I(instance, start, 2 ** 256 - 1)`.
    function argsOnERC1967I(address instance, uint256 start)
        internal
        view
        returns (bytes memory args)
    {
        return _argsOn(instance, 0x52, start);
    }

    /// @dev Returns a slice of the immutable arguments on `instance` from `start` to `end`.
    /// `start` and `end` will be clamped to the range `[0, args.length]`.
    /// The `instance` MUST be deployed via the ERC1967 with immutable args functions.
    /// Otherwise, the behavior is undefined.
    /// Out-of-gas reverts if `instance` does not have any code.
    function argsOnERC1967I(address instance, uint256 start, uint256 end)
        internal
        view
        returns (bytes memory args)
    {
        return _argsOn(instance, 0x52, start, end);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                ERC1967 BOOTSTRAP OPERATIONS                */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    /// @dev Deploys the ERC1967 bootstrap if it has not been deployed.
    function erc1967Bootstrap() internal returns (address) {
        return erc1967Bootstrap(address(this));
    }

    /// @dev Deploys the ERC1967 bootstrap if it has not been deployed.
    function erc1967Bootstrap(address authorizedUpgrader) internal returns (address bootstrap) {
        bytes memory c = initCodeERC1967Bootstrap(authorizedUpgrader);
        bootstrap = predictDeterministicAddress(keccak256(c), bytes32(0), address(this));
        if (bootstrap.code.length == 0) Create.deploy2(c, bytes32(0), 0);
    }

    /// @dev Replaces the implementation at `instance`.
    function bootstrapERC1967(address instance, address implementation) internal {
        // The bootstrap takes the new implementation as its whole calldata.
        (bool success,,) =
            Calls.callBounded(instance, 0, gasleft(), abi.encodePacked(implementation), 0);
        if (!success) revert DeploymentFailed();
    }

    /// @dev Replaces the implementation at `instance`, and then call it with `data`.
    function bootstrapERC1967AndCall(address instance, address implementation, bytes memory data)
        internal
    {
        // The bootstrap takes the new implementation, then calls it with the rest.
        (bool success, bytes memory result) = instance.call(abi.encodePacked(implementation, data));
        if (!success) {
            if (result.length == 0) revert DeploymentFailed();
            Revert.raw(result);
        }
    }

    /// @dev Returns the implementation address of the ERC1967 bootstrap for this contract.
    function predictDeterministicAddressERC1967Bootstrap() internal view returns (address) {
        return predictDeterministicAddressERC1967Bootstrap(address(this), address(this));
    }

    /// @dev Returns the implementation address of the ERC1967 bootstrap for this contract.
    function predictDeterministicAddressERC1967Bootstrap(
        address authorizedUpgrader,
        address deployer
    ) internal pure returns (address) {
        bytes32 hash = initCodeHashERC1967Bootstrap(authorizedUpgrader);
        return predictDeterministicAddress(hash, bytes32(0), deployer);
    }

    /// @dev Returns the initialization code of the ERC1967 bootstrap.
    function initCodeERC1967Bootstrap(address authorizedUpgrader)
        internal
        pure
        returns (bytes memory c)
    {
        return
            abi.encodePacked(_ERC1967_BOOTSTRAP_HEAD, authorizedUpgrader, _ERC1967_BOOTSTRAP_TAIL);
    }

    /// @dev Returns the initialization code hash of the ERC1967 bootstrap.
    function initCodeHashERC1967Bootstrap(address authorizedUpgrader)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(_ERC1967_BOOTSTRAP_HEAD, authorizedUpgrader, _ERC1967_BOOTSTRAP_TAIL)
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*          MINIMAL ERC1967 BEACON PROXY OPERATIONS           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    /// @dev Deploys a minimal ERC1967 beacon proxy.
    function deployERC1967BeaconProxy(address beacon) internal returns (address instance) {
        instance = deployERC1967BeaconProxy(0, beacon);
    }

    /// @dev Deploys a minimal ERC1967 beacon proxy.
    /// Deposits `value` ETH during deployment.
    function deployERC1967BeaconProxy(uint256 value, address beacon)
        internal
        returns (address instance)
    {
        return Create.deploy(
            abi.encodePacked(_ERC1967_BEACON_PROXY_HEAD, beacon, _ERC1967_BEACON_PROXY_TAIL), value
        );
    }

    /// @dev Deploys a deterministic minimal ERC1967 beacon proxy with `salt`.
    function deployDeterministicERC1967BeaconProxy(address beacon, bytes32 salt)
        internal
        returns (address instance)
    {
        instance = deployDeterministicERC1967BeaconProxy(0, beacon, salt);
    }

    /// @dev Deploys a deterministic minimal ERC1967 beacon proxy with `salt`.
    /// Deposits `value` ETH during deployment.
    function deployDeterministicERC1967BeaconProxy(uint256 value, address beacon, bytes32 salt)
        internal
        returns (address instance)
    {
        return Create.deploy2(
            abi.encodePacked(_ERC1967_BEACON_PROXY_HEAD, beacon, _ERC1967_BEACON_PROXY_TAIL),
            salt,
            value
        );
    }

    /// @dev Creates a deterministic minimal ERC1967 beacon proxy with `salt`.
    /// Note: This method is intended for use in ERC4337 factories,
    /// which are expected to NOT revert if the proxy is already deployed.
    function createDeterministicERC1967BeaconProxy(address beacon, bytes32 salt)
        internal
        returns (bool alreadyDeployed, address instance)
    {
        return createDeterministicERC1967BeaconProxy(0, beacon, salt);
    }

    /// @dev Creates a deterministic minimal ERC1967 beacon proxy with `salt`.
    /// Deposits `value` ETH during deployment.
    /// Note: This method is intended for use in ERC4337 factories,
    /// which are expected to NOT revert if the proxy is already deployed.
    function createDeterministicERC1967BeaconProxy(uint256 value, address beacon, bytes32 salt)
        internal
        returns (bool alreadyDeployed, address instance)
    {
        return _createDeterministic(
            abi.encodePacked(_ERC1967_BEACON_PROXY_HEAD, beacon, _ERC1967_BEACON_PROXY_TAIL),
            salt,
            value
        );
    }

    /// @dev Returns the initialization code of the minimal ERC1967 beacon proxy.
    function initCodeERC1967BeaconProxy(address beacon) internal pure returns (bytes memory c) {
        return abi.encodePacked(_ERC1967_BEACON_PROXY_HEAD, beacon, _ERC1967_BEACON_PROXY_TAIL);
    }

    /// @dev Returns the initialization code hash of the minimal ERC1967 beacon proxy.
    function initCodeHashERC1967BeaconProxy(address beacon) internal pure returns (bytes32 hash) {
        return
            keccak256(
                abi.encodePacked(_ERC1967_BEACON_PROXY_HEAD, beacon, _ERC1967_BEACON_PROXY_TAIL)
            );
    }

    /// @dev Returns the address of the ERC1967 beacon proxy, with `salt` by `deployer`.
    function predictDeterministicAddressERC1967BeaconProxy(
        address beacon,
        bytes32 salt,
        address deployer
    ) internal pure returns (address predicted) {
        predicted = predictDeterministicAddress(
            initCodeHashERC1967BeaconProxy(beacon), salt, deployer
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*    ERC1967 BEACON PROXY WITH IMMUTABLE ARGS OPERATIONS     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    /// @dev Deploys a minimal ERC1967 beacon proxy with `args`.
    function deployERC1967BeaconProxy(address beacon, bytes memory args)
        internal
        returns (address instance)
    {
        instance = deployERC1967BeaconProxy(0, beacon, args);
    }

    /// @dev Deploys a minimal ERC1967 beacon proxy with `args`.
    /// Deposits `value` ETH during deployment.
    function deployERC1967BeaconProxy(uint256 value, address beacon, bytes memory args)
        internal
        returns (address instance)
    {
        return Create.deploy(
            abi.encodePacked(
                hex"61",
                _runtimeSize(0x52, args),
                _ERC1967_ARGS_HEAD,
                beacon,
                _ERC1967_BEACON_PROXY_TAIL,
                args
            ),
            value
        );
    }

    /// @dev Deploys a deterministic minimal ERC1967 beacon proxy with `args` and `salt`.
    function deployDeterministicERC1967BeaconProxy(address beacon, bytes memory args, bytes32 salt)
        internal
        returns (address instance)
    {
        instance = deployDeterministicERC1967BeaconProxy(0, beacon, args, salt);
    }

    /// @dev Deploys a deterministic minimal ERC1967 beacon proxy with `args` and `salt`.
    /// Deposits `value` ETH during deployment.
    function deployDeterministicERC1967BeaconProxy(
        uint256 value,
        address beacon,
        bytes memory args,
        bytes32 salt
    ) internal returns (address instance) {
        return Create.deploy2(
            abi.encodePacked(
                hex"61",
                _runtimeSize(0x52, args),
                _ERC1967_ARGS_HEAD,
                beacon,
                _ERC1967_BEACON_PROXY_TAIL,
                args
            ),
            salt,
            value
        );
    }

    /// @dev Creates a deterministic minimal ERC1967 beacon proxy with `args` and `salt`.
    /// Note: This method is intended for use in ERC4337 factories,
    /// which are expected to NOT revert if the proxy is already deployed.
    function createDeterministicERC1967BeaconProxy(address beacon, bytes memory args, bytes32 salt)
        internal
        returns (bool alreadyDeployed, address instance)
    {
        return createDeterministicERC1967BeaconProxy(0, beacon, args, salt);
    }

    /// @dev Creates a deterministic minimal ERC1967 beacon proxy with `args` and `salt`.
    /// Deposits `value` ETH during deployment.
    /// Note: This method is intended for use in ERC4337 factories,
    /// which are expected to NOT revert if the proxy is already deployed.
    function createDeterministicERC1967BeaconProxy(
        uint256 value,
        address beacon,
        bytes memory args,
        bytes32 salt
    ) internal returns (bool alreadyDeployed, address instance) {
        return _createDeterministic(
            abi.encodePacked(
                hex"61",
                _runtimeSize(0x52, args),
                _ERC1967_ARGS_HEAD,
                beacon,
                _ERC1967_BEACON_PROXY_TAIL,
                args
            ),
            salt,
            value
        );
    }

    /// @dev Returns the initialization code of the minimal ERC1967 beacon proxy.
    function initCodeERC1967BeaconProxy(address beacon, bytes memory args)
        internal
        pure
        returns (bytes memory c)
    {
        return abi.encodePacked(
            hex"61",
            _runtimeSize(0x52, args),
            _ERC1967_ARGS_HEAD,
            beacon,
            _ERC1967_BEACON_PROXY_TAIL,
            args
        );
    }

    /// @dev Returns the initialization code hash of the minimal ERC1967 beacon proxy with `args`.
    function initCodeHashERC1967BeaconProxy(address beacon, bytes memory args)
        internal
        pure
        returns (bytes32 hash)
    {
        return keccak256(
            abi.encodePacked(
                hex"61",
                _runtimeSize(0x52, args),
                _ERC1967_ARGS_HEAD,
                beacon,
                _ERC1967_BEACON_PROXY_TAIL,
                args
            )
        );
    }

    /// @dev Returns the address of the ERC1967 beacon proxy with `args`, with `salt` by `deployer`.
    function predictDeterministicAddressERC1967BeaconProxy(
        address beacon,
        bytes memory args,
        bytes32 salt,
        address deployer
    ) internal pure returns (address predicted) {
        predicted = predictDeterministicAddress(
            initCodeHashERC1967BeaconProxy(beacon, args), salt, deployer
        );
    }

    /// @dev Equivalent to `argsOnERC1967BeaconProxy(instance, start, 2 ** 256 - 1)`.
    function argsOnERC1967BeaconProxy(address instance) internal view returns (bytes memory args) {
        return _argsOn(instance, 0x52);
    }

    /// @dev Equivalent to `argsOnERC1967BeaconProxy(instance, start, 2 ** 256 - 1)`.
    function argsOnERC1967BeaconProxy(address instance, uint256 start)
        internal
        view
        returns (bytes memory args)
    {
        return _argsOn(instance, 0x52, start);
    }

    /// @dev Returns a slice of the immutable arguments on `instance` from `start` to `end`.
    /// `start` and `end` will be clamped to the range `[0, args.length]`.
    /// The `instance` MUST be deployed via the ERC1967 beacon proxy with immutable args functions.
    /// Otherwise, the behavior is undefined.
    /// Out-of-gas reverts if `instance` does not have any code.
    function argsOnERC1967BeaconProxy(address instance, uint256 start, uint256 end)
        internal
        view
        returns (bytes memory args)
    {
        return _argsOn(instance, 0x52, start, end);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*              ERC1967I BEACON PROXY OPERATIONS              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    /// @dev Deploys a ERC1967I beacon proxy.
    function deployERC1967IBeaconProxy(address beacon) internal returns (address instance) {
        instance = deployERC1967IBeaconProxy(0, beacon);
    }

    /// @dev Deploys a ERC1967I beacon proxy.
    /// Deposits `value` ETH during deployment.
    function deployERC1967IBeaconProxy(uint256 value, address beacon)
        internal
        returns (address instance)
    {
        return Create.deploy(
            abi.encodePacked(_ERC1967I_BEACON_PROXY_HEAD, beacon, _ERC1967I_BEACON_PROXY_TAIL),
            value
        );
    }

    /// @dev Deploys a deterministic ERC1967I beacon proxy with `salt`.
    function deployDeterministicERC1967IBeaconProxy(address beacon, bytes32 salt)
        internal
        returns (address instance)
    {
        instance = deployDeterministicERC1967IBeaconProxy(0, beacon, salt);
    }

    /// @dev Deploys a deterministic ERC1967I beacon proxy with `salt`.
    /// Deposits `value` ETH during deployment.
    function deployDeterministicERC1967IBeaconProxy(uint256 value, address beacon, bytes32 salt)
        internal
        returns (address instance)
    {
        return Create.deploy2(
            abi.encodePacked(_ERC1967I_BEACON_PROXY_HEAD, beacon, _ERC1967I_BEACON_PROXY_TAIL),
            salt,
            value
        );
    }

    /// @dev Creates a deterministic ERC1967I beacon proxy with `salt`.
    /// Note: This method is intended for use in ERC4337 factories,
    /// which are expected to NOT revert if the proxy is already deployed.
    function createDeterministicERC1967IBeaconProxy(address beacon, bytes32 salt)
        internal
        returns (bool alreadyDeployed, address instance)
    {
        return createDeterministicERC1967IBeaconProxy(0, beacon, salt);
    }

    /// @dev Creates a deterministic ERC1967I beacon proxy with `salt`.
    /// Deposits `value` ETH during deployment.
    /// Note: This method is intended for use in ERC4337 factories,
    /// which are expected to NOT revert if the proxy is already deployed.
    function createDeterministicERC1967IBeaconProxy(uint256 value, address beacon, bytes32 salt)
        internal
        returns (bool alreadyDeployed, address instance)
    {
        return _createDeterministic(
            abi.encodePacked(_ERC1967I_BEACON_PROXY_HEAD, beacon, _ERC1967I_BEACON_PROXY_TAIL),
            salt,
            value
        );
    }

    /// @dev Returns the initialization code of the ERC1967I beacon proxy.
    function initCodeERC1967IBeaconProxy(address beacon) internal pure returns (bytes memory c) {
        return abi.encodePacked(_ERC1967I_BEACON_PROXY_HEAD, beacon, _ERC1967I_BEACON_PROXY_TAIL);
    }

    /// @dev Returns the initialization code hash of the ERC1967I beacon proxy.
    function initCodeHashERC1967IBeaconProxy(address beacon) internal pure returns (bytes32 hash) {
        return keccak256(
            abi.encodePacked(_ERC1967I_BEACON_PROXY_HEAD, beacon, _ERC1967I_BEACON_PROXY_TAIL)
        );
    }

    /// @dev Returns the address of the ERC1967I beacon proxy, with `salt` by `deployer`.
    function predictDeterministicAddressERC1967IBeaconProxy(
        address beacon,
        bytes32 salt,
        address deployer
    ) internal pure returns (address predicted) {
        predicted = predictDeterministicAddress(
            initCodeHashERC1967IBeaconProxy(beacon), salt, deployer
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*    ERC1967I BEACON PROXY WITH IMMUTABLE ARGS OPERATIONS    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    /// @dev Deploys a ERC1967I beacon proxy with `args.
    function deployERC1967IBeaconProxy(address beacon, bytes memory args)
        internal
        returns (address instance)
    {
        instance = deployERC1967IBeaconProxy(0, beacon, args);
    }

    /// @dev Deploys a ERC1967I beacon proxy with `args.
    /// Deposits `value` ETH during deployment.
    function deployERC1967IBeaconProxy(uint256 value, address beacon, bytes memory args)
        internal
        returns (address instance)
    {
        return Create.deploy(
            abi.encodePacked(
                hex"61",
                _runtimeSize(0x57, args),
                _ERC1967_ARGS_HEAD,
                beacon,
                _ERC1967I_BEACON_PROXY_TAIL,
                args
            ),
            value
        );
    }

    /// @dev Deploys a deterministic ERC1967I beacon proxy with `args` and `salt`.
    function deployDeterministicERC1967IBeaconProxy(address beacon, bytes memory args, bytes32 salt)
        internal
        returns (address instance)
    {
        instance = deployDeterministicERC1967IBeaconProxy(0, beacon, args, salt);
    }

    /// @dev Deploys a deterministic ERC1967I beacon proxy with `args` and `salt`.
    /// Deposits `value` ETH during deployment.
    function deployDeterministicERC1967IBeaconProxy(
        uint256 value,
        address beacon,
        bytes memory args,
        bytes32 salt
    ) internal returns (address instance) {
        return Create.deploy2(
            abi.encodePacked(
                hex"61",
                _runtimeSize(0x57, args),
                _ERC1967_ARGS_HEAD,
                beacon,
                _ERC1967I_BEACON_PROXY_TAIL,
                args
            ),
            salt,
            value
        );
    }

    /// @dev Creates a deterministic ERC1967I beacon proxy with `args` and `salt`.
    /// Note: This method is intended for use in ERC4337 factories,
    /// which are expected to NOT revert if the proxy is already deployed.
    function createDeterministicERC1967IBeaconProxy(address beacon, bytes memory args, bytes32 salt)
        internal
        returns (bool alreadyDeployed, address instance)
    {
        return createDeterministicERC1967IBeaconProxy(0, beacon, args, salt);
    }

    /// @dev Creates a deterministic ERC1967I beacon proxy with `args` and `salt`.
    /// Deposits `value` ETH during deployment.
    /// Note: This method is intended for use in ERC4337 factories,
    /// which are expected to NOT revert if the proxy is already deployed.
    function createDeterministicERC1967IBeaconProxy(
        uint256 value,
        address beacon,
        bytes memory args,
        bytes32 salt
    ) internal returns (bool alreadyDeployed, address instance) {
        return _createDeterministic(
            abi.encodePacked(
                hex"61",
                _runtimeSize(0x57, args),
                _ERC1967_ARGS_HEAD,
                beacon,
                _ERC1967I_BEACON_PROXY_TAIL,
                args
            ),
            salt,
            value
        );
    }

    /// @dev Returns the initialization code of the ERC1967I beacon proxy with `args`.
    function initCodeERC1967IBeaconProxy(address beacon, bytes memory args)
        internal
        pure
        returns (bytes memory c)
    {
        return abi.encodePacked(
            hex"61",
            _runtimeSize(0x57, args),
            _ERC1967_ARGS_HEAD,
            beacon,
            _ERC1967I_BEACON_PROXY_TAIL,
            args
        );
    }

    /// @dev Returns the initialization code hash of the ERC1967I beacon proxy with `args`.
    function initCodeHashERC1967IBeaconProxy(address beacon, bytes memory args)
        internal
        pure
        returns (bytes32 hash)
    {
        return keccak256(
            abi.encodePacked(
                hex"61",
                _runtimeSize(0x57, args),
                _ERC1967_ARGS_HEAD,
                beacon,
                _ERC1967I_BEACON_PROXY_TAIL,
                args
            )
        );
    }

    /// @dev Returns the address of the ERC1967I beacon proxy, with  `args` and salt` by `deployer`.
    function predictDeterministicAddressERC1967IBeaconProxy(
        address beacon,
        bytes memory args,
        bytes32 salt,
        address deployer
    ) internal pure returns (address predicted) {
        predicted = predictDeterministicAddress(
            initCodeHashERC1967IBeaconProxy(beacon, args), salt, deployer
        );
    }

    /// @dev Equivalent to `argsOnERC1967IBeaconProxy(instance, start, 2 ** 256 - 1)`.
    function argsOnERC1967IBeaconProxy(address instance) internal view returns (bytes memory args) {
        return _argsOn(instance, 0x57);
    }

    /// @dev Equivalent to `argsOnERC1967IBeaconProxy(instance, start, 2 ** 256 - 1)`.
    function argsOnERC1967IBeaconProxy(address instance, uint256 start)
        internal
        view
        returns (bytes memory args)
    {
        return _argsOn(instance, 0x57, start);
    }

    /// @dev Returns a slice of the immutable arguments on `instance` from `start` to `end`.
    /// `start` and `end` will be clamped to the range `[0, args.length]`.
    /// The `instance` MUST be deployed via the ERC1967I beacon proxy with immutable args functions.
    /// Otherwise, the behavior is undefined.
    /// Out-of-gas reverts if `instance` does not have any code.
    function argsOnERC1967IBeaconProxy(address instance, uint256 start, uint256 end)
        internal
        view
        returns (bytes memory args)
    {
        return _argsOn(instance, 0x57, start, end);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      OTHER OPERATIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    /// @dev Returns `address(0)` if the implementation address cannot be determined.
    function implementationOf(address instance) internal view returns (address result) {
        // The first 0x57 bytes of the code, and zeros past its end.
        uint256 size = instance.code.length;
        bytes memory code = new bytes(0x57);
        Code.copyInto(code, 0, instance, 0, size < 0x57 ? size : 0x57);
        if (
            Bytes.readBytes32(code, 0x2d) != 0
                && (Hash.keccak256Range(code, 0, 0x52) == ERC1967I_CODE_HASH
                    || keccak256(code) == ERC1967I_BEACON_PROXY_CODE_HASH)
        ) {
            // Called with one byte, an ERC1967I proxy answers its implementation. What it
            // answers replaces the start of the code, as the assembly reads it.
            (, bytes memory answer,) =
                Calls.staticCallBounded(instance, gasleft(), Bytes.slice(code, 0, 1), 32);
            Bytes.copyInto(code, 0, answer, 0, answer.length);
            return address(uint160(uint256(Bytes.readBytes32(code, 0))));
        }
        // A minimal proxy holds its implementation at 0x0b, a clone with arguments at 0x0a,
        // and a PUSH0 proxy at 0x09: each is recognized by the hash of its code head with
        // that address zeroed.
        if (_maskedHash(code, 0x0b, 0x2c) == CLONE_CODE_HASH) return _addressAt(code, 0x0b);
        if (_maskedHash(code, 0x0a, 0x2d) == CWIA_CODE_HASH) return _addressAt(code, 0x0a);
        if (_maskedHash(code, 0x09, 0x2d) == PUSH0_CLONE_CODE_HASH) return _addressAt(code, 0x09);
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

    /// @dev Returns the `bytes32` at `offset` in `args`, without any bounds checks.
    /// To load an address, you can use `address(bytes20(argLoad(args, offset)))`.
    function argLoad(bytes memory args, uint256 offset) internal pure returns (bytes32 result) {
        if (offset >= args.length) return 0;
        uint256 available = args.length - offset;
        if (available >= 32) return Bytes.readBytes32(args, offset);
        // The word runs past the end of `args`: the missing bytes read as zeros.
        bytes memory word = new bytes(32);
        Bytes.copyInto(word, 0, args, offset, available);
        return Bytes.readBytes32(word, 0);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PRIVATE HELPERS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The runtime size of a proxy whose code before its arguments is
    /// `base` bytes, which its creation code pushes in two bytes. Arguments that
    /// do not fit fail with `DeploymentFailed()`.
    function _runtimeSize(uint256 base, bytes memory args) private pure returns (uint16) {
        if (args.length > 0xffff - base) revert DeploymentFailed();
        return uint16(base + args.length);
    }

    /// @dev Deploys `c` with `salt` unless its address already has code, and
    /// sends `value` there either way.
    function _createDeterministic(bytes memory c, bytes32 salt, uint256 value)
        private
        returns (bool alreadyDeployed, address instance)
    {
        instance = predictDeterministicAddress(keccak256(c), salt, address(this));
        if (instance.code.length == 0) return (false, Create.deploy2(c, salt, value));
        if (value != 0) {
            (bool sent,,) = Calls.callBounded(instance, value, gasleft(), "", 0);
            if (!sent) revert ETHTransferFailed();
        }
        return (true, instance);
    }

    /// @dev The arguments of the proxy `instance`, whose code before them is
    /// `base` bytes.
    function _argsOn(address instance, uint256 base) private view returns (bytes memory) {
        return Code.read(instance, base, instance.code.length - base);
    }

    /// @dev The arguments of the proxy `instance` from `start`.
    function _argsOn(address instance, uint256 base, uint256 start)
        private
        view
        returns (bytes memory)
    {
        uint256 n = instance.code.length - base;
        if (start >= n) return "";
        return Code.read(instance, base + start, n - start);
    }

    /// @dev The arguments of the proxy `instance` from `start` to `end`, which is
    /// clamped to the arguments and to `0xffff`.
    function _argsOn(address instance, uint256 base, uint256 start, uint256 end)
        private
        view
        returns (bytes memory)
    {
        uint256 n = instance.code.length - base;
        if (end > n) end = n;
        if (end > 0xffff) end = 0xffff;
        if (start >= end) return "";
        return Code.read(instance, base + start, end - start);
    }

    /// @dev The hash of the first `length` bytes of `code` with the 20 bytes at
    /// `at` zeroed.
    function _maskedHash(bytes memory code, uint256 at, uint256 length)
        private
        pure
        returns (bytes32)
    {
        bytes memory head = Bytes.slice(code, 0, length);
        Bytes.fill(head, at, 20, 0x00);
        return keccak256(head);
    }

    /// @dev The address held in the 20 bytes of `code` at `at`.
    function _addressAt(bytes memory code, uint256 at) private pure returns (address) {
        return address(Bytes.readBytes20(code, at));
    }
}
