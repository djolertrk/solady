// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @notice Library for generating pseudorandom numbers.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/LibPRNG.sol)
/// @author LazyShuffler based on NextShuffler by aschlosberg (divergencearran)
/// (https://github.com/divergencetech/ethier/blob/main/contracts/random/NextShuffler.sol)
/// @dev The checked port draws the same numbers and makes the same swaps as the
/// assembly. The normal sample's lane sum multiplies past the word on purpose, so
/// it goes through the raw `_mul`. A lazy shuffler keeps its packed state in its
/// struct and its permutation in the slots the assembly derives from the struct's
/// slot; trusted helpers name that slot and read and write the derived ones, and
/// the signed and address shuffles go through upstream's trusted array casts. A
/// shuffle keeps the state in a local and stores it when it ends, where the
/// assembly stores it after every draw: they differ only for an array that
/// overlaps the generator's memory.
/// @custom:solar-safe memory arithmetic
library LibPRNG {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The initial length must be greater than zero and less than `2**32 - 1`.
    error InvalidInitialLazyShufflerLength();

    /// @dev The new length must not be less than the current length.
    /// It must also be less than `2**32 - 1`.
    error InvalidNewLazyShufflerLength();

    /// @dev The lazy shuffler has not been initialized.
    error LazyShufflerNotInitialized();

    /// @dev Cannot double initialize the lazy shuffler.
    error LazyShufflerAlreadyInitialized();

    /// @dev The lazy shuffle has finished.
    error LazyShuffleFinished();

    /// @dev The queried index is out of bounds.
    error LazyShufflerGetOutOfBounds();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The scalar of ETH and most ERC20s.
    uint256 internal constant WAD = 1e18;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STRUCTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev A pseudorandom number state in memory.
    struct PRNG {
        uint256 state;
    }

    /// @dev A lazy Fisher-Yates shuffler for a range `[0..n)` in storage.
    struct LazyShuffler {
        // Bits Layout:
        // - [0..31]    `numShuffled`
        // - [32..223]  `permutationSlot`
        // - [224..255] `length`
        uint256 _state;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         OPERATIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Seeds the `prng` with `state`.
    function seed(PRNG memory prng, uint256 state) internal pure {
        prng.state = state;
    }

    /// @dev Returns the next pseudorandom uint256.
    /// All bits of the returned uint256 pass the NIST Statistical Test Suite.
    function next(PRNG memory prng) internal pure returns (uint256 result) {
        // We simply use `keccak256` for a great balance between
        // runtime gas costs, bytecode size, and statistical properties.
        result = uint256(keccak256(abi.encode(prng.state)));
        prng.state = result;
    }

    /// @dev Returns a pseudorandom uint256, uniformly distributed
    /// between 0 (inclusive) and `upper` (exclusive).
    /// If your modulus is big, this method is recommended
    /// for uniform sampling to avoid modulo bias.
    /// For uniform sampling across all uint256 values,
    /// or for small enough moduli such that the bias is negligible,
    /// use {next} instead.
    function uniform(PRNG memory prng, uint256 upper) internal pure returns (uint256 result) {
        // `2**256 % upper`: draws below it would bias the remainder.
        uint256 threshold = upper == 0 ? 0 : (type(uint256).max - upper + 1) % upper;
        do {
            result = next(prng);
        } while (result < threshold);
        result = upper == 0 ? 0 : result % upper;
    }

    /// @dev Returns a sample from the standard normal distribution denominated in `WAD`.
    function standardNormalWad(PRNG memory prng) internal pure returns (int256 result) {
        // Technically, this is the Irwin-Hall distribution with 20 samples.
        // The chance of drawing a sample outside 10 σ from the standard normal distribution
        // is ≈ 0.000000000000000000000015, which is insignificant for most practical purposes.
        // Passes the Kolmogorov-Smirnov test for 200k samples.
        uint256 r0 = next(prng);
        uint256 n = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff43; // Prime.
        uint256 a = 0x100000000000000000000000000000051; // Prime and a primitive root of `n`.
        uint256 m = 0x1fffffffffffffff1fffffffffffffff1fffffffffffffff1fffffffffffffff;
        uint256 r1 = mulmod(r0, a, n);
        uint256 r2 = mulmod(r1, a, n);
        uint256 r3 = mulmod(r2, a, n);
        uint256 sum = _laneSum((m & r0) + (m & r1)) + _laneSum((m & r2) + (m & r3))
            + _laneSum(m & mulmod(r3, a, n));
        result = (int256(26614938895861601847173011183 * sum) >> 96) - 7745966692414833770;
    }

    /// @dev Returns a sample from the unit exponential distribution denominated in `WAD`.
    function exponentialWad(PRNG memory prng) internal pure returns (uint256 result) {
        // Passes the Kolmogorov-Smirnov test for 200k samples.
        uint256 r = next(prng);
        uint256 p = r << 129;
        uint256 w = r << 1;
        if (w <= p) {
            uint256 n = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff43; // Prime.
            uint256 a = 0x100000000000000000000000000000051; // Prime and a primitive root of `n`.
            while (true) {
                r = mulmod(r, a, n);
                if (r << 129 >= w) {
                    r = mulmod(r, a, n);
                    result += 1000000000000000000;
                    w = r << 1;
                    p = r << 129;
                    if (w >= p) break;
                    continue;
                }
                w = r << 1;
                if (w >= r << 129) break;
            }
        }
        result += p / (uint256(170141183460469231732) << 129);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*             MEMORY ARRAY SHUFFLING OPERATIONS              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Shuffles the array in-place with Fisher-Yates shuffle.
    function shuffle(PRNG memory prng, uint256[] memory a) internal pure {
        uint256 n = a.length;
        if (n == 0) return;
        // The state stays in a local until the shuffle ends.
        uint256 r = prng.state;
        while (true) {
            r = uint256(keccak256(abi.encode(r)));
            // Note that there will be a very tiny modulo bias
            // if the length of the array is not a power of 2.
            // For all practical purposes, it is negligible
            // and will not be a fairness or security concern.
            uint256 j = (r >> 128) % n;
            if (--n == 0) break;
            (a[n], a[j]) = (a[j], a[n]);
            j = (r & type(uint128).max) % n;
            if (--n == 0) break;
            (a[n], a[j]) = (a[j], a[n]);
        }
        prng.state = r;
    }

    /// @dev Shuffles the array in-place with Fisher-Yates shuffle.
    function shuffle(PRNG memory prng, int256[] memory a) internal pure {
        shuffle(prng, _toUints(a));
    }

    /// @dev Shuffles the array in-place with Fisher-Yates shuffle.
    function shuffle(PRNG memory prng, address[] memory a) internal pure {
        shuffle(prng, _toUints(a));
    }

    /// @dev Partially shuffles the array in-place with Fisher-Yates shuffle.
    /// The first `k` elements will be uniformly sampled without replacement.
    function shuffle(PRNG memory prng, uint256[] memory a, uint256 k) internal pure {
        uint256 n = a.length;
        if (k > n) k = n;
        if (k == 0) return;
        uint256 b;
        // The state stays in a local until the shuffle ends.
        uint256 r = prng.state;
        while (true) {
            r = uint256(keccak256(abi.encode(r)));
            // Note that there will be a very tiny modulo bias
            // if the length of the array is not a power of 2.
            // For all practical purposes, it is negligible
            // and will not be a fairness or security concern.
            uint256 j = b + (r >> 128) % (n - b);
            (a[b], a[j]) = (a[j], a[b]);
            if (++b == k) break;
            j = b + (r & type(uint128).max) % (n - b);
            (a[b], a[j]) = (a[j], a[b]);
            if (++b == k) break;
        }
        prng.state = r;
    }

    /// @dev Partially shuffles the array in-place with Fisher-Yates shuffle.
    /// The first `k` elements will be uniformly sampled without replacement.
    function shuffle(PRNG memory prng, int256[] memory a, uint256 k) internal pure {
        shuffle(prng, _toUints(a), k);
    }

    /// @dev Partially shuffles the array in-place with Fisher-Yates shuffle.
    /// The first `k` elements will be uniformly sampled without replacement.
    function shuffle(PRNG memory prng, address[] memory a, uint256 k) internal pure {
        shuffle(prng, _toUints(a), k);
    }

    /// @dev Shuffles the bytes in-place with Fisher-Yates shuffle.
    function shuffle(PRNG memory prng, bytes memory a) internal pure {
        uint256 n = a.length;
        if (n == 0) return;
        // The state stays in a local until the shuffle ends.
        uint256 r = prng.state;
        while (true) {
            r = uint256(keccak256(abi.encode(r)));
            // Note that there will be a very tiny modulo bias
            // if the length of the array is not a power of 2.
            // For all practical purposes, it is negligible
            // and will not be a fairness or security concern.
            uint256 o = (r >> 128) % n;
            if (--n == 0) break;
            (a[n], a[o]) = (a[o], a[n]);
            o = (r & type(uint128).max) % n;
            if (--n == 0) break;
            (a[n], a[o]) = (a[o], a[n]);
        }
        prng.state = r;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*       STORAGE-BASED RANGE LAZY SHUFFLING OPERATIONS        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Initializes the state for lazy-shuffling the range `[0..n)`.
    /// Reverts if `n == 0 || n >= 2**32 - 1`.
    /// Reverts if `$` has already been initialized.
    /// If you need to reduce the length after initialization, just use a fresh new `$`.
    function initialize(LazyShuffler storage $, uint256 n) internal {
        if (n == 0 || n > 0xfffffffe) revert InvalidInitialLazyShufflerLength();
        if ($._state != 0) revert LazyShufflerAlreadyInitialized();
        uint256 permutationSlot = uint256(keccak256(abi.encode(_slotOf($)))) >> 64;
        $._state = (n << 224) | (permutationSlot << 32);
    }

    /// @dev Increases the length of `$`.
    /// Reverts if `$` has not been initialized.
    /// Reverts if `n` is less than the current length, or if `n >= 2**32 - 1`.
    /// Reverts if `n` crosses the entry width boundary at a length of 65535.
    function grow(LazyShuffler storage $, uint256 n) internal {
        uint256 state = $._state; // The packed value at `$`.
        if (state == 0) revert LazyShufflerNotInitialized();
        uint256 o = state >> 224; // The old length.
        uint256 limit = o > 0xfffe ? 0xfffffffe : 0xfffe;
        if (n < o || n > limit) revert InvalidNewLazyShufflerLength();
        $._state = (n << 224) | ((state << 32) >> 32);
    }

    /// @dev Restarts the shuffler by setting `numShuffled` to zero,
    /// such that all elements can be drawn again.
    /// Restarting does NOT clear the internal permutation, nor changes the length.
    /// Even with the same sequence of randomness, reshuffling can yield different results.
    function restart(LazyShuffler storage $) internal {
        uint256 state = $._state;
        if (state == 0) revert LazyShufflerNotInitialized();
        $._state = (state >> 32) << 32;
    }

    /// @dev Returns the number of elements that have been shuffled.
    function numShuffled(LazyShuffler storage $) internal view returns (uint256 result) {
        result = $._state & 0xffffffff;
    }

    /// @dev Returns the length of `$`.
    /// Returns zero if `$` is not initialized, else a non-zero value less than `2**32 - 1`.
    function length(LazyShuffler storage $) internal view returns (uint256 result) {
        result = $._state >> 224;
    }

    /// @dev Returns if `$` has been initialized.
    function initialized(LazyShuffler storage $) internal view returns (bool result) {
        result = $._state != 0;
    }

    /// @dev Returns if there are any more elements left to shuffle.
    /// Reverts if `$` is not initialized.
    function finished(LazyShuffler storage $) internal view returns (bool result) {
        uint256 state = $._state; // The packed value at `$`.
        if (state == 0) revert LazyShufflerNotInitialized();
        result = state >> 224 == state & 0xffffffff;
    }

    /// @dev Returns the current value stored at `index`, accounting for all historical shuffling.
    /// Reverts if `index` is greater than or equal to the `length` of `$`.
    function get(LazyShuffler storage $, uint256 index) internal view returns (uint256 result) {
        uint256 state = $._state; // The packed value at `$`.
        uint256 n = state >> 224; // Length of `$`.
        if (index >= n) revert LazyShufflerGetOutOfBounds();
        result = _getAt(n > 0xfffe, state, index);
    }

    /// @dev Does a single Fisher-Yates shuffle step, increments the `numShuffled` in `$`,
    /// and returns the next value in the shuffled range.
    /// `randomness` can be taken from a good-enough source, or a higher quality source like VRF.
    /// Reverts if there are no more values to shuffle, which includes the case if `$` is not initialized.
    function next(LazyShuffler storage $, uint256 randomness) internal returns (uint256 chosen) {
        uint256 state = $._state; // The packed value at `$`.
        uint256 shuffled = state & 0xffffffff; // Number of elements shuffled.
        uint256 n = state >> 224; // Length of `$`.
        uint256 remainder = n - shuffled; // Number of elements left to shuffle.
        if (remainder == 0) revert LazyShuffleFinished();
        // (Re)hash the randomness so that we don't
        // need to expect guarantees on its distribution.
        uint256 index = uint256(keccak256(abi.encode(randomness, shuffled))) % remainder + shuffled;
        bool u32 = n > 0xfffe;
        chosen = _getAt(u32, state, index);
        _setAt(u32, state, index, _getAt(u32, state, shuffled));
        _setAt(u32, state, shuffled, chosen);
        $._state = state + 1; // Increment the `numShuffled` by 1, and store it.
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PRIVATE HELPERS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Reinterpret cast to an uint256 array.
    /// @custom:solar-trusted
    function _toUints(int256[] memory a) private pure returns (uint256[] memory casted) {
        /// @solidity memory-safe-assembly
        assembly {
            casted := a
        }
    }

    /// @dev Reinterpret cast to an uint256 array.
    /// @custom:solar-trusted
    function _toUints(address[] memory a) private pure returns (uint256[] memory casted) {
        /// @solidity memory-safe-assembly
        assembly {
            // As any address written to memory will have the upper 96 bits
            // of the word zeroized (as per Solidity spec), we can directly
            // compare these addresses as if they are whole uint256 words.
            casted := a
        }
    }

    /// @dev The sum of the four 64-bit lanes of `x`, which the multiplication gathers in its
    /// top lane: the bits it carries past the word are dropped, as the assembly drops them.
    function _laneSum(uint256 x) private pure returns (uint256) {
        return _mul(0x1000000000000000100000000000000010000000000000001, x) >> 192;
    }

    /// @dev The permuted value at `i`, or `i` itself where the permutation holds zero: entries
    /// are 16 bits wide, or 32 bits once the length passes `0xfffe`, at `permutationSlot`
    /// onwards.
    function _getAt(bool u32, uint256 state, uint256 i) private view returns (uint256 value) {
        uint256 w = u32 ? 1 : 0;
        uint256 s = (i >> (4 - w)) + ((state << 32) >> 64); // Bucket slot.
        uint256 o = (i & (15 >> w)) << (4 + w); // Bucket slot offset (bits).
        uint256 m = (uint256(1) << (16 << w)) - 1; // Value mask.
        value = (_sload(s) >> o) & m;
        value = value == 0 ? i : value - 1;
    }

    /// @dev Records `value` at `i`, as zero where it is `i` itself.
    function _setAt(bool u32, uint256 state, uint256 i, uint256 value) private {
        uint256 w = u32 ? 1 : 0;
        uint256 s = (i >> (4 - w)) + ((state << 32) >> 64); // Bucket slot.
        uint256 o = (i & (15 >> w)) << (4 + w); // Bucket slot offset (bits).
        uint256 m = (uint256(1) << (16 << w)) - 1; // Value mask.
        uint256 v = _sload(s); // Bucket slot value.
        value = i == value ? 0 : value + 1;
        _sstore(s, v ^ ((((v >> o) ^ value) & m) << o));
    }

    /// @dev Unchecked arithmetic for multiplying two numbers.
    /// @custom:solar-trusted
    function _mul(uint256 a, uint256 b) private pure returns (uint256 c) {
        unchecked {
            c = a * b;
        }
    }

    /// @dev The storage slot of `$`, which Solidity spells only in assembly.
    /// @custom:solar-trusted
    function _slotOf(LazyShuffler storage $) private pure returns (uint256 slot) {
        /// @solidity memory-safe-assembly
        assembly {
            slot := $.slot
        }
    }

    /// @dev The word in storage slot `slot`. Solidity cannot name a slot it did not allocate.
    /// @custom:solar-trusted
    function _sload(uint256 slot) private view returns (uint256 value) {
        /// @solidity memory-safe-assembly
        assembly {
            value := sload(slot)
        }
    }

    /// @dev Stores `value` in storage slot `slot`.
    /// @custom:solar-trusted
    function _sstore(uint256 slot, uint256 value) private {
        /// @solidity memory-safe-assembly
        assembly {
            sstore(slot, value)
        }
    }
}
