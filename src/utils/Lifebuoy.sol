// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @notice Class that allows for rescue of ETH, ERC20, ERC721 tokens.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/Lifebuoy.sol)
///
/// @dev This contract is created to mitigate the following disasters:
/// - Careless user sends tokens to the wrong chain or wrong contract.
/// - Careless dev deploys a contract without a withdraw function in attempt to rescue
///   careless user's tokens, due to deployment nonce mismatch caused by
///   script misfire / misconfiguration.
/// - Careless dev forgets to add a withdraw function to a NFT sale contract.
///
/// Note: if you are deploying via a untrusted `tx.origin`,
/// you MUST override `_lifebuoyDefaultDeployer` to return a trusted address.
///
/// For best safety:
/// - For non-escrow contracts, inherit Lifebuoy as much as possible,
///   and leave it unlocked.
/// - For escrow contracts, lock access as tight as possible,
///   as soon as possible. Or simply don't inherit Lifebuoy.
/// Escrow: Your contract is designed to hold ETH, ERC20s, ERC721s
/// (e.g. liquidity pools).
///
/// All rescue and rescue authorization functions require either:
/// - Caller is the deployer
///   AND the contract is not a proxy
///   AND `rescueLocked() & _LIFEBUOY_DEPLOYER_ACCESS_LOCK == 0`.
/// - Caller is `owner()`
///   AND `rescueLocked() & _LIFEBUOY_OWNER_ACCESS_LOCK == 0`.
///
/// The choice of using bit flags to represent locked statuses is for
/// efficiency, flexibility, convenience.
///
/// This contract is optimized with a priority on minimal bytecode size,
/// as the methods are not intended to be called often.
///
/// The checked port keeps the lock flags in upstream's slot, which Solidity cannot name, so
/// the trusted `_lifebuoySload` and `_lifebuoySstore` read and write it. The deployer hash is
/// `keccak256(abi.encode(address(this), deployer))`, and the rescues and the `owner()` query
/// are plain calls with the calldata, value and gas the assembly passes; the ERC1155 rescue
/// appends `data` unpadded, as the assembly does.
/// @custom:solar-safe memory arithmetic
contract Lifebuoy {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The caller is not authorized to rescue or lock the rescue function.
    error RescueUnauthorizedOrLocked();

    /// @dev The rescue operation has failed due to a failed transfer.
    error RescueTransferFailed();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    LOCK FLAGS CONSTANTS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // These flags are kept internal to avoid bloating up the function dispatch.
    // You can just copy paste this into your own code.

    /// @dev Flag to denote that the deployer's access is locked. (1)
    uint256 internal constant _LIFEBUOY_DEPLOYER_ACCESS_LOCK = 1 << 0;

    /// @dev Flag to denote that the `owner()`'s access is locked. (2)
    uint256 internal constant _LIFEBUOY_OWNER_ACCESS_LOCK = 1 << 1;

    /// @dev Flag to denote that the `lockRescue` function is locked. (4)
    uint256 internal constant _LIFEBUOY_LOCK_RESCUE_LOCK = 1 << 2;

    /// @dev Flag to denote that the `rescueETH` function is locked. (8)
    uint256 internal constant _LIFEBUOY_RESCUE_ETH_LOCK = 1 << 3;

    /// @dev Flag to denote that the `rescueERC20` function is locked. (16)
    uint256 internal constant _LIFEBUOY_RESCUE_ERC20_LOCK = 1 << 4;

    /// @dev Flag to denote that the `rescueERC721` function is locked. (32)
    uint256 internal constant _LIFEBUOY_RESCUE_ERC721_LOCK = 1 << 5;

    /// @dev Flag to denote that the `rescueERC1155` function is locked. (64)
    uint256 internal constant _LIFEBUOY_RESCUE_ERC1155_LOCK = 1 << 6;

    /// @dev Flag to denote that the `rescueERC6909` function is locked. (128)
    uint256 internal constant _LIFEBUOY_RESCUE_ERC6909_LOCK = 1 << 7;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         IMMUTABLES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev For checking that the caller is the deployer and
    /// that the context is not a delegatecall
    /// (so that the implementation deployer cannot drain proxies).
    bytes32 internal immutable _lifebuoyDeployerHash;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The rescue locked flags slot is given by:
    /// `bytes32(~uint256(uint32(bytes4(keccak256("_RESCUE_LOCKED_FLAGS_SLOT_NOT")))))`.
    /// It is intentionally chosen to be a high value
    /// to avoid collision with lower slots.
    /// The choice of manual storage layout is to enable compatibility
    /// with both regular and upgradeable contracts.
    bytes32 internal constant _RESCUE_LOCKED_FLAGS_SLOT =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffb8e2915b;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    constructor() payable {
        uint256 deployer = uint160(_lifebuoyDefaultDeployer());
        _lifebuoyDeployerHash = keccak256(abi.encode(address(this), deployer));
    }

    /// @dev Returns `tx.origin` by default. Override to return another address if needed.
    ///
    /// Note: If you are deploying via a untrusted `tx.origin` (e.g. ERC4337 bundler)
    /// you MUST override this function to return a trusted address.
    function _lifebuoyDefaultDeployer() internal view virtual returns (address) {
        // I know about EIP7645, and I will stop it if it gets traction.
        // Worse case, I will add an `ecrecover` method. But not today.
        return tx.origin;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     RESCUE OPERATIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Sends `amount` (in wei) ETH from the current contract to `to`.
    /// Reverts upon failure.
    function rescueETH(address to, uint256 amount)
        public
        payable
        virtual
        onlyRescuer(_LIFEBUOY_RESCUE_ETH_LOCK)
    {
        (bool success,) = to.call{value: amount}("");
        if (!success) revert RescueTransferFailed();
    }

    /// @dev Sends `amount` of ERC20 `token` from the current contract to `to`.
    /// Does not check for existence of token or return data. Reverts upon failure.
    function rescueERC20(address token, address to, uint256 amount)
        public
        payable
        virtual
        onlyRescuer(_LIFEBUOY_RESCUE_ERC20_LOCK)
    {
        // `transfer(address,uint256)`.
        (bool success,) =
            token.call{value: msg.value}(abi.encodeWithSelector(0xa9059cbb, to, amount));
        if (!success) revert RescueTransferFailed();
    }

    /// @dev Sends `id` of ERC721 `token` from the current contract to `to`.
    /// Does not check for existence of token or return data. Reverts upon failure.
    function rescueERC721(address token, address to, uint256 id)
        public
        payable
        virtual
        onlyRescuer(_LIFEBUOY_RESCUE_ERC721_LOCK)
    {
        // `transferFrom(address,address,uint256)`.
        (bool success,) =
            token.call{value: msg.value}(abi.encodeWithSelector(0x23b872dd, address(this), to, id));
        if (!success) revert RescueTransferFailed();
    }

    /// @dev Sends `amount` of `id` of ERC1155 `token` from the current contract to `to`.
    /// Does not check for existence of token or return data. Reverts upon failure.
    function rescueERC1155(
        address token,
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) public payable virtual onlyRescuer(_LIFEBUOY_RESCUE_ERC1155_LOCK) {
        // `safeTransferFrom(address,address,uint256,uint256,bytes)`, with `data` unpadded.
        (bool success,) = token.call{value: msg.value}(
            abi.encodePacked(
                bytes4(0xf242432a),
                abi.encode(address(this), to, id, amount, 0xa0, data.length),
                data
            )
        );
        if (!success) revert RescueTransferFailed();
    }

    /// @dev Sends `amount` of `id` of ERC6909 `token` from the current contract to `to`.
    /// Does not check for existence of token or return data. Reverts upon failure.
    function rescueERC6909(address token, address to, uint256 id, uint256 amount)
        public
        payable
        virtual
        onlyRescuer(_LIFEBUOY_RESCUE_ERC6909_LOCK)
    {
        // `transfer(address,uint256,uint256)`.
        (bool success,) =
            token.call{value: msg.value}(abi.encodeWithSelector(0x095bcdb6, to, id, amount));
        if (!success) revert RescueTransferFailed();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*              RESCUE AUTHORIZATION OPERATIONS               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns the flags denoting whether access to rescue functions
    /// (including `lockRescue`) is locked.
    function rescueLocked() public view virtual returns (uint256 locks) {
        locks = _lifebuoySload(uint256(_RESCUE_LOCKED_FLAGS_SLOT));
    }

    /// @dev Locks (i.e. permanently removes) access to rescue functions (including `lockRescue`).
    function lockRescue(uint256 locksToSet)
        public
        payable
        virtual
        onlyRescuer(_LIFEBUOY_LOCK_RESCUE_LOCK)
    {
        _lockRescue(locksToSet);
    }

    /// @dev Internal function to set the lock flags without going through access control.
    function _lockRescue(uint256 locksToSet) internal virtual {
        uint256 s = uint256(_RESCUE_LOCKED_FLAGS_SLOT);
        _lifebuoySstore(s, _lifebuoySload(s) | locksToSet);
    }

    /// @dev Requires that the rescue function being guarded is:
    /// 1. Not locked, AND
    /// 2. Called by either:
    ///   (a) The `owner()`, OR
    ///   (b) The deployer (if not via a delegate call and deployer is an EOA).
    function _checkRescuer(uint256 modeLock) internal view virtual {
        uint256 locks = rescueLocked();
        bytes32 h = _lifebuoyDeployerHash;
        // If the `modeLock` flag is true, set all bits in `locks` to true.
        if (modeLock & locks != 0) locks = type(uint256).max;
        // Caller is the deployer
        // AND the contract is not a proxy
        // AND `locks & _LIFEBUOY_DEPLOYER_ACCESS_LOCK` is false.
        if (locks & _LIFEBUOY_DEPLOYER_ACCESS_LOCK == 0) {
            if (keccak256(abi.encode(address(this), msg.sender)) == h) return;
        }
        // If the caller is `owner()`
        // AND `locks & _LIFEBUOY_OWNER_ACCESS_LOCK` is false.
        // The query is made whether or not the owner's access is locked.
        (bool success, bytes memory result) =
            address(this).staticcall(abi.encodeWithSelector(0x8da5cb5b)); // `owner()`.
        if (success && locks & _LIFEBUOY_OWNER_ACCESS_LOCK == 0 && result.length > 0x1f) {
            if (abi.decode(result, (uint256)) == uint160(msg.sender)) return;
        }
        revert RescueUnauthorizedOrLocked();
    }

    /// @dev Modifier that calls `_checkRescuer()` at the start of the function.
    modifier onlyRescuer(uint256 modeLock) virtual {
        _checkRescuer(modeLock);
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PRIVATE HELPERS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns the word in storage slot `slot`. Solidity cannot name a slot it did not
    /// allocate.
    /// @custom:solar-trusted
    function _lifebuoySload(uint256 slot) private view returns (uint256 value) {
        /// @solidity memory-safe-assembly
        assembly {
            value := sload(slot)
        }
    }

    /// @dev Stores `value` in storage slot `slot`. Solidity cannot name a slot it did not
    /// allocate.
    /// @custom:solar-trusted
    function _lifebuoySstore(uint256 slot, uint256 value) private {
        /// @solidity memory-safe-assembly
        assembly {
            sstore(slot, value)
        }
    }
}
