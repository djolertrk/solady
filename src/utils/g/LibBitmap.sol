// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// This file is auto-generated.

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*                          STRUCTS                           */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

/// @dev A bitmap in storage.
struct Bitmap {
    mapping(uint256 => uint256) map;
}

using LibBitmap for Bitmap global;

import {LibBit} from "../LibBit.sol";

/// @notice Library for storage of packed unsigned booleans.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/g/LibBitmap.sol)
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/utils/LibBitmap.sol)
/// @author Modified from Solidity-Bits (https://github.com/estarriolvetch/solidity-bits/blob/main/contracts/BitMaps.sol)
/// @dev The checked port spells the assembly's word operations in Solidity, over
/// the same mapping slots. A batch's `start + amount` and a scan's bucket steps
/// are checked: the assembly wraps them only for ranges of more bits than any
/// call can touch.
/// @custom:solar-safe memory arithmetic
library LibBitmap {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The constant returned when a bitmap scan does not find a result.
    uint256 internal constant NOT_FOUND = type(uint256).max;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         OPERATIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns the boolean value of the bit at `index` in `bitmap`.
    function get(Bitmap storage bitmap, uint256 index) internal view returns (bool isSet) {
        isSet = (bitmap.map[index >> 8] >> (index & 0xff)) & 1 != 0;
    }

    /// @dev Updates the bit at `index` in `bitmap` to true.
    function set(Bitmap storage bitmap, uint256 index) internal {
        bitmap.map[index >> 8] |= (1 << (index & 0xff));
    }

    /// @dev Updates the bit at `index` in `bitmap` to false.
    function unset(Bitmap storage bitmap, uint256 index) internal {
        bitmap.map[index >> 8] &= ~(1 << (index & 0xff));
    }

    /// @dev Flips the bit at `index` in `bitmap`.
    /// Returns the boolean result of the flipped bit.
    function toggle(Bitmap storage bitmap, uint256 index) internal returns (bool newIsSet) {
        uint256 shift = index & 0xff;
        uint256 storageValue = bitmap.map[index >> 8] ^ (1 << shift);
        bitmap.map[index >> 8] = storageValue;
        newIsSet = (storageValue >> shift) & 1 != 0;
    }

    /// @dev Updates the bit at `index` in `bitmap` to `shouldSet`.
    function setTo(Bitmap storage bitmap, uint256 index, bool shouldSet) internal {
        uint256 shift = index & 0xff;
        uint256 storageValue = bitmap.map[index >> 8];
        uint256 bit = shouldSet ? 1 : 0;
        // Unsets the bit at `shift` via `and`, then sets its new value via `or`.
        bitmap.map[index >> 8] = (storageValue & ~(uint256(1) << shift)) | (bit << shift);
    }

    /// @dev Consecutively sets `amount` of bits starting from the bit at `start`.
    function setBatch(Bitmap storage bitmap, uint256 start, uint256 amount) internal {
        uint256 shift = start & 0xff;
        uint256 bucket = start >> 8;
        if (shift + amount > 256) {
            bitmap.map[bucket] |= type(uint256).max << shift;
            uint256 bucketEnd = bucket + ((amount + shift) >> 8);
            amount = (amount + shift) & 0xff;
            shift = 0;
            for (++bucket; bucket != bucketEnd; ++bucket) {
                bitmap.map[bucket] = type(uint256).max;
            }
        }
        bitmap.map[bucket] |= (type(uint256).max >> (256 - amount)) << shift;
    }

    /// @dev Consecutively unsets `amount` of bits starting from the bit at `start`.
    function unsetBatch(Bitmap storage bitmap, uint256 start, uint256 amount) internal {
        uint256 shift = start & 0xff;
        uint256 bucket = start >> 8;
        if (shift + amount > 256) {
            bitmap.map[bucket] &= ~(type(uint256).max << shift);
            uint256 bucketEnd = bucket + ((amount + shift) >> 8);
            amount = (amount + shift) & 0xff;
            shift = 0;
            for (++bucket; bucket != bucketEnd; ++bucket) {
                bitmap.map[bucket] = 0;
            }
        }
        bitmap.map[bucket] &= ~((type(uint256).max >> (256 - amount)) << shift);
    }

    /// @dev Returns number of set bits within a range by
    /// scanning `amount` of bits starting from the bit at `start`.
    function popCount(Bitmap storage bitmap, uint256 start, uint256 amount)
        internal
        view
        returns (uint256 count)
    {
        uint256 bucket = start >> 8;
        uint256 shift = start & 0xff;
        if (!(amount + shift < 257)) {
            count = LibBit.popCount(bitmap.map[bucket] >> shift);
            uint256 bucketEnd = bucket + ((amount + shift) >> 8);
            amount = (amount + shift) & 0xff;
            shift = 0;
            for (++bucket; bucket != bucketEnd; ++bucket) {
                count += LibBit.popCount(bitmap.map[bucket]);
            }
        }
        count += LibBit.popCount((bitmap.map[bucket] >> shift) << (256 - amount));
    }

    /// @dev Returns the index of the most significant set bit in `[0..upTo]`.
    /// If no set bit is found, returns `NOT_FOUND`.
    function findLastSet(Bitmap storage bitmap, uint256 upTo)
        internal
        view
        returns (uint256 setBitIndex)
    {
        setBitIndex = NOT_FOUND;
        uint256 bucket = upTo >> 8;
        // `256 - (255 & upTo) - 1`.
        uint256 offset = 0xff & ~upTo;
        uint256 bits = (bitmap.map[bucket] << offset) >> offset;
        while (bits == 0 && bucket != 0) {
            bits = bitmap.map[--bucket];
        }
        if (bits != 0) {
            setBitIndex = (bucket << 8) | LibBit.fls(bits);
            if (setBitIndex > upTo) setBitIndex = NOT_FOUND;
        }
    }

    /// @dev Returns the index of the least significant unset bit in `[begin..upTo]`.
    /// If no unset bit is found, returns `NOT_FOUND`.
    function findFirstUnset(Bitmap storage bitmap, uint256 begin, uint256 upTo)
        internal
        view
        returns (uint256 unsetBitIndex)
    {
        unsetBitIndex = NOT_FOUND;
        uint256 bucket = begin >> 8;
        uint256 offset = begin & 0xff;
        uint256 negBits = (~bitmap.map[bucket] >> offset) << offset;
        if (negBits == 0) {
            uint256 lastBucket = upTo >> 8;
            do {
                negBits = ~bitmap.map[++bucket];
            } while (negBits == 0 && bucket <= lastBucket);
            if (bucket > lastBucket) {
                uint256 o = 0xff & ~upTo;
                negBits = (negBits >> o) << o;
            }
        }
        if (negBits != 0) {
            uint256 r = (bucket << 8) | LibBit.ffs(negBits);
            if (r <= upTo && r >= begin) unsetBitIndex = r;
        }
    }
}
