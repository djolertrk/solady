// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @notice Reentrancy guard mixin.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/ReentrancyGuard.sol)
/// @dev The checked port keeps the guard in upstream's slot and words: the contract's address
/// while a guarded function runs, and the size of the running code after it. Solidity cannot
/// name that slot, nor read the size of the running code, which `address(this).code.length`
/// is not in a constructor or a delegate call, so three trusted helpers read and write the
/// slot and read the code size. Private functions carry the guard's name, so that the mixin
/// combines with other mixins.
/// @custom:solar-safe memory arithmetic
abstract contract ReentrancyGuard {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Unauthorized reentrant call.
    error Reentrancy();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Equivalent to: `uint72(bytes9(keccak256("_REENTRANCY_GUARD_SLOT")))`.
    /// 9 bytes is large enough to avoid collisions with lower slots,
    /// but not too large to result in excessive bytecode bloat.
    uint256 private constant _REENTRANCY_GUARD_SLOT = 0x929eee149b4bd21268;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      REENTRANCY GUARD                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Guards a function from reentrancy.
    modifier nonReentrant() virtual {
        if (_guardSload(_REENTRANCY_GUARD_SLOT) == uint256(uint160(address(this)))) {
            revert Reentrancy();
        }
        _guardSstore(_REENTRANCY_GUARD_SLOT, uint256(uint160(address(this))));
        _;
        _guardSstore(_REENTRANCY_GUARD_SLOT, _guardCodeSize());
    }

    /// @dev Guards a view function from read-only reentrancy.
    modifier nonReadReentrant() virtual {
        if (_guardSload(_REENTRANCY_GUARD_SLOT) == uint256(uint160(address(this)))) {
            revert Reentrancy();
        }
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PRIVATE HELPERS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The word in storage slot `slot`. Solidity cannot name a slot it did not allocate.
    /// @custom:solar-trusted
    function _guardSload(uint256 slot) private view returns (uint256 value) {
        /// @solidity memory-safe-assembly
        assembly {
            value := sload(slot)
        }
    }

    /// @dev Stores `value` in storage slot `slot`.
    /// @custom:solar-trusted
    function _guardSstore(uint256 slot, uint256 value) private {
        /// @solidity memory-safe-assembly
        assembly {
            sstore(slot, value)
        }
    }

    /// @dev The size of the code that is running. Solidity has no spelling for it:
    /// `address(this).code.length` is the size of the code at this address.
    /// @custom:solar-trusted
    function _guardCodeSize() private pure returns (uint256 size) {
        /// @solidity memory-safe-assembly
        assembly {
            size := codesize()
        }
    }
}
