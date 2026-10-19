// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Checked Solidity replacements for the byte storage operations of
/// LibBytes.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/LibBytes.sol)
/// @dev Only the `BytesStorage` operations are ported. The layout is the
/// original's: a value of up to 254 bytes keeps its length in the low byte of
/// the struct's slot and its first 31 bytes above it, a longer one keeps
/// `0xff` there and its length above, and the rest of the value fills the
/// words derived from the slot, which the trusted helpers below move in whole
/// words: Solidity has no spelling of a slot derived from a struct's. Stores
/// write zeros past the end of the value, where the original copies whatever
/// memory or calldata follows it. `uint8At` returns zero from the length on,
/// as the original does since its stale-byte fix; the pinned release could
/// return a byte left there by a longer value.
/// @custom:solar-safe memory arithmetic
library LibBytes {
    /// @dev Goated bytes storage struct that totally MOGs, no cap, fr.
    /// Uses less gas and bytecode than Solidity's native bytes storage. It's meta af.
    /// Packs length with the first 31 bytes if <255 bytes, so it’s mad tight.
    struct BytesStorage {
        bytes32 _spacer;
    }

    /// @dev Sets the value of the bytes storage `$` to `s`.
    function set(BytesStorage storage $, bytes memory s) internal {
        uint256 n = s.length;
        if (n < 32) {
            // The length in the low byte and the value above it.
            $._spacer = bytes32((uint256(bytes32(s)) >> 8 << 8) | n);
        } else if (n < 0xff) {
            // The length in the low byte, the first 31 bytes above it, from
            // a first word that is whole, and the rest from byte 31 on in the
            // derived words.
            $._spacer = bytes32((uint256(_readBytes32(s, 0)) >> 8 << 8) | n);
            _storeBytes($, s, 31, n - 31);
        } else {
            $._spacer = bytes32((n << 8) | 0xff);
            _storeBytes($, s, 0, n);
        }
    }

    /// @dev Sets the value of the bytes storage `$` to `s`.
    function setCalldata(BytesStorage storage $, bytes calldata s) internal {
        uint256 n = s.length;
        if (n < 32) {
            $._spacer = bytes32((uint256(bytes32(s)) >> 8 << 8) | n);
        } else if (n < 0xff) {
            $._spacer = bytes32((uint256(_calldataReadBytes32(s, 0)) >> 8 << 8) | n);
            _storeCalldataBytes($, s, 31, n - 31);
        } else {
            $._spacer = bytes32((n << 8) | 0xff);
            _storeCalldataBytes($, s, 0, n);
        }
    }

    /// @dev Sets the value of the bytes storage `$` to the empty bytes.
    function clear(BytesStorage storage $) internal {
        delete $._spacer;
    }

    /// @dev Returns whether the value stored is `$` is the empty bytes "".
    function isEmpty(BytesStorage storage $) internal view returns (bool) {
        return uint256($._spacer) & 0xff == 0;
    }

    /// @dev Returns the length of the value stored in `$`.
    function length(BytesStorage storage $) internal view returns (uint256 result) {
        uint256 packed = uint256($._spacer);
        result = packed & 0xff;
        if (result == 0xff) result = packed >> 8;
    }

    /// @dev Returns the value stored in `$`.
    function get(BytesStorage storage $) internal view returns (bytes memory result) {
        uint256 packed = uint256($._spacer);
        uint256 n = packed & 0xff;
        if (n == 0xff) {
            n = packed >> 8;
            result = new bytes(n);
            _loadBytes($, result, 0, n);
            return result;
        }
        // Up to 31 bytes above the length, then the rest from the derived
        // words, all of them whole: a spare word past the end takes the
        // whole root word and the last derived word's bytes past the value.
        result = new bytes(n + 32);
        _writeBytes32(result, 0, bytes32(packed));
        if (n > 31) {
            // Up to two derived words directly, more through the loop.
            if (n < 96) {
                _writeBytes32(result, 31, _load($, 0));
                if (n > 63) _writeBytes32(result, 63, _load($, 1));
            } else {
                _loadBytes($, result, 31, n & ~uint256(31));
            }
        }
        // Zero past the end, as the original does, then cut to the length.
        _writeBytes32(result, n, bytes32(0));
        _truncate(result, n);
    }

    /// @dev Returns the uint8 at index `i`. If out-of-bounds, returns 0.
    function uint8At(BytesStorage storage $, uint256 i) internal view returns (uint8 result) {
        uint256 packed = uint256($._spacer);
        uint256 n = packed & 0xff;
        if (n != 0xff) {
            if (i >= n) return 0;
            if (i < 31) return uint8(bytes32(packed)[i]);
            uint256 j = i - 31;
            return uint8(_load($, j >> 5)[j & 31]);
        }
        if (i >= packed >> 8) return 0;
        return uint8(_load($, i >> 5)[i & 31]);
    }

    /// @dev The word `index` slots into the region `$` roots, `keccak256` of
    /// its slot onwards. The index must be below `2**64`, so a region never
    /// reaches another variable's slots.
    /// @custom:solar-trusted
    function _load(BytesStorage storage $, uint256 index) private view returns (bytes32 value) {
        if (index >> 64 != 0) index = new uint256[](0)[0];
        assembly ("memory-safe") {
            mstore(0x00, $.slot)
            value := sload(add(keccak256(0x00, 0x20), index))
        }
    }

    /// @dev Stores `count` bytes of `b` from `offset` into the region `$`
    /// roots, 32 bytes to a word from word 0, zeroing the last word past them.
    /// @custom:solar-trusted
    function _storeBytes(BytesStorage storage $, bytes memory b, uint256 offset, uint256 count)
        private
    {
        if (count >> 69 != 0 || offset > b.length || count > b.length - offset) {
            count = new uint256[](0)[0];
        }
        assembly ("memory-safe") {
            mstore(0x00, $.slot)
            let base := keccak256(0x00, 0x20)
            let src := add(add(b, 0x20), offset)
            for { let k := 0 } lt(shl(5, k), count) { k := add(k, 1) } {
                let w := mload(add(src, shl(5, k)))
                let rest := sub(count, shl(5, k))
                if lt(rest, 0x20) { w := and(w, not(shr(shl(3, rest), not(0)))) }
                sstore(add(base, k), w)
            }
        }
    }

    /// @dev `_storeBytes` from calldata.
    /// @custom:solar-trusted
    function _storeCalldataBytes(
        BytesStorage storage $,
        bytes calldata b,
        uint256 offset,
        uint256 count
    ) private {
        if (count >> 69 != 0 || offset > b.length || count > b.length - offset) {
            count = new uint256[](0)[0];
        }
        assembly ("memory-safe") {
            mstore(0x00, $.slot)
            let base := keccak256(0x00, 0x20)
            let src := add(b.offset, offset)
            for { let k := 0 } lt(shl(5, k), count) { k := add(k, 1) } {
                let w := calldataload(add(src, shl(5, k)))
                let rest := sub(count, shl(5, k))
                if lt(rest, 0x20) { w := and(w, not(shr(shl(3, rest), not(0)))) }
                sstore(add(base, k), w)
            }
        }
    }

    /// @dev Writes `count` bytes of the region `$` roots, from the start of
    /// word 0, into `b` at `offset`. The other bytes of `b` stay unchanged.
    /// @custom:solar-trusted
    function _loadBytes(BytesStorage storage $, bytes memory b, uint256 offset, uint256 count)
        private
        view
    {
        if (count >> 69 != 0 || offset > b.length || count > b.length - offset) {
            count = new uint256[](0)[0];
        }
        assembly ("memory-safe") {
            mstore(0x00, $.slot)
            let base := keccak256(0x00, 0x20)
            let dst := add(add(b, 0x20), offset)
            for { let k := 0 } lt(shl(5, k), count) { k := add(k, 1) } {
                let w := sload(add(base, k))
                let at := add(dst, shl(5, k))
                let rest := sub(count, shl(5, k))
                if lt(rest, 0x20) {
                    let keep := shr(shl(3, rest), not(0))
                    w := or(and(w, not(keep)), and(mload(at), keep))
                }
                mstore(at, w)
            }
        }
    }

    /// @dev Shrinks `b` to its first `n` bytes in place. Solidity cannot spell
    /// a shorter length for an existing buffer.
    /// @custom:solar-trusted
    function _truncate(bytes memory b, uint256 n) private pure {
        if (n > b.length) n = new uint256[](0)[0];
        assembly ("memory-safe") {
            mstore(b, n)
        }
    }

    /// @dev The 32 bytes of `b` at `offset`.
    function _readBytes32(bytes memory b, uint256 offset)
        private
        pure
        returns (bytes32 result)
    {
        for (uint256 k; k < 32; ++k) {
            result |= bytes32(b[offset + k]) >> (8 * k);
        }
    }

    /// @dev Writes `value` into `b` at `offset`.
    function _writeBytes32(bytes memory b, uint256 offset, bytes32 value) private pure {
        for (uint256 k; k < 32; ++k) {
            b[offset + k] = value[k];
        }
    }

    /// @dev The 32 bytes of `b` at `offset`.
    function _calldataReadBytes32(bytes calldata b, uint256 offset)
        private
        pure
        returns (bytes32 result)
    {
        for (uint256 k; k < 32; ++k) {
            result |= bytes32(b[offset + k]) >> (8 * k);
        }
    }
}
