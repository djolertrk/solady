// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Checked Solidity implementation of the pinned Solady Base64 API.
/// @dev Decode accepts the documented standard, URL and IMAP alphabets and
/// padding modes. Invalid input has unspecified output in the upstream API.
library Base64 {
    /// @dev The standard alphabet. The two URL-safe replacements are patched
    /// into a single memory copy so every lookup in a call shares one buffer.
    string private constant ENCODE =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    /// @dev Sextet per byte value, zero where the byte is not part of any
    /// accepted alphabet. Codes 43 and 45 map to 62; codes 44, 47 and 95 map
    /// to 63, covering the standard, URL and IMAP alphabets. The table spans
    /// the whole byte range so a lookup needs neither a range test nor a
    /// bounds check.
    bytes private constant DECODE = hex"0000000000000000000000000000000000000000000000000000000000000000"
        hex"00000000000000000000003e3f3e003f3435363738393a3b3c3d000000000000"
        hex"00000102030405060708090a0b0c0d0e0f10111213141516171819000000003f"
        hex"001a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132330000000000"
        hex"0000000000000000000000000000000000000000000000000000000000000000"
        hex"0000000000000000000000000000000000000000000000000000000000000000"
        hex"0000000000000000000000000000000000000000000000000000000000000000"
        hex"0000000000000000000000000000000000000000000000000000000000000000";

    function encode(bytes memory data, bool fileSafe, bool noPadding)
        internal
        pure
        returns (string memory result)
    {
        uint256 n = data.length;
        uint256 padding = n % 3 == 0 ? 0 : 3 - n % 3;
        uint256 length = ((n + 2) / 3) * 4;
        if (noPadding) length -= padding;
        bytes memory out = new bytes(length);
        if (n == 0) return string(out);
        bytes memory table = bytes(ENCODE);
        if (fileSafe) {
            // Written as byte values: a one-character string literal is first
            // materialized as a `bytes` value before the `bytes1` conversion.
            table[62] = bytes1(uint8(0x2d));
            table[63] = bytes1(uint8(0x5f));
        }
        uint256 i;
        uint256 j;
        while (i + 2 < n && j + 3 < length) {
            uint256 word = (uint256(uint8(data[i])) << 16) | (uint256(uint8(data[i + 1])) << 8)
                | uint256(uint8(data[i + 2]));
            out[j] = table[word >> 18];
            out[j + 1] = table[(word >> 12) & 63];
            out[j + 2] = table[(word >> 6) & 63];
            out[j + 3] = table[word & 63];
            i += 3;
            j += 4;
        }
        if (i < n) {
            uint256 word = uint256(uint8(data[i])) << 16;
            if (i + 1 < n) word |= uint256(uint8(data[i + 1])) << 8;
            if (i + 2 < n) word |= uint8(data[i + 2]);
            out[j] = table[word >> 18];
            out[j + 1] = table[(word >> 12) & 63];
            if (j + 2 < length) {
                out[j + 2] = i + 1 < n ? table[(word >> 6) & 63] : bytes1("=");
            }
            if (j + 3 < length) {
                out[j + 3] = i + 2 < n ? table[word & 63] : bytes1("=");
            }
        }
        return string(out);
    }

    function encode(bytes memory data) internal pure returns (string memory result) {
        return encode(data, false, false);
    }

    function encode(bytes memory data, bool fileSafe) internal pure returns (string memory result) {
        return encode(data, fileSafe, false);
    }

    function decode(string memory data) internal pure returns (bytes memory result) {
        bytes memory input = bytes(data);
        uint256 n = input.length;
        if (n == 0) return new bytes(0);
        uint256 length = (n / 4) * 3;
        uint256 tail = n % 4;
        if (tail != 0) {
            length += tail - 1;
        } else {
            if (input[n - 1] == "=") --length;
            if (input[n - 2] == "=") --length;
        }
        result = new bytes(length);
        bytes memory table = DECODE;
        uint256 i;
        uint256 j;
        while (i + 3 < n && j + 2 < length) {
            uint256 word = (uint256(uint8(table[uint8(input[i])])) << 18)
                | (uint256(uint8(table[uint8(input[i + 1])])) << 12)
                | (uint256(uint8(table[uint8(input[i + 2])])) << 6)
                | uint256(uint8(table[uint8(input[i + 3])]));
            result[j] = bytes1(uint8(word >> 16));
            result[j + 1] = bytes1(uint8(word >> 8));
            result[j + 2] = bytes1(uint8(word));
            i += 4;
            j += 3;
        }
        if (i < n) {
            uint256 word = uint256(uint8(table[uint8(input[i])])) << 18;
            if (i + 1 < n) word |= uint256(uint8(table[uint8(input[i + 1])])) << 12;
            if (i + 2 < n) word |= uint256(uint8(table[uint8(input[i + 2])])) << 6;
            if (i + 3 < n) word |= uint256(uint8(table[uint8(input[i + 3])]));
            if (j < length) result[j] = bytes1(uint8(word >> 16));
            if (j + 1 < length) result[j + 1] = bytes1(uint8(word >> 8));
            if (j + 2 < length) result[j + 2] = bytes1(uint8(word));
        }
    }
}
