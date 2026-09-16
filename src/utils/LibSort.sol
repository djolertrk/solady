// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Arrays} from "solar:core/v1/Arrays.sol";

/// @notice Checked Solidity sorting without type punning or sentinel reads.
/// @dev Shrinking an array in place has no Solidity spelling, so the APIs
/// that do it go through the compiler-owned `Arrays.truncate`.
library LibSort {
    function insertionSort(uint256[] memory a) internal pure {
        uint256 order = _presorted(a);
        if (order == 1) return;
        if (order == 2) {
            reverse(a);
            return;
        }
        if (a.length > 16) {
            _sort(a, 0, a.length);
            return;
        }
        for (uint256 i = 1; i < a.length; ++i) {
            uint256 value = a[i];
            uint256 j = i;
            while (j != 0 && a[j - 1] > value) {
                a[j] = a[j - 1];
                --j;
            }
            a[j] = value;
        }
    }

    function sort(uint256[] memory a) internal pure {
        uint256 order = _presorted(a);
        if (order == 1) return;
        if (order == 2) {
            reverse(a);
            return;
        }
        _sort(a, 0, a.length);
    }

    function _presorted(uint256[] memory a) private pure returns (uint256 order) {
        bool ascending = true;
        bool descending = true;
        for (uint256 i = 1; i < a.length; ++i) {
            uint256 previous = a[i - 1];
            uint256 current = a[i];
            if (previous > current) ascending = false;
            if (previous < current) descending = false;
            if (!ascending && !descending) return 0;
        }
        return ascending ? 1 : 2;
    }

    // Three-way partitioning bounds recursion on equal elements.
    function _sort(uint256[] memory a, uint256 lo, uint256 hi) private pure {
        while (hi - lo > 16) {
            uint256 pivot = a[lo + (hi - lo) / 2];
            uint256 left = lo;
            uint256 i = lo;
            uint256 right = hi;
            while (i < right) {
                if (a[i] < pivot) {
                    (a[left], a[i]) = (a[i], a[left]);
                    ++left;
                    ++i;
                } else if (a[i] > pivot) {
                    --right;
                    (a[i], a[right]) = (a[right], a[i]);
                } else {
                    ++i;
                }
            }
            if (left - lo < hi - right) {
                _sort(a, lo, left);
                lo = right;
            } else {
                _sort(a, right, hi);
                hi = left;
            }
        }
        for (uint256 i = lo + 1; i < hi; ++i) {
            uint256 value = a[i];
            uint256 j = i;
            while (j > lo && a[j - 1] > value) {
                a[j] = a[j - 1];
                --j;
            }
            a[j] = value;
        }
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
        if (a.length < 2) return false;
        uint256 capacity = 1;
        while (capacity < a.length * 2) capacity *= 2;
        uint256[] memory seen = new uint256[](capacity);
        uint256 mask = capacity - 1;
        for (uint256 i = a.length; i != 0;) {
            --i;
            // Use the upstream LibPRNG hash with checked array indexing.
            uint256 slot =
                mulmod(uint256(a[i]), 0x100000000000000000000000000000051, ~uint256(0xbc)) & mask;
            while (seen[slot] != 0) {
                if (a[seen[slot] - 1] == a[i]) return true;
                slot = (slot + 1) & mask;
            }
            seen[slot] = i + 1;
        }
        return false;
    }

    /// @dev Removes duplicate elements from a ascendingly sorted memory array.
    function uniquifySorted(uint256[] memory a) internal pure {
        if (a.length < 2) return;
        // Every element is compared with the last one kept, so a run of equal
        // values collapses onto its first occurrence.
        uint256 w = 1;
        for (uint256 r = 1; r < a.length; ++r) {
            if (a[r] != a[w - 1]) {
                a[w] = a[r];
                ++w;
            }
        }
        Arrays.truncate(a, w);
    }

    function insertionSort(int256[] memory a) internal pure {
        uint256 order = _presorted(a);
        if (order == 1) return;
        if (order == 2) {
            reverse(a);
            return;
        }
        if (a.length > 16) {
            _sort(a, 0, a.length);
            return;
        }
        for (uint256 i = 1; i < a.length; ++i) {
            int256 value = a[i];
            uint256 j = i;
            while (j != 0 && a[j - 1] > value) {
                a[j] = a[j - 1];
                --j;
            }
            a[j] = value;
        }
    }

    function sort(int256[] memory a) internal pure {
        uint256 order = _presorted(a);
        if (order == 1) return;
        if (order == 2) {
            reverse(a);
            return;
        }
        _sort(a, 0, a.length);
    }

    function _presorted(int256[] memory a) private pure returns (uint256 order) {
        bool ascending = true;
        bool descending = true;
        for (uint256 i = 1; i < a.length; ++i) {
            int256 previous = a[i - 1];
            int256 current = a[i];
            if (previous > current) ascending = false;
            if (previous < current) descending = false;
            if (!ascending && !descending) return 0;
        }
        return ascending ? 1 : 2;
    }

    // Three-way partitioning bounds recursion on equal elements.
    function _sort(int256[] memory a, uint256 lo, uint256 hi) private pure {
        while (hi - lo > 16) {
            int256 pivot = a[lo + (hi - lo) / 2];
            uint256 left = lo;
            uint256 i = lo;
            uint256 right = hi;
            while (i < right) {
                if (a[i] < pivot) {
                    (a[left], a[i]) = (a[i], a[left]);
                    ++left;
                    ++i;
                } else if (a[i] > pivot) {
                    --right;
                    (a[i], a[right]) = (a[right], a[i]);
                } else {
                    ++i;
                }
            }
            if (left - lo < hi - right) {
                _sort(a, lo, left);
                lo = right;
            } else {
                _sort(a, right, hi);
                hi = left;
            }
        }
        for (uint256 i = lo + 1; i < hi; ++i) {
            int256 value = a[i];
            uint256 j = i;
            while (j > lo && a[j - 1] > value) {
                a[j] = a[j - 1];
                --j;
            }
            a[j] = value;
        }
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
        if (a.length < 2) return false;
        uint256 capacity = 1;
        while (capacity < a.length * 2) capacity *= 2;
        uint256[] memory seen = new uint256[](capacity);
        uint256 mask = capacity - 1;
        for (uint256 i = a.length; i != 0;) {
            --i;
            // Use the upstream LibPRNG hash with checked array indexing.
            uint256 slot =
                mulmod(uint256(a[i]), 0x100000000000000000000000000000051, ~uint256(0xbc)) & mask;
            while (seen[slot] != 0) {
                if (a[seen[slot] - 1] == a[i]) return true;
                slot = (slot + 1) & mask;
            }
            seen[slot] = i + 1;
        }
        return false;
    }

    /// @dev Removes duplicate elements from a ascendingly sorted memory array.
    function uniquifySorted(int256[] memory a) internal pure {
        if (a.length < 2) return;
        // Every element is compared with the last one kept, so a run of equal
        // values collapses onto its first occurrence.
        uint256 w = 1;
        for (uint256 r = 1; r < a.length; ++r) {
            if (a[r] != a[w - 1]) {
                a[w] = a[r];
                ++w;
            }
        }
        Arrays.truncate(a, w);
    }

    function insertionSort(address[] memory a) internal pure {
        uint256 order = _presorted(a);
        if (order == 1) return;
        if (order == 2) {
            reverse(a);
            return;
        }
        if (a.length > 16) {
            _sort(a, 0, a.length);
            return;
        }
        for (uint256 i = 1; i < a.length; ++i) {
            address value = a[i];
            uint256 j = i;
            while (j != 0 && a[j - 1] > value) {
                a[j] = a[j - 1];
                --j;
            }
            a[j] = value;
        }
    }

    function sort(address[] memory a) internal pure {
        uint256 order = _presorted(a);
        if (order == 1) return;
        if (order == 2) {
            reverse(a);
            return;
        }
        _sort(a, 0, a.length);
    }

    function _presorted(address[] memory a) private pure returns (uint256 order) {
        bool ascending = true;
        bool descending = true;
        for (uint256 i = 1; i < a.length; ++i) {
            address previous = a[i - 1];
            address current = a[i];
            if (previous > current) ascending = false;
            if (previous < current) descending = false;
            if (!ascending && !descending) return 0;
        }
        return ascending ? 1 : 2;
    }

    // Three-way partitioning bounds recursion on equal elements.
    function _sort(address[] memory a, uint256 lo, uint256 hi) private pure {
        while (hi - lo > 16) {
            address pivot = a[lo + (hi - lo) / 2];
            uint256 left = lo;
            uint256 i = lo;
            uint256 right = hi;
            while (i < right) {
                if (a[i] < pivot) {
                    (a[left], a[i]) = (a[i], a[left]);
                    ++left;
                    ++i;
                } else if (a[i] > pivot) {
                    --right;
                    (a[i], a[right]) = (a[right], a[i]);
                } else {
                    ++i;
                }
            }
            if (left - lo < hi - right) {
                _sort(a, lo, left);
                lo = right;
            } else {
                _sort(a, right, hi);
                hi = left;
            }
        }
        for (uint256 i = lo + 1; i < hi; ++i) {
            address value = a[i];
            uint256 j = i;
            while (j > lo && a[j - 1] > value) {
                a[j] = a[j - 1];
                --j;
            }
            a[j] = value;
        }
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
        if (a.length < 2) return false;
        uint256 capacity = 1;
        while (capacity < a.length * 2) capacity *= 2;
        uint256[] memory seen = new uint256[](capacity);
        uint256 mask = capacity - 1;
        for (uint256 i = a.length; i != 0;) {
            --i;
            // Use the upstream LibPRNG hash with checked array indexing.
            uint256 slot = mulmod(
                uint256(uint160(a[i])), 0x100000000000000000000000000000051, ~uint256(0xbc)
            ) & mask;
            while (seen[slot] != 0) {
                if (a[seen[slot] - 1] == a[i]) return true;
                slot = (slot + 1) & mask;
            }
            seen[slot] = i + 1;
        }
        return false;
    }

    /// @dev Removes duplicate elements from a ascendingly sorted memory array.
    function uniquifySorted(address[] memory a) internal pure {
        if (a.length < 2) return;
        // Every element is compared with the last one kept, so a run of equal
        // values collapses onto its first occurrence.
        uint256 w = 1;
        for (uint256 r = 1; r < a.length; ++r) {
            if (a[r] != a[w - 1]) {
                a[w] = a[r];
                ++w;
            }
        }
        Arrays.truncate(a, w);
    }

    function insertionSort(bytes32[] memory a) internal pure {
        uint256 order = _presorted(a);
        if (order == 1) return;
        if (order == 2) {
            reverse(a);
            return;
        }
        if (a.length > 16) {
            _sort(a, 0, a.length);
            return;
        }
        for (uint256 i = 1; i < a.length; ++i) {
            bytes32 value = a[i];
            uint256 j = i;
            while (j != 0 && a[j - 1] > value) {
                a[j] = a[j - 1];
                --j;
            }
            a[j] = value;
        }
    }

    function sort(bytes32[] memory a) internal pure {
        uint256 order = _presorted(a);
        if (order == 1) return;
        if (order == 2) {
            reverse(a);
            return;
        }
        _sort(a, 0, a.length);
    }

    function _presorted(bytes32[] memory a) private pure returns (uint256 order) {
        bool ascending = true;
        bool descending = true;
        for (uint256 i = 1; i < a.length; ++i) {
            bytes32 previous = a[i - 1];
            bytes32 current = a[i];
            if (previous > current) ascending = false;
            if (previous < current) descending = false;
            if (!ascending && !descending) return 0;
        }
        return ascending ? 1 : 2;
    }

    // Three-way partitioning bounds recursion on equal elements.
    function _sort(bytes32[] memory a, uint256 lo, uint256 hi) private pure {
        while (hi - lo > 16) {
            bytes32 pivot = a[lo + (hi - lo) / 2];
            uint256 left = lo;
            uint256 i = lo;
            uint256 right = hi;
            while (i < right) {
                if (a[i] < pivot) {
                    (a[left], a[i]) = (a[i], a[left]);
                    ++left;
                    ++i;
                } else if (a[i] > pivot) {
                    --right;
                    (a[i], a[right]) = (a[right], a[i]);
                } else {
                    ++i;
                }
            }
            if (left - lo < hi - right) {
                _sort(a, lo, left);
                lo = right;
            } else {
                _sort(a, right, hi);
                hi = left;
            }
        }
        for (uint256 i = lo + 1; i < hi; ++i) {
            bytes32 value = a[i];
            uint256 j = i;
            while (j > lo && a[j - 1] > value) {
                a[j] = a[j - 1];
                --j;
            }
            a[j] = value;
        }
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
        if (a.length < 2) return false;
        uint256 capacity = 1;
        while (capacity < a.length * 2) capacity *= 2;
        uint256[] memory seen = new uint256[](capacity);
        uint256 mask = capacity - 1;
        for (uint256 i = a.length; i != 0;) {
            --i;
            // Use the upstream LibPRNG hash with checked array indexing.
            uint256 slot =
                mulmod(uint256(a[i]), 0x100000000000000000000000000000051, ~uint256(0xbc)) & mask;
            while (seen[slot] != 0) {
                if (a[seen[slot] - 1] == a[i]) return true;
                slot = (slot + 1) & mask;
            }
            seen[slot] = i + 1;
        }
        return false;
    }

    /// @dev Removes duplicate elements from a ascendingly sorted memory array.
    function uniquifySorted(bytes32[] memory a) internal pure {
        if (a.length < 2) return;
        // Every element is compared with the last one kept, so a run of equal
        // values collapses onto its first occurrence.
        uint256 w = 1;
        for (uint256 r = 1; r < a.length; ++r) {
            if (a[r] != a[w - 1]) {
                a[w] = a[r];
                ++w;
            }
        }
        Arrays.truncate(a, w);
    }

    /// @dev Returns whether `a` contains `needle`, and the index of `needle`.
    /// `index` precedence: equal to > nearest before > nearest after.
    function searchSorted(uint256[] memory a, uint256 needle)
        internal
        pure
        returns (bool found, uint256 index)
    {
        // The upstream probe sequence: a one-based binary search whose last
        // probe decides the nearest index when the needle is absent.
        uint256 l = 1;
        uint256 h = a.length;
        uint256 t;
        while (true) {
            index = (l + h) / 2;
            if (index != 0) t = a[index - 1];
            if (l > h || (index != 0 && t == needle)) break;
            if (needle <= t) {
                h = index - 1;
            } else {
                l = index + 1;
            }
        }
        found = index != 0 && t == needle;
        if (index != 0) index -= 1;
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
        // The upstream probe sequence: a one-based binary search whose last
        // probe decides the nearest index when the needle is absent.
        uint256 l = 1;
        uint256 h = a.length;
        int256 t;
        while (true) {
            index = (l + h) / 2;
            if (index != 0) t = a[index - 1];
            if (l > h || (index != 0 && t == needle)) break;
            if (needle <= t) {
                h = index - 1;
            } else {
                l = index + 1;
            }
        }
        found = index != 0 && t == needle;
        if (index != 0) index -= 1;
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
        // The upstream probe sequence: a one-based binary search whose last
        // probe decides the nearest index when the needle is absent.
        uint256 l = 1;
        uint256 h = a.length;
        address t;
        while (true) {
            index = (l + h) / 2;
            if (index != 0) t = a[index - 1];
            if (l > h || (index != 0 && t == needle)) break;
            if (needle <= t) {
                h = index - 1;
            } else {
                l = index + 1;
            }
        }
        found = index != 0 && t == needle;
        if (index != 0) index -= 1;
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
        // The upstream probe sequence: a one-based binary search whose last
        // probe decides the nearest index when the needle is absent.
        uint256 l = 1;
        uint256 h = a.length;
        bytes32 t;
        while (true) {
            index = (l + h) / 2;
            if (index != 0) t = a[index - 1];
            if (l > h || (index != 0 && t == needle)) break;
            if (needle <= t) {
                h = index - 1;
            } else {
                l = index + 1;
            }
        }
        found = index != 0 && t == needle;
        if (index != 0) index -= 1;
    }

    /// @dev Returns whether `a` contains `needle`.
    function inSorted(bytes32[] memory a, bytes32 needle) internal pure returns (bool found) {
        (found,) = searchSorted(a, needle);
    }

    /// @dev Returns the number of values present in both `a` and `b`, walking
    /// them in the same order as the set operations below. Their result lengths
    /// are exact functions of this count, so each operation walks once.
    function _common(uint256[] memory a, uint256[] memory b) private pure returns (uint256 n) {
        uint256 i;
        uint256 j;
        while (i < a.length && j < b.length) {
            uint256 u = a[i];
            uint256 v = b[j];
            if (u == v) {
                ++n;
                ++i;
                ++j;
            } else if (u > v) {
                ++j;
            } else {
                ++i;
            }
        }
    }

    /// @dev Returns the sorted set difference of `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function difference(uint256[] memory a, uint256[] memory b)
        internal
        pure
        returns (uint256[] memory c)
    {
        c = new uint256[](a.length - _common(a, b));
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
    }

    /// @dev Returns the sorted set intersection between `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function intersection(uint256[] memory a, uint256[] memory b)
        internal
        pure
        returns (uint256[] memory c)
    {
        c = new uint256[](_common(a, b));
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
    }

    /// @dev Returns the sorted set union of `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function union(uint256[] memory a, uint256[] memory b)
        internal
        pure
        returns (uint256[] memory c)
    {
        c = new uint256[](a.length + b.length - _common(a, b));
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
    }

    /// @dev Returns the number of values present in both `a` and `b`, walking
    /// them in the same order as the set operations below. Their result lengths
    /// are exact functions of this count, so each operation walks once.
    function _common(int256[] memory a, int256[] memory b) private pure returns (uint256 n) {
        uint256 i;
        uint256 j;
        while (i < a.length && j < b.length) {
            int256 u = a[i];
            int256 v = b[j];
            if (u == v) {
                ++n;
                ++i;
                ++j;
            } else if (u > v) {
                ++j;
            } else {
                ++i;
            }
        }
    }

    /// @dev Returns the sorted set difference of `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function difference(int256[] memory a, int256[] memory b)
        internal
        pure
        returns (int256[] memory c)
    {
        c = new int256[](a.length - _common(a, b));
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
    }

    /// @dev Returns the sorted set intersection between `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function intersection(int256[] memory a, int256[] memory b)
        internal
        pure
        returns (int256[] memory c)
    {
        c = new int256[](_common(a, b));
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
    }

    /// @dev Returns the sorted set union of `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function union(int256[] memory a, int256[] memory b) internal pure returns (int256[] memory c) {
        c = new int256[](a.length + b.length - _common(a, b));
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
    }

    /// @dev Returns the number of values present in both `a` and `b`, walking
    /// them in the same order as the set operations below. Their result lengths
    /// are exact functions of this count, so each operation walks once.
    function _common(address[] memory a, address[] memory b) private pure returns (uint256 n) {
        uint256 i;
        uint256 j;
        while (i < a.length && j < b.length) {
            address u = a[i];
            address v = b[j];
            if (u == v) {
                ++n;
                ++i;
                ++j;
            } else if (u > v) {
                ++j;
            } else {
                ++i;
            }
        }
    }

    /// @dev Returns the sorted set difference of `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function difference(address[] memory a, address[] memory b)
        internal
        pure
        returns (address[] memory c)
    {
        c = new address[](a.length - _common(a, b));
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
    }

    /// @dev Returns the sorted set intersection between `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function intersection(address[] memory a, address[] memory b)
        internal
        pure
        returns (address[] memory c)
    {
        c = new address[](_common(a, b));
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
    }

    /// @dev Returns the sorted set union of `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function union(address[] memory a, address[] memory b)
        internal
        pure
        returns (address[] memory c)
    {
        c = new address[](a.length + b.length - _common(a, b));
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
    }

    /// @dev Returns the number of values present in both `a` and `b`, walking
    /// them in the same order as the set operations below. Their result lengths
    /// are exact functions of this count, so each operation walks once.
    function _common(bytes32[] memory a, bytes32[] memory b) private pure returns (uint256 n) {
        uint256 i;
        uint256 j;
        while (i < a.length && j < b.length) {
            bytes32 u = a[i];
            bytes32 v = b[j];
            if (u == v) {
                ++n;
                ++i;
                ++j;
            } else if (u > v) {
                ++j;
            } else {
                ++i;
            }
        }
    }

    /// @dev Returns the sorted set difference of `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function difference(bytes32[] memory a, bytes32[] memory b)
        internal
        pure
        returns (bytes32[] memory c)
    {
        c = new bytes32[](a.length - _common(a, b));
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
    }

    /// @dev Returns the sorted set intersection between `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function intersection(bytes32[] memory a, bytes32[] memory b)
        internal
        pure
        returns (bytes32[] memory c)
    {
        c = new bytes32[](_common(a, b));
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
    }

    /// @dev Returns the sorted set union of `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function union(bytes32[] memory a, bytes32[] memory b)
        internal
        pure
        returns (bytes32[] memory c)
    {
        c = new bytes32[](a.length + b.length - _common(a, b));
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
    }

    /// @dev Cleans the upper 96 bits of the addresses.
    /// In case `a` is produced via assembly and might have dirty upper bits.
    function clean(address[] memory a) internal pure {
        for (uint256 i; i < a.length; ++i) {
            a[i] = a[i];
        }
    }
}
