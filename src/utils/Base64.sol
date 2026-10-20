// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Library to encode strings in Base64.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/Base64.sol)
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/utils/Base64.sol)
/// @author Modified from (https://github.com/Brechtpd/base64/blob/main/base64.sol) by Brecht Devos - <brecht@loopring.org>.
/// @dev The checked port works a word at a time in both directions without a lookup table:
/// `encode` turns twenty-four bytes into thirty-two characters and `decode` thirty-two
/// characters into twenty-four bytes with arithmetic on every byte of a word at once, the
/// input's tail read as one shorter word. `encode` writes the standard alphabet with padding,
/// or the URL-safe one and no padding on request. `decode` accepts the documented standard,
/// URL and IMAP alphabets and padding modes. One deliberate difference: where upstream's
/// output is undefined, `decode` reverts with `InvalidBase64()`: on a character outside those
/// alphabets, padding anywhere but the end of a padded input, or a length no encoding has. It
/// does not reject unused low bits in a final group, which RFC 4648 leaves to the decoder.
/// @custom:solar-safe memory arithmetic
library Base64 {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    ENCODING / DECODING                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Encodes `data` using the base64 encoding described in RFC 4648.
    /// See: https://datatracker.ietf.org/doc/html/rfc4648
    /// @param fileSafe  Whether to replace '+' with '-' and '/' with '_'.
    /// @param noPadding Whether to strip away the padding.
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
        uint256 i;
        uint256 j;
        // Twenty-four bytes are thirty-two characters, one word of output,
        // which always fits: the output holds at least four characters per
        // three input bytes.
        while (i + 24 <= n) {
            _writeBytes32(out, j, _encodeWord(uint256(uint192(_readBytes24(data, i))), fileSafe));
            i += 24;
            j += 32;
        }
        if (i < n) {
            // The rest is one shorter word, zeros past its bytes, of which
            // the output keeps the characters the bytes need, then padding.
            uint256 rest = n - i;
            bytes32 chars = _encodeWord(uint256(_readBytesN(data, i, rest)) >> 64, fileSafe);
            uint256 used = (rest * 4 + 2) / 3;
            _writeBytesN(out, j, chars, used);
            for (uint256 k = j + used; k < length; ++k) {
                out[k] = "=";
            }
        }
        return string(out);
    }

    /// @dev Encodes `data` using the base64 encoding described in RFC 4648.
    /// Equivalent to `encode(data, false, false)`.
    function encode(bytes memory data) internal pure returns (string memory result) {
        return encode(data, false, false);
    }

    /// @dev Encodes `data` using the base64 encoding described in RFC 4648.
    /// Equivalent to `encode(data, fileSafe, false)`.
    function encode(bytes memory data, bool fileSafe) internal pure returns (string memory result) {
        return encode(data, fileSafe, false);
    }

    /// @dev Decodes base64 encoded `data`.
    ///
    /// Supports:
    /// - RFC 4648 (both standard and file-safe mode).
    /// - RFC 3501 (63: ',').
    ///
    /// Does not support:
    /// - Line breaks.
    ///
    /// Note: For performance reasons,
    /// this function will NOT revert on invalid `data` inputs.
    /// Outputs for invalid inputs will simply be undefined behaviour.
    /// It is the user's responsibility to ensure that the `data`
    /// is a valid base64 encoded string.
    /// The checked port reverts with `InvalidBase64()` on such an input instead.
    function decode(string memory data) internal pure returns (bytes memory result) {
        bytes memory input = bytes(data);
        uint256 n = input.length;
        // Padding is at most two characters, at the end of a padded input.
        if (n != 0 && n % 4 == 0 && input[n - 1] == "=") {
            --n;
            if (input[n - 1] == "=") --n;
        }
        uint256 tail = n % 4;
        if (tail == 1) revert InvalidBase64();
        uint256 length = (n / 4) * 3;
        if (tail != 0) length += tail - 1;
        result = new bytes(length);
        uint256 bad;
        uint256 i;
        uint256 j;
        // Thirty-two characters are twenty-four bytes. The word written
        // carries eight more, which the next step overwrites, as long as the
        // output has room for it.
        while (i + 32 <= n) {
            (uint256 packed, uint256 invalid) = _decodeWord(uint256(_readBytes32(input, i)));
            bad |= invalid;
            if (j + 32 <= length) {
                _writeBytes32(result, j, bytes32(packed));
            } else {
                _writeBytesN(result, j, bytes32(packed), 24);
            }
            i += 32;
            j += 24;
        }
        if (i < n) {
            // The rest, a final group of two or three characters included, is
            // one shorter word filled up with `A`, which decodes to zero bits.
            uint256 rest = n - i;
            uint256 word = uint256(_readBytesN(input, i, rest)) | (LETTER_A >> (8 * rest));
            (uint256 packed, uint256 invalid) = _decodeWord(word);
            bad |= invalid;
            _writeBytesN(result, j, bytes32(packed), length - j);
        }
        if (bad != 0) revert InvalidBase64();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PRIVATE HELPERS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev One copy of the value in every byte.
    uint256 private constant ONES =
        0x0101010101010101010101010101010101010101010101010101010101010101;

    /// @dev The top bit of every byte.
    uint256 private constant HIGHS =
        0x8080808080808080808080808080808080808080808080808080808080808080;

    /// @dev The low seven bits of every byte.
    uint256 private constant LOWS =
        0x7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f;

    /// @dev The character `A`, which decodes to zero, in every byte.
    uint256 private constant LETTER_A =
        0x4141414141414141414141414141414141414141414141414141414141414141;

    /// @dev Masks for spreading twenty-four packed bytes into eight groups of
    /// three, one group to each four-byte lane. Each step moves the upper half
    /// of every group up and leaves the lower half where it is.
    uint256 private constant MASK_96 =
        0x0000000000000000000000000000000000000000ffffffffffffffffffffffff;

    uint256 private constant SPREAD_HIGH_48 =
        0x00000000ffffffffffff00000000000000000000ffffffffffff000000000000;

    uint256 private constant SPREAD_LOW_48 =
        0x00000000000000000000ffffffffffff00000000000000000000ffffffffffff;

    uint256 private constant SPREAD_HIGH_24 =
        0x0000ffffff0000000000ffffff0000000000ffffff0000000000ffffff000000;

    uint256 private constant SPREAD_LOW_24 =
        0x0000000000ffffff0000000000ffffff0000000000ffffff0000000000ffffff;

    /// @dev Six set bits at the bottom of every four-byte lane.
    uint256 private constant LANE_63 =
        0x0000003f0000003f0000003f0000003f0000003f0000003f0000003f0000003f;

    /// @dev Masks for gathering thirty-two sextets, one to a byte, into twenty-four
    /// bytes: each step joins the two halves of every lane twice its width.
    uint256 private constant HIGH_8 =
        0xff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00;

    uint256 private constant LOW_8 =
        0x00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff;

    uint256 private constant HIGH_16 =
        0xffff0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff0000;

    uint256 private constant LOW_16 =
        0x0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff;

    uint256 private constant HIGH_32 =
        0xffffffff00000000ffffffff00000000ffffffff00000000ffffffff00000000;

    uint256 private constant LOW_32 =
        0x00000000ffffffff00000000ffffffff00000000ffffffff00000000ffffffff;

    uint256 private constant HIGH_64 =
        0xffffffffffffffff0000000000000000ffffffffffffffff0000000000000000;

    uint256 private constant LOW_64 =
        0x0000000000000000ffffffffffffffff0000000000000000ffffffffffffffff;

    uint256 private constant HIGH_128 =
        0xffffffffffffffffffffffffffffffff00000000000000000000000000000000;

    uint256 private constant LOW_128 =
        0x00000000000000000000000000000000ffffffffffffffffffffffffffffffff;

    /// @dev The input is not Base64.
    error InvalidBase64();

    /// @dev The thirty-two characters of the twenty-four bytes packed into the
    /// low bits of `packed`.
    function _encodeWord(uint256 packed, bool fileSafe) private pure returns (bytes32) {
        // The URL-safe alphabet differs only in its last two characters.
        uint256 stepDown = fileSafe ? 13 : 15;
        uint256 stepUp = fileSafe ? 49 : 3;
        // Spread the eight groups of three bytes one to a four-byte lane,
        // halving the packing each step.
        uint256 x = ((packed >> 96) << 128) | (packed & MASK_96);
        x = ((x & SPREAD_HIGH_48) << 16) | (x & SPREAD_LOW_48);
        x = ((x & SPREAD_HIGH_24) << 8) | (x & SPREAD_LOW_24);
        // Cut each lane's twenty-four bits into four six-bit values, one to a
        // byte. Shifting the whole word and masking per lane keeps the
        // neighbours out.
        uint256 v = (((x >> 18) & LANE_63) << 24) | (((x >> 12) & LANE_63) << 16)
            | (((x >> 6) & LANE_63) << 8) | (x & LANE_63);
        // Each threshold the alphabet steps at is found by adding its distance
        // to 128, which carries into a byte's high bit exactly at the
        // threshold: a one marks every byte at or above it. No adjustment
        // carries out of its own byte, so the whole word steps at once.
        uint256 letter = ((v + 102 * ONES) >> 7) & ONES;
        uint256 digit = ((v + 76 * ONES) >> 7) & ONES;
        uint256 last2 = ((v + 66 * ONES) >> 7) & ONES;
        uint256 last1 = ((v + 65 * ONES) >> 7) & ONES;
        return bytes32(v + 65 * ONES + 6 * letter - 75 * digit - stepDown * last2 + stepUp * last1);
    }

    /// @dev The twenty-four bytes thirty-two characters encode, left-aligned,
    /// and a nonzero `bad` when a character is not Base64.
    function _decodeWord(uint256 w) private pure returns (uint256 packed, uint256 bad) {
        // A byte with its top bit set is not ASCII; the classes below test the
        // low seven bits, and each class's bytes take its value. A letter's
        // distance is taken from the byte with its top bit set, so no byte
        // borrows from the next.
        bad = w & HIGHS;
        uint256 x = w & LOWS;
        uint256 c = _range(x, 65, 91);
        uint256 valid = c;
        uint256 s = _lanes(c) & (((x | HIGHS) - 65 * ONES) & LOWS);
        c = _range(x, 97, 123);
        valid |= c;
        s |= _lanes(c) & (((x | HIGHS) - 71 * ONES) & LOWS);
        c = _range(x, 48, 58);
        valid |= c;
        s |= _lanes(c) & (x + 4 * ONES);
        // `+` and `-` are 62; `/`, `_` and the IMAP `,` are 63.
        c = _range(x, 43, 44) | _range(x, 45, 46);
        valid |= c;
        s |= _lanes(c) & (62 * ONES);
        c = _range(x, 44, 45) | _range(x, 47, 48) | _range(x, 95, 96);
        valid |= c;
        s |= _lanes(c) & (63 * ONES);
        bad |= ~valid & HIGHS;
        // Join the sextets: two to twelve bits, four to twenty-four, then the
        // eight groups of three bytes into twenty-four contiguous bytes.
        s = ((s & HIGH_8) >> 2) | (s & LOW_8);
        s = ((s & HIGH_16) >> 4) | (s & LOW_16);
        s = ((s & HIGH_32) >> 8) | (s & LOW_32);
        s = ((s & HIGH_64) >> 16) | (s & LOW_64);
        s = ((s & HIGH_128) >> 32) | (s & LOW_128);
        packed = s << 64;
    }

    /// @dev The top bit of every byte of `x`, whose bytes are below 128, that
    /// lies in `[low, high)`. Adding a bound's distance to 128 carries into a
    /// byte's top bit exactly when the byte is at least the bound, and never
    /// out of the byte.
    /// @custom:solar-inline
    function _range(uint256 x, uint256 low, uint256 high) private pure returns (uint256) {
        return (x + (128 - low) * ONES) & ~(x + (128 - high) * ONES) & HIGHS;
    }

    /// @dev Every byte whose top bit is set in `flags` as `0xff`, the others zero.
    /// @custom:solar-inline
    function _lanes(uint256 flags) private pure returns (uint256) {
        return (flags >> 7) * 0xff;
    }

    /// @dev The 24 bytes of `b` at `offset`.
    /// @custom:solar-inline
    function _readBytes24(bytes memory b, uint256 offset) private pure returns (bytes24 result) {
        for (uint256 k; k < 24; ++k) {
            result |= bytes24(b[offset + k]) >> (8 * k);
        }
    }

    /// @dev The 32 bytes of `b` at `offset`.
    /// @custom:solar-inline
    function _readBytes32(bytes memory b, uint256 offset) private pure returns (bytes32 result) {
        for (uint256 k; k < 32; ++k) {
            result |= bytes32(b[offset + k]) >> (8 * k);
        }
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

    /// @dev Writes `value` to the 32 bytes of `b` at `offset`.
    /// @custom:solar-inline
    function _writeBytes32(bytes memory b, uint256 offset, bytes32 value) private pure {
        for (uint256 k; k < 32; ++k) {
            b[offset + k] = value[k];
        }
    }

    /// @dev Writes the leading `count` bytes of `value`, at most a word, to `b` at `offset`.
    /// @custom:solar-inline
    function _writeBytesN(bytes memory b, uint256 offset, bytes32 value, uint256 count)
        private
        pure
    {
        for (uint256 k; k < count; ++k) {
            b[offset + k] = value[k];
        }
    }
}
