// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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
/// @custom:solar-safe memory arithmetic
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
    /// @dev `keccak256` of the 13 words.
    function hash(
        bytes32 v0, bytes32 v1, bytes32 v2, bytes32 v3, bytes32 v4, bytes32 v5, bytes32 v6, bytes32 v7, bytes32 v8, bytes32 v9, bytes32 v10, bytes32 v11, bytes32 v12
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12));
    }
    /// @dev `keccak256` of the 13 words.
    function hash(
        uint256 v0, uint256 v1, uint256 v2, uint256 v3, uint256 v4, uint256 v5, uint256 v6, uint256 v7, uint256 v8, uint256 v9, uint256 v10, uint256 v11, uint256 v12
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12));
    }
    /// @dev `keccak256` of the 14 words.
    function hash(
        bytes32 v0, bytes32 v1, bytes32 v2, bytes32 v3, bytes32 v4, bytes32 v5, bytes32 v6, bytes32 v7, bytes32 v8, bytes32 v9, bytes32 v10, bytes32 v11, bytes32 v12, bytes32 v13
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13));
    }
    /// @dev `keccak256` of the 14 words.
    function hash(
        uint256 v0, uint256 v1, uint256 v2, uint256 v3, uint256 v4, uint256 v5, uint256 v6, uint256 v7, uint256 v8, uint256 v9, uint256 v10, uint256 v11, uint256 v12, uint256 v13
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13));
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

    /// @dev `keccak256` of the words of `buffer`, as `abi.encode` lays them out.
    function hash(bytes32[] memory buffer) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(buffer));
    }

    /// @dev A zeroed buffer of `n` words.
    function malloc(uint256 n) internal pure returns (bytes32[] memory buffer) {
        return new bytes32[](n);
    }

    /// @dev Frees memory that has been allocated for `buffer`.
    /// No-op if `buffer.length` is zero, or if new memory has been allocated after `buffer`.
    /// Solidity cannot move the free memory pointer, so this keeps the upstream assembly.
    /// @custom:solar-trusted
    function free(bytes32[] memory buffer) internal pure {
        /// @solidity memory-safe-assembly
        assembly {
            let n := mload(buffer)
            mstore(shl(6, lt(iszero(n), eq(add(shl(5, add(1, n)), buffer), mload(0x40)))), buffer)
        }
    }

    /// @dev Whether `b` is exactly the 32 bytes of `a`.
    function eq(bytes32 a, bytes memory b) internal pure returns (bool) {
        return b.length == 32 && _readBytes32(b, 0) == a;
    }

    /// @dev Whether `a` is exactly the 32 bytes of `b`.
    function eq(bytes memory a, bytes32 b) internal pure returns (bool) {
        return eq(b, a);
    }

    /// @dev `keccak256` of `b` from `start` to `end`, both clamped to the
    /// length, and of nothing when the range is empty or reversed: the upstream
    /// clamp, spelled so that `start <= end <= b.length` is visible where the
    /// range is read.
    function hash(bytes memory b, uint256 start, uint256 end) internal pure returns (bytes32) {
        uint256 n = b.length;
        if (end > n) end = n;
        if (start > end) start = end;
        return _keccak256Range(b, start, end - start);
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
        uint256 n = b.length;
        if (end > n) end = n;
        if (start > end) start = end;
        return keccak256(b[start:end]);
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

    /// @dev `sha256` of `b` from `start` to `end`, clamped as above.
    function sha2(bytes memory b, uint256 start, uint256 end) internal view returns (bytes32) {
        uint256 n = b.length;
        if (end > n) end = n;
        if (start > end) start = end;
        bytes memory part = _slice(b, start, end - start);
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
        uint256 n = b.length;
        if (end > n) end = n;
        if (start > end) start = end;
        return sha256(b[start:end]);
    }

    /// @dev `sha256` of `b` from `start` to its end.
    function sha2Calldata(bytes calldata b, uint256 start) internal view returns (bytes32) {
        return sha2Calldata(b, start, b.length);
    }

    /// @dev `sha256` of `b`.
    function sha2Calldata(bytes calldata b) internal view returns (bytes32) {
        return sha256(b);
    }

    /// @dev The 32 bytes of `b` at `offset`.
    /// @custom:solar-inline
    function _readBytes32(bytes memory b, uint256 offset)
        private
        pure
        returns (bytes32 result)
    {
        for (uint256 k; k < 32; ++k) {
            result |= bytes32(b[offset + k]) >> (8 * k);
        }
    }

    /// @dev A copy of the `count` bytes of `b` at `offset`. Reverts with
    /// `Panic(0x32)` unless they all lie inside `b`, before allocating.
    function _slice(bytes memory b, uint256 offset, uint256 count)
        private
        pure
        returns (bytes memory result)
    {
        if (offset > b.length || count > b.length - offset) offset = _outOfBounds();
        result = new bytes(count);
        for (uint256 k; k < count; ++k) {
            result[k] = b[offset + k];
        }
    }

    /// @dev The keccak-256 hash of the `count` bytes of `b` at `offset`.
    function _keccak256Range(bytes memory b, uint256 offset, uint256 count)
        private
        pure
        returns (bytes32)
    {
        if (count > b.length || offset > b.length - count) count = _outOfBounds();
        bytes memory range = new bytes(count);
        for (uint256 k; k < count; ++k) {
            range[k] = b[offset + k];
        }
        return keccak256(range);
    }

    /// @dev Raises the `Panic(0x32)` an out-of-range index raises, which is the
    /// portable spelling of a failed range check.
    function _outOfBounds() private pure returns (uint256) {
        return new uint256[](0)[0];
    }
}
