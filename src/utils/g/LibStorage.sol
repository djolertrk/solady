// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// This file is auto-generated.

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*                          STRUCTS                           */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

/// @dev Generates a storage slot that can be invalidated.
struct Bump {
    uint256 _current;
}

/// @dev Pointer struct to a `uint256` in storage.
/// We have opted for a `uint256` as the inner type,
/// as it requires less casting to get / set specific bits.
struct Ref {
    uint256 value;
}

using LibStorage for Bump global;
using LibStorage for Ref global;

/// @notice Library for basic storage operations.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/g/LibStorage.sol)
/// @dev The checked port hashes a bump's slot, the seed and the low 216 bits of its counter
/// with `abi.encodePacked`, the same 63 bytes the assembly hashes. Trusted helpers read a
/// bump's slot number and make `Bump` and `Ref` storage pointers from slot numbers, which
/// Solidity cannot spell, and wrap the counter's increment at `2**256` as upstream does.
/// @custom:solar-safe memory arithmetic
library LibStorage {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The storage slot seed for calculating a bumped storage slot.
    /// `bytes4(keccak256("_BUMPED_STORAGE_REF_SLOT_SEED"))`.
    uint256 private constant _BUMPED_STORAGE_REF_SLOT_SEED = 0xd4203f8b;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         OPERATIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns the current storage slot pointed by the bump.
    /// Use inline-assembly to cast the result to a desired custom data type storage pointer.
    function slot(Bump storage b) internal view returns (bytes32 result) {
        result = keccak256(
            abi.encodePacked(_slot(b), uint32(_BUMPED_STORAGE_REF_SLOT_SEED), uint216(b._current))
        );
    }

    /// @dev Makes the bump point to a whole new storage slot.
    function invalidate(Bump storage b) internal {
        b._current = _add(b._current, 1);
    }

    /// @dev Returns a bump at the storage slot.
    function bump(bytes32 sSlot) internal pure returns (Bump storage $) {
        $ = _bumpAt(uint256(sSlot));
    }

    /// @dev Returns a bump at the storage slot.
    function bump(uint256 sSlot) internal pure returns (Bump storage $) {
        $ = _bumpAt(sSlot);
    }

    /// @dev Returns a pointer to a `uint256` in storage.
    function ref(bytes32 sSlot) internal pure returns (Ref storage $) {
        $ = _refAt(uint256(sSlot));
    }

    /// @dev Returns a pointer to a `uint256` in storage.
    function ref(uint256 sSlot) internal pure returns (Ref storage $) {
        $ = _refAt(sSlot);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PRIVATE HELPERS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The storage slot of `b`.
    /// Solidity does not expose a storage pointer's slot number.
    /// @custom:solar-trusted
    function _slot(Bump storage b) private pure returns (uint256 s) {
        /// @solidity memory-safe-assembly
        assembly {
            s := b.slot
        }
    }

    /// @dev The bump at storage slot `s`.
    /// Solidity cannot make a storage pointer from a slot number.
    /// @custom:solar-trusted
    function _bumpAt(uint256 s) private pure returns (Bump storage $) {
        /// @solidity memory-safe-assembly
        assembly {
            $.slot := s
        }
    }

    /// @dev The `uint256` pointer at storage slot `s`.
    /// Solidity cannot make a storage pointer from a slot number.
    /// @custom:solar-trusted
    function _refAt(uint256 s) private pure returns (Ref storage $) {
        /// @solidity memory-safe-assembly
        assembly {
            $.slot := s
        }
    }

    /// @dev `a + b` modulo `2**256`.
    /// Checked arithmetic reverts where upstream's increment wraps.
    /// @custom:solar-trusted
    function _add(uint256 a, uint256 b) private pure returns (uint256 c) {
        unchecked {
            c = a + b;
        }
    }
}
