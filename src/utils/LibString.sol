// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Arrays} from "solar:core/v1/Arrays.sol";
import {Build} from "solar:core/v1/Build.sol";
import {Bytes} from "solar:core/v1/Bytes.sol";
import {Hash} from "solar:core/v1/Hash.sol";
import {Hex} from "solar:core/v1/codecs/Hex.sol";
import {Math} from "solar:core/v1/Math.sol";
import {Return} from "solar:core/v1/Return.sol";
import {Strings} from "solar:core/v1/Strings.sol";
import {LibBytes} from "./LibBytes.sol";

/// @notice Checked Solidity replacements for the LibString APIs.
/// @dev `StringStorage` keeps the original's packed layout through the
/// storage operations of `LibBytes`, and `directReturn` ends the call through
/// the compiler-owned `Return` module. `bytesStorage` is absent: it retypes a
/// storage reference in a `pure` function, and reaching the nested
/// `BytesStorage` without assembly is a storage access, so only a `view`
/// function could return it.
library LibString {
    /// @dev Goated string storage struct that totally MOGs, no cap, fr.
    /// Uses less gas and bytecode than Solidity's native string storage. It's meta af.
    /// Packs length with the first 31 bytes if <255 bytes, so it’s mad tight.
    struct StringStorage {
        LibBytes.BytesStorage _spacer;
    }

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
    uint256 private constant LANES_01 =
        0x0101010101010101010101010101010101010101010101010101010101010101;

    /// @dev The top bit of every byte lane.
    uint256 private constant _HIGH_BITS =
        0x8080808080808080808080808080808080808080808080808080808080808080;

    /// @dev Sets the value of the string storage `$` to `s`.
    function set(StringStorage storage $, string memory s) internal {
        LibBytes.set($._spacer, bytes(s));
    }

    /// @dev Sets the value of the string storage `$` to `s`.
    function setCalldata(StringStorage storage $, string calldata s) internal {
        LibBytes.setCalldata($._spacer, bytes(s));
    }

    /// @dev Sets the value of the string storage `$` to the empty string.
    function clear(StringStorage storage $) internal {
        delete $._spacer;
    }

    /// @dev Returns whether the value stored is `$` is the empty string "".
    function isEmpty(StringStorage storage $) internal view returns (bool) {
        return LibBytes.isEmpty($._spacer);
    }

    /// @dev Returns the length of the value stored in `$`.
    function length(StringStorage storage $) internal view returns (uint256) {
        return LibBytes.length($._spacer);
    }

    /// @dev Returns the value stored in `$`.
    function get(StringStorage storage $) internal view returns (string memory) {
        return string(LibBytes.get($._spacer));
    }

    /// @dev Returns the uint8 at index `i`. If out-of-bounds, returns 0.
    function uint8At(StringStorage storage $, uint256 i) internal view returns (uint8) {
        return LibBytes.uint8At($._spacer, i);
    }

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
        if (!Build.gasFirst()) {
            // The lowercase spelling, then each letter uppercased whose nibble of the hash
            // of the forty digits, counted from the top, is at least eight.
            bytes memory text = bytes(toHexString(value));
            uint256 digest = uint256(Hash.keccak256Range(text, 2, 40));
            for (uint256 i = 2; i < 42; ++i) {
                uint8 char = uint8(text[i]);
                if (char > 0x39 && (digest >> (260 - 4 * i)) & 15 > 7) {
                    text[i] = bytes1(char - 0x20);
                }
            }
            return string(text);
        }
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
        return n.length <= s.length && Bytes.equalsAt(s, 0, n);
    }

    /// @dev Returns whether `subject` ends with `needle`.
    function endsWith(string memory subject, string memory needle) internal pure returns (bool) {
        bytes memory s = bytes(subject);
        bytes memory n = bytes(needle);
        return n.length <= s.length && Bytes.equalsAt(s, s.length - n.length, n);
    }

    /// @dev Returns `subject` repeated `times`.
    function repeat(string memory subject, uint256 times) internal pure returns (string memory) {
        return Strings.repeat(subject, times);
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
        // The end is the length itself, so only the start needs a bound.
        bytes memory s = bytes(subject);
        if (start >= s.length) return "";
        bytes memory out = new bytes(s.length - start);
        Bytes.copyInto(out, 0, s, start, s.length - start);
        return string(out);
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

    /// @dev Returns the length of a small string up to its first null byte,
    /// from the string's `_nullTail` marks.
    function _smallStringLength(uint256 tail) private pure returns (uint256) {
        // One mark for each byte from the first zero byte on; the bytes before
        // it are the string. Multiplying the marks, one per byte, by a one in
        // every byte sums them into the top byte, modulo `2**256` on purpose:
        // no byte of the product exceeds 32, so no sum carries into another.
        return 32 - (Math.wrappingMul(tail >> 7, LANES_01) >> 248);
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

    /// @dev Keeps the bytes before the first null byte, from the string's
    /// `_nullTail` marks: a marked byte minus its mark shifted to the byte's
    /// low bit leaves the seven bits below the mark, which the mark completes
    /// to the whole byte. A shift never exceeds its operand, so the difference
    /// cannot wrap.
    function _smallStringMask(uint256 tail) private pure returns (uint256) {
        return ~((tail - (tail >> 7)) | tail);
    }

    /// @dev The index of the first null byte of `s`, or 32 without one.
    function _nullIndex(bytes32 s) private pure returns (uint256 n) {
        while (n < 32 && s[n] != 0) ++n;
    }

    /// @dev The first `n` bytes of `s`, with the rest cleared.
    function _smallStringPrefix(bytes32 s, uint256 n) private pure returns (bytes32) {
        return s & ~bytes32(type(uint256).max >> (n << 3));
    }

    /// @dev Returns a string from a small bytes32 string.
    /// `s` must be null-terminated, or behavior will be undefined.
    function fromSmallString(bytes32 s) internal pure returns (string memory result) {
        if (!Build.gasFirst()) {
            // The bytes before the first null, found by a scan.
            uint256 n = _nullIndex(s);
            bytes memory text = abi.encodePacked(_smallStringPrefix(s, n));
            Arrays.truncate(text, n);
            return string(text);
        }
        // A null in the first eight bytes is found by testing them in turn,
        // which costs less than spreading and counting its marks. After eight
        // tests, spreading the marks still costs less than scanning to the
        // null a byte at a time, so no length pays more than a scan.
        if (s[0] == 0) return "";
        bytes32 word;
        uint256 length;
        if (s[1] == 0) (word, length) = (s & bytes32(bytes1(0xff)), 1);
        else if (s[2] == 0) (word, length) = (s & bytes32(bytes2(0xffff)), 2);
        else if (s[3] == 0) (word, length) = (s & bytes32(bytes3(0xffffff)), 3);
        else if (s[4] == 0) (word, length) = (s & bytes32(bytes4(0xffffffff)), 4);
        else if (s[5] == 0) (word, length) = (s & bytes32(bytes5(0xffffffffff)), 5);
        else if (s[6] == 0) (word, length) = (s & bytes32(bytes6(0xffffffffffff)), 6);
        else if (s[7] == 0) (word, length) = (s & bytes32(bytes7(0xffffffffffffff)), 7);
        else {
            uint256 tail = _nullTail(s);
            (word, length) = (s & bytes32(_smallStringMask(tail)), _smallStringLength(tail));
        }
        // The word is written whole, with the bytes from the null on cleared,
        // and the string then shortened to them.
        bytes memory out = abi.encodePacked(word);
        Arrays.truncate(out, length);
        return string(out);
    }

    /// @dev Returns the small string, with all bytes after the first null byte zeroized.
    function normalizeSmallString(bytes32 s) internal pure returns (bytes32 result) {
        if (!Build.gasFirst()) return _smallStringPrefix(s, _nullIndex(s));
        // A null in the first seven bytes is found by testing them in turn,
        // which costs less than clearing from it with word operations; after
        // seven tests the word path costs less than a byte scan to the null.
        if (s[0] == 0) return 0;
        if (s[1] == 0) return s & bytes32(bytes1(0xff));
        if (s[2] == 0) return s & bytes32(bytes2(0xffff));
        if (s[3] == 0) return s & bytes32(bytes3(0xffffff));
        if (s[4] == 0) return s & bytes32(bytes4(0xffffffff));
        if (s[5] == 0) return s & bytes32(bytes5(0xffffffffff));
        if (s[6] == 0) return s & bytes32(bytes6(0xffffffffffff));
        // Otherwise each byte from the first zero byte on is cleared, spelled
        // out here so that the word path pays for no helper calls where the
        // helpers are shared.
        uint256 x = uint256(s);
        uint256 tail = ~(x | ((x & LANES_7F) + LANES_7F) | LANES_7F);
        tail |= tail >> 8;
        tail |= tail >> 16;
        tail |= tail >> 32;
        tail |= tail >> 64;
        tail |= tail >> 128;
        return s & bytes32(~((tail - (tail >> 7)) | tail));
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
        uint256 tail = _nullTail(b);
        // `b`'s null marks must start exactly where `a` ends.
        if (s.length > 32 || tail != _HIGH_BITS >> (s.length * 8)) return false;
        // The conversion pads `a` with zeros after its bytes, and the mask
        // clears `b` from its first null byte on.
        return bytes32(s) == b & bytes32(_smallStringMask(tail));
    }

    /// @dev Returns 0 if `a == b`, -1 if `a < b`, +1 if `a > b`.
    /// If `a` == b[:a.length]`, and `a.length < b.length`, returns -1.
    function cmp(string memory a, string memory b) internal pure returns (int256) {
        bytes memory x = bytes(a);
        bytes memory y = bytes(b);
        uint256 n = x.length < y.length ? x.length : y.length;
        if (!Build.gasFirst()) {
            // The first differing byte orders the strings, and the shorter
            // one comes first when none differs.
            for (uint256 i; i < n; ++i) {
                if (x[i] != y[i]) return x[i] < y[i] ? int256(-1) : int256(1);
            }
            if (x.length == y.length) return 0;
            return x.length < y.length ? int256(-1) : int256(1);
        }
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

    /// @dev Directly returns `a` without copying.
    function directReturn(string memory a) internal pure {
        Return.abiEncoded(a);
    }
}
