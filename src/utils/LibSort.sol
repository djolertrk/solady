// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Arrays} from "solar:core/v1/Arrays.sol";
import {WordArrays} from "solar:core/v1/WordArrays.sol";

/// @notice Checked Solidity sorting without type punning or sentinel reads.
/// @dev Shrinking an array in place has no Solidity spelling, so the APIs
/// that do it go through the compiler-owned `Arrays.truncate`.
library LibSort {
    function insertionSort(uint256[] memory a) internal pure {
        WordArrays.sort(a);
    }

    function sort(uint256[] memory a) internal pure {
        WordArrays.sort(a);
    }

    function reverse(uint256[] memory a) internal pure {
        for (uint256 i; i < a.length / 2; ++i) {
            uint256 j = a.length - 1 - i;
            (a[i], a[j]) = (a[j], a[i]);
        }
    }

    function copy(uint256[] memory a) internal pure returns (uint256[] memory result) {
        result = new uint256[](a.length);
        for (uint256 i; i < a.length; ++i) {
            result[i] = a[i];
        }
    }

    function isSorted(uint256[] memory a) internal pure returns (bool result) {
        for (uint256 i = 1; i < a.length; ++i) {
            if (a[i - 1] > a[i]) return false;
        }
        return true;
    }

    function isSortedAndUniquified(uint256[] memory a) internal pure returns (bool result) {
        for (uint256 i = 1; i < a.length; ++i) {
            if (a[i - 1] >= a[i]) return false;
        }
        return true;
    }

    function hasDuplicate(uint256[] memory a) internal pure returns (bool result) {
        return WordArrays.hasDuplicate(a);
    }

    /// @dev Removes duplicate elements from a ascendingly sorted memory array.
    function uniquifySorted(uint256[] memory a) internal pure {
        WordArrays.uniquifySorted(a);
    }

    function insertionSort(int256[] memory a) internal pure {
        WordArrays.sort(a);
    }

    function sort(int256[] memory a) internal pure {
        WordArrays.sort(a);
    }

    function reverse(int256[] memory a) internal pure {
        for (uint256 i; i < a.length / 2; ++i) {
            uint256 j = a.length - 1 - i;
            (a[i], a[j]) = (a[j], a[i]);
        }
    }

    function copy(int256[] memory a) internal pure returns (int256[] memory result) {
        result = new int256[](a.length);
        for (uint256 i; i < a.length; ++i) {
            result[i] = a[i];
        }
    }

    function isSorted(int256[] memory a) internal pure returns (bool result) {
        for (uint256 i = 1; i < a.length; ++i) {
            if (a[i - 1] > a[i]) return false;
        }
        return true;
    }

    function isSortedAndUniquified(int256[] memory a) internal pure returns (bool result) {
        for (uint256 i = 1; i < a.length; ++i) {
            if (a[i - 1] >= a[i]) return false;
        }
        return true;
    }

    function hasDuplicate(int256[] memory a) internal pure returns (bool result) {
        return WordArrays.hasDuplicate(a);
    }

    /// @dev Removes duplicate elements from a ascendingly sorted memory array.
    function uniquifySorted(int256[] memory a) internal pure {
        WordArrays.uniquifySorted(a);
    }

    function insertionSort(address[] memory a) internal pure {
        WordArrays.sort(a);
    }

    function sort(address[] memory a) internal pure {
        WordArrays.sort(a);
    }

    function reverse(address[] memory a) internal pure {
        for (uint256 i; i < a.length / 2; ++i) {
            uint256 j = a.length - 1 - i;
            (a[i], a[j]) = (a[j], a[i]);
        }
    }

    function copy(address[] memory a) internal pure returns (address[] memory result) {
        result = new address[](a.length);
        for (uint256 i; i < a.length; ++i) {
            result[i] = a[i];
        }
    }

    function isSorted(address[] memory a) internal pure returns (bool result) {
        for (uint256 i = 1; i < a.length; ++i) {
            if (a[i - 1] > a[i]) return false;
        }
        return true;
    }

    function isSortedAndUniquified(address[] memory a) internal pure returns (bool result) {
        for (uint256 i = 1; i < a.length; ++i) {
            if (a[i - 1] >= a[i]) return false;
        }
        return true;
    }

    function hasDuplicate(address[] memory a) internal pure returns (bool result) {
        return WordArrays.hasDuplicate(a);
    }

    /// @dev Removes duplicate elements from a ascendingly sorted memory array.
    function uniquifySorted(address[] memory a) internal pure {
        WordArrays.uniquifySorted(a);
    }

    function insertionSort(bytes32[] memory a) internal pure {
        WordArrays.sort(a);
    }

    function sort(bytes32[] memory a) internal pure {
        WordArrays.sort(a);
    }

    function reverse(bytes32[] memory a) internal pure {
        for (uint256 i; i < a.length / 2; ++i) {
            uint256 j = a.length - 1 - i;
            (a[i], a[j]) = (a[j], a[i]);
        }
    }

    function copy(bytes32[] memory a) internal pure returns (bytes32[] memory result) {
        result = new bytes32[](a.length);
        for (uint256 i; i < a.length; ++i) {
            result[i] = a[i];
        }
    }

    function isSorted(bytes32[] memory a) internal pure returns (bool result) {
        for (uint256 i = 1; i < a.length; ++i) {
            if (a[i - 1] > a[i]) return false;
        }
        return true;
    }

    function isSortedAndUniquified(bytes32[] memory a) internal pure returns (bool result) {
        for (uint256 i = 1; i < a.length; ++i) {
            if (a[i - 1] >= a[i]) return false;
        }
        return true;
    }

    function hasDuplicate(bytes32[] memory a) internal pure returns (bool result) {
        return WordArrays.hasDuplicate(a);
    }

    /// @dev Removes duplicate elements from a ascendingly sorted memory array.
    function uniquifySorted(bytes32[] memory a) internal pure {
        WordArrays.uniquifySorted(a);
    }

    /// @dev Returns whether `a` contains `needle`, and the index of `needle`.
    /// `index` precedence: equal to > nearest before > nearest after.
    function searchSorted(uint256[] memory a, uint256 needle)
        internal
        pure
        returns (bool found, uint256 index)
    {
        // The upstream probe sequence: a one-based binary search. An absent
        // needle ends it at `l == h + 1`, where the upstream's last probe reads
        // `h`, the nearest element below the needle when there is one.
        uint256 l = 1;
        uint256 h = a.length;
        while (l <= h) {
            uint256 m = (l + h) / 2;
            uint256 t = a[m - 1];
            if (t == needle) return (true, m - 1);
            if (needle <= t) {
                h = m - 1;
            } else {
                l = m + 1;
            }
        }
        if (h != 0) index = h - 1;
    }

    /// @dev Returns whether `a` contains `needle`.
    function inSorted(uint256[] memory a, uint256 needle) internal pure returns (bool found) {
        (found,) = searchSorted(a, needle);
    }

    /// @dev Returns whether `a` contains `needle`, and the index of `needle`.
    /// `index` precedence: equal to > nearest before > nearest after.
    function searchSorted(int256[] memory a, int256 needle)
        internal
        pure
        returns (bool found, uint256 index)
    {
        // The upstream probe sequence: a one-based binary search. An absent
        // needle ends it at `l == h + 1`, where the upstream's last probe reads
        // `h`, the nearest element below the needle when there is one.
        uint256 l = 1;
        uint256 h = a.length;
        while (l <= h) {
            uint256 m = (l + h) / 2;
            int256 t = a[m - 1];
            if (t == needle) return (true, m - 1);
            if (needle <= t) {
                h = m - 1;
            } else {
                l = m + 1;
            }
        }
        if (h != 0) index = h - 1;
    }

    /// @dev Returns whether `a` contains `needle`.
    function inSorted(int256[] memory a, int256 needle) internal pure returns (bool found) {
        (found,) = searchSorted(a, needle);
    }

    /// @dev Returns whether `a` contains `needle`, and the index of `needle`.
    /// `index` precedence: equal to > nearest before > nearest after.
    function searchSorted(address[] memory a, address needle)
        internal
        pure
        returns (bool found, uint256 index)
    {
        // The upstream probe sequence: a one-based binary search. An absent
        // needle ends it at `l == h + 1`, where the upstream's last probe reads
        // `h`, the nearest element below the needle when there is one.
        uint256 l = 1;
        uint256 h = a.length;
        while (l <= h) {
            uint256 m = (l + h) / 2;
            address t = a[m - 1];
            if (t == needle) return (true, m - 1);
            if (needle <= t) {
                h = m - 1;
            } else {
                l = m + 1;
            }
        }
        if (h != 0) index = h - 1;
    }

    /// @dev Returns whether `a` contains `needle`.
    function inSorted(address[] memory a, address needle) internal pure returns (bool found) {
        (found,) = searchSorted(a, needle);
    }

    /// @dev Returns whether `a` contains `needle`, and the index of `needle`.
    /// `index` precedence: equal to > nearest before > nearest after.
    function searchSorted(bytes32[] memory a, bytes32 needle)
        internal
        pure
        returns (bool found, uint256 index)
    {
        // The upstream probe sequence: a one-based binary search. An absent
        // needle ends it at `l == h + 1`, where the upstream's last probe reads
        // `h`, the nearest element below the needle when there is one.
        uint256 l = 1;
        uint256 h = a.length;
        while (l <= h) {
            uint256 m = (l + h) / 2;
            bytes32 t = a[m - 1];
            if (t == needle) return (true, m - 1);
            if (needle <= t) {
                h = m - 1;
            } else {
                l = m + 1;
            }
        }
        if (h != 0) index = h - 1;
    }

    /// @dev Returns whether `a` contains `needle`.
    function inSorted(bytes32[] memory a, bytes32 needle) internal pure returns (bool found) {
        (found,) = searchSorted(a, needle);
    }

    /// @dev Returns the number of values present in both `a` and `b`, walking
    /// them in the same order as the set operations below. Their result lengths
    /// are exact functions of this count, so each operation walks once.
    /// @dev Returns the sorted set difference of `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function difference(uint256[] memory a, uint256[] memory b)
        internal
        pure
        returns (uint256[] memory c)
    {
        c = new uint256[](a.length);
        uint256 i;
        uint256 j;
        uint256 k;
        while (i < a.length && j < b.length) {
            uint256 u = a[i];
            uint256 v = b[j];
            if (u == v) {
                ++i;
                ++j;
            } else if (u > v) {
                ++j;
            } else {
                c[k] = u;
                ++k;
                ++i;
            }
        }
        while (i < a.length) {
            c[k] = a[i];
            ++k;
            ++i;
        }
        Arrays.truncate(c, k);
    }

    /// @dev Returns the sorted set intersection between `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function intersection(uint256[] memory a, uint256[] memory b)
        internal
        pure
        returns (uint256[] memory c)
    {
        c = new uint256[](a.length < b.length ? a.length : b.length);
        uint256 i;
        uint256 j;
        uint256 k;
        while (i < a.length && j < b.length) {
            uint256 u = a[i];
            uint256 v = b[j];
            if (u == v) {
                c[k] = u;
                ++k;
                ++i;
                ++j;
            } else if (u > v) {
                ++j;
            } else {
                ++i;
            }
        }
        Arrays.truncate(c, k);
    }

    /// @dev Returns the sorted set union of `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function union(uint256[] memory a, uint256[] memory b)
        internal
        pure
        returns (uint256[] memory c)
    {
        c = new uint256[](a.length + b.length);
        uint256 i;
        uint256 j;
        uint256 k;
        while (i < a.length && j < b.length) {
            uint256 u = a[i];
            uint256 v = b[j];
            if (u == v) {
                c[k] = u;
                ++k;
                ++i;
                ++j;
            } else if (u > v) {
                c[k] = v;
                ++k;
                ++j;
            } else {
                c[k] = u;
                ++k;
                ++i;
            }
        }
        while (i < a.length) {
            c[k] = a[i];
            ++k;
            ++i;
        }
        while (j < b.length) {
            c[k] = b[j];
            ++k;
            ++j;
        }
        Arrays.truncate(c, k);
    }

    /// @dev Returns the number of values present in both `a` and `b`, walking
    /// them in the same order as the set operations below. Their result lengths
    /// are exact functions of this count, so each operation walks once.
    /// @dev Returns the sorted set difference of `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function difference(int256[] memory a, int256[] memory b)
        internal
        pure
        returns (int256[] memory c)
    {
        c = new int256[](a.length);
        uint256 i;
        uint256 j;
        uint256 k;
        while (i < a.length && j < b.length) {
            int256 u = a[i];
            int256 v = b[j];
            if (u == v) {
                ++i;
                ++j;
            } else if (u > v) {
                ++j;
            } else {
                c[k] = u;
                ++k;
                ++i;
            }
        }
        while (i < a.length) {
            c[k] = a[i];
            ++k;
            ++i;
        }
        Arrays.truncate(c, k);
    }

    /// @dev Returns the sorted set intersection between `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function intersection(int256[] memory a, int256[] memory b)
        internal
        pure
        returns (int256[] memory c)
    {
        c = new int256[](a.length < b.length ? a.length : b.length);
        uint256 i;
        uint256 j;
        uint256 k;
        while (i < a.length && j < b.length) {
            int256 u = a[i];
            int256 v = b[j];
            if (u == v) {
                c[k] = u;
                ++k;
                ++i;
                ++j;
            } else if (u > v) {
                ++j;
            } else {
                ++i;
            }
        }
        Arrays.truncate(c, k);
    }

    /// @dev Returns the sorted set union of `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function union(int256[] memory a, int256[] memory b) internal pure returns (int256[] memory c) {
        c = new int256[](a.length + b.length);
        uint256 i;
        uint256 j;
        uint256 k;
        while (i < a.length && j < b.length) {
            int256 u = a[i];
            int256 v = b[j];
            if (u == v) {
                c[k] = u;
                ++k;
                ++i;
                ++j;
            } else if (u > v) {
                c[k] = v;
                ++k;
                ++j;
            } else {
                c[k] = u;
                ++k;
                ++i;
            }
        }
        while (i < a.length) {
            c[k] = a[i];
            ++k;
            ++i;
        }
        while (j < b.length) {
            c[k] = b[j];
            ++k;
            ++j;
        }
        Arrays.truncate(c, k);
    }

    /// @dev Returns the number of values present in both `a` and `b`, walking
    /// them in the same order as the set operations below. Their result lengths
    /// are exact functions of this count, so each operation walks once.
    /// @dev Returns the sorted set difference of `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function difference(address[] memory a, address[] memory b)
        internal
        pure
        returns (address[] memory c)
    {
        c = new address[](a.length);
        uint256 i;
        uint256 j;
        uint256 k;
        while (i < a.length && j < b.length) {
            address u = a[i];
            address v = b[j];
            if (u == v) {
                ++i;
                ++j;
            } else if (u > v) {
                ++j;
            } else {
                c[k] = u;
                ++k;
                ++i;
            }
        }
        while (i < a.length) {
            c[k] = a[i];
            ++k;
            ++i;
        }
        Arrays.truncate(c, k);
    }

    /// @dev Returns the sorted set intersection between `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function intersection(address[] memory a, address[] memory b)
        internal
        pure
        returns (address[] memory c)
    {
        c = new address[](a.length < b.length ? a.length : b.length);
        uint256 i;
        uint256 j;
        uint256 k;
        while (i < a.length && j < b.length) {
            address u = a[i];
            address v = b[j];
            if (u == v) {
                c[k] = u;
                ++k;
                ++i;
                ++j;
            } else if (u > v) {
                ++j;
            } else {
                ++i;
            }
        }
        Arrays.truncate(c, k);
    }

    /// @dev Returns the sorted set union of `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function union(address[] memory a, address[] memory b)
        internal
        pure
        returns (address[] memory c)
    {
        c = new address[](a.length + b.length);
        uint256 i;
        uint256 j;
        uint256 k;
        while (i < a.length && j < b.length) {
            address u = a[i];
            address v = b[j];
            if (u == v) {
                c[k] = u;
                ++k;
                ++i;
                ++j;
            } else if (u > v) {
                c[k] = v;
                ++k;
                ++j;
            } else {
                c[k] = u;
                ++k;
                ++i;
            }
        }
        while (i < a.length) {
            c[k] = a[i];
            ++k;
            ++i;
        }
        while (j < b.length) {
            c[k] = b[j];
            ++k;
            ++j;
        }
        Arrays.truncate(c, k);
    }

    /// @dev Returns the number of values present in both `a` and `b`, walking
    /// them in the same order as the set operations below. Their result lengths
    /// are exact functions of this count, so each operation walks once.
    /// @dev Returns the sorted set difference of `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function difference(bytes32[] memory a, bytes32[] memory b)
        internal
        pure
        returns (bytes32[] memory c)
    {
        c = new bytes32[](a.length);
        uint256 i;
        uint256 j;
        uint256 k;
        while (i < a.length && j < b.length) {
            bytes32 u = a[i];
            bytes32 v = b[j];
            if (u == v) {
                ++i;
                ++j;
            } else if (u > v) {
                ++j;
            } else {
                c[k] = u;
                ++k;
                ++i;
            }
        }
        while (i < a.length) {
            c[k] = a[i];
            ++k;
            ++i;
        }
        Arrays.truncate(c, k);
    }

    /// @dev Returns the sorted set intersection between `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function intersection(bytes32[] memory a, bytes32[] memory b)
        internal
        pure
        returns (bytes32[] memory c)
    {
        c = new bytes32[](a.length < b.length ? a.length : b.length);
        uint256 i;
        uint256 j;
        uint256 k;
        while (i < a.length && j < b.length) {
            bytes32 u = a[i];
            bytes32 v = b[j];
            if (u == v) {
                c[k] = u;
                ++k;
                ++i;
                ++j;
            } else if (u > v) {
                ++j;
            } else {
                ++i;
            }
        }
        Arrays.truncate(c, k);
    }

    /// @dev Returns the sorted set union of `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function union(bytes32[] memory a, bytes32[] memory b)
        internal
        pure
        returns (bytes32[] memory c)
    {
        c = new bytes32[](a.length + b.length);
        uint256 i;
        uint256 j;
        uint256 k;
        while (i < a.length && j < b.length) {
            bytes32 u = a[i];
            bytes32 v = b[j];
            if (u == v) {
                c[k] = u;
                ++k;
                ++i;
                ++j;
            } else if (u > v) {
                c[k] = v;
                ++k;
                ++j;
            } else {
                c[k] = u;
                ++k;
                ++i;
            }
        }
        while (i < a.length) {
            c[k] = a[i];
            ++k;
            ++i;
        }
        while (j < b.length) {
            c[k] = b[j];
            ++k;
            ++j;
        }
        Arrays.truncate(c, k);
    }

    /// @dev Cleans the upper 96 bits of the addresses.
    /// In case `a` is produced via assembly and might have dirty upper bits.
    function clean(address[] memory a) internal pure {
        for (uint256 i; i < a.length; ++i) {
            a[i] = a[i];
        }
    }

    /// @dev Sorts and uniquifies `keys`. Updates `values` with the grouped sums by key.
    function groupSum(uint256[] memory keys, uint256[] memory values) internal pure {
        WordArrays.groupSum(keys, values);
    }

    /// @dev Sorts and uniquifies `keys`. Updates `values` with the grouped sums by key.
    function groupSum(address[] memory keys, uint256[] memory values) internal pure {
        WordArrays.groupSum(keys, values);
    }

    /// @dev Sorts and uniquifies `keys`. Updates `values` with the grouped sums by key.
    function groupSum(bytes32[] memory keys, uint256[] memory values) internal pure {
        WordArrays.groupSum(keys, values);
    }

    /// @dev Sorts and uniquifies `keys`. Updates `values` with the grouped sums by key.
    function groupSum(int256[] memory keys, uint256[] memory values) internal pure {
        WordArrays.groupSum(keys, values);
    }
}
