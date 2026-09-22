// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Arrays} from "solar:core/v1/Arrays.sol";
import {Bits} from "solar:core/v1/Bits.sol";
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
    bytes16 private constant HEX = "0123456789abcdef";

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
    uint256 private constant SPREAD_ASCII_A =
        0x4141414141414141414141414141414141414141414141414141414141414141;
    uint256 private constant SPREAD_20 =
        0x2020202020202020202020202020202020202020202020202020202020202020;
    uint256 private constant SPREAD_22 =
        0x2222222222222222222222222222222222222222222222222222222222222222;
    uint256 private constant SPREAD_5C =
        0x5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c;
    uint256 private constant LANES_7F =
        0x7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f;

    /// @dev Set bit per byte value that `escapeHTML` rewrites: `"`, `&`, `'`,
    /// `<` and `>`. Testing membership with one shift keeps every other byte
    /// out of the escape helper.
    uint256 private constant _HTML_ESCAPED =
        (1 << 0x22) | (1 << 0x26) | (1 << 0x27) | (1 << 0x3c) | (1 << 0x3e);

    /// @dev Set bit per byte value that `escapeJSON` rewrites: every control
    /// byte below 0x20, plus `"` and `\`.
    uint256 private constant _JSON_ESCAPED = 0xffffffff | (1 << 0x22) | (1 << 0x5c);

    /// @dev Set bit per byte accepted unchanged by `encodeURIComponent`.
    uint256 private constant _URI_UNRESERVED = 0x47fffffe87fffffe03ff678200000000;

    /// @dev The top bit of every byte lane.
    uint256 private constant _HIGH_BITS =
        0x8080808080808080808080808080808080808080808080808080808080808080;

    /// @dev The length of the rune a high lead byte starts, indexed by its top six bits
    /// less 32: two for 0x80 to 0xdf, then three, four, five and six.
    bytes32 private constant _RUNE_LENGTHS =
        0x0202020202020202020202020202020202020202020202020303030304040506;

    function toString(uint256 value) internal pure returns (string memory result) {
        // Halving the remaining magnitude costs at most seven steps, where
        // dividing by ten once per digit costs up to seventy-eight.
        uint256 length = 1;
        uint256 x = value;
        if (x >= 1e64) {
            x /= 1e64;
            length += 64;
        }
        if (x >= 1e32) {
            x /= 1e32;
            length += 32;
        }
        if (x >= 1e16) {
            x /= 1e16;
            length += 16;
        }
        if (x >= 1e8) {
            x /= 1e8;
            length += 8;
        }
        if (x >= 1e4) {
            x /= 1e4;
            length += 4;
        }
        if (x >= 1e2) {
            x /= 1e2;
            length += 2;
        }
        if (x >= 10) ++length;
        bytes memory out = new bytes(length);
        do {
            --length;
            out[length] = bytes1(uint8(48 + value % 10));
            value /= 10;
        } while (length != 0);
        return string(out);
    }

    function toString(int256 value) internal pure returns (string memory result) {
        if (value >= 0) return toString(uint256(value));
        return string.concat("-", toString(uint256(-(value + 1)) + 1));
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
        bytes memory b = bytes(s);
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
        bytes memory b = bytes(s);
        uint256 n = b.length;
        for (uint256 i; i < n;) {
            // Every byte below 0x80 is one rune, so a word of them is thirty-two runes, and
            // the bytes before the first high byte of a mixed word are one rune each too.
            // Past the last full word, the last word of the string is read instead, with the
            // bytes already counted shifted out of it.
            if (n >= 32) {
                uint256 high;
                if (i + 32 <= n) {
                    high = uint256(Bytes.readBytes32(b, i)) & _HIGH_BITS;
                    if (high == 0) {
                        i += 32;
                        result += 32;
                        continue;
                    }
                } else {
                    high =
                        (uint256(Bytes.readBytes32(b, n - 32)) << ((i + 32 - n) << 3)) & _HIGH_BITS;
                    if (high == 0) {
                        result += n - i;
                        break;
                    }
                }
                uint256 ascii = Bits.leadingZeros(high) >> 3;
                i += ascii;
                result += ascii;
            }
            // A high byte leads a rune of the length its top six bits declare, the same
            // length for a stray continuation byte as for a two-byte lead. A run of them is
            // stepped through here before the next word is probed.
            uint256 c = uint8(b[i]);
            while (true) {
                i += c < 0x80 ? 1 : uint8(_RUNE_LENGTHS[(c >> 2) - 32]);
                ++result;
                if (i >= n) break;
                c = uint8(b[i]);
                if (c < 0x80) break;
            }
        }
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
        // `0x80` marks each zero byte: a byte carries into its own high bit
        // exactly when it is not zero, and only the high bits are kept. The
        // first zero byte is the highest mark.
        uint256 x = uint256(s);
        uint256 zeros = ~(x | ((x & LANES_7F) + LANES_7F) | LANES_7F);
        return zeros == 0 ? 32 : Bits.leadingZeros(zeros) >> 3;
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
        uint256 n = _smallStringLength(s);
        if (n == 32) return s;
        return s & bytes32(type(uint256).max << ((32 - n) * 8));
    }

    /// @dev Returns the string as a normalized null-terminated small string.
    function toSmallString(string memory s) internal pure returns (bytes32 result) {
        bytes memory b = bytes(s);
        if (b.length > 32) revert TooBigForSmallString();
        return bytes32(b);
    }

    /// @dev Returns the HTML escape of the byte `c`, or an empty string when it needs none.
    /// @dev Returns the HTML escape of the byte `c` left-aligned in a word,
    /// with its length, or a zero length when `c` needs none.
    /// A word costs nothing to return, where a `bytes` would allocate once per
    /// scanned byte.
    function _htmlEscape(bytes1 c) private pure returns (bytes32 seq, uint256 len) {
        if (c == "\"") return (bytes32("&quot;"), 6);
        if (c == "&") return (bytes32("&amp;"), 5);
        if (c == "'") return (bytes32("&#39;"), 5);
        if (c == "<") return (bytes32("&lt;"), 4);
        if (c == ">") return (bytes32("&gt;"), 4);
        return (bytes32(0), 0);
    }

    /// @dev Escapes the string to be used within HTML tags.
    function escapeHTML(string memory s) internal pure returns (string memory result) {
        bytes memory b = bytes(s);
        // Six bytes is the longest entity. Write into that capacity once and
        // hand the used prefix back, avoiding a complete counting pass.
        bytes memory out = new bytes(b.length * 6);
        uint256 o;
        for (uint256 i; i < b.length; ++i) {
            if ((_HTML_ESCAPED >> uint8(b[i])) & 1 == 0) {
                out[o] = b[i];
                ++o;
                continue;
            }
            (bytes32 seq, uint256 escaped) = _htmlEscape(b[i]);
            if (escaped == 4) Bytes.writeBytes4(out, o, bytes4(seq));
            else if (escaped == 5) Bytes.writeBytes5(out, o, bytes5(seq));
            else Bytes.writeBytes6(out, o, bytes6(seq));
            o += escaped;
        }
        Arrays.truncate(out, o);
        return string(out);
    }

    /// @dev Returns the JSON escape of the byte `c`, or an empty string when it needs none.
    /// @dev Returns the JSON escape of the byte `c` left-aligned in a word,
    /// with its length, or a zero length when `c` needs none.
    function _jsonEscape(bytes1 c) private pure returns (bytes32 seq, uint256 len) {
        if (c >= 0x20) {
            if (c == "\"") return (bytes32("\\\""), 2);
            if (c == "\\") return (bytes32("\\\\"), 2);
            return (bytes32(0), 0);
        }
        if (c == 0x08) return (bytes32("\\b"), 2);
        if (c == 0x09) return (bytes32("\\t"), 2);
        if (c == 0x0a) return (bytes32("\\n"), 2);
        if (c == 0x0c) return (bytes32("\\f"), 2);
        if (c == 0x0d) return (bytes32("\\r"), 2);
        // "\u00" with the two hex digits of `c` written into bytes four and five.
        uint256 x = uint8(c);
        return (
            bytes32(
                uint256(bytes32("\\u00")) | (uint256(uint8(HEX[x >> 4])) << 216)
                    | (uint256(uint8(HEX[x & 15])) << 208)
            ),
            6
        );
    }

    /// @dev Escapes the string to be used within double-quotes in a JSON.
    /// If `addDoubleQuotes` is true, the result will be enclosed in double-quotes.
    function escapeJSON(string memory s, bool addDoubleQuotes)
        internal
        pure
        returns (string memory result)
    {
        bytes memory b = bytes(s);
        uint256 n = b.length;
        // Six bytes is the longest escape, so six a byte always suffice; the buffer is cut to
        // what one pass writes rather than sized by a pass that counts first.
        bytes memory out = new bytes((addDoubleQuotes ? 2 : 0) + n * 6);
        uint256 o;
        if (addDoubleQuotes) {
            out[0] = "\"";
            o = 1;
        }
        // A word without a control character, quote or backslash is copied whole, and so is
        // a tail without one, probed through the last word of the string; the bytes of any
        // other word or tail are written one at a time.
        for (uint256 i; i < n;) {
            (uint256 end, uint256 word, bool probed) = _jsonWindow(b, i);
            if (probed && _jsonPlain(word)) {
                Bytes.copyInto(out, o, b, i, end - i);
                o += end - i;
                i = end;
                continue;
            }
            while (i < end) {
                if ((_JSON_ESCAPED >> uint8(b[i])) & 1 == 0) {
                    out[o] = b[i];
                    ++o;
                } else {
                    (bytes32 seq, uint256 escaped) = _jsonEscape(b[i]);
                    if (escaped == 2) {
                        Bytes.writeBytes2(out, o, bytes2(seq));
                    } else {
                        Bytes.writeBytes6(out, o, bytes6(seq));
                    }
                    o += escaped;
                }
                ++i;
            }
        }
        if (addDoubleQuotes) {
            out[o] = "\"";
            ++o;
        }
        Arrays.truncate(out, o);
        return string(out);
    }

    /// @dev The next window of `b` from `i`: the end of the word starting there and that word
    /// when a whole one remains; otherwise the end of `b` and, when `b` has thirty-two bytes
    /// for it to be read through, the tail as `_jsonTail` gives it. A window of fewer than
    /// thirty-two bytes at the front of a shorter `b` has no word to probe.
    function _jsonWindow(bytes memory b, uint256 i)
        private
        pure
        returns (uint256 end, uint256 word, bool probed)
    {
        uint256 n = b.length;
        end = i + 32;
        if (end <= n) return (end, uint256(Bytes.readBytes32(b, i)), true);
        if (n >= 32) return (n, _jsonTail(b, i), true);
        return (n, 0, false);
    }

    /// @dev The bytes of `b` from `i`, fewer than thirty-two of them, read through the last
    /// word of `b`, where they are its low lanes; the lanes above them are given a letter, so
    /// that `_jsonPlain` answers for the tail alone. Only for `b` of at least thirty-two bytes.
    function _jsonTail(bytes memory b, uint256 i) private pure returns (uint256) {
        uint256 tail = b.length - i;
        uint256 word = uint256(Bytes.readBytes32(b, b.length - 32));
        uint256 above = (32 - tail) << 3;
        return ((word << above) >> above) | (SPREAD_ASCII_A << (tail << 3));
    }

    /// @dev Whether no byte of `word` needs escaping in JSON: none below 0x20, none a quote
    /// and none a backslash. A lane below 0x20 borrows when 0x20 is taken from it, and a
    /// lane equal to a byte is zero after xor with it and borrows when one is taken; either
    /// leaves a top bit that the lane itself did not have. Borrows can spill into higher
    /// lanes, so the result tells only whether some lane matched, which is all that is asked.
    function _jsonPlain(uint256 word) private pure returns (bool) {
        uint256 low = Math.wrappingSub(word, SPREAD_20) & ~word;
        uint256 quote = word ^ SPREAD_22;
        quote = Math.wrappingSub(quote, SPREAD_1) & ~quote;
        uint256 backslash = word ^ SPREAD_5C;
        backslash = Math.wrappingSub(backslash, SPREAD_1) & ~backslash;
        return (low | quote | backslash) & _HIGH_BITS == 0;
    }

    /// @dev Escapes the string to be used within double-quotes in a JSON.
    function escapeJSON(string memory s) internal pure returns (string memory result) {
        result = escapeJSON(s, false);
    }

    /// @dev Returns whether the byte `c` is unreserved by `encodeURIComponent`.
    function _uriUnreserved(uint8 c) private pure returns (bool) {
        return ((_URI_UNRESERVED >> c) & 1) != 0;
    }

    /// @dev Encodes `s` so that it can be safely used in a URI,
    /// just like `encodeURIComponent` in JavaScript.
    /// See: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/encodeURIComponent
    /// See: https://datatracker.ietf.org/doc/html/rfc2396
    /// See: https://datatracker.ietf.org/doc/html/rfc3986
    function encodeURIComponent(string memory s) internal pure returns (string memory result) {
        bytes memory b = bytes(s);
        bytes16 upperHex = "0123456789ABCDEF";
        // Every input byte needs at most `%XX`. Write once into that capacity
        // and truncate the logical length instead of scanning twice.
        bytes memory out = new bytes(b.length * 3);
        uint256 o;
        for (uint256 i; i < b.length; ++i) {
            uint8 c = uint8(b[i]);
            if (_uriUnreserved(c)) {
                out[o++] = b[i];
            } else {
                uint24 encoded = (uint24(uint8(bytes1("%"))) << 16)
                    | (uint24(uint8(upperHex[c >> 4])) << 8) | uint24(uint8(upperHex[c & 15]));
                Bytes.writeBytes3(out, o, bytes3(encoded));
                o += 3;
            }
        }
        Arrays.truncate(out, o);
        return string(out);
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
        for (uint256 i; i < n; ++i) {
            if (x[i] != y[i]) return x[i] < y[i] ? int256(-1) : int256(1);
        }
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
