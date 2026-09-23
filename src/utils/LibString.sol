// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Arrays} from "solar:core/v1/Arrays.sol";
import {Bytes} from "solar:core/v1/Bytes.sol";
import {Hash} from "solar:core/v1/Hash.sol";
import {Hex} from "solar:core/v1/codecs/Hex.sol";
import {Math} from "solar:core/v1/Math.sol";
import {Strings} from "solar:core/v1/Strings.sol";

/// @notice Checked Solidity replacements for the value-oriented LibString APIs.
/// @dev Storage reinterpretation and direct-return APIs are deliberately absent.
library LibString {
    error HexLengthInsufficient();
    error TooBigForSmallString();
    error StringNot7BitASCII();
    uint256 internal constant NOT_FOUND = type(uint256).max;

    /// @dev Nibble-spreading masks, one per halving of the packing.
    uint256 private constant MASK_64 =
        0x0000000000000000ffffffffffffffff0000000000000000ffffffffffffffff;
    uint256 private constant MASK_32 =
        0x00000000ffffffff00000000ffffffff00000000ffffffff00000000ffffffff;
    uint256 private constant MASK_16 =
        0x0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff;
    uint256 private constant MASK_8 =
        0x00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff;
    uint256 private constant MASK_4 =
        0x0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f;

    /// @dev One copy of the value in every byte.
    uint256 private constant SPREAD_1 =
        0x0101010101010101010101010101010101010101010101010101010101010101;
    uint256 private constant SPREAD_5 =
        0x0505050505050505050505050505050505050505050505050505050505050505;
    uint256 private constant SPREAD_6 =
        0x0606060606060606060606060606060606060606060606060606060606060606;
    uint256 private constant SPREAD_ASCII_0 =
        0x3030303030303030303030303030303030303030303030303030303030303030;
    uint256 private constant SPREAD_1F =
        0x1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f;
    uint256 private constant SPREAD_20 =
        0x2020202020202020202020202020202020202020202020202020202020202020;
    uint256 private constant LANES_7F =
        0x7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f;

    /// @dev The top bit of every byte lane.
    uint256 private constant _HIGH_BITS =
        0x8080808080808080808080808080808080808080808080808080808080808080;

    function toString(uint256 value) internal pure returns (string memory result) {
        return Strings.toString(value);
    }

    function toString(int256 value) internal pure returns (string memory result) {
        return Strings.toString(value);
    }

    function toHexStringNoPrefix(uint256 value, uint256 byteCount)
        internal
        pure
        returns (string memory result)
    {
        return Strings.toHexStringNoPrefix(value, byteCount);
    }

    /// @dev The thirty-two hex characters of the sixteen bytes in `x`, which
    /// must be below `2 ** 128`.
    function _hexWord(uint256 x) private pure returns (bytes32) {
        // Spread the thirty-two nibbles one to a byte, halving the packing
        // each step: eight bytes, four, two, one, then one nibble.
        x = (x | (x << 64)) & MASK_64;
        x = (x | (x << 32)) & MASK_32;
        x = (x | (x << 16)) & MASK_16;
        x = (x | (x << 8)) & MASK_8;
        x = (x | (x << 4)) & MASK_4;
        // Adding six carries every nibble above nine into the next bit, which
        // marks the ones that become letters rather than digits.
        uint256 letters = ((x + SPREAD_6) >> 4) & SPREAD_1;
        return bytes32(x + SPREAD_ASCII_0 + letters * 39);
    }

    /// @dev Spreads the thirty-two nibbles of the low sixteen bytes of `x` one to a byte,
    /// the highest nibble first, as `_hexWord` does before it turns them into digits. Kept
    /// apart from it so that the hex formatters' loops keep their inlined body.
    function _nibbles(uint256 x) private pure returns (uint256) {
        x = (x | (x << 64)) & MASK_64;
        x = (x | (x << 32)) & MASK_32;
        x = (x | (x << 16)) & MASK_16;
        x = (x | (x << 8)) & MASK_8;
        return (x | (x << 4)) & MASK_4;
    }

    function toHexString(uint256 value, uint256 byteCount)
        internal
        pure
        returns (string memory result)
    {
        return Strings.toHexString(value, byteCount);
    }

    function toHexStringNoPrefix(uint256 value) internal pure returns (string memory result) {
        return Strings.toHexStringNoPrefix(value);
    }

    function toHexString(uint256 value) internal pure returns (string memory result) {
        return Strings.toHexString(value);
    }

    function toMinimalHexStringNoPrefix(uint256 value)
        internal
        pure
        returns (string memory result)
    {
        return Strings.toMinimalHexStringNoPrefix(value);
    }

    function toMinimalHexString(uint256 value) internal pure returns (string memory result) {
        return Strings.toMinimalHexString(value);
    }

    function toHexStringNoPrefix(address value) internal pure returns (string memory result) {
        return toHexStringNoPrefix(uint160(value), 20);
    }

    function toHexString(address value) internal pure returns (string memory result) {
        return toHexString(uint160(value), 20);
    }

    function toHexStringNoPrefix(bytes memory raw) internal pure returns (string memory result) {
        return Hex.encode(raw);
    }

    function toHexString(bytes memory raw) internal pure returns (string memory result) {
        return Hex.encodePrefixed(raw);
    }

    function is7BitASCII(string memory s) internal pure returns (bool result) {
        bytes memory b = bytes(s);
        for (uint256 i; i < b.length; ++i) {
            if (b[i] > 0x7f) return false;
        }
        return true;
    }

    function is7BitASCII(string memory s, uint128 allowed) internal pure returns (bool result) {
        // With every 7-bit byte allowed, only the high bits matter.
        if (allowed == type(uint128).max) return is7BitASCII(s);
        return _allowedBytes(bytes(s), allowed);
    }

    /// @dev Whether every byte of `b` has its bit set in `allowed`.
    function _allowedBytes(bytes memory b, uint256 allowed) private pure returns (bool) {
        for (uint256 i; i < b.length; ++i) {
            if (((allowed >> uint8(b[i])) & 1) == 0) return false;
        }
        return true;
    }

    function to7BitASCIIAllowedLookup(string memory s) internal pure returns (uint128 result) {
        bytes memory b = bytes(s);
        if (b.length == 0) return 0;
        uint256 lookup;
        for (uint256 i; i < b.length; ++i) {
            lookup |= uint256(1) << uint8(b[i]);
        }
        if (lookup > type(uint128).max) revert StringNot7BitASCII();
        return uint128(lookup);
    }

    function runeCount(string memory s) internal pure returns (uint256 result) {
        return Strings.runeCount(s);
    }

    function concat(string memory a, string memory b) internal pure returns (string memory) {
        return string.concat(a, b);
    }

    function eq(string memory a, string memory b) internal pure returns (bool result) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function toCase(string memory subject, bool toUpper)
        internal
        pure
        returns (string memory result)
    {
        bytes memory b = bytes(subject);
        uint256 n = b.length;
        if (n == 0) return result;
        // Either direction is the same single bit flip, applied a word at a
        // time. Flipping that bit in every byte first maps uppercase letters
        // onto the lowercase range, so both directions test one range. A
        // shorter string is one zero-padded word.
        uint256 flip = toUpper ? 0 : SPREAD_20;
        if (n < 32) {
            uint256 word = uint256(bytes32(b));
            bytes memory short = abi.encodePacked(bytes32(word ^ _caseFlips(word, flip)));
            Arrays.truncate(short, n);
            return string(short);
        }
        bytes memory out = new bytes(n);
        uint256 i;
        for (; i + 32 <= n; i += 32) {
            uint256 word = uint256(Bytes.readBytes32(b, i));
            Bytes.writeBytes32(out, i, bytes32(word ^ _caseFlips(word, flip)));
        }
        // The last word ends at the end of the string, repeating bytes already
        // converted with the same result.
        if (i < n) {
            uint256 word = uint256(Bytes.readBytes32(b, n - 32));
            Bytes.writeBytes32(out, n - 32, bytes32(word ^ _caseFlips(word, flip)));
        }
        return string(out);
    }

    /// @dev `0x20` in each byte of `word` that is a lowercase letter once
    /// `flip` is applied. A byte's low seven bits plus `0x80 - x` reach its
    /// high bit exactly when they are at least `x`, and never carry into the
    /// next byte; bytes of `0x80` and above are no letters.
    function _caseFlips(uint256 word, uint256 flip) private pure returns (uint256) {
        uint256 low = (word ^ flip) & LANES_7F;
        // `a` through `z` are 0x61 through 0x7a.
        uint256 letters = (low + SPREAD_1F) ^ (low + SPREAD_5);
        return (letters & ~word & _HIGH_BITS) >> 2;
    }

    function lower(string memory subject) internal pure returns (string memory result) {
        return toCase(subject, false);
    }

    function upper(string memory subject) internal pure returns (string memory result) {
        return toCase(subject, true);
    }

    /// @dev Returns the hexadecimal representation of `value`.
    /// The output is prefixed with "0x", encoded using 2 hexadecimal digits per byte,
    /// and the alphabets are capitalized conditionally according to
    /// https://eips.ethereum.org/EIPS/eip-55
    function toHexStringChecksummed(address value) internal pure returns (string memory result) {
        bytes memory out = new bytes(42);
        out[0] = "0";
        out[1] = "x";
        // The top sixteen bytes make one word of characters; the low four make the top eight
        // characters of another.
        uint256 raw = uint160(value);
        uint256 head = uint256(_hexWord(raw >> 32));
        uint256 tail = uint256(_hexWord((raw & 0xffffffff) << 96));
        Bytes.writeBytes32(out, 2, bytes32(head));
        Bytes.writeBytes8(out, 34, bytes8(bytes32(tail)));
        // A character is uppercased when it is a letter and its nibble of the hash of the
        // lowercase digits is at least eight: nibble by nibble, the hash's top sixteen bytes
        // line up with the head and the next four with the tail.
        uint256 hash = uint256(Hash.keccak256Range(out, 2, 40));
        Bytes.writeBytes32(out, 2, bytes32(_checksumCase(head, _nibbles(hash >> 128))));
        Bytes.writeBytes8(
            out, 34, bytes8(bytes32(_checksumCase(tail, _nibbles(hash & type(uint128).max))))
        );
        return string(out);
    }

    /// @dev Uppercases every letter of the hex `chars` whose lane of `nibbles` is at least
    /// eight. Adding 0x1f sets the top bit of a letter's lane, 0x61 to 0x66, and of no digit's
    /// or empty lane; the nibble's bit three shifted up is the other condition, and taking
    /// 0x20 off a marked lane is the case change.
    function _checksumCase(uint256 chars, uint256 nibbles) private pure returns (uint256) {
        uint256 letters = (chars + SPREAD_1F) & _HIGH_BITS;
        uint256 marked = letters & ((nibbles << 4) & _HIGH_BITS);
        return chars - (marked >> 2);
    }

    /// @dev Returns whether `needle` occurs in `subject` at byte offset `i`.
    function _matchAt(bytes memory subject, bytes memory needle, uint256 i)
        private
        pure
        returns (bool)
    {
        for (uint256 k; k < needle.length; ++k) {
            if (subject[i + k] != needle[k]) return false;
        }
        return true;
    }

    /// @dev Returns `subject` all occurrences of `needle` replaced with `replacement`.
    function replace(string memory subject, string memory needle, string memory replacement)
        internal
        pure
        returns (string memory)
    {
        return Strings.replace(subject, needle, replacement);
    }

    /// @dev Returns the byte index of the first location of `needle` in `subject`,
    /// needleing from left to right, starting from `from`.
    /// Returns `NOT_FOUND` (i.e. `type(uint256).max`) if the `needle` is not found.
    function indexOf(string memory subject, string memory needle, uint256 from)
        internal
        pure
        returns (uint256)
    {
        return Strings.indexOf(subject, needle, from);
    }

    /// @dev Returns the byte index of the first location of `needle` in `subject`,
    /// needleing from left to right.
    /// Returns `NOT_FOUND` (i.e. `type(uint256).max`) if the `needle` is not found.
    function indexOf(string memory subject, string memory needle) internal pure returns (uint256) {
        return indexOf(subject, needle, 0);
    }

    /// @dev Returns the byte index of the first location of `needle` in `subject`,
    /// needleing from right to left, starting from `from`.
    /// Returns `NOT_FOUND` (i.e. `type(uint256).max`) if the `needle` is not found.
    function lastIndexOf(string memory subject, string memory needle, uint256 from)
        internal
        pure
        returns (uint256)
    {
        return Strings.lastIndexOf(subject, needle, from);
    }

    /// @dev Returns the byte index of the first location of `needle` in `subject`,
    /// needleing from right to left.
    /// Returns `NOT_FOUND` (i.e. `type(uint256).max`) if the `needle` is not found.
    function lastIndexOf(string memory subject, string memory needle)
        internal
        pure
        returns (uint256)
    {
        return lastIndexOf(subject, needle, NOT_FOUND);
    }

    /// @dev Returns true if `needle` is found in `subject`, false otherwise.
    function contains(string memory subject, string memory needle) internal pure returns (bool) {
        return indexOf(subject, needle) != NOT_FOUND;
    }

    /// @dev Returns whether `subject` starts with `needle`.
    function startsWith(string memory subject, string memory needle) internal pure returns (bool) {
        bytes memory s = bytes(subject);
        bytes memory n = bytes(needle);
        return n.length <= s.length && _matchAt(s, n, 0);
    }

    /// @dev Returns whether `subject` ends with `needle`.
    function endsWith(string memory subject, string memory needle) internal pure returns (bool) {
        bytes memory s = bytes(subject);
        bytes memory n = bytes(needle);
        return n.length <= s.length && _matchAt(s, n, s.length - n.length);
    }

    /// @dev Returns `subject` repeated `times`.
    function repeat(string memory subject, uint256 times) internal pure returns (string memory) {
        bytes memory s = bytes(subject);
        if (times == 0 || s.length == 0) return "";
        // Sizing the result first keeps the overflow panic of the original.
        uint256 total = s.length * times;
        if (total == 0) return "";
        // Doubling the accumulated chunk turns the copy into whole-buffer
        // concatenations: `times` bytes are moved a logarithmic number of times
        // instead of one byte at a time.
        bytes memory out;
        bytes memory chunk = s;
        uint256 remaining = times;
        while (true) {
            if (remaining & 1 == 1) out = bytes.concat(out, chunk);
            remaining >>= 1;
            if (remaining == 0) break;
            chunk = bytes.concat(chunk, chunk);
        }
        return string(out);
    }

    /// @dev Returns a copy of `subject` sliced from `start` to `end` (exclusive).
    /// `start` and `end` are byte offsets.
    function slice(string memory subject, uint256 start, uint256 end)
        internal
        pure
        returns (string memory)
    {
        bytes memory s = bytes(subject);
        if (end > s.length) end = s.length;
        if (start > s.length) start = s.length;
        if (start >= end) return "";
        bytes memory out = new bytes(end - start);
        Bytes.copyInto(out, 0, s, start, end - start);
        return string(out);
    }

    /// @dev Returns a copy of `subject` sliced from `start` to the end of the string.
    /// `start` is a byte offset.
    function slice(string memory subject, uint256 start) internal pure returns (string memory) {
        return slice(subject, start, NOT_FOUND);
    }

    /// @dev Returns all the indices of `needle` in `subject`.
    /// The indices are byte offsets.
    function indicesOf(string memory subject, string memory needle)
        internal
        pure
        returns (uint256[] memory)
    {
        return Strings.indicesOf(subject, needle);
    }

    /// @dev Returns an arrays of strings based on the `delimiter` inside of the `subject` string.
    function split(string memory subject, string memory delimiter)
        internal
        pure
        returns (string[] memory)
    {
        return Strings.split(subject, delimiter);
    }

    /// @dev Returns the length of the small string `s` up to its first null byte.
    function _smallStringLength(bytes32 s) private pure returns (uint256) {
        // One mark for each byte from the first zero byte on; the bytes before
        // it are the string. The marks are one per byte, so the byte sums the
        // folds build stay below 33 and never carry into their neighbours.
        uint256 c = _nullTail(s) >> 7;
        c += c >> 8;
        c += c >> 16;
        c += c >> 32;
        c += c >> 64;
        c += c >> 128;
        return 32 - (c & 0xff);
    }

    /// @dev `0x80` in every byte of `s` from its first zero byte on. A byte
    /// carries into its own high bit exactly when it is not zero, so the kept
    /// high bits mark the zero bytes; each mark then spreads to every lower
    /// byte, which the first zero byte's mark reaches first.
    function _nullTail(bytes32 s) private pure returns (uint256 marks) {
        uint256 x = uint256(s);
        marks = ~(x | ((x & LANES_7F) + LANES_7F) | LANES_7F);
        marks |= marks >> 8;
        marks |= marks >> 16;
        marks |= marks >> 32;
        marks |= marks >> 64;
        marks |= marks >> 128;
    }

    /// @dev Returns a string from a small bytes32 string.
    /// `s` must be null-terminated, or behavior will be undefined.
    function fromSmallString(bytes32 s) internal pure returns (string memory result) {
        // The word is written whole, with the bytes from the null on cleared,
        // and the string then shortened to them.
        uint256 n = _smallStringLength(s);
        bytes32 kept = n == 32 ? s : s & bytes32(type(uint256).max << ((32 - n) * 8));
        bytes memory out = abi.encodePacked(kept);
        Arrays.truncate(out, n);
        return string(out);
    }

    /// @dev Returns the small string, with all bytes after the first null byte zeroized.
    function normalizeSmallString(bytes32 s) internal pure returns (bytes32 result) {
        // Each byte from the first zero byte on is cleared: its mark fills the
        // byte downwards without leaving it.
        uint256 tail = _nullTail(s);
        tail |= tail >> 1;
        tail |= tail >> 2;
        tail |= tail >> 4;
        return s & bytes32(~tail);
    }

    /// @dev Returns the string as a normalized null-terminated small string.
    function toSmallString(string memory s) internal pure returns (bytes32 result) {
        bytes memory b = bytes(s);
        if (b.length > 32) revert TooBigForSmallString();
        return bytes32(b);
    }

    /// @dev Escapes the string to be used within HTML tags.
    function escapeHTML(string memory s) internal pure returns (string memory result) {
        return Strings.escapeHTML(s);
    }

    /// @dev Escapes the string to be used within double-quotes in a JSON.
    /// If `addDoubleQuotes` is true, the result will be enclosed in double-quotes.
    function escapeJSON(string memory s, bool addDoubleQuotes)
        internal
        pure
        returns (string memory result)
    {
        return Strings.escapeJSON(s, addDoubleQuotes);
    }

    /// @dev Escapes the string to be used within double-quotes in a JSON.
    function escapeJSON(string memory s) internal pure returns (string memory result) {
        return Strings.escapeJSON(s);
    }

    /// @dev Encodes `s` so that it can be safely used in a URI,
    /// just like `encodeURIComponent` in JavaScript.
    /// See: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/encodeURIComponent
    /// See: https://datatracker.ietf.org/doc/html/rfc2396
    /// See: https://datatracker.ietf.org/doc/html/rfc3986
    function encodeURIComponent(string memory s) internal pure returns (string memory result) {
        return Strings.encodeURIComponent(s);
    }

    /// @dev Returns whether `a` equals `b`, where `b` is a null-terminated small string.
    function eqs(string memory a, bytes32 b) internal pure returns (bool result) {
        bytes memory s = bytes(a);
        uint256 n = _smallStringLength(b);
        if (s.length != n) return false;
        // Both sides keep only their first `n` bytes.
        uint256 shift = (32 - n) * 8;
        return uint256(bytes32(s)) >> shift == uint256(b) >> shift;
    }

    /// @dev Returns 0 if `a == b`, -1 if `a < b`, +1 if `a > b`.
    /// If `a` == b[:a.length]`, and `a.length < b.length`, returns -1.
    function cmp(string memory a, string memory b) internal pure returns (int256) {
        bytes memory x = bytes(a);
        bytes memory y = bytes(b);
        uint256 n = x.length < y.length ? x.length : y.length;
        // Words compare as big-endian integers, so the first differing word
        // orders the strings. A common prefix shorter than a word is masked to
        // its length; a longer one ends with the word ending at its end, whose
        // bytes already compared are equal.
        uint256 u;
        uint256 v;
        if (n < 32) {
            uint256 mask = ~(type(uint256).max >> (n << 3));
            u = uint256(bytes32(x)) & mask;
            v = uint256(bytes32(y)) & mask;
        } else {
            for (uint256 i; i + 32 < n; i += 32) {
                uint256 p = uint256(Bytes.readBytes32(x, i));
                uint256 q = uint256(Bytes.readBytes32(y, i));
                if (p != q) return p < q ? int256(-1) : int256(1);
            }
            u = uint256(Bytes.readBytes32(x, n - 32));
            v = uint256(Bytes.readBytes32(y, n - 32));
        }
        if (u != v) return u < v ? int256(-1) : int256(1);
        if (x.length == y.length) return 0;
        return x.length < y.length ? int256(-1) : int256(1);
    }

    /// @dev Packs a single string with its length into a single word.
    /// Returns `bytes32(0)` if the length is zero or greater than 31.
    function packOne(string memory a) internal pure returns (bytes32 result) {
        return Strings.packOne(a);
    }

    /// @dev Unpacks a string packed using {packOne}.
    /// Returns the empty string if `packed` is `bytes32(0)`.
    /// If `packed` is not an output of {packOne}, the output behavior is undefined.
    function unpackOne(bytes32 packed) internal pure returns (string memory result) {
        return Strings.unpackOne(packed);
    }

    /// @dev Packs two strings with their lengths into a single word.
    /// Returns `bytes32(0)` if combined length is zero or greater than 30.
    function packTwo(string memory a, string memory b) internal pure returns (bytes32 result) {
        return Strings.packTwo(a, b);
    }

    /// @dev Unpacks strings packed using {packTwo}.
    /// Returns the empty strings if `packed` is `bytes32(0)`.
    /// If `packed` is not an output of {packTwo}, the output behavior is undefined.
    function unpackTwo(bytes32 packed)
        internal
        pure
        returns (string memory resultA, string memory resultB)
    {
        return Strings.unpackTwo(packed);
    }
}
