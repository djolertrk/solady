// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Arrays} from "solar:core/v1/Arrays.sol";
import {Bytes} from "solar:core/v1/Bytes.sol";
import {CalldataBytes} from "solar:core/v1/CalldataBytes.sol";
import {Slots} from "solar:core/v1/Slots.sol";

/// @notice Checked Solidity replacements for the byte storage operations of
/// LibBytes.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/LibBytes.sol)
/// @dev Only the `BytesStorage` operations are ported. The layout is the
/// original's: a value of up to 254 bytes keeps its length in the low byte of
/// the struct's slot and its first 31 bytes above it, a longer one keeps
/// `0xff` there and its length above, and the rest of the value fills the
/// words derived from the slot, which `Slots` addresses. Stores write zeros
/// past the end of the value, where the original copies whatever memory or
/// calldata follows it. `uint8At` returns zero from the length on, as the
/// original does since its stale-byte fix; the pinned release could return a
/// byte left there by a longer value.
library LibBytes {
    /// @dev Goated bytes storage struct that totally MOGs, no cap, fr.
    /// Uses less gas and bytecode than Solidity's native bytes storage. It's meta af.
    /// Packs length with the first 31 bytes if <255 bytes, so it’s mad tight.
    struct BytesStorage {
        Slots.Root _spacer;
    }

    /// @dev Sets the value of the bytes storage `$` to `s`.
    function set(BytesStorage storage $, bytes memory s) internal {
        uint256 n = s.length;
        uint256 i;
        if (n < 0xff) {
            // The length in the low byte, the first 31 bytes above it, and
            // the rest from byte 31 on in the derived words.
            $._spacer.word = bytes32((uint256(bytes32(s)) >> 8 << 8) | n);
            i = 31;
        } else {
            $._spacer.word = bytes32((n << 8) | 0xff);
        }
        // Tested at the bottom behind one guard, the loop runs whenever it is
        // entered, so the slot hash moves out of it. The last word keeps only
        // the bytes before the end.
        if (i < n) {
            do {
                bytes32 w = i + 32 <= n
                    ? Bytes.readBytes32(s, i)
                    : bytes32(uint256(Bytes.readBytes32(s, n - 32)) << (8 * (32 - (n - i))));
                Slots.store($._spacer, i >> 5, w);
                i += 32;
            } while (i < n);
        }
    }

    /// @dev Sets the value of the bytes storage `$` to `s`.
    function setCalldata(BytesStorage storage $, bytes calldata s) internal {
        uint256 n = s.length;
        uint256 i;
        if (n < 0xff) {
            $._spacer.word = bytes32((uint256(bytes32(s)) >> 8 << 8) | n);
            i = 31;
        } else {
            $._spacer.word = bytes32((n << 8) | 0xff);
        }
        if (i < n) {
            do {
                bytes32 w = i + 32 <= n
                    ? CalldataBytes.readBytes32(s, i)
                    : bytes32(uint256(CalldataBytes.readBytes32(s, n - 32)) << (8 * (32 - (n - i))));
                Slots.store($._spacer, i >> 5, w);
                i += 32;
            } while (i < n);
        }
    }

    /// @dev Sets the value of the bytes storage `$` to the empty bytes.
    function clear(BytesStorage storage $) internal {
        delete $._spacer;
    }

    /// @dev Returns whether the value stored is `$` is the empty bytes "".
    function isEmpty(BytesStorage storage $) internal view returns (bool) {
        return uint256($._spacer.word) & 0xff == 0;
    }

    /// @dev Returns the length of the value stored in `$`.
    function length(BytesStorage storage $) internal view returns (uint256 result) {
        uint256 packed = uint256($._spacer.word);
        result = packed & 0xff;
        if (result == 0xff) result = packed >> 8;
    }

    /// @dev Returns the value stored in `$`.
    function get(BytesStorage storage $) internal view returns (bytes memory result) {
        uint256 packed = uint256($._spacer.word);
        uint256 n = packed & 0xff;
        uint256 i;
        // A spare word past the end takes the last derived word whole.
        if (n != 0xff) {
            result = new bytes(n + 32);
            Bytes.writeBytes32(result, 0, bytes32(packed));
            i = 31;
        } else {
            n = packed >> 8;
            result = new bytes(n + 32);
        }
        if (i < n) {
            do {
                Bytes.writeBytes32(result, i, Slots.load($._spacer, i >> 5));
                i += 32;
            } while (i < n);
        }
        // Zero past the end, as the original does, then cut to the length.
        Bytes.writeBytes32(result, n, bytes32(0));
        Arrays.truncate(result, n);
    }

    /// @dev Returns the uint8 at index `i`. If out-of-bounds, returns 0.
    function uint8At(BytesStorage storage $, uint256 i) internal view returns (uint8 result) {
        uint256 packed = uint256($._spacer.word);
        uint256 n = packed & 0xff;
        if (n != 0xff) {
            if (i >= n) return 0;
            if (i < 31) return uint8(bytes32(packed)[i]);
            uint256 j = i - 31;
            return uint8(Slots.load($._spacer, j >> 5)[j & 31]);
        }
        if (i >= packed >> 8) return 0;
        return uint8(Slots.load($._spacer, i >> 5)[i & 31]);
    }
}
