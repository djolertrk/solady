// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Bytes} from "solar:core/v1/Bytes.sol";
import {Hash} from "solar:core/v1/Hash.sol";

/// @notice Checked Solidity hashing without assembly.
/// @dev The upstream library exists because `abi.encode` allocates before
/// hashing. Here every fixed-arity hash is the plain `keccak256(abi.encode(...))`
/// the source would write anyway, and the compiler decides where the words
/// live: one or two words go to scratch space, more are built at the free
/// pointer without moving it.
///
/// `free` cannot rewind the free-memory pointer from checked Solidity, so it
/// is a no-op that keeps the API shape; a buffer is reclaimed by going out of
/// scope, not by calling it.
/// The 13- and 14-word overloads are left out: solc's legacy pipeline cannot
/// compile a wrapper that takes them, so they cannot be measured side by side.
library EfficientHashLib {
    /// @dev `keccak256` of the word.
    function hash(bytes32 v0) internal pure returns (bytes32) {
        return keccak256(abi.encode(v0));
    }
    /// @dev `keccak256` of the word.
    function hash(uint256 v0) internal pure returns (bytes32) {
        return keccak256(abi.encode(v0));
    }
    /// @dev `keccak256` of the 2 words.
    function hash(
        bytes32 v0, bytes32 v1
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(v0, v1));
    }
    /// @dev `keccak256` of the 2 words.
    function hash(
        uint256 v0, uint256 v1
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(v0, v1));
    }
    /// @dev `keccak256` of the 3 words.
    function hash(
        bytes32 v0, bytes32 v1, bytes32 v2
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(v0, v1, v2));
    }
    /// @dev `keccak256` of the 3 words.
    function hash(
        uint256 v0, uint256 v1, uint256 v2
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(v0, v1, v2));
    }
    /// @dev `keccak256` of the 4 words.
    function hash(
        bytes32 v0, bytes32 v1, bytes32 v2, bytes32 v3
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(v0, v1, v2, v3));
    }
    /// @dev `keccak256` of the 4 words.
    function hash(
        uint256 v0, uint256 v1, uint256 v2, uint256 v3
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(v0, v1, v2, v3));
    }
    /// @dev `keccak256` of the 5 words.
    function hash(
        bytes32 v0, bytes32 v1, bytes32 v2, bytes32 v3, bytes32 v4
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(v0, v1, v2, v3, v4));
    }
    /// @dev `keccak256` of the 5 words.
    function hash(
        uint256 v0, uint256 v1, uint256 v2, uint256 v3, uint256 v4
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(v0, v1, v2, v3, v4));
    }
    /// @dev `keccak256` of the 6 words.
    function hash(
        bytes32 v0, bytes32 v1, bytes32 v2, bytes32 v3, bytes32 v4, bytes32 v5
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(v0, v1, v2, v3, v4, v5));
    }
    /// @dev `keccak256` of the 6 words.
    function hash(
        uint256 v0, uint256 v1, uint256 v2, uint256 v3, uint256 v4, uint256 v5
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(v0, v1, v2, v3, v4, v5));
    }
    /// @dev `keccak256` of the 7 words.
    function hash(
        bytes32 v0, bytes32 v1, bytes32 v2, bytes32 v3, bytes32 v4, bytes32 v5, bytes32 v6
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(v0, v1, v2, v3, v4, v5, v6));
    }
    /// @dev `keccak256` of the 7 words.
    function hash(
        uint256 v0, uint256 v1, uint256 v2, uint256 v3, uint256 v4, uint256 v5, uint256 v6
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(v0, v1, v2, v3, v4, v5, v6));
    }
    /// @dev `keccak256` of the 8 words.
    function hash(
        bytes32 v0, bytes32 v1, bytes32 v2, bytes32 v3, bytes32 v4, bytes32 v5, bytes32 v6, bytes32 v7
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(v0, v1, v2, v3, v4, v5, v6, v7));
    }
    /// @dev `keccak256` of the 8 words.
    function hash(
        uint256 v0, uint256 v1, uint256 v2, uint256 v3, uint256 v4, uint256 v5, uint256 v6, uint256 v7
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(v0, v1, v2, v3, v4, v5, v6, v7));
    }
    /// @dev `keccak256` of the 9 words.
    function hash(
        bytes32 v0, bytes32 v1, bytes32 v2, bytes32 v3, bytes32 v4, bytes32 v5, bytes32 v6, bytes32 v7, bytes32 v8
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(v0, v1, v2, v3, v4, v5, v6, v7, v8));
    }
    /// @dev `keccak256` of the 9 words.
    function hash(
        uint256 v0, uint256 v1, uint256 v2, uint256 v3, uint256 v4, uint256 v5, uint256 v6, uint256 v7, uint256 v8
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(v0, v1, v2, v3, v4, v5, v6, v7, v8));
    }
    /// @dev `keccak256` of the 10 words.
    function hash(
        bytes32 v0, bytes32 v1, bytes32 v2, bytes32 v3, bytes32 v4, bytes32 v5, bytes32 v6, bytes32 v7, bytes32 v8, bytes32 v9
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(v0, v1, v2, v3, v4, v5, v6, v7, v8, v9));
    }
    /// @dev `keccak256` of the 10 words.
    function hash(
        uint256 v0, uint256 v1, uint256 v2, uint256 v3, uint256 v4, uint256 v5, uint256 v6, uint256 v7, uint256 v8, uint256 v9
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(v0, v1, v2, v3, v4, v5, v6, v7, v8, v9));
    }
    /// @dev `keccak256` of the 11 words.
    function hash(
        bytes32 v0, bytes32 v1, bytes32 v2, bytes32 v3, bytes32 v4, bytes32 v5, bytes32 v6, bytes32 v7, bytes32 v8, bytes32 v9, bytes32 v10
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10));
    }
    /// @dev `keccak256` of the 11 words.
    function hash(
        uint256 v0, uint256 v1, uint256 v2, uint256 v3, uint256 v4, uint256 v5, uint256 v6, uint256 v7, uint256 v8, uint256 v9, uint256 v10
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10));
    }
    /// @dev `keccak256` of the 12 words.
    function hash(
        bytes32 v0, bytes32 v1, bytes32 v2, bytes32 v3, bytes32 v4, bytes32 v5, bytes32 v6, bytes32 v7, bytes32 v8, bytes32 v9, bytes32 v10, bytes32 v11
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11));
    }
    /// @dev `keccak256` of the 12 words.
    function hash(
        uint256 v0, uint256 v1, uint256 v2, uint256 v3, uint256 v4, uint256 v5, uint256 v6, uint256 v7, uint256 v8, uint256 v9, uint256 v10, uint256 v11
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11));
    }
    /// @dev Sets `buffer[i]`, returning the buffer so calls chain.
    function set(bytes32[] memory buffer, uint256 i, bytes32 value)
        internal
        pure
        returns (bytes32[] memory)
    {
        buffer[i] = value;
        return buffer;
    }

    /// @dev Sets `buffer[i]`, returning the buffer so calls chain.
    function set(bytes32[] memory buffer, uint256 i, uint256 value)
        internal
        pure
        returns (bytes32[] memory)
    {
        buffer[i] = bytes32(value);
        return buffer;
    }

    /// @dev A zeroed buffer of `n` words.
    function malloc(uint256 n) internal pure returns (bytes32[] memory buffer) {
        return new bytes32[](n);
    }

    /// @dev Kept for API compatibility. Reclaiming memory is the compiler's.
    function free(bytes32[] memory buffer) internal pure {}

    /// @dev Whether `b` is exactly the 32 bytes of `a`.
    function eq(bytes32 a, bytes memory b) internal pure returns (bool) {
        return b.length == 32 && Bytes.readBytes32(b, 0) == a;
    }

    /// @dev Whether `a` is exactly the 32 bytes of `b`.
    function eq(bytes memory a, bytes32 b) internal pure returns (bool) {
        return eq(b, a);
    }

    /// @dev `keccak256` of `b` from `start` to `end`, both clamped to the
    /// length, and of nothing when the range is empty or reversed.
    function hash(bytes memory b, uint256 start, uint256 end) internal pure returns (bytes32) {
        (uint256 offset, uint256 count) = range(b.length, start, end);
        return Hash.keccak256Range(b, offset, count);
    }

    /// @dev `keccak256` of `b` from `start` to its end.
    function hash(bytes memory b, uint256 start) internal pure returns (bytes32) {
        return hash(b, start, b.length);
    }

    /// @dev `keccak256` of `b`.
    function hash(bytes memory b) internal pure returns (bytes32) {
        return keccak256(b);
    }

    /// @dev `keccak256` of `b` from `start` to `end`, clamped as above.
    function hashCalldata(bytes calldata b, uint256 start, uint256 end)
        internal
        pure
        returns (bytes32)
    {
        (uint256 offset, uint256 count) = range(b.length, start, end);
        return keccak256(b[offset:offset + count]);
    }

    /// @dev `keccak256` of `b` from `start` to its end.
    function hashCalldata(bytes calldata b, uint256 start) internal pure returns (bytes32) {
        return hashCalldata(b, start, b.length);
    }

    /// @dev `keccak256` of `b`.
    function hashCalldata(bytes calldata b) internal pure returns (bytes32) {
        return keccak256(b);
    }

    /// @dev `sha256` of the word.
    function sha2(bytes32 b) internal view returns (bytes32) {
        return sha256(abi.encode(b));
    }

    /// @dev `sha256` of `b` from `start` to `end`, clamped as above. The range
    /// is a view of `b`, which Solar hashes where it lies and other compilers
    /// copy out first.
    function sha2(bytes memory b, uint256 start, uint256 end) internal view returns (bytes32) {
        (uint256 offset, uint256 count) = range(b.length, start, end);
        /// @custom:solar-view
        bytes memory part = Bytes.slice(b, offset, count);
        return sha256(part);
    }

    /// @dev `sha256` of `b` from `start` to its end.
    function sha2(bytes memory b, uint256 start) internal view returns (bytes32) {
        return sha2(b, start, b.length);
    }

    /// @dev `sha256` of `b`.
    function sha2(bytes memory b) internal view returns (bytes32) {
        return sha256(b);
    }

    /// @dev `sha256` of `b` from `start` to `end`, clamped as above.
    function sha2Calldata(bytes calldata b, uint256 start, uint256 end)
        internal
        view
        returns (bytes32)
    {
        (uint256 offset, uint256 count) = range(b.length, start, end);
        return sha256(b[offset:offset + count]);
    }

    /// @dev `sha256` of `b` from `start` to its end.
    function sha2Calldata(bytes calldata b, uint256 start) internal view returns (bytes32) {
        return sha2Calldata(b, start, b.length);
    }

    /// @dev `sha256` of `b`.
    function sha2Calldata(bytes calldata b) internal view returns (bytes32) {
        return sha256(b);
    }

    /// @dev The upstream clamp: both ends are pulled down to `length`, and a
    /// reversed range hashes nothing.
    function range(uint256 length, uint256 start, uint256 end)
        private
        pure
        returns (uint256 offset, uint256 count)
    {
        if (end > length) end = length;
        if (start > length) start = length;
        return (start, end > start ? end - start : 0);
    }
}
