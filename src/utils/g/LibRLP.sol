// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// This file is auto-generated.

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*                          STRUCTS                           */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

/// @dev A pointer to a RLP item list in memory.
struct List {
    // Do NOT modify the `_data` directly.
    uint256 _data;
}

using LibRLP for List global;

/// @notice Library for RLP encoding and CREATE address computation.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/g/LibRLP.sol)
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/utils/LibRLP.sol)
/// @dev The checked port keeps upstream's memory list. A list's `_data` packs the addresses
/// of its first and last nodes; a node is a `List` too, whose `_data` packs the address of
/// the next node, the item's kind and the item: a number below `2 ** 208`, or the address of
/// a word holding a bigger one, of a `bytes` or of a list, or an address. Trusted casts turn
/// memory references into these addresses and back, so, as upstream says, `_data` must not
/// be modified. `encode` puts an encoding of at most 32 bytes together in a word. It writes
/// a longer one into a buffer that grows as needed: the outer list's items after room for
/// the longest prefix, which then goes right before them, the trusted `_bytesAt` making the
/// result start there, and an inner list's items after a byte for its prefix, moved up for a
/// longer one. Past 4096 bytes, it works out the lengths first and writes each item once
/// where it goes. `_truncate` shortens buffers allocated in whole words, so that the bytes
/// after a result are zero under every compiler, as upstream zeroes them, and a hashed
/// preimage to its length. `computeAddress` returns a clean address, where upstream leaves
/// the upper 96 bits of the word dirty.
/// @custom:solar-safe memory arithmetic
library LibRLP {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 CREATE ADDRESS PREDICTION                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns the address where a contract will be stored if deployed via
    /// `deployer` with `nonce` using the `CREATE` opcode.
    /// For the specification of the Recursive Length Prefix (RLP)
    /// encoding scheme, please refer to p. 19 of the Ethereum Yellow Paper
    /// (https://ethereum.github.io/yellowpaper/paper.pdf)
    /// and the Ethereum Wiki (https://eth.wiki/fundamentals/rlp).
    ///
    /// Based on the EIP-161 (https://github.com/ethereum/EIPs/blob/master/EIPS/eip-161.md)
    /// specification, all contract accounts on the Ethereum mainnet are initiated with
    /// `nonce = 1`. Thus, the first contract address created by another contract
    /// is calculated with a non-zero nonce.
    ///
    /// The theoretical allowed limit, based on EIP-2681
    /// (https://eips.ethereum.org/EIPS/eip-2681), for an account nonce is 2**64-2.
    ///
    /// Caution! This function will NOT check that the nonce is within the theoretical range.
    /// This is for performance, as exceeding the range is extremely impractical.
    /// It is the user's responsibility to ensure that the nonce is valid
    /// (e.g. no dirty bits after packing / unpacking).
    ///
    /// This is equivalent to:
    /// `address(uint160(uint256(keccak256(LibRLP.p(deployer).p(nonce).encode()))))`.
    ///
    /// Note: The returned result has dirty upper 96 bits. Please clean if used in assembly.
    function computeAddress(address deployer, uint256 nonce)
        internal
        pure
        returns (address deployed)
    {
        // The integer zero is treated as an empty byte string,
        // and as a result it only has a length prefix, 0x80,
        // computed via `0x80 + 0`.

        // A one-byte integer in the [0x00, 0x7f] range uses its
        // own value as a length prefix,
        // there is no additional `0x80 + length` prefix that precedes it.
        if (nonce <= 0x7f) {
            uint8 n = uint8(nonce | (nonce == 0 ? 0x80 : 0));
            return _address(keccak256(abi.encodePacked(hex"d694", deployer, n)));
        }
        // A nonce of up to eight bytes, as every account's is, makes a preimage of at most 31
        // bytes: a packed hash of fixed-size values, which needs no allocation.
        if (nonce <= type(uint8).max) {
            return _address(keccak256(abi.encodePacked(hex"d794", deployer, hex"81", uint8(nonce))));
        }
        if (nonce <= type(uint16).max) {
            return
                _address(keccak256(abi.encodePacked(hex"d894", deployer, hex"82", uint16(nonce))));
        }
        if (nonce <= type(uint24).max) {
            return
                _address(keccak256(abi.encodePacked(hex"d994", deployer, hex"83", uint24(nonce))));
        }
        if (nonce <= type(uint32).max) {
            return
                _address(keccak256(abi.encodePacked(hex"da94", deployer, hex"84", uint32(nonce))));
        }
        if (nonce <= type(uint40).max) {
            return
                _address(keccak256(abi.encodePacked(hex"db94", deployer, hex"85", uint40(nonce))));
        }
        if (nonce <= type(uint48).max) {
            return
                _address(keccak256(abi.encodePacked(hex"dc94", deployer, hex"86", uint48(nonce))));
        }
        if (nonce <= type(uint56).max) {
            return
                _address(keccak256(abi.encodePacked(hex"dd94", deployer, hex"87", uint56(nonce))));
        }
        if (nonce <= type(uint64).max) {
            return
                _address(keccak256(abi.encodePacked(hex"de94", deployer, hex"88", uint64(nonce))));
        }
        // The list's prefix, the address, the nonce's prefix and the nonce's `i` bytes, which
        // a word holds for any nonce below `2 ** 72`.
        uint256 i = _byteLength(nonce);
        nonce <<= 256 - 8 * i;
        uint256 w = ((0xd6 + i) << 248) | (0x94 << 240) | (uint256(uint160(deployer)) << 80)
            | ((0x80 + i) << 72) | (nonce >> 184);
        bytes memory preimage = i < 10 ? abi.encodePacked(w) : abi.encodePacked(w, nonce << 72);
        _truncate(preimage, 0x17 + i);
        deployed = _address(keccak256(preimage));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  RLP ENCODING OPERATIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // Note:
    // - addresses are treated like byte strings of length 20, agnostic of leading zero bytes.
    // - uint256s are converted to byte strings, stripped of leading zero bytes, and encoded.
    // - bools are converted to uint256s (`b ? 1 : 0`), then encoded with the uint256.
    // - For bytes1 to bytes32, you must manually convert them to bytes memory
    //   with `abi.encodePacked(x)` before encoding.

    /// @dev Returns a new empty list.
    function p() internal pure returns (List memory result) {}

    /// @dev Returns a new list with `x` as the only element. Equivalent to `LibRLP.p().p(x)`.
    function p(uint256 x) internal pure returns (List memory result) {
        p(result, x);
    }

    /// @dev Returns a new list with `x` as the only element. Equivalent to `LibRLP.p().p(x)`.
    function p(address x) internal pure returns (List memory result) {
        p(result, x);
    }

    /// @dev Returns a new list with `x` as the only element. Equivalent to `LibRLP.p().p(x)`.
    function p(bool x) internal pure returns (List memory result) {
        p(result, x);
    }

    /// @dev Returns a new list with `x` as the only element. Equivalent to `LibRLP.p().p(x)`.
    function p(bytes memory x) internal pure returns (List memory result) {
        p(result, x);
    }

    /// @dev Returns a new list with `x` as the only element. Equivalent to `LibRLP.p().p(x)`.
    function p(List memory x) internal pure returns (List memory result) {
        p(result, x);
    }

    /// @dev Appends `x` to `list`. Returns `list` for function chaining.
    function p(List memory list, uint256 x) internal pure returns (List memory result) {
        result._data = x << 48;
        _updateTail(list, result);
        // If `x` is too big, we cannot pack it inline with the node.
        // We'll have to allocate a new slot for `x` and store the pointer to it in the node.
        if (x >> 208 != 0) result._data = (_addr(List(x)) << 48) | (1 << 40);
        result = list;
    }

    /// @dev Appends `x` to `list`. Returns `list` for function chaining.
    function p(List memory list, address x) internal pure returns (List memory result) {
        result._data = (uint256(uint160(x)) << 48) | (4 << 40);
        _updateTail(list, result);
        result = list;
    }

    /// @dev Appends `x` to `list`. Returns `list` for function chaining.
    function p(List memory list, bool x) internal pure returns (List memory result) {
        result._data = (x ? uint256(1) : 0) << 48;
        _updateTail(list, result);
        result = list;
    }

    /// @dev Appends `x` to `list`. Returns `list` for function chaining.
    function p(List memory list, bytes memory x) internal pure returns (List memory result) {
        result._data = (_addr(x) << 48) | (2 << 40);
        _updateTail(list, result);
        result = list;
    }

    /// @dev Appends `x` to `list`. Returns `list` for function chaining.
    function p(List memory list, List memory x) internal pure returns (List memory result) {
        result._data = (_addr(x) << 48) | (3 << 40);
        _updateTail(list, result);
        result = list;
    }

    /// @dev Returns the RLP encoding of `list`.
    function encode(List memory list) internal pure returns (bytes memory result) {
        // An encoding of at most 32 bytes, as most are, is put together in a word.
        (uint256 w, uint256 end, uint256 h) = _packList(list);
        if (h == 0) {
            result = abi.encodePacked(((0xc0 + end) << 248) | (w >> 8));
            ++end;
        } else {
            // Else the items that fit in the word go after five bytes, room for the longest
            // prefix, and the rest after them; the prefix goes right before them.
            result = new bytes(0x100);
            _writeBytes32(result, 5, bytes32(w));
            (result, end) = _writeItems(result, 5, 5 + end, h, _TOP);
            if (end != _UNKNOWN) {
                uint256 n = end - 5;
                uint256 p = _prefixLength(n);
                _writePrefixAt(result, 5 - p, n);
                return _bytesAt(result, 5 - p, p + n);
            }
            uint256 n = _payloadLength(list);
            (result, end) = _writeList(new bytes(_prefixLength(n) + n + 0x40), 0, list, n);
        }
        _truncate(result, end);
    }

    /// @dev Returns the RLP encoding of `x`.
    function encode(uint256 x) internal pure returns (bytes memory result) {
        if (x <= 0x7f) {
            result = abi.encodePacked((x == 0 ? 0x80 : x) << 248);
            _truncate(result, 1);
            return result;
        }
        uint256 n = _byteLength(x);
        // The prefix and the bytes, a word and a byte at most, the rest zero.
        uint256 left = x << (256 - 8 * n);
        result = abi.encodePacked(((0x80 + n) << 248) | (left >> 8), left << 248);
        _truncate(result, n + 1);
    }

    /// @dev Returns the RLP encoding of `x`.
    function encode(address x) internal pure returns (bytes memory result) {
        result = abi.encodePacked((uint256(0x94) << 248) | (uint256(uint160(x)) << 88));
        _truncate(result, 0x15);
    }

    /// @dev Returns the RLP encoding of `x`.
    function encode(bool x) internal pure returns (bytes memory result) {
        result = abi.encodePacked(uint256(x ? 0x01 : 0x80) << 248);
        _truncate(result, 1);
    }

    /// @dev Returns the RLP encoding of `x`.
    function encode(bytes memory x) internal pure returns (bytes memory result) {
        uint256 n = x.length;
        // A single byte below 0x80 is its own encoding: `x` itself.
        if (n == 1 && uint8(x[0]) < 0x80) return x;
        if (n <= 55) {
            result = abi.encodePacked(uint8(0x80 + n), x, bytes32(0));
            _truncate(result, n + 1);
            return result;
        }
        n += _prefixLength(n);
        result = new bytes(n + 0x20);
        _writeBytes(result, 0, x);
        _truncate(result, n);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PRIVATE HELPERS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The low 40 bits of a list's or node's `_data`: the first node, or the next.
    uint256 private constant _NODE_MASK = 0xffffffffff;

    /// @dev For `_writeList`, the length of a list's items that is not yet known, and the end of
    /// a write that stopped.
    uint256 private constant _UNKNOWN = type(uint256).max;

    /// @dev For `_writeItems`, a first pass over the items of the list being encoded, which
    /// leaves its prefix to the caller.
    uint256 private constant _TOP = type(uint256).max - 1;

    /// @dev The size a buffer of `_writeList`'s first pass grows to at most.
    uint256 private constant _FIRST_PASS_MAX = 0x1000;

    /// @dev Updates the tail in `list`.
    function _updateTail(List memory list, List memory result) private pure {
        uint256 r = _addr(result);
        // `list`'s data, or `result` as its first node if it is empty.
        uint256 v = (r >> list._data) | list._data;
        uint256 tail = v >> 40;
        list._data = ((tail ^ r) << 40) ^ v; // Update the tail.
        if (tail != 0) {
            List memory last = _list(tail);
            last._data |= r; // Make the previous tail point to `result`.
        }
    }

    /// @dev The encodings of `list`'s items left-aligned in a word, and their length, as far as
    /// they take at most 31 bytes, and the node where they stop, or zero after the last.
    function _packList(List memory list) private pure returns (uint256 w, uint256 n, uint256 h) {
        for (h = list._data & _NODE_MASK; h != 0;) {
            uint256 node = _list(h)._data;
            uint256 t = (node >> 40) & 0xff;
            uint256 v = node >> 48;
            // The item's encoding left-aligned in `e`, and its length.
            uint256 e;
            uint256 m;
            if (t <= 1) {
                if (t == 1) v = _list(v)._data;
                if (v <= 0x7f) {
                    (e, m) = ((v == 0 ? 0x80 : v) << 248, 1);
                } else {
                    m = _byteLength(v);
                    (e, m) = (((0x80 + m) << 248) | ((v << (256 - 8 * m)) >> 8), m + 1);
                }
            } else if (t == 2) {
                bytes memory x = _bytes(v);
                m = x.length;
                if (m > 30) return (w, n, h);
                e = uint256(_readBytesN(x, 0, m));
                if (m != 1 || e >= 0x80 << 248) (e, m) = (((0x80 + m) << 248) | (e >> 8), m + 1);
            } else if (t == 3) {
                uint256 rest;
                (e, m, rest) = _packList(_list(v));
                if (rest != 0) return (w, n, h);
                (e, m) = (((0xc0 + m) << 248) | (e >> 8), m + 1);
            } else {
                (e, m) = ((0x94 << 248) | (uint256(uint160(v)) << 88), 0x15);
            }
            if (n + m > 0x1f) return (w, n, h);
            w |= e >> (8 * n);
            n += m;
            h = node & _NODE_MASK;
        }
    }

    /// @dev The length of the encodings of `list`'s items.
    function _payloadLength(List memory list) private pure returns (uint256 n) {
        for (uint256 h = list._data & _NODE_MASK; h != 0;) {
            uint256 node = _list(h)._data;
            uint256 t = (node >> 40) & 0xff;
            uint256 v = node >> 48;
            if (t <= 1) {
                if (t == 1) v = _list(v)._data;
                n += v <= 0x7f ? 1 : 1 + _byteLength(v);
            } else if (t == 2) {
                bytes memory x = _bytes(v);
                uint256 m = x.length;
                n += m == 1 && uint8(x[0]) < 0x80 ? 1 : _prefixLength(m) + m;
            } else if (t == 3) {
                uint256 m = _payloadLength(_list(v));
                n += _prefixLength(m) + m;
            } else {
                n += 0x15;
            }
            h = node & _NODE_MASK;
        }
    }

    /// @dev Writes the encoding of `list` into `out` at `o`, and returns the buffer, `out` or a
    /// bigger copy, and where the encoding ends in it. As with every write below, the buffer
    /// has room past the encoding, and what is written past it is zero. `n` is the length of
    /// the items' encodings, or `_UNKNOWN` for a first pass: then a byte is left for the
    /// prefix and the items move up after if it needs more, and should the buffer need to
    /// grow past `_FIRST_PASS_MAX` bytes, the write stops and returns `_UNKNOWN` as the end, so
    /// that the lengths are worked out first and nothing moves.
    function _writeList(bytes memory out, uint256 o, List memory list, uint256 n)
        private
        pure
        returns (bytes memory, uint256)
    {
        uint256 h = list._data & _NODE_MASK;
        if (n == _UNKNOWN) return _writeItems(out, o, o + 1, h, n);
        return _writeItems(out, o, _writePrefix(out, o, n, 0xc0), h, n);
    }

    /// @dev Writes the encodings of a list's items from the node `h` on into `out` at `o`, the
    /// list's encoding starting at `start`, and finishes it as `_writeList` does.
    function _writeItems(bytes memory out, uint256 start, uint256 o, uint256 h, uint256 n)
        private
        pure
        returns (bytes memory, uint256)
    {
        for (; h != 0;) {
            uint256 node = _list(h)._data;
            uint256 t = (node >> 40) & 0xff;
            uint256 v = node >> 48;
            if (t == 2) {
                bytes memory x = _bytes(v);
                // Room for the string and its prefix.
                if (o + x.length + 0x25 > out.length) {
                    out = _grow(out, o, x.length + 5);
                    if (out.length == 0) return (out, _UNKNOWN);
                }
                o = _writeBytes(out, o, x);
            } else if (t == 3) {
                List memory sub = _list(v);
                (out, o) = _writeList(out, o, sub, n >= _TOP ? _UNKNOWN : _payloadLength(sub));
                if (o == _UNKNOWN) return (out, o);
            } else {
                // Room for a number, which takes at most 33 bytes, or an address.
                if (o + 0x41 > out.length) {
                    out = _grow(out, o, 0x21);
                    if (out.length == 0) return (out, _UNKNOWN);
                }
                if (t <= 1) o = _writeUint(out, o, t == 1 ? _list(v)._data : v);
                else o = _writeAddress(out, o, v);
            }
            h = node & _NODE_MASK;
        }
        if (n != _UNKNOWN) return (out, o);
        n = o - start - 1;
        if (n <= 55) {
            out[start] = bytes1(uint8(0xc0 + n));
            return (out, o);
        }
        uint256 l = _lengthOfLength(n);
        if (o + l + 0x20 > out.length) {
            out = _grow(out, o, l);
            if (out.length == 0) return (out, _UNKNOWN);
        }
        // Move the items up by `l`, a word at a time from the end, so that no word is read
        // after it is overwritten, and put the prefix before them.
        uint256 from = start + 1;
        uint256 k = n;
        while (k >= 32) {
            k -= 32;
            _writeBytes32(out, from + l + k, _readBytes32(out, from + k));
        }
        if (k != 0) _writeBytesN(out, from + l, _readBytesN(out, from, k), k);
        _writeBytesN(out, start, bytes32(((0xf7 + l) << 248) | (n << (248 - 8 * l))), 1 + l);
        return (out, o + l);
    }

    /// @dev A copy of the first `o` bytes of `out` in a buffer at least twice as long, with
    /// room for `n` bytes and a word at `o`, if the first pass may grow that big, else an empty
    /// one.
    function _grow(bytes memory out, uint256 o, uint256 n)
        private
        pure
        returns (bytes memory bigger)
    {
        uint256 size = 2 * out.length;
        if (size < o + n + 0x20) size = o + n + 0x20;
        if (size > _FIRST_PASS_MAX) return bigger;
        bigger = new bytes(size);
        for (uint256 k; k < o; ++k) {
            bigger[k] = out[k];
        }
    }

    /// @dev Writes the encoding of the address `x` into `out` at `o`, and returns where it ends.
    /// @custom:solar-inline
    function _writeAddress(bytes memory out, uint256 o, uint256 x) private pure returns (uint256) {
        _writeBytes32(out, o, bytes32((0x94 << 248) | (uint256(uint160(x)) << 88)));
        return o + 0x15;
    }

    /// @dev Writes the encoding of the number `x` into `out` at `o`, and returns where it ends.
    /// @custom:solar-inline
    function _writeUint(bytes memory out, uint256 o, uint256 x) private pure returns (uint256) {
        if (x <= 0x7f) {
            _writeBytes32(out, o, bytes32((x == 0 ? 0x80 : x) << 248));
            return o + 1;
        }
        uint256 n = _byteLength(x);
        _writeBytes32(out, o, bytes32(((0x80 + n) << 248) | ((x << (256 - 8 * n)) >> 8)));
        if (n == 32) out[o + 32] = bytes1(uint8(x));
        return o + 1 + n;
    }

    /// @dev Writes the encoding of the string `x` into `out` at `o`, and returns where it ends.
    /// @custom:solar-inline
    function _writeBytes(bytes memory out, uint256 o, bytes memory x)
        private
        pure
        returns (uint256)
    {
        uint256 n = x.length;
        if (n < 32) {
            uint256 w = uint256(_readBytesN(x, 0, n));
            // A single byte below 0x80 is its own encoding.
            if (n == 1 && w < 0x80 << 248) {
                _writeBytes32(out, o, bytes32(w));
                return o + 1;
            }
            _writeBytes32(out, o, bytes32(((0x80 + n) << 248) | (w >> 8)));
            return o + 1 + n;
        }
        o = _writePrefix(out, o, n, 0x80);
        for (uint256 k; k < n; ++k) {
            out[o + k] = x[k];
        }
        return o + n;
    }

    /// @dev Writes the prefix of a list of `n` bytes into `out` at `o`, before bytes already
    /// written.
    function _writePrefixAt(bytes memory out, uint256 o, uint256 n) private pure {
        if (n <= 55) {
            out[o] = bytes1(uint8(0xc0 + n));
            return;
        }
        uint256 l = _lengthOfLength(n);
        _writeBytesN(out, o, bytes32(((0xf7 + l) << 248) | (n << (248 - 8 * l))), 1 + l);
    }

    /// @dev Writes the prefix of a string or list of `n` bytes, with `c` its base, into `out`
    /// at `o`, and returns where it ends.
    /// @custom:solar-inline
    function _writePrefix(bytes memory out, uint256 o, uint256 n, uint256 c)
        private
        pure
        returns (uint256)
    {
        if (n <= 55) {
            _writeBytes32(out, o, bytes32((c + n) << 248));
            return o + 1;
        }
        uint256 l = _lengthOfLength(n);
        _writeBytes32(out, o, bytes32(((c + 55 + l) << 248) | (n << (248 - 8 * l))));
        return o + 1 + l;
    }

    /// @dev The length of the prefix of a string or list of `n` bytes.
    /// @custom:solar-inline
    function _prefixLength(uint256 n) private pure returns (uint256) {
        return n <= 55 ? 1 : 1 + _lengthOfLength(n);
    }

    /// @dev The number of bytes of `n`, a length above 55, in a long prefix. Upstream halts
    /// past four, on a length that memory cannot hold.
    /// @custom:solar-inline
    function _lengthOfLength(uint256 n) private pure returns (uint256) {
        if (n >> 32 != 0) revert();
        return _byteLength(n);
    }

    /// @dev The number of bytes of `x` from its first nonzero one, at least one: its base-256
    /// logarithm plus one, by the binary search of `log2` to whole bytes.
    /// @custom:solar-inline
    function _byteLength(uint256 x) private pure returns (uint256) {
        uint256 r = (x > type(uint128).max ? 1 : 0) << 7;
        r |= ((x >> r) > type(uint64).max ? 1 : 0) << 6;
        r |= ((x >> r) > type(uint32).max ? 1 : 0) << 5;
        r |= ((x >> r) > type(uint16).max ? 1 : 0) << 4;
        r |= ((x >> r) > type(uint8).max ? 1 : 0) << 3;
        return (r >> 3) + 1;
    }

    /// @dev The address in the low 20 bytes of the hash `h`.
    function _address(bytes32 h) private pure returns (address) {
        return address(uint160(uint256(h)));
    }

    /// @dev The 32 bytes of `b` at `offset`.
    /// @custom:solar-inline
    function _readBytes32(bytes memory b, uint256 offset) private pure returns (bytes32 result) {
        for (uint256 k; k < 32; ++k) {
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

    /// @dev Shrinks `b` to its first `n` bytes in place. Solidity cannot spell a shorter length
    /// for an existing buffer.
    /// @custom:solar-trusted
    function _truncate(bytes memory b, uint256 n) private pure {
        if (n > b.length) n = new uint256[](0)[0];
        /// @solidity memory-safe-assembly
        assembly {
            mstore(b, n)
        }
    }

    /// @dev The `n` bytes of `b` from `offset` on as a `bytes`, whose length takes the place of
    /// the word before them, which the caller has no use for. Solidity cannot refer into a
    /// buffer.
    /// @custom:solar-trusted
    function _bytesAt(bytes memory b, uint256 offset, uint256 n)
        private
        pure
        returns (bytes memory result)
    {
        if (offset + n > b.length) n = new uint256[](0)[0];
        /// @solidity memory-safe-assembly
        assembly {
            result := add(b, offset)
            mstore(result, n)
        }
    }

    /// @dev The address of `x`, which a node holds. Solidity cannot convert a reference to
    /// an address.
    /// @custom:solar-trusted
    /// @custom:solar-inline
    function _addr(List memory x) private pure returns (uint256 result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := x
        }
    }

    /// @dev The address of `x`, which a node holds.
    /// @custom:solar-trusted
    /// @custom:solar-inline
    function _addr(bytes memory x) private pure returns (uint256 result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := x
        }
    }

    /// @dev The list, node or word at `ptr`, an address that a list's or a node's `_data`
    /// holds. Solidity cannot convert an address to a reference.
    /// @custom:solar-trusted
    /// @custom:solar-inline
    function _list(uint256 ptr) private pure returns (List memory result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := ptr
        }
    }

    /// @dev The string at `ptr`, an address that a node's `_data` holds.
    /// @custom:solar-trusted
    /// @custom:solar-inline
    function _bytes(uint256 ptr) private pure returns (bytes memory result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := ptr
        }
    }
}
