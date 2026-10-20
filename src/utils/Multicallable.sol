// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @notice Contract that enables a single call to call multiple methods on itself.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/Multicallable.sol)
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/utils/Multicallable.sol)
///
/// WARNING:
/// This implementation is NOT to be used with ERC2771 out-of-the-box.
/// https://blog.openzeppelin.com/arbitrary-address-spoofing-vulnerability-erc2771context-multicall-public-disclosure
/// This also applies to potentially other ERCs / patterns appending to the back of calldata.
///
/// We do NOT have a check for ERC2771, as we do not inherit from OpenZeppelin's context.
/// Moreover, it is infeasible and inefficient for us to add checks and mitigations
/// for all possible ERC / patterns appending to the back of calldata.
///
/// We would highly recommend using an alternative pattern such as
/// https://github.com/Vectorized/multicaller
/// which is more flexible, futureproof, and safer by default.
///
/// The checked port makes each `delegatecall` in Solidity and bubbles up a revert with the
/// trusted `_multicallableRevertRaw`. `_multicall` collects the results and `abi.encode`s
/// them, which is the encoding the assembly builds, and packs the encoding's address and
/// length into `results` as the assembly does. Solidity cannot hold an address in a word or
/// follow one, so the trusted `_multicallableAddr` takes the address,
/// `_multicallableMload` and `_multicallableBytesAt` follow it to give the decoded results
/// as views into the encoding, as upstream does, and `_multicallableReturn` returns it.
/// @custom:solar-safe memory arithmetic
abstract contract Multicallable {
    /// @dev Apply `delegatecall` with the current contract to each calldata in `data`,
    /// and store the `abi.encode` formatted results of each `delegatecall` into `results`.
    /// If any of the `delegatecall`s reverts, the entire context is reverted,
    /// and the error is bubbled up.
    ///
    /// By default, this function directly returns the results and terminates the call context.
    /// If you need to add before and after actions to the multicall, please override this function.
    function multicall(bytes[] calldata data) public payable virtual returns (bytes[] memory) {
        // Revert if `msg.value` is non-zero by default to guard against double-spending.
        // (See: https://www.paradigm.xyz/2021/08/two-rights-might-make-a-wrong)
        //
        // If you really need to pass in a `msg.value`, then you will have to
        // override this function and add in any relevant before and after checks.
        if (msg.value != 0) revert();
        // `_multicallDirectReturn` returns the results directly and terminates the call context.
        _multicallDirectReturn(_multicall(data));
    }

    /// @dev The inner logic of `multicall`.
    /// This function is included so that you can override `multicall`
    /// to add before and after actions, and use the `_multicallDirectReturn` function.
    function _multicall(bytes[] calldata data) internal virtual returns (bytes32 results) {
        bytes[] memory returned = new bytes[](data.length);
        for (uint256 i; i < data.length; ++i) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);
            // Bubble up the revert if the delegatecall reverts.
            if (!success) _multicallableRevertRaw(result);
            returned[i] = result;
        }
        bytes memory encoded = abi.encode(returned);
        // Pack the bytes length into `results`, over the address of the encoding.
        results = bytes32(encoded.length << 64 | (_multicallableAddr(encoded) + 0x20));
    }

    /// @dev Decodes the `results` into an array of bytes.
    /// This can be useful if you need to access the results or re-encode it.
    function _multicallResultsToBytesArray(bytes32 results)
        internal
        pure
        virtual
        returns (bytes[] memory decoded)
    {
        uint256 c = uint64(uint256(results)); // Extract the offset.
        uint256 s = c + 0x40; // Start of elements in `results`.
        decoded = new bytes[](_multicallableMload(c + 0x20));
        for (uint256 i; i < decoded.length; ++i) {
            decoded[i] = _multicallableBytesAt(_multicallableMload(s + i * 0x20) + s);
        }
    }

    /// @dev Directly returns the `results` and terminates the current call context.
    /// `results` must be from `_multicall`, else behavior is undefined.
    function _multicallDirectReturn(bytes32 results) internal pure virtual {
        _multicallableReturn(uint64(uint256(results)), uint256(results) >> 64);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PRIVATE HELPERS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Reverts the current call with exactly `data`. Solidity can only revert with an
    /// error or a reason string.
    /// @custom:solar-trusted
    function _multicallableRevertRaw(bytes memory data) private pure {
        /// @solidity memory-safe-assembly
        assembly {
            revert(add(data, 0x20), mload(data))
        }
    }

    /// @dev The address of `b`. Solidity cannot convert a reference to a number.
    /// @custom:solar-trusted
    function _multicallableAddr(bytes memory b) private pure returns (uint256 result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := b
        }
    }

    /// @dev The word at address `a`. Solidity cannot read memory at an address.
    /// @custom:solar-trusted
    function _multicallableMload(uint256 a) private pure returns (uint256 result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(a)
        }
    }

    /// @dev The bytes at address `a`, a result inside `results`. Solidity cannot convert a
    /// number to a reference.
    /// @custom:solar-trusted
    function _multicallableBytesAt(uint256 a) private pure returns (bytes memory result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := a
        }
    }

    /// @dev Ends the call, returning the `size` bytes of memory at `offset`. Solidity can only
    /// return the encoding of the function's return values.
    /// @custom:solar-trusted
    function _multicallableReturn(uint256 offset, uint256 size) private pure {
        /// @solidity memory-safe-assembly
        assembly {
            return(offset, size)
        }
    }
}
