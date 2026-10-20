// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @notice Enumerable multiroles authorization mixin.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/auth/EnumerableRoles.sol)
///
/// @dev Note:
/// This implementation is agnostic to the Ownable that the contract inherits from.
/// It performs a self-staticcall to the `owner()` function to determine the owner.
/// This is useful for situations where the contract inherits from
/// OpenZeppelin's Ownable, such as in LayerZero's OApp contracts.
///
/// This implementation performs a self-staticcall to `MAX_ROLE()` to determine
/// the maximum role that can be set/unset. If the inheriting contract does not
/// have `MAX_ROLE()`, then any role can be set/unset.
///
/// This implementation allows for any uint256 role,
/// it does NOT take in a bitmask of roles.
/// This is to accommodate teams that are allergic to bitwise flags.
///
/// By default, the `owner()` is the only account that is authorized to set roles.
/// This behavior can be changed via overrides.
///
/// This implementation is compatible with any Ownable.
/// This implementation is NOT compatible with OwnableRoles.
///
/// The checked port keeps the holders in the assembly's slots and words, so it is
/// storage-compatible with it, and leaves the stale words a removal leaves there. It
/// derives the slots in Solidity as `abi.encodePacked` hashes; Solidity cannot name
/// them, so two trusted helpers read and write a slot, and a third adds an index to
/// the root slot with wrap-around, as the assembly does. The self-staticcalls to
/// `owner()` and `MAX_ROLE()` are plain low-level calls whose first returned word is
/// compared, the roles in `encodedRoles` are read a word at a time, and the event and
/// errors are ordinary emits and reverts. The private helpers carry the contract's
/// name, as upstream's do, so that it still combines with Ownable and TimedRoles.
/// @custom:solar-safe memory arithmetic
abstract contract EnumerableRoles {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The status of `role` for `holder` has been set to `active`.
    event RoleSet(address indexed holder, uint256 indexed role, bool indexed active);

    /// @dev `keccak256(bytes("RoleSet(address,uint256,bool)"))`.
    uint256 private constant _ROLE_SET_EVENT_SIGNATURE =
        0xaddc47d7e02c95c00ec667676636d772a589ffbf0663cfd7cd4dd3d4758201b8;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The index is out of bounds of the role holders array.
    error RoleHoldersIndexOutOfBounds();

    /// @dev Cannot set the role of the zero address.
    error RoleHolderIsZeroAddress();

    /// @dev The role has exceeded the maximum role.
    error InvalidRole();

    /// @dev Unauthorized to perform the action.
    error EnumerableRolesUnauthorized();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The storage layout of the holders enumerable mapping is given by:
    /// ```
    ///     mstore(0x18, holder)
    ///     mstore(0x04, _ENUMERABLE_ROLES_SLOT_SEED)
    ///     mstore(0x00, role)
    ///     let rootSlot := keccak256(0x00, 0x24)
    ///     let positionSlot := keccak256(0x00, 0x38)
    ///     let holderSlot := add(rootSlot, sload(positionSlot))
    ///     let holderInStorage := shr(96, sload(holderSlot))
    ///     let length := shr(160, shl(160, sload(rootSlot)))
    /// ```
    uint256 private constant _ENUMERABLE_ROLES_SLOT_SEED = 0xee9853bb;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  PUBLIC UPDATE FUNCTIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Sets the status of `role` of `holder` to `active`.
    function setRole(address holder, uint256 role, bool active) public payable virtual {
        _authorizeSetRole(holder, role, active);
        _setRole(holder, role, active);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   PUBLIC READ FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns if `holder` has active `role`.
    function hasRole(address holder, uint256 role) public view virtual returns (bool result) {
        result = _enumerableRolesSload(_enumerableRolesPositionSlot(role, holder)) != 0;
    }

    /// @dev Returns an array of the holders of `role`.
    function roleHolders(uint256 role) public view virtual returns (address[] memory result) {
        uint256 rootSlot = _enumerableRolesRootSlot(role);
        uint256 rootPacked = _enumerableRolesSload(rootSlot);
        uint256 n = uint96(rootPacked);
        result = new address[](n);
        if (n != 0) {
            // The first holder shares the root slot with the length.
            result[0] = address(uint160(rootPacked >> 96));
            for (uint256 i = 1; i < n; ++i) {
                result[i] =
                    address(uint160(_enumerableRolesSload(_enumerableRolesAdd(rootSlot, i)) >> 96));
            }
        }
    }

    /// @dev Returns the total number of holders of `role`.
    function roleHolderCount(uint256 role) public view virtual returns (uint256 result) {
        result = uint96(_enumerableRolesSload(_enumerableRolesRootSlot(role)));
    }

    /// @dev Returns the holder of `role` at the index `i`.
    function roleHolderAt(uint256 role, uint256 i) public view virtual returns (address result) {
        uint256 rootSlot = _enumerableRolesRootSlot(role);
        uint256 rootPacked = _enumerableRolesSload(rootSlot);
        if (i >= uint96(rootPacked)) revert RoleHoldersIndexOutOfBounds();
        result = address(uint160(rootPacked >> 96));
        if (i != 0) {
            uint256 holderSlot = _enumerableRolesAdd(rootSlot, i);
            result = address(uint160(_enumerableRolesSload(holderSlot) >> 96));
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Set the role for holder directly without authorization guard.
    function _setRole(address holder, uint256 role, bool active) internal virtual {
        _validateRole(role);
        if (holder == address(0)) revert RoleHolderIsZeroAddress();
        uint256 rootSlot = _enumerableRolesRootSlot(role);
        uint256 rootPacked = _enumerableRolesSload(rootSlot);
        uint256 n = uint96(rootPacked);
        uint256 positionSlot = _enumerableRolesPositionSlot(role, holder);
        uint256 position = _enumerableRolesSload(positionSlot);
        if (!active) {
            if (position != 0) {
                uint256 nSub = n - 1;
                // The root's holder word, which the removal of the last holder leaves.
                uint256 rootHolder = rootPacked >> 96 << 96;
                if (position - 1 != nSub) {
                    // Move the last holder into the removed holder's place.
                    uint256 lastHolder =
                        _enumerableRolesSload(_enumerableRolesAdd(rootSlot, nSub)) >> 96;
                    if (position == 1) {
                        rootHolder = lastHolder << 96;
                    } else {
                        _enumerableRolesSstore(
                            _enumerableRolesAdd(rootSlot, position - 1), lastHolder << 96
                        );
                    }
                    _enumerableRolesSstore(_enumerableRolesAdd(rootSlot, nSub), 0);
                    _enumerableRolesSstore(
                        _enumerableRolesPositionSlot(role, address(uint160(lastHolder))), position
                    );
                }
                _enumerableRolesSstore(rootSlot, rootHolder | nSub);
                _enumerableRolesSstore(positionSlot, 0);
            }
        } else if (position == 0) {
            uint256 holderWord = uint256(uint160(holder)) << 96;
            if (n == 0) {
                // The first holder replaces whatever a removal left in the root.
                _enumerableRolesSstore(rootSlot, holderWord | 1);
            } else {
                _enumerableRolesSstore(_enumerableRolesAdd(rootSlot, n), holderWord);
                _enumerableRolesSstore(rootSlot, rootPacked + 1);
            }
            _enumerableRolesSstore(positionSlot, n + 1);
        }
        emit RoleSet(holder, role, active);
    }

    /// @dev Requires the role is not greater than `MAX_ROLE()`.
    /// If `MAX_ROLE()` is not implemented, this is an no-op.
    function _validateRole(uint256 role) internal view virtual {
        (bool success, bytes memory answer) =
            address(this).staticcall(abi.encodeWithSelector(0xd24f19d5)); // `MAX_ROLE()`.
        if (success && answer.length >= 0x20) {
            if (role > uint256(_enumerableRolesReadBytes32(answer, 0))) revert InvalidRole();
        }
    }

    /// @dev Checks that the caller is authorized to set the role.
    function _authorizeSetRole(address holder, uint256 role, bool active) internal virtual {
        if (!_enumerableRolesSenderIsContractOwner()) _revertEnumerableRolesUnauthorized();
        // Silence compiler warning on unused variables.
        (holder, role, active) = (holder, role, active);
    }

    /// @dev Returns if `holder` has any roles in `encodedRoles`.
    /// `encodedRoles` is `abi.encode(SAMPLE_ROLE_0, SAMPLE_ROLE_1, ...)`.
    function _hasAnyRoles(address holder, bytes memory encodedRoles)
        internal
        view
        virtual
        returns (bool result)
    {
        // Each whole word is a role; the bytes past the last whole word are ignored.
        uint256 n = encodedRoles.length >> 5;
        for (uint256 i; i < n; ++i) {
            uint256 role = uint256(_enumerableRolesReadBytes32(encodedRoles, i << 5));
            if (_enumerableRolesSload(_enumerableRolesPositionSlot(role, holder)) != 0) {
                return true;
            }
        }
    }

    /// @dev Reverts if `msg.sender` does not have `role`.
    function _checkRole(uint256 role) internal view virtual {
        if (!hasRole(msg.sender, role)) _revertEnumerableRolesUnauthorized();
    }

    /// @dev Reverts if `msg.sender` does not have any role in `encodedRoles`.
    function _checkRoles(bytes memory encodedRoles) internal view virtual {
        if (!_hasAnyRoles(msg.sender, encodedRoles)) _revertEnumerableRolesUnauthorized();
    }

    /// @dev Reverts if `msg.sender` is not the contract owner and does not have `role`.
    function _checkOwnerOrRole(uint256 role) internal view virtual {
        if (!_enumerableRolesSenderIsContractOwner()) _checkRole(role);
    }

    /// @dev Reverts if `msg.sender` is not the contract owner and
    /// does not have any role in `encodedRoles`.
    function _checkOwnerOrRoles(bytes memory encodedRoles) internal view virtual {
        if (!_enumerableRolesSenderIsContractOwner()) _checkRoles(encodedRoles);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MODIFIERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Marks a function as only callable by an account with `role`.
    modifier onlyRole(uint256 role) virtual {
        _checkRole(role);
        _;
    }

    /// @dev Marks a function as only callable by an account with any role in `encodedRoles`.
    /// `encodedRoles` is `abi.encode(SAMPLE_ROLE_0, SAMPLE_ROLE_1, ...)`.
    modifier onlyRoles(bytes memory encodedRoles) virtual {
        _checkRoles(encodedRoles);
        _;
    }

    /// @dev Marks a function as only callable by the owner or by an account with `role`.
    modifier onlyOwnerOrRole(uint256 role) virtual {
        _checkOwnerOrRole(role);
        _;
    }

    /// @dev Marks a function as only callable by the owner or
    /// by an account with any role in `encodedRoles`.
    /// Checks for ownership first, then checks for roles.
    /// `encodedRoles` is `abi.encode(SAMPLE_ROLE_0, SAMPLE_ROLE_1, ...)`.
    modifier onlyOwnerOrRoles(bytes memory encodedRoles) virtual {
        _checkOwnerOrRoles(encodedRoles);
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PRIVATE HELPERS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns if the `msg.sender` is equal to `owner()` on this contract.
    /// If the contract does not have `owner()` implemented, returns false.
    function _enumerableRolesSenderIsContractOwner() private view returns (bool result) {
        (bool success, bytes memory answer) =
            address(this).staticcall(abi.encodeWithSelector(0x8da5cb5b)); // `owner()`.
        result = success && answer.length >= 0x20
            && uint256(_enumerableRolesReadBytes32(answer, 0)) == uint256(uint160(msg.sender));
    }

    /// @dev Reverts with `EnumerableRolesUnauthorized()`.
    /// @custom:solar-terminates
    function _revertEnumerableRolesUnauthorized() private pure {
        revert EnumerableRolesUnauthorized();
    }

    /// @dev The root slot of `role`: the hash of `role` and the seed's four bytes. It holds
    /// the first holder above the 96-bit length; the holder at index `i > 0` is `i` slots on.
    /// @custom:solar-inline
    function _enumerableRolesRootSlot(uint256 role) private pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(role, uint32(_ENUMERABLE_ROLES_SLOT_SEED))));
    }

    /// @dev The position slot of `holder` for `role`, which holds its index plus one.
    /// @custom:solar-inline
    function _enumerableRolesPositionSlot(uint256 role, address holder)
        private
        pure
        returns (uint256)
    {
        // The seed's four bytes and the holder's twenty, packed as one item.
        uint256 seedAndHolder = _ENUMERABLE_ROLES_SLOT_SEED << 160 | uint160(holder);
        return uint256(keccak256(abi.encodePacked(role, uint192(seedAndHolder))));
    }

    /// @dev The 32 bytes of `b` at `offset`.
    /// @custom:solar-inline
    function _enumerableRolesReadBytes32(bytes memory b, uint256 offset)
        private
        pure
        returns (bytes32 result)
    {
        for (uint256 k; k < 32; ++k) {
            result |= bytes32(b[offset + k]) >> (8 * k);
        }
    }

    /// @dev Returns the word in storage slot `slot`. Solidity cannot name a slot it did not
    /// allocate.
    /// @custom:solar-trusted
    function _enumerableRolesSload(uint256 slot) private view returns (uint256 value) {
        /// @solidity memory-safe-assembly
        assembly {
            value := sload(slot)
        }
    }

    /// @dev Stores `value` in storage slot `slot`. Solidity cannot name a slot it did not
    /// allocate.
    /// @custom:solar-trusted
    function _enumerableRolesSstore(uint256 slot, uint256 value) private {
        /// @solidity memory-safe-assembly
        assembly {
            sstore(slot, value)
        }
    }

    /// @dev `a + b` modulo `2**256`, as the assembly adds an index to a slot; checked
    /// arithmetic would revert where it wraps.
    /// @custom:solar-trusted
    function _enumerableRolesAdd(uint256 a, uint256 b) private pure returns (uint256 c) {
        unchecked {
            c = a + b;
        }
    }
}
