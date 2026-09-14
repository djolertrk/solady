// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Checked Solidity replacements for the value-oriented LibString APIs.
/// @dev Storage reinterpretation and direct-return APIs are deliberately absent.
library LibString {
    error HexLengthInsufficient();
    error TooBigForSmallString();
    error StringNot7BitASCII();
    uint256 internal constant NOT_FOUND = type(uint256).max;
    bytes16 private constant HEX = "0123456789abcdef";

    /// @dev Set bit per byte value that `escapeHTML` rewrites: `"`, `&`, `'`,
    /// `<` and `>`. Testing membership with one shift keeps every other byte
    /// out of the escape helper.
    uint256 private constant _HTML_ESCAPED =
        (1 << 0x22) | (1 << 0x26) | (1 << 0x27) | (1 << 0x3c) | (1 << 0x3e);

    /// @dev Set bit per byte value that `escapeJSON` rewrites: every control
    /// byte below 0x20, plus `"` and `\`.
    uint256 private constant _JSON_ESCAPED = 0xffffffff | (1 << 0x22) | (1 << 0x5c);

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
        bytes memory out = new bytes(byteCount * 2);
        for (uint256 i = out.length; i != 0;) {
            --i;
            out[i] = HEX[value & 15];
            value >>= 4;
        }
        if (value != 0) revert HexLengthInsufficient();
        return string(out);
    }

    function toHexString(uint256 value, uint256 byteCount)
        internal
        pure
        returns (string memory result)
    {
        return string.concat("0x", toHexStringNoPrefix(value, byteCount));
    }

    function toHexStringNoPrefix(uint256 value) internal pure returns (string memory result) {
        uint256 length = 1;
        for (uint256 x = value; x > 255; x >>= 8) {
            ++length;
        }
        return toHexStringNoPrefix(value, length);
    }

    function toHexString(uint256 value) internal pure returns (string memory result) {
        return string.concat("0x", toHexStringNoPrefix(value));
    }

    function toMinimalHexStringNoPrefix(uint256 value)
        internal
        pure
        returns (string memory result)
    {
        uint256 length = 1;
        for (uint256 x = value; x > 15; x >>= 4) {
            ++length;
        }
        bytes memory out = new bytes(length);
        while (length != 0) {
            --length;
            out[length] = HEX[value & 15];
            value >>= 4;
        }
        return string(out);
    }

    function toMinimalHexString(uint256 value) internal pure returns (string memory result) {
        return string.concat("0x", toMinimalHexStringNoPrefix(value));
    }

    function toHexStringNoPrefix(address value) internal pure returns (string memory result) {
        return toHexStringNoPrefix(uint160(value), 20);
    }

    function toHexString(address value) internal pure returns (string memory result) {
        return toHexString(uint160(value), 20);
    }

    function toHexStringNoPrefix(bytes memory raw) internal pure returns (string memory result) {
        bytes memory out = new bytes(raw.length * 2);
        for (uint256 i; i < raw.length; ++i) {
            uint256 x = uint8(raw[i]);
            out[2 * i] = HEX[x >> 4];
            out[2 * i + 1] = HEX[x & 15];
        }
        return string(out);
    }

    function toHexString(bytes memory raw) internal pure returns (string memory result) {
        return string.concat("0x", toHexStringNoPrefix(raw));
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
        for (uint256 i; i < b.length; ++i) {
            if (b[i] > 0x7f) revert StringNot7BitASCII();
            result |= uint128(1) << uint8(b[i]);
        }
    }

    function runeCount(string memory s) internal pure returns (uint256 result) {
        bytes memory b = bytes(s);
        for (uint256 i; i < b.length; ++result) {
            uint256 c = uint8(b[i]);
            // Counting the thresholds `c` reaches instead is branch-free but
            // measured worse: the first test already settles every ASCII byte.
            i += c < 0xc0 ? 1 : c < 0xe0 ? 2 : c < 0xf0 ? 3 : c < 0xf8 ? 4 : c < 0xfc ? 5 : 6;
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
        bytes memory out = new bytes(b.length);
        // The two cases differ only in which letter range is converted, and
        // either direction is the same single bit flip.
        uint256 lower = toUpper ? 97 : 65;
        for (uint256 i; i < b.length; ++i) {
            uint256 c = uint8(b[i]);
            out[i] = bytes1(uint8(c ^ (c >= lower && c <= lower + 25 ? 0x20 : 0)));
        }
        return string(out);
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
        bytes memory hexed = bytes(toHexStringNoPrefix(value));
        bytes32 hash = keccak256(hexed);
        for (uint256 i; i < 40; ++i) {
            uint8 c = uint8(hexed[i]);
            uint8 nibble = uint8(hash[i / 2]);
            if (i % 2 == 0) nibble >>= 4;
            if (c >= 97 && (nibble & 15) >= 8) hexed[i] = bytes1(c - 32);
        }
        return string.concat("0x", string(hexed));
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

    /// @dev Returns the byte offset of the first occurrence of `needle` in
    /// `subject` at or after `from`, or `NOT_FOUND`.
    /// Comparing the first byte in the scan rejects nearly every offset without
    /// entering the full comparison, so a scan costs one byte read per offset.
    function _find(bytes memory s, bytes memory n, uint256 from) private pure returns (uint256) {
        uint256 needleLength = n.length;
        uint256 length = s.length;
        if (needleLength == 0) return from > length ? length : from;
        if (needleLength > length || from > length - needleLength) return NOT_FOUND;
        bytes1 first = n[0];
        for (uint256 i = from; i + needleLength <= length; ++i) {
            if (s[i] == first && (needleLength < 2 || _matchAt(s, n, i))) return i;
        }
        return NOT_FOUND;
    }

    /// @dev Returns `subject` all occurrences of `needle` replaced with `replacement`.
    function replace(string memory subject, string memory needle, string memory replacement)
        internal
        pure
        returns (string memory)
    {
        bytes memory s = bytes(subject);
        bytes memory n = bytes(needle);
        bytes memory r = bytes(replacement);
        uint256 needleLength = n.length;
        uint256 length = s.length;
        if (needleLength > length) return subject;
        if (needleLength == 0) return _replaceEmpty(s, r);
        bytes1 first = n[0];
        uint256 count;
        for (uint256 i; i + needleLength <= length;) {
            if (s[i] == first && (needleLength < 2 || _matchAt(s, n, i))) {
                ++count;
                i += needleLength;
            } else {
                ++i;
            }
        }
        bytes memory out = new bytes(length + count * r.length - count * needleLength);
        uint256 o;
        uint256 at;
        while (at + needleLength <= length) {
            if (s[at] == first && (needleLength < 2 || _matchAt(s, n, at))) {
                for (uint256 k; k < r.length; ++k) {
                    out[o + k] = r[k];
                }
                o += r.length;
                at += needleLength;
            } else {
                out[o] = s[at];
                ++o;
                ++at;
            }
        }
        while (at < length) {
            out[o] = s[at];
            ++o;
            ++at;
        }
        return string(out);
    }

    /// @dev `replace` with an empty needle: `replacement` is inserted before
    /// every byte of `s` and once more at the end.
    function _replaceEmpty(bytes memory s, bytes memory r) private pure returns (string memory) {
        uint256 length = s.length;
        bytes memory out = new bytes(length + (length + 1) * r.length);
        uint256 o;
        for (uint256 i; i <= length; ++i) {
            for (uint256 k; k < r.length; ++k) {
                out[o + k] = r[k];
            }
            o += r.length;
            if (i < length) {
                out[o] = s[i];
                ++o;
            }
        }
        return string(out);
    }

    /// @dev Returns the byte index of the first location of `needle` in `subject`,
    /// needleing from left to right, starting from `from`.
    /// Returns `NOT_FOUND` (i.e. `type(uint256).max`) if the `needle` is not found.
    function indexOf(string memory subject, string memory needle, uint256 from)
        internal
        pure
        returns (uint256)
    {
        return _find(bytes(subject), bytes(needle), from);
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
        bytes memory s = bytes(subject);
        bytes memory n = bytes(needle);
        uint256 needleLength = n.length;
        if (needleLength > s.length) return NOT_FOUND;
        uint256 fromMax = s.length - needleLength;
        if (from > fromMax) from = fromMax;
        if (needleLength == 0) return from;
        bytes1 first = n[0];
        for (uint256 i = from + 1; i != 0;) {
            --i;
            if (s[i] == first && (needleLength < 2 || _matchAt(s, n, i))) return i;
        }
        return NOT_FOUND;
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
        for (uint256 k; k < out.length; ++k) {
            out[k] = s[start + k];
        }
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
        bytes memory s = bytes(subject);
        bytes memory n = bytes(needle);
        uint256 needleLength = n.length;
        uint256 length = s.length;
        if (needleLength > length) return new uint256[](0);
        if (needleLength == 0) {
            uint256[] memory every = new uint256[](length + 1);
            for (uint256 i; i <= length; ++i) {
                every[i] = i;
            }
            return every;
        }
        bytes1 first = n[0];
        uint256 count;
        for (uint256 i; i + needleLength <= length;) {
            if (s[i] == first && (needleLength < 2 || _matchAt(s, n, i))) {
                ++count;
                i += needleLength;
            } else {
                ++i;
            }
        }
        uint256[] memory found = new uint256[](count);
        uint256 k;
        for (uint256 i; i + needleLength <= length;) {
            if (s[i] == first && (needleLength < 2 || _matchAt(s, n, i))) {
                found[k] = i;
                ++k;
                i += needleLength;
            } else {
                ++i;
            }
        }
        return found;
    }

    /// @dev Returns an arrays of strings based on the `delimiter` inside of the `subject` string.
    function split(string memory subject, string memory delimiter)
        internal
        pure
        returns (string[] memory result)
    {
        bytes memory s = bytes(subject);
        uint256 d = bytes(delimiter).length;
        if (d == 0) {
            result = new string[](s.length);
            for (uint256 i; i < s.length; ++i) {
                result[i] = slice(subject, i, i + 1);
            }
            return result;
        }
        uint256[] memory indices = indicesOf(subject, delimiter);
        result = new string[](indices.length + 1);
        uint256 previous;
        for (uint256 k; k < indices.length; ++k) {
            result[k] = slice(subject, previous, indices[k]);
            previous = indices[k] + d;
        }
        result[indices.length] = slice(subject, previous, s.length);
    }

    /// @dev Returns the length of the small string `s` up to its first null byte.
    function _smallStringLength(bytes32 s) private pure returns (uint256 n) {
        while (n < 32 && s[n] != 0) ++n;
    }

    /// @dev Returns a string from a small bytes32 string.
    /// `s` must be null-terminated, or behavior will be undefined.
    function fromSmallString(bytes32 s) internal pure returns (string memory result) {
        uint256 n = _smallStringLength(s);
        bytes memory out = new bytes(n);
        for (uint256 i; i < n; ++i) {
            out[i] = s[i];
        }
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
        for (uint256 i; i < b.length; ++i) {
            result |= bytes32(uint256(uint8(b[i])) << ((31 - i) * 8));
        }
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
        uint256 length;
        for (uint256 i; i < b.length; ++i) {
            if ((_HTML_ESCAPED >> uint8(b[i])) & 1 == 0) {
                ++length;
                continue;
            }
            (, uint256 escaped) = _htmlEscape(b[i]);
            length += escaped;
        }
        bytes memory out = new bytes(length);
        uint256 o;
        for (uint256 i; i < b.length; ++i) {
            if ((_HTML_ESCAPED >> uint8(b[i])) & 1 == 0) {
                out[o] = b[i];
                ++o;
                continue;
            }
            (bytes32 seq, uint256 escaped) = _htmlEscape(b[i]);
            for (uint256 k; k < escaped; ++k) {
                out[o + k] = seq[k];
            }
            o += escaped;
        }
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
        uint256 length = addDoubleQuotes ? 2 : 0;
        for (uint256 i; i < b.length; ++i) {
            if ((_JSON_ESCAPED >> uint8(b[i])) & 1 == 0) {
                ++length;
                continue;
            }
            (, uint256 escaped) = _jsonEscape(b[i]);
            length += escaped;
        }
        bytes memory out = new bytes(length);
        uint256 o;
        if (addDoubleQuotes) {
            out[o] = "\"";
            ++o;
        }
        for (uint256 i; i < b.length; ++i) {
            if ((_JSON_ESCAPED >> uint8(b[i])) & 1 == 0) {
                out[o] = b[i];
                ++o;
                continue;
            }
            (bytes32 seq, uint256 escaped) = _jsonEscape(b[i]);
            for (uint256 k; k < escaped; ++k) {
                out[o + k] = seq[k];
            }
            o += escaped;
        }
        if (addDoubleQuotes) out[o] = "\"";
        return string(out);
    }

    /// @dev Escapes the string to be used within double-quotes in a JSON.
    function escapeJSON(string memory s) internal pure returns (string memory result) {
        result = escapeJSON(s, false);
    }

    /// @dev Returns whether the byte `c` is unreserved by `encodeURIComponent`.
    function _uriUnreserved(uint8 c) private pure returns (bool) {
        if (c >= 48 && c <= 57) return true;
        if (c >= 65 && c <= 90) return true;
        if (c >= 97 && c <= 122) return true;
        return c == 45 || c == 95 || c == 46 || c == 33 || c == 126 || c == 42 || c == 39 || c == 40
            || c == 41;
    }

    /// @dev Encodes `s` so that it can be safely used in a URI,
    /// just like `encodeURIComponent` in JavaScript.
    /// See: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/encodeURIComponent
    /// See: https://datatracker.ietf.org/doc/html/rfc2396
    /// See: https://datatracker.ietf.org/doc/html/rfc3986
    function encodeURIComponent(string memory s) internal pure returns (string memory result) {
        bytes memory b = bytes(s);
        bytes16 upperHex = "0123456789ABCDEF";
        uint256 length;
        for (uint256 i; i < b.length; ++i) {
            length += _uriUnreserved(uint8(b[i])) ? 1 : 3;
        }
        bytes memory out = new bytes(length);
        uint256 o;
        for (uint256 i; i < b.length; ++i) {
            uint8 c = uint8(b[i]);
            if (_uriUnreserved(c)) {
                out[o++] = b[i];
            } else {
                out[o] = "%";
                out[o + 1] = upperHex[c >> 4];
                out[o + 2] = upperHex[c & 15];
                o += 3;
            }
        }
        return string(out);
    }

    /// @dev Returns whether `a` equals `b`, where `b` is a null-terminated small string.
    function eqs(string memory a, bytes32 b) internal pure returns (bool result) {
        bytes memory s = bytes(a);
        uint256 n = _smallStringLength(b);
        if (s.length != n) return false;
        for (uint256 i; i < n; ++i) {
            if (s[i] != b[i]) return false;
        }
        return true;
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
        bytes memory s = bytes(a);
        if (s.length == 0 || s.length > 31) return 0;
        result = bytes32(s.length << 248);
        for (uint256 i; i < s.length; ++i) {
            result |= bytes32(uint256(uint8(s[i])) << ((30 - i) * 8));
        }
    }

    /// @dev Unpacks a string packed using {packOne}.
    /// Returns the empty string if `packed` is `bytes32(0)`.
    /// If `packed` is not an output of {packOne}, the output behavior is undefined.
    function unpackOne(bytes32 packed) internal pure returns (string memory result) {
        uint256 n = uint8(packed[0]);
        if (n > 31) n = 31;
        bytes memory out = new bytes(n);
        for (uint256 i; i < n; ++i) {
            out[i] = packed[i + 1];
        }
        return string(out);
    }

    /// @dev Packs two strings with their lengths into a single word.
    /// Returns `bytes32(0)` if combined length is zero or greater than 30.
    function packTwo(string memory a, string memory b) internal pure returns (bytes32 result) {
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

    /// @dev Unpacks strings packed using {packTwo}.
    /// Returns the empty strings if `packed` is `bytes32(0)`.
    /// If `packed` is not an output of {packTwo}, the output behavior is undefined.
    function unpackTwo(bytes32 packed)
        internal
        pure
        returns (string memory resultA, string memory resultB)
    {
        uint256 n = uint8(packed[0]);
        if (n > 30) n = 30;
        bytes memory x = new bytes(n);
        for (uint256 i; i < n; ++i) {
            x[i] = packed[i + 1];
        }
        uint256 m = uint8(packed[n + 1]);
        if (m > 30 - n) m = 30 - n;
        bytes memory y = new bytes(m);
        for (uint256 i; i < m; ++i) {
            y[i] = packed[n + 2 + i];
        }
        return (string(x), string(y));
    }
}
