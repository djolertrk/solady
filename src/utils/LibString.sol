// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LibBytes} from "./LibBytes.sol";

/// @notice Checked Solidity replacements for the LibString APIs.
/// @dev `StringStorage` keeps the original's packed layout through the
/// storage operations of `LibBytes`, and `directReturn` ends the call through
/// the trusted `_directReturn`. `bytesStorage` is absent: it retypes a
/// storage reference in a `pure` function, and reaching the nested
/// `BytesStorage` without assembly is a storage access, so only a `view`
/// function could return it.
/// @custom:solar-safe memory arithmetic
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
        return _toString(value);
    }

    function toString(int256 value) internal pure returns (string memory result) {
        return _toString(value);
    }

    function toHexStringNoPrefix(uint256 value, uint256 byteCount)
        internal
        pure
        returns (string memory result)
    {
        return _toHexStringNoPrefix(value, byteCount);
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
        return _toHexString(value, byteCount);
    }

    function toHexStringNoPrefix(uint256 value) internal pure returns (string memory result) {
        return _toHexStringNoPrefix(value);
    }

    function toHexString(uint256 value) internal pure returns (string memory result) {
        return _toHexString(value);
    }

    function toMinimalHexStringNoPrefix(uint256 value)
        internal
        pure
        returns (string memory result)
    {
        return _toMinimalHexStringNoPrefix(value);
    }

    function toMinimalHexString(uint256 value) internal pure returns (string memory result) {
        return _toMinimalHexString(value);
    }

    function toHexStringNoPrefix(address value) internal pure returns (string memory result) {
        return toHexStringNoPrefix(uint160(value), 20);
    }

    function toHexString(address value) internal pure returns (string memory result) {
        return toHexString(uint160(value), 20);
    }

    function toHexStringNoPrefix(bytes memory raw) internal pure returns (string memory result) {
        return _hexEncode(raw);
    }

    function toHexString(bytes memory raw) internal pure returns (string memory result) {
        return _hexEncodePrefixed(raw);
    }

    function is7BitASCII(string memory s) internal pure returns (bool result) {
        // A word at a time: any byte with its top bit set fails the whole word.
        bytes memory b = bytes(s);
        uint256 n = b.length;
        uint256 i;
        while (i + 32 <= n) {
            if (uint256(_readBytes32(b, i)) & _HIGH_BITS != 0) return false;
            i += 32;
        }
        if (i < n) return uint256(_readBytesN(b, i, n - i)) & _HIGH_BITS == 0;
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
        return _runeCount(s);
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
            _truncate(short, n);
            return string(short);
        }
        bytes memory out = new bytes(n);
        uint256 i;
        for (; i + 32 <= n; i += 32) {
            uint256 word = uint256(_readBytes32(b, i));
            _writeBytes32(out, i, bytes32(word ^ _caseFlips(word, flip)));
        }
        // The last word ends at the end of the string, repeating bytes already
        // converted with the same result.
        if (i < n) {
            uint256 word = uint256(_readBytes32(b, n - 32));
            _writeBytes32(out, n - 32, bytes32(word ^ _caseFlips(word, flip)));
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
        _writeBytes32(out, 2, bytes32(head));
        _writeBytes8(out, 34, bytes8(bytes32(tail)));
        // A character is uppercased when it is a letter and its nibble of the hash of the
        // lowercase digits is at least eight: nibble by nibble, the hash's top sixteen bytes
        // line up with the head and the next four with the tail.
        uint256 hash = uint256(_keccak256Range(out, 2, 40));
        _writeBytes32(out, 2, bytes32(_checksumCase(head, _nibbles(hash >> 128))));
        _writeBytes8(
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
        return _replace(subject, needle, replacement);
    }

    /// @dev Returns the byte index of the first location of `needle` in `subject`,
    /// needleing from left to right, starting from `from`.
    /// Returns `NOT_FOUND` (i.e. `type(uint256).max`) if the `needle` is not found.
    function indexOf(string memory subject, string memory needle, uint256 from)
        internal
        pure
        returns (uint256)
    {
        return _indexOf(subject, needle, from);
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
        return _lastIndexOf(subject, needle, from);
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
        // The range's hash against the needle's, equal exactly when the bytes
        // are, barring a keccak collision.
        return n.length <= s.length && _keccak256Range(s, 0, n.length) == keccak256(n);
    }

    /// @dev Returns whether `subject` ends with `needle`.
    function endsWith(string memory subject, string memory needle) internal pure returns (bool) {
        bytes memory s = bytes(subject);
        bytes memory n = bytes(needle);
        return n.length <= s.length
            && _keccak256Range(s, s.length - n.length, n.length) == keccak256(n);
    }

    /// @dev Returns `subject` repeated `times`.
    function repeat(string memory subject, uint256 times) internal pure returns (string memory) {
        return _repeat(subject, times);
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
        _copyInto(out, 0, s, start, end - start);
        return string(out);
    }

    /// @dev Returns a copy of `subject` sliced from `start` to the end of the string.
    /// `start` is a byte offset.
    function slice(string memory subject, uint256 start) internal pure returns (string memory) {
        // The end is the length itself, so only the start needs a bound.
        bytes memory s = bytes(subject);
        if (start >= s.length) return "";
        bytes memory out = new bytes(s.length - start);
        _copyInto(out, 0, s, start, s.length - start);
        return string(out);
    }

    /// @dev Returns all the indices of `needle` in `subject`.
    /// The indices are byte offsets.
    function indicesOf(string memory subject, string memory needle)
        internal
        pure
        returns (uint256[] memory)
    {
        return _indicesOf(subject, needle);
    }

    /// @dev Returns an arrays of strings based on the `delimiter` inside of the `subject` string.
    function split(string memory subject, string memory delimiter)
        internal
        pure
        returns (string[] memory)
    {
        return _split(subject, delimiter);
    }

    /// @dev Returns the length of a small string up to its first null byte,
    /// from the string's `_nullTail` marks.
    function _smallStringLength(uint256 tail) private pure returns (uint256) {
        // One mark for each byte from the first zero byte on; the bytes before
        // it are the string. Multiplying the marks, one per byte, by a one in
        // every byte sums them into the top byte, modulo `2**256` on purpose:
        // no byte of the product exceeds 32, so no sum carries into another.
        return 32 - (_rawMul(tail >> 7, LANES_01) >> 248);
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
        _truncate(out, length);
        return string(out);
    }

    /// @dev Returns the small string, with all bytes after the first null byte zeroized.
    function normalizeSmallString(bytes32 s) internal pure returns (bytes32 result) {
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
        return _escapeHTML(s);
    }

    /// @dev Escapes the string to be used within double-quotes in a JSON.
    /// If `addDoubleQuotes` is true, the result will be enclosed in double-quotes.
    function escapeJSON(string memory s, bool addDoubleQuotes)
        internal
        pure
        returns (string memory result)
    {
        return _escapeJSON(s, addDoubleQuotes);
    }

    /// @dev Escapes the string to be used within double-quotes in a JSON.
    function escapeJSON(string memory s) internal pure returns (string memory result) {
        return _escapeJSON(s);
    }

    /// @dev Encodes `s` so that it can be safely used in a URI,
    /// just like `encodeURIComponent` in JavaScript.
    /// See: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/encodeURIComponent
    /// See: https://datatracker.ietf.org/doc/html/rfc2396
    /// See: https://datatracker.ietf.org/doc/html/rfc3986
    function encodeURIComponent(string memory s) internal pure returns (string memory result) {
        return _encodeURIComponent(s);
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
                uint256 p = uint256(_readBytes32(x, i));
                uint256 q = uint256(_readBytes32(y, i));
                if (p != q) return p < q ? int256(-1) : int256(1);
            }
            u = uint256(_readBytes32(x, n - 32));
            v = uint256(_readBytes32(y, n - 32));
        }
        if (u != v) return u < v ? int256(-1) : int256(1);
        if (x.length == y.length) return 0;
        return x.length < y.length ? int256(-1) : int256(1);
    }

    /// @dev Packs a single string with its length into a single word.
    /// Returns `bytes32(0)` if the length is zero or greater than 31.
    function packOne(string memory a) internal pure returns (bytes32 result) {
        return _packOne(a);
    }

    /// @dev Unpacks a string packed using {packOne}.
    /// Returns the empty string if `packed` is `bytes32(0)`.
    /// If `packed` is not an output of {packOne}, the output behavior is undefined.
    function unpackOne(bytes32 packed) internal pure returns (string memory result) {
        return _unpackOne(packed);
    }

    /// @dev Packs two strings with their lengths into a single word.
    /// Returns `bytes32(0)` if combined length is zero or greater than 30.
    function packTwo(string memory a, string memory b) internal pure returns (bytes32 result) {
        return _packTwo(a, b);
    }

    /// @dev Unpacks strings packed using {packTwo}.
    /// Returns the empty strings if `packed` is `bytes32(0)`.
    /// If `packed` is not an output of {packTwo}, the output behavior is undefined.
    function unpackTwo(bytes32 packed)
        internal
        pure
        returns (string memory resultA, string memory resultB)
    {
        return _unpackTwo(packed);
    }

    /// @dev Directly returns `a` without copying.
    function directReturn(string memory a) internal pure {
        _directReturn(a);
    }

    /// @dev Lowercase hexadecimal digits.
    bytes16 private constant _DIGITS = "0123456789abcdef";

    /// @dev Uppercase hexadecimal digits.
    bytes16 private constant _UPPER_DIGITS = "0123456789ABCDEF";

    /// @dev One bit per byte a URI component keeps: letters, digits and `-_.!~*'()`.
    uint256 private constant _URI_UNRESERVED = 0x47fffffe87fffffe03ff678200000000;

    /// @dev `value` in decimal. Halving the remaining magnitude finds the
    /// length in at most seven steps, where dividing by ten once per digit
    /// costs up to seventy-eight.
    function _toString(uint256 value) private pure returns (string memory) {
        uint256 n = 1;
        uint256 x = value;
        if (x >= 1e64) {
            x /= 1e64;
            n += 64;
        }
        if (x >= 1e32) {
            x /= 1e32;
            n += 32;
        }
        if (x >= 1e16) {
            x /= 1e16;
            n += 16;
        }
        if (x >= 1e8) {
            x /= 1e8;
            n += 8;
        }
        if (x >= 1e4) {
            x /= 1e4;
            n += 4;
        }
        if (x >= 1e2) {
            x /= 1e2;
            n += 2;
        }
        if (x >= 10) ++n;
        bytes memory out = new bytes(n);
        do {
            --n;
            out[n] = bytes1(uint8(48 + value % 10));
            value /= 10;
        } while (n != 0);
        return string(out);
    }

    /// @dev `value` in decimal, with a leading `-` when negative.
    function _toString(int256 value) private pure returns (string memory) {
        if (value >= 0) return _toString(uint256(value));
        // The magnitude of the most negative value does not fit `int256`.
        uint256 magnitude = value == type(int256).min ? uint256(1) << 255 : uint256(-value);
        return string.concat("-", _toString(magnitude));
    }

    /// @dev `s` with every character JSON requires escaped, without quotes.
    function _escapeJSON(string memory s) private pure returns (string memory) {
        return _escapeJSON(s, false);
    }

    /// @dev `s` with the quote, the backslash and the control characters
    /// escaped, as the short forms where JSON has them and `\u00XX` elsewhere,
    /// enclosed in double quotes when `addDoubleQuotes`. The output is built at
    /// its largest size, six characters per input byte, then cut down.
    function _escapeJSON(string memory s, bool addDoubleQuotes)
        private
        pure
        returns (string memory)
    {
        bytes memory input = bytes(s);
        bytes memory out = new bytes(input.length * 6 + 2);
        uint256 o;
        if (addDoubleQuotes) out[o++] = '"';
        for (uint256 i; i < input.length; ++i) {
            bytes1 c = input[i];
            if (c == '"' || c == "\\") {
                out[o++] = "\\";
                out[o++] = c;
            } else if (uint8(c) >= 0x20) {
                out[o++] = c;
            } else {
                out[o++] = "\\";
                if (c == 0x08) {
                    out[o++] = "b";
                } else if (c == 0x09) {
                    out[o++] = "t";
                } else if (c == 0x0a) {
                    out[o++] = "n";
                } else if (c == 0x0c) {
                    out[o++] = "f";
                } else if (c == 0x0d) {
                    out[o++] = "r";
                } else {
                    out[o++] = "u";
                    out[o++] = "0";
                    out[o++] = "0";
                    out[o++] = _DIGITS[uint8(c) >> 4];
                    out[o++] = _DIGITS[uint8(c) & 15];
                }
            }
        }
        if (addDoubleQuotes) out[o++] = '"';
        _truncate(out, o);
        return string(out);
    }

    /// @dev `s` with the characters HTML gives meaning to replaced by their
    /// entities: `&quot;`, `&amp;`, `&#39;`, `&lt;` and `&gt;`. Built at its
    /// largest size, six characters per input byte, then cut down.
    function _escapeHTML(string memory s) private pure returns (string memory) {
        bytes memory input = bytes(s);
        bytes memory out = new bytes(input.length * 6);
        uint256 o;
        for (uint256 i; i < input.length; ++i) {
            bytes1 c = input[i];
            if (c == '"') {
                o = _put(out, o, "&quot;", 6);
            } else if (c == "&") {
                o = _put(out, o, "&amp;", 5);
            } else if (c == "'") {
                o = _put(out, o, "&#39;", 5);
            } else if (c == "<") {
                o = _put(out, o, "&lt;", 4);
            } else if (c == ">") {
                o = _put(out, o, "&gt;", 4);
            } else {
                out[o++] = c;
            }
        }
        _truncate(out, o);
        return string(out);
    }

    /// @dev Writes the leading `count` bytes of `text` into `out` at `o` and
    /// returns the offset after them.
    function _put(bytes memory out, uint256 o, bytes32 text, uint256 count)
        private
        pure
        returns (uint256)
    {
        for (uint256 k; k < count; ++k) {
            out[o + k] = text[k];
        }
        return o + count;
    }

    /// @dev `s` as a URI component, like JavaScript's `encodeURIComponent`:
    /// every byte other than the letters, the digits and `-_.!~*'()` becomes
    /// `%` and two uppercase hexadecimal digits.
    function _encodeURIComponent(string memory s) private pure returns (string memory) {
        bytes memory input = bytes(s);
        bytes memory out = new bytes(input.length * 3);
        uint256 o;
        for (uint256 i; i < input.length; ++i) {
            bytes1 c = input[i];
            if ((_URI_UNRESERVED >> uint8(c)) & 1 != 0) {
                out[o++] = c;
            } else {
                out[o++] = "%";
                out[o++] = _UPPER_DIGITS[uint8(c) >> 4];
                out[o++] = _UPPER_DIGITS[uint8(c) & 15];
            }
        }
        _truncate(out, o);
        return string(out);
    }

    /// @dev `subject` with each non-overlapping occurrence of `needle`
    /// replaced by `replacement`.
    function _replace(string memory subject, string memory needle, string memory replacement)
        private
        pure
        returns (string memory)
    {
        bytes memory s = bytes(subject);
        bytes memory n = bytes(needle);
        bytes memory r = bytes(replacement);
        if (n.length > s.length) return subject;
        if (n.length == 0) {
            bytes memory expanded = new bytes(s.length + (s.length + 1) * r.length);
            uint256 o;
            for (uint256 i; i <= s.length; ++i) {
                _copyInto(expanded, o, r, 0, r.length);
                o += r.length;
                if (i < s.length) expanded[o++] = s[i];
            }
            return string(expanded);
        }
        uint256 width = n.length < 32 ? n.length : 32;
        bytes32 head = _readBytesN(n, 0, width);
        uint256 count;
        for (uint256 i; i + n.length <= s.length;) {
            if (_matchAt(s, i, n, head, width)) {
                ++count;
                i += n.length;
            } else {
                ++i;
            }
        }
        bytes memory out = new bytes(s.length + count * r.length - count * n.length);
        uint256 at;
        uint256 copied;
        uint256 o;
        while (at + n.length <= s.length) {
            if (_matchAt(s, at, n, head, width)) {
                _copyInto(out, o, s, copied, at - copied);
                o += at - copied;
                _copyInto(out, o, r, 0, r.length);
                o += r.length;
                at += n.length;
                copied = at;
            } else {
                ++at;
            }
        }
        _copyInto(out, o, s, copied, s.length - copied);
        return string(out);
    }

    /// @dev Whether `needle` occurs in `subject` at `at`, where `at + needle.length`
    /// fits the subject. `head` is the needle's first `width` bytes, `width`
    /// being its length up to a word: the word of the subject at `at` decides a
    /// needle of up to a word, and a longer one is confirmed by its hash, as the
    /// assembly does.
    /// @custom:solar-inline
    function _matchAt(bytes memory subject, uint256 at, bytes memory needle, bytes32 head, uint256 width)
        private
        pure
        returns (bool)
    {
        if (_readBytesN(subject, at, width) != head) return false;
        return needle.length <= 32 || _keccak256Range(subject, at, needle.length) == keccak256(needle);
    }

    /// @dev The byte offsets of each non-overlapping occurrence of `needle`.
    function _indicesOf(string memory subject, string memory needle)
        private
        pure
        returns (uint256[] memory)
    {
        bytes memory s = bytes(subject);
        bytes memory n = bytes(needle);
        if (n.length > s.length) return new uint256[](0);
        if (n.length == 0) {
            uint256[] memory every = new uint256[](s.length + 1);
            for (uint256 i; i <= s.length; ++i) every[i] = i;
            return every;
        }
        uint256 width = n.length < 32 ? n.length : 32;
        bytes32 head = _readBytesN(n, 0, width);
        uint256 count;
        for (uint256 i; i + n.length <= s.length;) {
            if (_matchAt(s, i, n, head, width)) {
                ++count;
                i += n.length;
            } else {
                ++i;
            }
        }
        uint256[] memory found = new uint256[](count);
        count = 0;
        for (uint256 i; i + n.length <= s.length;) {
            if (_matchAt(s, i, n, head, width)) {
                found[count++] = i;
                i += n.length;
            } else {
                ++i;
            }
        }
        return found;
    }

    /// @dev The byte offset of the first occurrence of `needle` at or after
    /// `from`, or `NOT_FOUND`. An empty needle is found at `from`, or at the
    /// end of a subject shorter than `from`.
    function _indexOf(string memory subject, string memory needle, uint256 from)
        private
        pure
        returns (uint256)
    {
        bytes memory s = bytes(subject);
        bytes memory n = bytes(needle);
        if (n.length == 0) return from > s.length ? s.length : from;
        if (n.length > s.length) return NOT_FOUND;
        uint256 last = s.length - n.length;
        uint256 width = n.length < 32 ? n.length : 32;
        bytes32 head = _readBytesN(n, 0, width);
        for (uint256 i = from; i <= last; ++i) {
            if (_matchAt(s, i, n, head, width)) return i;
        }
        return NOT_FOUND;
    }

    /// @dev The byte offset of the last occurrence of `needle` at or before
    /// `from`, or `NOT_FOUND`.
    function _lastIndexOf(string memory subject, string memory needle, uint256 from)
        private
        pure
        returns (uint256)
    {
        bytes memory s = bytes(subject);
        bytes memory n = bytes(needle);
        if (n.length > s.length) return NOT_FOUND;
        uint256 last = s.length - n.length;
        if (from > last) from = last;
        uint256 width = n.length < 32 ? n.length : 32;
        bytes32 head = _readBytesN(n, 0, width);
        for (uint256 i = from + 1; i != 0;) {
            --i;
            if (_matchAt(s, i, n, head, width)) return i;
        }
        return NOT_FOUND;
    }

    /// @dev The number of UTF-8 runes in `subject`. Each rune is stepped over by
    /// the length its lead byte declares from the byte's top six bits: one below
    /// 0x80, two up to 0xdf (a stray continuation byte included), then three,
    /// four, five and six. Malformed text is counted by the same steps.
    function _runeCount(string memory subject) private pure returns (uint256 count) {
        bytes memory s = bytes(subject);
        // One nibble per value of the top six bits, at four times that value.
        uint256 lengths = 0x6544333322222222222222222222222211111111111111111111111111111111;
        for (uint256 i; i < s.length; ++count) {
            i += (lengths >> (uint8(s[i]) & 0xfc)) & 15;
        }
    }

    /// @dev `subject` repeated `times` times, or the empty string when either
    /// is zero: one copy of the subject, then the filled prefix doubled in
    /// place, each copy reading only bytes already written.
    function _repeat(string memory subject, uint256 times) private pure returns (string memory) {
        bytes memory s = bytes(subject);
        if (times == 0 || s.length == 0) return "";
        uint256 total = s.length * times;
        bytes memory out = new bytes(total);
        _copyInto(out, 0, s, 0, s.length);
        uint256 filled = s.length;
        while (filled < total) {
            uint256 rest = total - filled;
            uint256 step = filled < rest ? filled : rest;
            _copyInto(out, filled, out, 0, step);
            filled += step;
        }
        return string(out);
    }

    /// @dev `subject` split at each non-overlapping `delimiter` occurrence.
    function _split(string memory subject, string memory delimiter)
        private
        pure
        returns (string[] memory result)
    {
        bytes memory s = bytes(subject);
        bytes memory d = bytes(delimiter);
        if (d.length == 0) {
            result = new string[](s.length);
            for (uint256 i; i < s.length; ++i) {
                bytes memory part = new bytes(1);
                part[0] = s[i];
                result[i] = string(part);
            }
            return result;
        }
        uint256[] memory indices = _indicesOf(subject, delimiter);
        result = new string[](indices.length + 1);
        uint256 previous;
        for (uint256 i; i <= indices.length; ++i) {
            uint256 end = i == indices.length ? s.length : indices[i];
            bytes memory part = new bytes(end - previous);
            _copyInto(part, 0, s, previous, part.length);
            result[i] = string(part);
            previous = end + d.length;
        }
    }

    /// @dev The low `byteCount` bytes of `value` as lowercase hexadecimal, two
    /// digits per byte, without a prefix. Reverts with `HexLengthInsufficient()`
    /// when `value` does not fit in them.
    function _toHexStringNoPrefix(uint256 value, uint256 byteCount)
        private
        pure
        returns (string memory)
    {
        bytes memory out = new bytes(byteCount * 2);
        uint256 i = byteCount;
        while (i != 0) {
            --i;
            out[i * 2 + 1] = _DIGITS[value & 15];
            value >>= 4;
            out[i * 2] = _DIGITS[value & 15];
            value >>= 4;
        }
        if (value != 0) revert HexLengthInsufficient();
        return string(out);
    }

    /// @dev `_toHexStringNoPrefix(value, byteCount)` after `0x`.
    function _toHexString(uint256 value, uint256 byteCount) private pure returns (string memory) {
        return string.concat("0x", _toHexStringNoPrefix(value, byteCount));
    }

    /// @dev `value` as lowercase hexadecimal in its fewest whole bytes, at
    /// least one, without a prefix.
    function _toHexStringNoPrefix(uint256 value) private pure returns (string memory) {
        uint256 n = 1;
        for (uint256 x = value; x > 255; x >>= 8) ++n;
        return _toHexStringNoPrefix(value, n);
    }

    /// @dev `_toHexStringNoPrefix(value)` after `0x`.
    function _toHexString(uint256 value) private pure returns (string memory) {
        return string.concat("0x", _toHexStringNoPrefix(value));
    }

    /// @dev Minimal lowercase hexadecimal digits without a prefix.
    function _toMinimalHexStringNoPrefix(uint256 value) private pure returns (string memory) {
        uint256 n = 1;
        for (uint256 x = value; x > 15; x >>= 4) ++n;
        bytes memory out = new bytes(n);
        while (n != 0) {
            --n;
            out[n] = _DIGITS[value & 15];
            value >>= 4;
        }
        return string(out);
    }

    /// @dev Minimal lowercase hexadecimal digits after `0x`.
    function _toMinimalHexString(uint256 value) private pure returns (string memory) {
        return string.concat("0x", _toMinimalHexStringNoPrefix(value));
    }

    /// @dev The digits of `data`, without a prefix.
    function _hexEncode(bytes memory data) private pure returns (string memory) {
        bytes memory out = new bytes(data.length * 2);
        _hexEncodeInto(out, 0, data);
        return string(out);
    }

    /// @dev The digits of `data` after `0x`.
    function _hexEncodePrefixed(bytes memory data) private pure returns (string memory) {
        bytes memory out = new bytes(data.length * 2 + 2);
        (out[0], out[1]) = ("0", "x");
        _hexEncodeInto(out, 2, data);
        return string(out);
    }

    /// @dev Writes the digits of `data` into `out` from `start`. Sixteen bytes
    /// make one word of digits; a remainder is one more block pulled back to
    /// end where the input ends, and an input below sixteen bytes goes a byte
    /// at a time.
    function _hexEncodeInto(bytes memory out, uint256 start, bytes memory data) private pure {
        uint256 n = data.length;
        uint256 i;
        uint256 o = start;
        while (i + 16 <= n) {
            _writeBytes32(out, o, _hexWord(uint128(_readBytes16(data, i))));
            i += 16;
            o += 32;
        }
        if (i == n) return;
        if (n >= 16) {
            uint256 last = n - 16;
            _writeBytes32(out, start + last * 2, _hexWord(uint128(_readBytes16(data, last))));
            return;
        }
        for (; i < n; ++i) {
            uint256 x = uint8(data[i]);
            out[o] = _DIGITS[x >> 4];
            out[o + 1] = _DIGITS[x & 15];
            o += 2;
        }
    }

    /// @dev Packs a nonempty string of at most 31 bytes into one word. The
    /// first byte is its length and the remaining bytes are its contents.
    function _packOne(string memory value) private pure returns (bytes32 result) {
        bytes memory input = bytes(value);
        if (input.length == 0 || input.length > 31) return 0;
        result = bytes32(input.length << 248);
        for (uint256 i; i < input.length; ++i) {
            result |= bytes32(uint256(uint8(input[i])) << ((30 - i) * 8));
        }
    }

    /// @dev Reconstructs a string produced by `_packOne`.
    function _unpackOne(bytes32 packed) private pure returns (string memory result) {
        uint256 n = uint8(packed[0]);
        if (n > 31) n = 31;
        bytes memory out = new bytes(n);
        for (uint256 i; i < n; ++i) out[i] = packed[i + 1];
        return string(out);
    }

    /// @dev Packs two strings whose combined length is 1..30 bytes into one
    /// word. Each string is preceded by one length byte.
    function _packTwo(string memory a, string memory b) private pure returns (bytes32 result) {
        bytes memory x = bytes(a);
        bytes memory y = bytes(b);
        uint256 total = x.length + y.length;
        if (total == 0 || total > 30) return 0;
        result = bytes32(x.length << 248);
        for (uint256 i; i < x.length; ++i) {
            result |= bytes32(uint256(uint8(x[i])) << ((30 - i) * 8));
        }
        result |= bytes32(y.length << ((30 - x.length) * 8));
        for (uint256 i; i < y.length; ++i) {
            result |= bytes32(uint256(uint8(y[i])) << ((29 - x.length - i) * 8));
        }
    }

    /// @dev Reconstructs two strings produced by `_packTwo`.
    function _unpackTwo(bytes32 packed)
        private
        pure
        returns (string memory resultA, string memory resultB)
    {
        uint256 aLength = uint8(packed[0]);
        if (aLength > 30) aLength = 30;
        bytes memory a = new bytes(aLength);
        for (uint256 i; i < aLength; ++i) a[i] = packed[i + 1];
        uint256 bLength = uint8(packed[aLength + 1]);
        if (bLength > 30 - aLength) bLength = 30 - aLength;
        bytes memory b = new bytes(bLength);
        for (uint256 i; i < bLength; ++i) b[i] = packed[aLength + i + 2];
        return (string(a), string(b));
    }

    /// @dev `x * y` modulo `2**256`.
    /// @custom:solar-trusted
    function _rawMul(uint256 x, uint256 y) private pure returns (uint256 z) {
        unchecked {
            z = x * y;
        }
    }

    /// @dev Shrinks `b` to its first `n` bytes in place and clears the rest of
    /// its last word, so the bytes past the new end read as zero padding.
    /// Solidity cannot spell a shorter length for an existing buffer.
    /// @custom:solar-trusted
    function _truncate(bytes memory b, uint256 n) private pure {
        if (n > b.length) n = new uint256[](0)[0];
        assembly ("memory-safe") {
            mstore(b, n)
            mstore(add(add(b, 0x20), n), 0)
        }
    }

    /// @dev Ends the call, returning `s` ABI-encoded as the single result of a
    /// function that returns `string`. A `return` statement leaves only the
    /// function it is in.
    /// @custom:solar-trusted
    function _directReturn(string memory s) private pure {
        bytes memory data = abi.encode(s);
        assembly ("memory-safe") {
            return(add(data, 0x20), mload(data))
        }
    }

    /// @dev Copies `count` bytes from `src` at `srcOffset` to `dst` at
    /// `dstOffset`. The ranges may overlap: the result is as if the source
    /// were read in full before the first write.
    function _copyInto(
        bytes memory dst,
        uint256 dstOffset,
        bytes memory src,
        uint256 srcOffset,
        uint256 count
    ) private pure {
        // Both ranges are validated before anything is written, so a copy
        // running downwards fails on its range the way one running upwards
        // does, rather than on the arithmetic reaching its far end.
        if (
            count > dst.length || dstOffset > dst.length - count || count > src.length
                || srcOffset > src.length - count
        ) count = _outOfBounds();
        if (dstOffset > srcOffset) {
            for (uint256 k = count; k > 0; --k) {
                dst[dstOffset + k - 1] = src[srcOffset + k - 1];
            }
        } else {
            for (uint256 k; k < count; ++k) {
                dst[dstOffset + k] = src[srcOffset + k];
            }
        }
    }

    /// @dev The 16 bytes of `b` at `offset`.
    /// @custom:solar-inline
    function _readBytes16(bytes memory b, uint256 offset)
        private
        pure
        returns (bytes16 result)
    {
        for (uint256 k; k < 16; ++k) {
            result |= bytes16(b[offset + k]) >> (8 * k);
        }
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

    /// @dev Writes `value` into `b` at `offset`.
    /// @custom:solar-inline
    function _writeBytes32(bytes memory b, uint256 offset, bytes32 value) private pure {
        for (uint256 k; k < 32; ++k) {
            b[offset + k] = value[k];
        }
    }

    /// @dev Writes `value` into `b` at `offset`.
    /// @custom:solar-inline
    function _writeBytes8(bytes memory b, uint256 offset, bytes8 value) private pure {
        for (uint256 k; k < 8; ++k) {
            b[offset + k] = value[k];
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

    /// @dev The leading `count` bytes of `b` from `offset`, at most a word, left-aligned.
    /// @custom:solar-inline
    function _readBytesN(bytes memory b, uint256 offset, uint256 count)
        private
        pure
        returns (bytes32 result)
    {
        for (uint256 k; k < count; ++k) {
            result |= bytes32(b[offset + k]) >> (8 * k);
        }
    }
}
