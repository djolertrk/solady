// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Arrays} from "solar:core/v1/Arrays.sol";
import {Bits} from "solar:core/v1/Bits.sol";
import {Bytes} from "solar:core/v1/Bytes.sol";

/// @notice Checked Solidity implementation of the pinned Solady LibBit API.
/// @dev Raw boolean operations require clean boolean inputs, as upstream does.
/// The bit scans and the population count are `Bits`: a table search on a
/// target without `clz`, the instruction on one that has it.
library LibBit {
    /// @dev Nibble-spreading masks, one per halving of the packing.
    uint256 private constant _MASK_64 =
        0x0000000000000000ffffffffffffffff0000000000000000ffffffffffffffff;
    uint256 private constant _MASK_32 =
        0x00000000ffffffff00000000ffffffff00000000ffffffff00000000ffffffff;
    uint256 private constant _MASK_16 =
        0x0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff;
    uint256 private constant _MASK_8 =
        0x00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff;
    uint256 private constant _MASK_4 =
        0x0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f;

    function fls(uint256 x) internal pure returns (uint256 r) {
        return Bits.highestSetBit(x);
    }

    function clz(uint256 x) internal pure returns (uint256 r) {
        return Bits.leadingZeros(x);
    }

    function ffs(uint256 x) internal pure returns (uint256 r) {
        return Bits.trailingZeros(x);
    }

    function popCount(uint256 x) internal pure returns (uint256 c) {
        return Bits.popCount(x);
    }

    // Every input byte is zero or one, so the sum is at most 32 and fits the
    // extracted byte. Pairing the halves bounds the product below 2**256.
    function _sumBytes(uint256 x) private pure returns (uint256) {
        uint256 paired = (x & type(uint128).max) + (x >> 128);
        return uint8((paired * (uint256(type(uint128).max) / 255)) >> 120);
    }

    function countZeroBytes(uint256 x) internal pure returns (uint256 c) {
        uint256 m = type(uint256).max / 255 * 127;
        return _sumBytes(~(((x & m) + m) | x | m) >> 7);
    }

    // The two loops below are left a byte at a time on purpose: the compiler
    // recognizes the shape and counts a word per step, which a hand-written
    // word loop over `Bytes.readBytes32` measured slower than.
    function countZeroBytes(bytes memory s) internal pure returns (uint256 c) {
        for (uint256 i; i < s.length; ++i) {
            if (s[i] == 0) ++c;
        }
    }

    function countZeroBytesCalldata(bytes calldata s) internal pure returns (uint256 c) {
        for (uint256 i; i < s.length; ++i) {
            if (s[i] == 0) ++c;
        }
    }

    function isPo2(uint256 x) internal pure returns (bool result) {
        return x != 0 && (x & (x - 1)) == 0;
    }

    function reverseBytes(uint256 x) internal pure returns (uint256 r) {
        uint256 m0 = 0x0000000000000000ffffffffffffffff0000000000000000ffffffffffffffff;
        uint256 m1 = m0 ^ (m0 << 32);
        uint256 m2 = m1 ^ (m1 << 16);
        uint256 m3 = m2 ^ (m2 << 8);
        r = (m3 & (x >> 8)) | ((m3 & x) << 8);
        r = (m2 & (r >> 16)) | ((m2 & r) << 16);
        r = (m1 & (r >> 32)) | ((m1 & r) << 32);
        r = (m0 & (r >> 64)) | ((m0 & r) << 64);
        return (r >> 128) | (r << 128);
    }

    function reverseBits(uint256 x) internal pure returns (uint256 r) {
        uint256 m0 = type(uint256).max / 17;
        uint256 m1 = m0 ^ (m0 << 2);
        uint256 m2 = m1 ^ (m1 << 1);
        r = reverseBytes(x);
        r = (m2 & (r >> 1)) | ((m2 & r) << 1);
        r = (m1 & (r >> 2)) | ((m1 & r) << 2);
        return (m0 & (r >> 4)) | ((m0 & r) << 4);
    }

    function commonBitPrefix(uint256 x, uint256 y) internal pure returns (uint256) {
        uint256 s = 256 - clz(x ^ y);
        return (x >> s) << s;
    }

    function commonNibblePrefix(uint256 x, uint256 y) internal pure returns (uint256) {
        uint256 s = (64 - (clz(x ^ y) >> 2)) << 2;
        return (x >> s) << s;
    }

    function commonBytePrefix(uint256 x, uint256 y) internal pure returns (uint256) {
        uint256 s = (32 - (clz(x ^ y) >> 3)) << 3;
        return (x >> s) << s;
    }

    function toNibbles(bytes memory s) internal pure returns (bytes memory result) {
        uint256 n = s.length;
        // Below one block the input fits one word, zero-padded by the
        // conversion: its nibbles fill one word, cut down to the output. An
        // empty input has none to spread.
        if (n < 16) {
            if (n == 0) return "";
            result = abi.encodePacked(bytes32(_spread(uint256(bytes32(s)) >> 128)));
            Arrays.truncate(result, n * 2);
            return result;
        }
        result = new bytes(n * 2);
        uint256 i;
        uint256 o;
        // Sixteen input bytes make one word of output. The spreading is
        // written out here rather than called, so that the loop is straight
        // code whose reads and writes the loop condition already bounds.
        while (i + 16 <= n) {
            uint256 x = uint128(Bytes.readBytes16(s, i));
            x = (x | (x << 64)) & _MASK_64;
            x = (x | (x << 32)) & _MASK_32;
            x = (x | (x << 16)) & _MASK_16;
            x = (x | (x << 8)) & _MASK_8;
            Bytes.writeBytes32(result, o, bytes32((x | (x << 4)) & _MASK_4));
            i += 16;
            o += 32;
        }
        if (i == n) return result;
        // What is left is shorter than a block. One more block pulled back to
        // end where the input ends covers it, rewriting the nibbles it shares
        // with the block before.
        uint256 tail = uint128(Bytes.readBytes16(s, n - 16));
        Bytes.writeBytes32(result, (n - 16) * 2, bytes32(_spread(tail)));
    }

    /// @dev The nibbles of `x`, which must be below `2 ** 128`, one to a byte:
    /// eight bytes apart, then four, two, one, and finally one nibble.
    function _spread(uint256 x) private pure returns (uint256) {
        x = (x | (x << 64)) & _MASK_64;
        x = (x | (x << 32)) & _MASK_32;
        x = (x | (x << 16)) & _MASK_16;
        x = (x | (x << 8)) & _MASK_8;
        return (x | (x << 4)) & _MASK_4;
    }

    function rawAnd(bool x, bool y) internal pure returns (bool z) {
        return x && y;
    }

    function and(bool x, bool y) internal pure returns (bool z) {
        return x && y;
    }

    function and(bool w, bool x, bool y) internal pure returns (bool z) {
        return w && x && y;
    }

    function and(bool v, bool w, bool x, bool y) internal pure returns (bool z) {
        return v && w && x && y;
    }

    function rawOr(bool x, bool y) internal pure returns (bool z) {
        return x || y;
    }

    function or(bool x, bool y) internal pure returns (bool z) {
        return x || y;
    }

    function or(bool w, bool x, bool y) internal pure returns (bool z) {
        return w || x || y;
    }

    function or(bool v, bool w, bool x, bool y) internal pure returns (bool z) {
        return v || w || x || y;
    }

    function rawToUint(bool b) internal pure returns (uint256 z) {
        return b ? 1 : 0;
    }

    function toUint(bool b) internal pure returns (uint256 z) {
        return b ? 1 : 0;
    }
}
