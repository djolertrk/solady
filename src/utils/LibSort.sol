// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @notice Optimized sorts and operations for sorted arrays.
/// @author Solady (https://github.com/Vectorized/solady/blob/main/src/utils/LibSort.sol)
/// @dev The checked port gives each element type its own implementation, so no array is read
/// as another type. Sorting is a median-of-three quicksort with insertion-sort leaves.
/// Shrinking an array in place has no Solidity spelling, so the APIs that do it, and the set
/// operations that build a result at its largest size, go through `_truncate`, the library's
/// only trusted code.
/// @custom:solar-safe memory arithmetic
library LibSort {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INSERTION SORT                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // - Faster on small arrays (32 or lesser elements).
    // - Faster on almost sorted arrays.
    // - Smaller bytecode (about 300 bytes smaller than sort, which uses intro-quicksort).
    // - May be suitable for view functions intended for off-chain querying.

    /// @dev Sorts the array in-place with insertion sort.
    function insertionSort(uint256[] memory a) internal pure {
        _sortAll(a);
    }

    /// @dev Sorts the array in-place with insertion sort.
    function insertionSort(int256[] memory a) internal pure {
        _sortAll(a);
    }

    /// @dev Sorts the array in-place with insertion sort.
    function insertionSort(address[] memory a) internal pure {
        _sortAll(a);
    }

    /// @dev Sorts the array in-place with insertion sort.
    function insertionSort(bytes32[] memory a) internal pure {
        _sortAll(a);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INTRO-QUICKSORT                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // - Faster on larger arrays (more than 32 elements).
    // - Robust performance.
    // - Larger bytecode.

    /// @dev Sorts the array in-place with intro-quicksort.
    function sort(uint256[] memory a) internal pure {
        _sortAll(a);
    }

    /// @dev Sorts the array in-place with intro-quicksort.
    function sort(int256[] memory a) internal pure {
        _sortAll(a);
    }

    /// @dev Sorts the array in-place with intro-quicksort.
    function sort(address[] memory a) internal pure {
        _sortAll(a);
    }

    /// @dev Sorts the array in-place with intro-quicksort.
    function sort(bytes32[] memory a) internal pure {
        _sortAll(a);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  OTHER USEFUL OPERATIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // For performance, the `uniquifySorted` methods will not revert if the
    // array is not sorted -- it will simply remove consecutive duplicate elements.

    /// @dev Removes duplicate elements from a ascendingly sorted memory array.
    function uniquifySorted(uint256[] memory a) internal pure {
        _uniquifySorted(a);
    }

    /// @dev Removes duplicate elements from a ascendingly sorted memory array.
    function uniquifySorted(int256[] memory a) internal pure {
        _uniquifySorted(a);
    }

    /// @dev Removes duplicate elements from a ascendingly sorted memory array.
    function uniquifySorted(address[] memory a) internal pure {
        _uniquifySorted(a);
    }

    /// @dev Removes duplicate elements from a ascendingly sorted memory array.
    function uniquifySorted(bytes32[] memory a) internal pure {
        _uniquifySorted(a);
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
        // `h`, the nearest element below the needle when there is one. The
        // midpoint `(l + h) / 2` is spelled so that it cannot overflow.
        uint256 l = 1;
        uint256 h = a.length;
        while (l <= h) {
            uint256 m = l + (h - l) / 2;
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

    /// @dev Returns whether `a` contains `needle`, and the index of `needle`.
    /// `index` precedence: equal to > nearest before > nearest after.
    function searchSorted(int256[] memory a, int256 needle)
        internal
        pure
        returns (bool found, uint256 index)
    {
        // The upstream probe sequence: a one-based binary search. An absent
        // needle ends it at `l == h + 1`, where the upstream's last probe reads
        // `h`, the nearest element below the needle when there is one. The
        // midpoint `(l + h) / 2` is spelled so that it cannot overflow.
        uint256 l = 1;
        uint256 h = a.length;
        while (l <= h) {
            uint256 m = l + (h - l) / 2;
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

    /// @dev Returns whether `a` contains `needle`, and the index of `needle`.
    /// `index` precedence: equal to > nearest before > nearest after.
    function searchSorted(address[] memory a, address needle)
        internal
        pure
        returns (bool found, uint256 index)
    {
        // The upstream probe sequence: a one-based binary search. An absent
        // needle ends it at `l == h + 1`, where the upstream's last probe reads
        // `h`, the nearest element below the needle when there is one. The
        // midpoint `(l + h) / 2` is spelled so that it cannot overflow.
        uint256 l = 1;
        uint256 h = a.length;
        while (l <= h) {
            uint256 m = l + (h - l) / 2;
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

    /// @dev Returns whether `a` contains `needle`, and the index of `needle`.
    /// `index` precedence: equal to > nearest before > nearest after.
    function searchSorted(bytes32[] memory a, bytes32 needle)
        internal
        pure
        returns (bool found, uint256 index)
    {
        // The upstream probe sequence: a one-based binary search. An absent
        // needle ends it at `l == h + 1`, where the upstream's last probe reads
        // `h`, the nearest element below the needle when there is one. The
        // midpoint `(l + h) / 2` is spelled so that it cannot overflow.
        uint256 l = 1;
        uint256 h = a.length;
        while (l <= h) {
            uint256 m = l + (h - l) / 2;
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
    function inSorted(uint256[] memory a, uint256 needle) internal pure returns (bool found) {
        (found,) = searchSorted(a, needle);
    }

    /// @dev Returns whether `a` contains `needle`.
    function inSorted(int256[] memory a, int256 needle) internal pure returns (bool found) {
        (found,) = searchSorted(a, needle);
    }

    /// @dev Returns whether `a` contains `needle`.
    function inSorted(address[] memory a, address needle) internal pure returns (bool found) {
        (found,) = searchSorted(a, needle);
    }

    /// @dev Returns whether `a` contains `needle`.
    function inSorted(bytes32[] memory a, bytes32 needle) internal pure returns (bool found) {
        (found,) = searchSorted(a, needle);
    }

    /// @dev Reverses the array in-place.
    function reverse(uint256[] memory a) internal pure {
        if (a.length < 2) return;
        for (uint256 i; i < a.length / 2; ++i) {
            uint256 j = a.length - 1 - i;
            (a[i], a[j]) = (a[j], a[i]);
        }
    }

    /// @dev Reverses the array in-place.
    function reverse(int256[] memory a) internal pure {
        if (a.length < 2) return;
        for (uint256 i; i < a.length / 2; ++i) {
            uint256 j = a.length - 1 - i;
            (a[i], a[j]) = (a[j], a[i]);
        }
    }

    /// @dev Reverses the array in-place.
    function reverse(address[] memory a) internal pure {
        if (a.length < 2) return;
        for (uint256 i; i < a.length / 2; ++i) {
            uint256 j = a.length - 1 - i;
            (a[i], a[j]) = (a[j], a[i]);
        }
    }

    /// @dev Reverses the array in-place.
    function reverse(bytes32[] memory a) internal pure {
        if (a.length < 2) return;
        for (uint256 i; i < a.length / 2; ++i) {
            uint256 j = a.length - 1 - i;
            (a[i], a[j]) = (a[j], a[i]);
        }
    }

    /// @dev Returns a copy of the array.
    function copy(uint256[] memory a) internal pure returns (uint256[] memory result) {
        return _copy(a);
    }

    /// @dev Returns a copy of the array.
    function copy(int256[] memory a) internal pure returns (int256[] memory result) {
        return _copy(a);
    }

    /// @dev Returns a copy of the array.
    function copy(address[] memory a) internal pure returns (address[] memory result) {
        return _copy(a);
    }

    /// @dev Returns a copy of the array.
    function copy(bytes32[] memory a) internal pure returns (bytes32[] memory result) {
        return _copy(a);
    }

    /// @dev Returns whether the array is sorted in ascending order.
    function isSorted(uint256[] memory a) internal pure returns (bool result) {
        for (uint256 i = 1; i < a.length; ++i) {
            if (a[i - 1] > a[i]) return false;
        }
        return true;
    }

    /// @dev Returns whether the array is sorted in ascending order.
    function isSorted(int256[] memory a) internal pure returns (bool result) {
        for (uint256 i = 1; i < a.length; ++i) {
            if (a[i - 1] > a[i]) return false;
        }
        return true;
    }

    /// @dev Returns whether the array is sorted in ascending order.
    function isSorted(address[] memory a) internal pure returns (bool result) {
        for (uint256 i = 1; i < a.length; ++i) {
            if (a[i - 1] > a[i]) return false;
        }
        return true;
    }

    /// @dev Returns whether the array is sorted in ascending order.
    function isSorted(bytes32[] memory a) internal pure returns (bool result) {
        for (uint256 i = 1; i < a.length; ++i) {
            if (a[i - 1] > a[i]) return false;
        }
        return true;
    }

    /// @dev Returns whether the array is strictly ascending (sorted and uniquified).
    function isSortedAndUniquified(uint256[] memory a) internal pure returns (bool result) {
        for (uint256 i = 1; i < a.length; ++i) {
            if (a[i - 1] >= a[i]) return false;
        }
        return true;
    }

    /// @dev Returns whether the array is strictly ascending (sorted and uniquified).
    function isSortedAndUniquified(int256[] memory a) internal pure returns (bool result) {
        for (uint256 i = 1; i < a.length; ++i) {
            if (a[i - 1] >= a[i]) return false;
        }
        return true;
    }

    /// @dev Returns whether the array is strictly ascending (sorted and uniquified).
    function isSortedAndUniquified(address[] memory a) internal pure returns (bool result) {
        for (uint256 i = 1; i < a.length; ++i) {
            if (a[i - 1] >= a[i]) return false;
        }
        return true;
    }

    /// @dev Returns whether the array is strictly ascending (sorted and uniquified).
    function isSortedAndUniquified(bytes32[] memory a) internal pure returns (bool result) {
        for (uint256 i = 1; i < a.length; ++i) {
            if (a[i - 1] >= a[i]) return false;
        }
        return true;
    }

    /// @dev Returns the sorted set difference of `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function difference(uint256[] memory a, uint256[] memory b)
        internal
        pure
        returns (uint256[] memory c)
    {
        c = _difference(a, b);
    }

    /// @dev Returns the sorted set difference between `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function difference(int256[] memory a, int256[] memory b)
        internal
        pure
        returns (int256[] memory c)
    {
        c = _difference(a, b);
    }

    /// @dev Returns the sorted set difference between `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function difference(address[] memory a, address[] memory b)
        internal
        pure
        returns (address[] memory c)
    {
        c = _difference(a, b);
    }

    /// @dev Returns the sorted set difference between `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function difference(bytes32[] memory a, bytes32[] memory b)
        internal
        pure
        returns (bytes32[] memory c)
    {
        c = _difference(a, b);
    }

    /// @dev Returns the sorted set intersection between `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function intersection(uint256[] memory a, uint256[] memory b)
        internal
        pure
        returns (uint256[] memory c)
    {
        c = _intersection(a, b);
    }

    /// @dev Returns the sorted set intersection between `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function intersection(int256[] memory a, int256[] memory b)
        internal
        pure
        returns (int256[] memory c)
    {
        c = _intersection(a, b);
    }

    /// @dev Returns the sorted set intersection between `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function intersection(address[] memory a, address[] memory b)
        internal
        pure
        returns (address[] memory c)
    {
        c = _intersection(a, b);
    }

    /// @dev Returns the sorted set intersection between `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function intersection(bytes32[] memory a, bytes32[] memory b)
        internal
        pure
        returns (bytes32[] memory c)
    {
        c = _intersection(a, b);
    }

    /// @dev Returns the sorted set union of `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function union(uint256[] memory a, uint256[] memory b)
        internal
        pure
        returns (uint256[] memory c)
    {
        c = _union(a, b);
    }

    /// @dev Returns the sorted set union of `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function union(int256[] memory a, int256[] memory b) internal pure returns (int256[] memory c) {
        c = _union(a, b);
    }

    /// @dev Returns the sorted set union between `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function union(address[] memory a, address[] memory b)
        internal
        pure
        returns (address[] memory c)
    {
        c = _union(a, b);
    }

    /// @dev Returns the sorted set union between `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function union(bytes32[] memory a, bytes32[] memory b)
        internal
        pure
        returns (bytes32[] memory c)
    {
        c = _union(a, b);
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
        _groupSum(keys, values);
    }

    /// @dev Sorts and uniquifies `keys`. Updates `values` with the grouped sums by key.
    function groupSum(address[] memory keys, uint256[] memory values) internal pure {
        _groupSum(keys, values);
    }

    /// @dev Sorts and uniquifies `keys`. Updates `values` with the grouped sums by key.
    function groupSum(bytes32[] memory keys, uint256[] memory values) internal pure {
        _groupSum(keys, values);
    }

    /// @dev Sorts and uniquifies `keys`. Updates `values` with the grouped sums by key.
    function groupSum(int256[] memory keys, uint256[] memory values) internal pure {
        _groupSum(keys, values);
    }

    /// @dev Returns if `a` has any duplicate. Does NOT mutate `a`. `O(n)`.
    function hasDuplicate(uint256[] memory a) internal pure returns (bool result) {
        return _hasDuplicate(a);
    }

    /// @dev Returns if `a` has any duplicate. Does NOT mutate `a`. `O(n)`.
    function hasDuplicate(address[] memory a) internal pure returns (bool result) {
        return _hasDuplicate(a);
    }

    /// @dev Returns if `a` has any duplicate. Does NOT mutate `a`. `O(n)`.
    function hasDuplicate(bytes32[] memory a) internal pure returns (bool result) {
        return _hasDuplicate(a);
    }

    /// @dev Returns if `a` has any duplicate. Does NOT mutate `a`. `O(n)`.
    function hasDuplicate(int256[] memory a) internal pure returns (bool result) {
        return _hasDuplicate(a);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PRIVATE HELPERS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Sorts `a[low:high]`: median-of-three Hoare partitions down to twelve
    /// elements, then insertion sort. The smaller part recurses and the larger
    /// one loops, so the recursion is at most `log2(high - low)` deep.
    function _sort(uint256[] memory a, uint256 low, uint256 high) private pure {
        while (high - low > 12) {
            uint256 last = high - 1;
            uint256 mid = low + ((high - low) >> 1);
            uint256 x = a[low];
            uint256 y = a[mid];
            uint256 z = a[last];
            if (y < x) (x, y) = (y, x);
            if (z < y) {
                (y, z) = (z, y);
                if (y < x) (x, y) = (y, x);
            }
            (a[low], a[mid], a[last]) = (x, y, z);
            // `a[low] <= y <= a[last]` stop both scans inside the range.
            uint256 i = low;
            uint256 j = last;
            while (true) {
                do {
                    ++i;
                } while (a[i] < y);
                do {
                    --j;
                } while (y < a[j]);
                if (i >= j) break;
                (a[i], a[j]) = (a[j], a[i]);
            }
            if (j + 1 - low < high - j - 1) {
                _sort(a, low, j + 1);
                low = j + 1;
            } else {
                _sort(a, j + 1, high);
                high = j + 1;
            }
        }
        for (uint256 i = low + 1; i < high; ++i) {
            uint256 v = a[i];
            uint256 j = i;
            while (j > low && a[j - 1] > v) {
                a[j] = a[j - 1];
                --j;
            }
            a[j] = v;
        }
    }

    /// @dev Sorts `keys[low:high]` as `_sort` does, moving each value with its key.
    function _sort(uint256[] memory keys, uint256[] memory values, uint256 low, uint256 high)
        private
        pure
    {
        while (high - low > 12) {
            uint256 last = high - 1;
            uint256 mid = low + ((high - low) >> 1);
            if (keys[mid] < keys[low]) _swap(keys, values, low, mid);
            if (keys[last] < keys[mid]) {
                _swap(keys, values, mid, last);
                if (keys[mid] < keys[low]) _swap(keys, values, low, mid);
            }
            uint256 y = keys[mid];
            uint256 i = low;
            uint256 j = last;
            while (true) {
                do {
                    ++i;
                } while (keys[i] < y);
                do {
                    --j;
                } while (y < keys[j]);
                if (i >= j) break;
                _swap(keys, values, i, j);
            }
            if (j + 1 - low < high - j - 1) {
                _sort(keys, values, low, j + 1);
                low = j + 1;
            } else {
                _sort(keys, values, j + 1, high);
                high = j + 1;
            }
        }
        for (uint256 i = low + 1; i < high; ++i) {
            uint256 k = keys[i];
            uint256 v = values[i];
            uint256 j = i;
            while (j > low && keys[j - 1] > k) {
                keys[j] = keys[j - 1];
                values[j] = values[j - 1];
                --j;
            }
            keys[j] = k;
            values[j] = v;
        }
    }

    /// @dev Exchanges the keys and the values at `i` and `j`.
    /// @custom:solar-inline
    function _swap(uint256[] memory keys, uint256[] memory values, uint256 i, uint256 j)
        private
        pure
    {
        (keys[i], keys[j]) = (keys[j], keys[i]);
        (values[i], values[j]) = (values[j], values[i]);
    }

    /// @dev Whether `a` contains the same value at two indices, through an
    /// open-addressed table of indices at least twice as long as `a`.
    function _hasDuplicate(uint256[] memory a) private pure returns (bool) {
        if (a.length < 2) return false;
        uint256 capacity = 1;
        while (capacity < a.length * 2) capacity *= 2;
        uint256[] memory seen = new uint256[](capacity);
        uint256 mask = capacity - 1;
        for (uint256 i = a.length; i != 0;) {
            --i;
            uint256 slot = mulmod(a[i], 0x100000000000000000000000000000051, ~uint256(0xbc)) & mask;
            while (seen[slot] != 0) {
                if (a[seen[slot] - 1] == a[i]) return true;
                slot = (slot + 1) & mask;
            }
            seen[slot] = i + 1;
        }
        return false;
    }

    /// @dev Copies `a[from:]` into `c` at `at`, and returns the index past it.
    /// @custom:solar-inline
    function _copyTail(uint256[] memory c, uint256 at, uint256[] memory a, uint256 from)
        private
        pure
        returns (uint256)
    {
        uint256 n = a.length - from;
        for (uint256 t; t < n; ++t) {
            c[at + t] = a[from + t];
        }
        return at + n;
    }

    /// @dev A new array holding the elements of `a`.
    function _copy(uint256[] memory a) private pure returns (uint256[] memory c) {
        uint256 n = a.length;
        c = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            c[i] = a[i];
        }
    }

    /// @dev Removes adjacent duplicates from sorted `a` in place.
    function _uniquifySorted(uint256[] memory a) private pure {
        if (a.length < 2) return;
        uint256 write = 1;
        // The last kept element, which `a[write - 1]` holds.
        uint256 last = a[0];
        for (uint256 read = 1; read < a.length; ++read) {
            uint256 x = a[read];
            if (x != last) {
                a[write++] = x;
                last = x;
            }
        }
        _truncate(a, write);
    }

    /// @dev The sorted union of sorted, duplicate-free `a` and `b`.
    function _union(uint256[] memory a, uint256[] memory b)
        private
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
                c[k++] = u;
                ++i;
                ++j;
            } else if (u > v) {
                c[k++] = v;
                ++j;
            } else {
                c[k++] = u;
                ++i;
            }
        }
        k = _copyTail(c, k, a, i);
        k = _copyTail(c, k, b, j);
        _truncate(c, k);
    }

    /// @dev The sorted intersection of sorted, duplicate-free `a` and `b`.
    function _intersection(uint256[] memory a, uint256[] memory b)
        private
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
                c[k++] = u;
                ++i;
                ++j;
            } else if (u > v) {
                ++j;
            } else {
                ++i;
            }
        }
        _truncate(c, k);
    }

    /// @dev The sorted difference of sorted, duplicate-free `a` and `b`.
    function _difference(uint256[] memory a, uint256[] memory b)
        private
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
                c[k++] = u;
                ++i;
            }
        }
        k = _copyTail(c, k, a, i);
        _truncate(c, k);
    }

    /// @dev Sorts `keys` with `values` moved alongside, keeps one of each key,
    /// and gives it the sum of the values its copies had. Both arrays shrink to
    /// the kept keys. The arrays must have one length, and every sum must fit a
    /// word.
    function _groupSum(uint256[] memory keys, uint256[] memory values) private pure {
        uint256 n = keys.length;
        if (values.length != n) n = _outOfBounds();
        if (n < 2) return;
        if (_sortAll(keys, values, n)) return;
        uint256 kept;
        uint256 sum = values[0];
        // The last kept key, which `keys[kept]` holds.
        uint256 last = keys[0];
        for (uint256 i = 1; i < keys.length; ++i) {
            uint256 key = keys[i];
            if (key == last) {
                sum += values[i];
            } else {
                values[kept] = sum;
                keys[++kept] = key;
                last = key;
                sum = values[i];
            }
        }
        values[kept] = sum;
        _truncate(keys, kept + 1);
        _truncate(values, kept + 1);
    }

    /// @dev Shrinks `a` to its first `n` elements in place. Solidity cannot
    /// spell a shorter length for an existing array; the elements past `n` stay
    /// in memory the array no longer covers.
    /// @custom:solar-trusted
    function _truncate(uint256[] memory a, uint256 n) private pure {
        if (n > a.length) n = _outOfBounds();
        /// @solidity memory-safe-assembly
        assembly {
            mstore(a, n)
        }
    }

    /// @dev Sorts `a[low:high]`: median-of-three Hoare partitions down to twelve
    /// elements, then insertion sort. The smaller part recurses and the larger
    /// one loops, so the recursion is at most `log2(high - low)` deep.
    function _sort(int256[] memory a, uint256 low, uint256 high) private pure {
        while (high - low > 12) {
            uint256 last = high - 1;
            uint256 mid = low + ((high - low) >> 1);
            int256 x = a[low];
            int256 y = a[mid];
            int256 z = a[last];
            if (y < x) (x, y) = (y, x);
            if (z < y) {
                (y, z) = (z, y);
                if (y < x) (x, y) = (y, x);
            }
            (a[low], a[mid], a[last]) = (x, y, z);
            // `a[low] <= y <= a[last]` stop both scans inside the range.
            uint256 i = low;
            uint256 j = last;
            while (true) {
                do {
                    ++i;
                } while (a[i] < y);
                do {
                    --j;
                } while (y < a[j]);
                if (i >= j) break;
                (a[i], a[j]) = (a[j], a[i]);
            }
            if (j + 1 - low < high - j - 1) {
                _sort(a, low, j + 1);
                low = j + 1;
            } else {
                _sort(a, j + 1, high);
                high = j + 1;
            }
        }
        for (uint256 i = low + 1; i < high; ++i) {
            int256 v = a[i];
            uint256 j = i;
            while (j > low && a[j - 1] > v) {
                a[j] = a[j - 1];
                --j;
            }
            a[j] = v;
        }
    }

    /// @dev Sorts `keys[low:high]` as `_sort` does, moving each value with its
    /// key. Signed keys are ordered by their two's-complement words, as the
    /// pinned upstream `groupSum` orders them.
    function _sort(int256[] memory keys, uint256[] memory values, uint256 low, uint256 high)
        private
        pure
    {
        while (high - low > 12) {
            uint256 last = high - 1;
            uint256 mid = low + ((high - low) >> 1);
            if (uint256(keys[mid]) < uint256(keys[low])) _swap(keys, values, low, mid);
            if (uint256(keys[last]) < uint256(keys[mid])) {
                _swap(keys, values, mid, last);
                if (uint256(keys[mid]) < uint256(keys[low])) _swap(keys, values, low, mid);
            }
            uint256 y = uint256(keys[mid]);
            uint256 i = low;
            uint256 j = last;
            while (true) {
                do {
                    ++i;
                } while (uint256(keys[i]) < y);
                do {
                    --j;
                } while (y < uint256(keys[j]));
                if (i >= j) break;
                _swap(keys, values, i, j);
            }
            if (j + 1 - low < high - j - 1) {
                _sort(keys, values, low, j + 1);
                low = j + 1;
            } else {
                _sort(keys, values, j + 1, high);
                high = j + 1;
            }
        }
        for (uint256 i = low + 1; i < high; ++i) {
            int256 k = keys[i];
            uint256 v = values[i];
            uint256 j = i;
            while (j > low && uint256(keys[j - 1]) > uint256(k)) {
                keys[j] = keys[j - 1];
                values[j] = values[j - 1];
                --j;
            }
            keys[j] = k;
            values[j] = v;
        }
    }

    /// @dev Exchanges the keys and the values at `i` and `j`.
    /// @custom:solar-inline
    function _swap(int256[] memory keys, uint256[] memory values, uint256 i, uint256 j)
        private
        pure
    {
        (keys[i], keys[j]) = (keys[j], keys[i]);
        (values[i], values[j]) = (values[j], values[i]);
    }

    /// @dev Whether `a` contains the same value at two indices, through an
    /// open-addressed table of indices at least twice as long as `a`.
    function _hasDuplicate(int256[] memory a) private pure returns (bool) {
        if (a.length < 2) return false;
        uint256 capacity = 1;
        while (capacity < a.length * 2) capacity *= 2;
        uint256[] memory seen = new uint256[](capacity);
        uint256 mask = capacity - 1;
        for (uint256 i = a.length; i != 0;) {
            --i;
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

    /// @dev Copies `a[from:]` into `c` at `at`, and returns the index past it.
    /// @custom:solar-inline
    function _copyTail(int256[] memory c, uint256 at, int256[] memory a, uint256 from)
        private
        pure
        returns (uint256)
    {
        uint256 n = a.length - from;
        for (uint256 t; t < n; ++t) {
            c[at + t] = a[from + t];
        }
        return at + n;
    }

    /// @dev A new array holding the elements of `a`.
    function _copy(int256[] memory a) private pure returns (int256[] memory c) {
        uint256 n = a.length;
        c = new int256[](n);
        for (uint256 i; i < n; ++i) {
            c[i] = a[i];
        }
    }

    /// @dev Removes adjacent duplicates from sorted `a` in place.
    function _uniquifySorted(int256[] memory a) private pure {
        if (a.length < 2) return;
        uint256 write = 1;
        // The last kept element, which `a[write - 1]` holds.
        int256 last = a[0];
        for (uint256 read = 1; read < a.length; ++read) {
            int256 x = a[read];
            if (x != last) {
                a[write++] = x;
                last = x;
            }
        }
        _truncate(a, write);
    }

    /// @dev The sorted union of sorted, duplicate-free `a` and `b`.
    function _union(int256[] memory a, int256[] memory b) private pure returns (int256[] memory c) {
        c = new int256[](a.length + b.length);
        uint256 i;
        uint256 j;
        uint256 k;
        while (i < a.length && j < b.length) {
            int256 u = a[i];
            int256 v = b[j];
            if (u == v) {
                c[k++] = u;
                ++i;
                ++j;
            } else if (u > v) {
                c[k++] = v;
                ++j;
            } else {
                c[k++] = u;
                ++i;
            }
        }
        k = _copyTail(c, k, a, i);
        k = _copyTail(c, k, b, j);
        _truncate(c, k);
    }

    /// @dev The sorted intersection of sorted, duplicate-free `a` and `b`.
    function _intersection(int256[] memory a, int256[] memory b)
        private
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
                c[k++] = u;
                ++i;
                ++j;
            } else if (u > v) {
                ++j;
            } else {
                ++i;
            }
        }
        _truncate(c, k);
    }

    /// @dev The sorted difference of sorted, duplicate-free `a` and `b`.
    function _difference(int256[] memory a, int256[] memory b)
        private
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
                c[k++] = u;
                ++i;
            }
        }
        k = _copyTail(c, k, a, i);
        _truncate(c, k);
    }

    /// @dev Sorts `keys` with `values` moved alongside, keeps one of each key,
    /// and gives it the sum of the values its copies had. Both arrays shrink to
    /// the kept keys. The arrays must have one length, and every sum must fit a
    /// word.
    function _groupSum(int256[] memory keys, uint256[] memory values) private pure {
        uint256 n = keys.length;
        if (values.length != n) n = _outOfBounds();
        if (n < 2) return;
        if (_sortAll(keys, values, n)) return;
        uint256 kept;
        uint256 sum = values[0];
        // The last kept key, which `keys[kept]` holds.
        int256 last = keys[0];
        for (uint256 i = 1; i < keys.length; ++i) {
            int256 key = keys[i];
            if (key == last) {
                sum += values[i];
            } else {
                values[kept] = sum;
                keys[++kept] = key;
                last = key;
                sum = values[i];
            }
        }
        values[kept] = sum;
        _truncate(keys, kept + 1);
        _truncate(values, kept + 1);
    }

    /// @dev Shrinks `a` to its first `n` elements in place. Solidity cannot
    /// spell a shorter length for an existing array; the elements past `n` stay
    /// in memory the array no longer covers.
    /// @custom:solar-trusted
    function _truncate(int256[] memory a, uint256 n) private pure {
        if (n > a.length) n = _outOfBounds();
        /// @solidity memory-safe-assembly
        assembly {
            mstore(a, n)
        }
    }

    /// @dev Sorts `a[low:high]`: median-of-three Hoare partitions down to twelve
    /// elements, then insertion sort. The smaller part recurses and the larger
    /// one loops, so the recursion is at most `log2(high - low)` deep.
    function _sort(address[] memory a, uint256 low, uint256 high) private pure {
        while (high - low > 12) {
            uint256 last = high - 1;
            uint256 mid = low + ((high - low) >> 1);
            address x = a[low];
            address y = a[mid];
            address z = a[last];
            if (y < x) (x, y) = (y, x);
            if (z < y) {
                (y, z) = (z, y);
                if (y < x) (x, y) = (y, x);
            }
            (a[low], a[mid], a[last]) = (x, y, z);
            // `a[low] <= y <= a[last]` stop both scans inside the range.
            uint256 i = low;
            uint256 j = last;
            while (true) {
                do {
                    ++i;
                } while (a[i] < y);
                do {
                    --j;
                } while (y < a[j]);
                if (i >= j) break;
                (a[i], a[j]) = (a[j], a[i]);
            }
            if (j + 1 - low < high - j - 1) {
                _sort(a, low, j + 1);
                low = j + 1;
            } else {
                _sort(a, j + 1, high);
                high = j + 1;
            }
        }
        for (uint256 i = low + 1; i < high; ++i) {
            address v = a[i];
            uint256 j = i;
            while (j > low && a[j - 1] > v) {
                a[j] = a[j - 1];
                --j;
            }
            a[j] = v;
        }
    }

    /// @dev Sorts `keys[low:high]` as `_sort` does, moving each value with its key.
    function _sort(address[] memory keys, uint256[] memory values, uint256 low, uint256 high)
        private
        pure
    {
        while (high - low > 12) {
            uint256 last = high - 1;
            uint256 mid = low + ((high - low) >> 1);
            if (keys[mid] < keys[low]) _swap(keys, values, low, mid);
            if (keys[last] < keys[mid]) {
                _swap(keys, values, mid, last);
                if (keys[mid] < keys[low]) _swap(keys, values, low, mid);
            }
            address y = keys[mid];
            uint256 i = low;
            uint256 j = last;
            while (true) {
                do {
                    ++i;
                } while (keys[i] < y);
                do {
                    --j;
                } while (y < keys[j]);
                if (i >= j) break;
                _swap(keys, values, i, j);
            }
            if (j + 1 - low < high - j - 1) {
                _sort(keys, values, low, j + 1);
                low = j + 1;
            } else {
                _sort(keys, values, j + 1, high);
                high = j + 1;
            }
        }
        for (uint256 i = low + 1; i < high; ++i) {
            address k = keys[i];
            uint256 v = values[i];
            uint256 j = i;
            while (j > low && keys[j - 1] > k) {
                keys[j] = keys[j - 1];
                values[j] = values[j - 1];
                --j;
            }
            keys[j] = k;
            values[j] = v;
        }
    }

    /// @dev Exchanges the keys and the values at `i` and `j`.
    /// @custom:solar-inline
    function _swap(address[] memory keys, uint256[] memory values, uint256 i, uint256 j)
        private
        pure
    {
        (keys[i], keys[j]) = (keys[j], keys[i]);
        (values[i], values[j]) = (values[j], values[i]);
    }

    /// @dev Whether `a` contains the same value at two indices, through an
    /// open-addressed table of indices at least twice as long as `a`.
    function _hasDuplicate(address[] memory a) private pure returns (bool) {
        if (a.length < 2) return false;
        uint256 capacity = 1;
        while (capacity < a.length * 2) capacity *= 2;
        uint256[] memory seen = new uint256[](capacity);
        uint256 mask = capacity - 1;
        for (uint256 i = a.length; i != 0;) {
            --i;
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

    /// @dev A new array holding the elements of `a`.
    function _copy(address[] memory a) private pure returns (address[] memory c) {
        uint256 n = a.length;
        c = new address[](n);
        for (uint256 i; i < n; ++i) {
            c[i] = a[i];
        }
    }

    /// @dev Removes adjacent duplicates from sorted `a` in place.
    function _uniquifySorted(address[] memory a) private pure {
        if (a.length < 2) return;
        uint256 write = 1;
        // The last kept element, which `a[write - 1]` holds.
        address last = a[0];
        for (uint256 read = 1; read < a.length; ++read) {
            address x = a[read];
            if (x != last) {
                a[write++] = x;
                last = x;
            }
        }
        _truncate(a, write);
    }

    /// @dev The sorted union of sorted, duplicate-free `a` and `b`.
    function _union(address[] memory a, address[] memory b)
        private
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
                c[k++] = u;
                ++i;
                ++j;
            } else if (u > v) {
                c[k++] = v;
                ++j;
            } else {
                c[k++] = u;
                ++i;
            }
        }
        while (i < a.length) c[k++] = a[i++];
        while (j < b.length) c[k++] = b[j++];
        _truncate(c, k);
    }

    /// @dev The sorted intersection of sorted, duplicate-free `a` and `b`.
    function _intersection(address[] memory a, address[] memory b)
        private
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
                c[k++] = u;
                ++i;
                ++j;
            } else if (u > v) {
                ++j;
            } else {
                ++i;
            }
        }
        _truncate(c, k);
    }

    /// @dev The sorted difference of sorted, duplicate-free `a` and `b`.
    function _difference(address[] memory a, address[] memory b)
        private
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
                c[k++] = u;
                ++i;
            }
        }
        while (i < a.length) c[k++] = a[i++];
        _truncate(c, k);
    }

    /// @dev Sorts `keys` with `values` moved alongside, keeps one of each key,
    /// and gives it the sum of the values its copies had. Both arrays shrink to
    /// the kept keys. The arrays must have one length, and every sum must fit a
    /// word.
    function _groupSum(address[] memory keys, uint256[] memory values) private pure {
        uint256 n = keys.length;
        if (values.length != n) n = _outOfBounds();
        if (n < 2) return;
        if (_sortAll(keys, values, n)) return;
        uint256 kept;
        uint256 sum = values[0];
        // The last kept key, which `keys[kept]` holds.
        address last = keys[0];
        for (uint256 i = 1; i < keys.length; ++i) {
            address key = keys[i];
            if (key == last) {
                sum += values[i];
            } else {
                values[kept] = sum;
                keys[++kept] = key;
                last = key;
                sum = values[i];
            }
        }
        values[kept] = sum;
        _truncate(keys, kept + 1);
        _truncate(values, kept + 1);
    }

    /// @dev Shrinks `a` to its first `n` elements in place. Solidity cannot
    /// spell a shorter length for an existing array; the elements past `n` stay
    /// in memory the array no longer covers.
    /// @custom:solar-trusted
    function _truncate(address[] memory a, uint256 n) private pure {
        if (n > a.length) n = _outOfBounds();
        /// @solidity memory-safe-assembly
        assembly {
            mstore(a, n)
        }
    }

    /// @dev Sorts `a[low:high]`: median-of-three Hoare partitions down to twelve
    /// elements, then insertion sort. The smaller part recurses and the larger
    /// one loops, so the recursion is at most `log2(high - low)` deep.
    function _sort(bytes32[] memory a, uint256 low, uint256 high) private pure {
        while (high - low > 12) {
            uint256 last = high - 1;
            uint256 mid = low + ((high - low) >> 1);
            bytes32 x = a[low];
            bytes32 y = a[mid];
            bytes32 z = a[last];
            if (y < x) (x, y) = (y, x);
            if (z < y) {
                (y, z) = (z, y);
                if (y < x) (x, y) = (y, x);
            }
            (a[low], a[mid], a[last]) = (x, y, z);
            // `a[low] <= y <= a[last]` stop both scans inside the range.
            uint256 i = low;
            uint256 j = last;
            while (true) {
                do {
                    ++i;
                } while (a[i] < y);
                do {
                    --j;
                } while (y < a[j]);
                if (i >= j) break;
                (a[i], a[j]) = (a[j], a[i]);
            }
            if (j + 1 - low < high - j - 1) {
                _sort(a, low, j + 1);
                low = j + 1;
            } else {
                _sort(a, j + 1, high);
                high = j + 1;
            }
        }
        for (uint256 i = low + 1; i < high; ++i) {
            bytes32 v = a[i];
            uint256 j = i;
            while (j > low && a[j - 1] > v) {
                a[j] = a[j - 1];
                --j;
            }
            a[j] = v;
        }
    }

    /// @dev Sorts `keys[low:high]` as `_sort` does, moving each value with its key.
    function _sort(bytes32[] memory keys, uint256[] memory values, uint256 low, uint256 high)
        private
        pure
    {
        while (high - low > 12) {
            uint256 last = high - 1;
            uint256 mid = low + ((high - low) >> 1);
            if (keys[mid] < keys[low]) _swap(keys, values, low, mid);
            if (keys[last] < keys[mid]) {
                _swap(keys, values, mid, last);
                if (keys[mid] < keys[low]) _swap(keys, values, low, mid);
            }
            bytes32 y = keys[mid];
            uint256 i = low;
            uint256 j = last;
            while (true) {
                do {
                    ++i;
                } while (keys[i] < y);
                do {
                    --j;
                } while (y < keys[j]);
                if (i >= j) break;
                _swap(keys, values, i, j);
            }
            if (j + 1 - low < high - j - 1) {
                _sort(keys, values, low, j + 1);
                low = j + 1;
            } else {
                _sort(keys, values, j + 1, high);
                high = j + 1;
            }
        }
        for (uint256 i = low + 1; i < high; ++i) {
            bytes32 k = keys[i];
            uint256 v = values[i];
            uint256 j = i;
            while (j > low && keys[j - 1] > k) {
                keys[j] = keys[j - 1];
                values[j] = values[j - 1];
                --j;
            }
            keys[j] = k;
            values[j] = v;
        }
    }

    /// @dev Exchanges the keys and the values at `i` and `j`.
    /// @custom:solar-inline
    function _swap(bytes32[] memory keys, uint256[] memory values, uint256 i, uint256 j)
        private
        pure
    {
        (keys[i], keys[j]) = (keys[j], keys[i]);
        (values[i], values[j]) = (values[j], values[i]);
    }

    /// @dev Whether `a` contains the same value at two indices, through an
    /// open-addressed table of indices at least twice as long as `a`.
    function _hasDuplicate(bytes32[] memory a) private pure returns (bool) {
        if (a.length < 2) return false;
        uint256 capacity = 1;
        while (capacity < a.length * 2) capacity *= 2;
        uint256[] memory seen = new uint256[](capacity);
        uint256 mask = capacity - 1;
        for (uint256 i = a.length; i != 0;) {
            --i;
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

    /// @dev Copies `a[from:]` into `c` at `at`, and returns the index past it.
    /// @custom:solar-inline
    function _copyTail(bytes32[] memory c, uint256 at, bytes32[] memory a, uint256 from)
        private
        pure
        returns (uint256)
    {
        uint256 n = a.length - from;
        for (uint256 t; t < n; ++t) {
            c[at + t] = a[from + t];
        }
        return at + n;
    }

    /// @dev A new array holding the elements of `a`.
    function _copy(bytes32[] memory a) private pure returns (bytes32[] memory c) {
        uint256 n = a.length;
        c = new bytes32[](n);
        for (uint256 i; i < n; ++i) {
            c[i] = a[i];
        }
    }

    /// @dev Removes adjacent duplicates from sorted `a` in place.
    function _uniquifySorted(bytes32[] memory a) private pure {
        if (a.length < 2) return;
        uint256 write = 1;
        // The last kept element, which `a[write - 1]` holds.
        bytes32 last = a[0];
        for (uint256 read = 1; read < a.length; ++read) {
            bytes32 x = a[read];
            if (x != last) {
                a[write++] = x;
                last = x;
            }
        }
        _truncate(a, write);
    }

    /// @dev The sorted union of sorted, duplicate-free `a` and `b`.
    function _union(bytes32[] memory a, bytes32[] memory b)
        private
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
                c[k++] = u;
                ++i;
                ++j;
            } else if (u > v) {
                c[k++] = v;
                ++j;
            } else {
                c[k++] = u;
                ++i;
            }
        }
        k = _copyTail(c, k, a, i);
        k = _copyTail(c, k, b, j);
        _truncate(c, k);
    }

    /// @dev The sorted intersection of sorted, duplicate-free `a` and `b`.
    function _intersection(bytes32[] memory a, bytes32[] memory b)
        private
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
                c[k++] = u;
                ++i;
                ++j;
            } else if (u > v) {
                ++j;
            } else {
                ++i;
            }
        }
        _truncate(c, k);
    }

    /// @dev The sorted difference of sorted, duplicate-free `a` and `b`.
    function _difference(bytes32[] memory a, bytes32[] memory b)
        private
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
                c[k++] = u;
                ++i;
            }
        }
        k = _copyTail(c, k, a, i);
        _truncate(c, k);
    }

    /// @dev Sorts `keys` with `values` moved alongside, keeps one of each key,
    /// and gives it the sum of the values its copies had. Both arrays shrink to
    /// the kept keys. The arrays must have one length, and every sum must fit a
    /// word.
    function _groupSum(bytes32[] memory keys, uint256[] memory values) private pure {
        uint256 n = keys.length;
        if (values.length != n) n = _outOfBounds();
        if (n < 2) return;
        if (_sortAll(keys, values, n)) return;
        uint256 kept;
        uint256 sum = values[0];
        // The last kept key, which `keys[kept]` holds.
        bytes32 last = keys[0];
        for (uint256 i = 1; i < keys.length; ++i) {
            bytes32 key = keys[i];
            if (key == last) {
                sum += values[i];
            } else {
                values[kept] = sum;
                keys[++kept] = key;
                last = key;
                sum = values[i];
            }
        }
        values[kept] = sum;
        _truncate(keys, kept + 1);
        _truncate(values, kept + 1);
    }

    /// @dev Shrinks `a` to its first `n` elements in place. Solidity cannot
    /// spell a shorter length for an existing array; the elements past `n` stay
    /// in memory the array no longer covers.
    /// @custom:solar-trusted
    function _truncate(bytes32[] memory a, uint256 n) private pure {
        if (n > a.length) n = _outOfBounds();
        /// @solidity memory-safe-assembly
        assembly {
            mstore(a, n)
        }
    }

    /// @dev Sorts all of `a`, as the assembly does: an array already in order
    /// is left alone and one in reverse order is reversed, each found by one
    /// scan from the end, before the quicksort runs.
    function _sortAll(uint256[] memory a) private pure {
        uint256 n = a.length;
        if (n < 2) return;
        uint256 j = n - 1;
        while (j != 0 && a[j - 1] <= a[j]) --j;
        if (j == 0) return;
        j = n - 1;
        while (j != 0 && a[j - 1] >= a[j]) --j;
        if (j == 0) {
            for (uint256 i; i < n / 2; ++i) {
                (a[i], a[n - 1 - i]) = (a[n - 1 - i], a[i]);
            }
            return;
        }
        _sort(a, 0, n);
    }

    /// @dev Sorts the `n >= 2` keys with each value moved alongside, as
    /// `_sortAll` sorts: keys already in order stay, keys in reverse order are
    /// reversed with their values, and any others go through the quicksort,
    /// unless they hold at most three distinct keys: those `_groupFew`
    /// groups without a sort, and `grouped` is true.
    function _sortAll(uint256[] memory keys, uint256[] memory values, uint256 n)
        private
        pure
        returns (bool grouped)
    {
        uint256 j = n - 1;
        uint256 next = keys[j];
        while (j != 0) {
            uint256 x = keys[j - 1];
            if (x > next) break;
            next = x;
            --j;
        }
        if (j == 0) return false;
        j = n - 1;
        next = keys[j];
        while (j != 0) {
            uint256 x = keys[j - 1];
            if (x < next) break;
            next = x;
            --j;
        }
        if (j == 0) {
            for (uint256 i; i < n / 2; ++i) {
                _swap(keys, values, i, n - 1 - i);
            }
            return false;
        }
        if (_groupFew(keys, values, n)) return true;
        _sort(keys, values, 0, n);
    }

    /// @dev Groups `n` keys of at most three distinct values in one read of
    /// the arrays, keeping each key and its sum on the stack, and writes the
    /// groups in key order. Returns false, with the arrays unchanged, at the
    /// first key past those. Keys order as `_sort` orders them.
    function _groupFew(uint256[] memory keys, uint256[] memory values, uint256 n)
        private
        pure
        returns (bool)
    {
        uint256 k0 = keys[0];
        uint256 s0 = values[0];
        uint256 k1;
        uint256 s1;
        uint256 k2;
        uint256 s2;
        uint256 u = 1;
        for (uint256 i = 1; i < n; ++i) {
            uint256 key = keys[i];
            if (key == k0) {
                s0 += values[i];
            } else if (u > 1 && key == k1) {
                s1 += values[i];
            } else if (u > 2 && key == k2) {
                s2 += values[i];
            } else if (u == 1) {
                (k1, s1, u) = (key, values[i], 2);
            } else if (u == 2) {
                (k2, s2, u) = (key, values[i], 3);
            } else {
                return false;
            }
        }
        if (u > 1) {
            if (k1 < k0) (k0, s0, k1, s1) = (k1, s1, k0, s0);
        }
        if (u > 2) {
            if (k2 < k1) (k1, s1, k2, s2) = (k2, s2, k1, s1);
            if (k1 < k0) (k0, s0, k1, s1) = (k1, s1, k0, s0);
        }
        keys[0] = k0;
        values[0] = s0;
        if (u > 1) {
            keys[1] = k1;
            values[1] = s1;
        }
        if (u > 2) {
            keys[2] = k2;
            values[2] = s2;
        }
        _truncate(keys, u);
        _truncate(values, u);
        return true;
    }

    /// @dev Sorts all of `a`, as the assembly does: an array already in order
    /// is left alone and one in reverse order is reversed, each found by one
    /// scan from the end, before the quicksort runs.
    function _sortAll(int256[] memory a) private pure {
        uint256 n = a.length;
        if (n < 2) return;
        uint256 j = n - 1;
        while (j != 0 && a[j - 1] <= a[j]) --j;
        if (j == 0) return;
        j = n - 1;
        while (j != 0 && a[j - 1] >= a[j]) --j;
        if (j == 0) {
            for (uint256 i; i < n / 2; ++i) {
                (a[i], a[n - 1 - i]) = (a[n - 1 - i], a[i]);
            }
            return;
        }
        _sort(a, 0, n);
    }

    /// @dev Sorts the `n >= 2` keys with each value moved alongside, as
    /// `_sortAll` sorts: keys already in order stay, keys in reverse order are
    /// reversed with their values, and any others go through the quicksort,
    /// unless they hold at most three distinct keys: those `_groupFew`
    /// groups without a sort, and `grouped` is true.
    /// Keys order by their two's-complement words, as `_sort` orders them.
    function _sortAll(int256[] memory keys, uint256[] memory values, uint256 n)
        private
        pure
        returns (bool grouped)
    {
        uint256 j = n - 1;
        uint256 next = uint256(keys[j]);
        while (j != 0) {
            uint256 x = uint256(keys[j - 1]);
            if (x > next) break;
            next = x;
            --j;
        }
        if (j == 0) return false;
        j = n - 1;
        next = uint256(keys[j]);
        while (j != 0) {
            uint256 x = uint256(keys[j - 1]);
            if (x < next) break;
            next = x;
            --j;
        }
        if (j == 0) {
            for (uint256 i; i < n / 2; ++i) {
                _swap(keys, values, i, n - 1 - i);
            }
            return false;
        }
        if (_groupFew(keys, values, n)) return true;
        _sort(keys, values, 0, n);
    }

    /// @dev Groups `n` keys of at most three distinct values in one read of
    /// the arrays, keeping each key and its sum on the stack, and writes the
    /// groups in key order. Returns false, with the arrays unchanged, at the
    /// first key past those. Keys order by their two's-complement words, as
    /// `_sort` orders them.
    function _groupFew(int256[] memory keys, uint256[] memory values, uint256 n)
        private
        pure
        returns (bool)
    {
        int256 k0 = keys[0];
        uint256 s0 = values[0];
        int256 k1;
        uint256 s1;
        int256 k2;
        uint256 s2;
        uint256 u = 1;
        for (uint256 i = 1; i < n; ++i) {
            int256 key = keys[i];
            if (key == k0) {
                s0 += values[i];
            } else if (u > 1 && key == k1) {
                s1 += values[i];
            } else if (u > 2 && key == k2) {
                s2 += values[i];
            } else if (u == 1) {
                (k1, s1, u) = (key, values[i], 2);
            } else if (u == 2) {
                (k2, s2, u) = (key, values[i], 3);
            } else {
                return false;
            }
        }
        if (u > 1) {
            if (uint256(k1) < uint256(k0)) (k0, s0, k1, s1) = (k1, s1, k0, s0);
        }
        if (u > 2) {
            if (uint256(k2) < uint256(k1)) (k1, s1, k2, s2) = (k2, s2, k1, s1);
            if (uint256(k1) < uint256(k0)) (k0, s0, k1, s1) = (k1, s1, k0, s0);
        }
        keys[0] = k0;
        values[0] = s0;
        if (u > 1) {
            keys[1] = k1;
            values[1] = s1;
        }
        if (u > 2) {
            keys[2] = k2;
            values[2] = s2;
        }
        _truncate(keys, u);
        _truncate(values, u);
        return true;
    }

    /// @dev Sorts all of `a`, as the assembly does: an array already in order
    /// is left alone and one in reverse order is reversed, each found by one
    /// scan from the end, before the quicksort runs.
    function _sortAll(address[] memory a) private pure {
        uint256 n = a.length;
        if (n < 2) return;
        uint256 j = n - 1;
        address next = a[j];
        while (j != 0) {
            address x = a[j - 1];
            if (x > next) break;
            next = x;
            --j;
        }
        if (j == 0) return;
        j = n - 1;
        next = a[j];
        while (j != 0) {
            address x = a[j - 1];
            if (x < next) break;
            next = x;
            --j;
        }
        if (j == 0) {
            for (uint256 i; i < n / 2; ++i) {
                (a[i], a[n - 1 - i]) = (a[n - 1 - i], a[i]);
            }
            return;
        }
        _sort(a, 0, n);
    }

    /// @dev Sorts the `n >= 2` keys with each value moved alongside, as
    /// `_sortAll` sorts: keys already in order stay, keys in reverse order are
    /// reversed with their values, and any others go through the quicksort,
    /// unless they hold at most three distinct keys: those `_groupFew`
    /// groups without a sort, and `grouped` is true.
    function _sortAll(address[] memory keys, uint256[] memory values, uint256 n)
        private
        pure
        returns (bool grouped)
    {
        uint256 j = n - 1;
        address next = keys[j];
        while (j != 0) {
            address x = keys[j - 1];
            if (x > next) break;
            next = x;
            --j;
        }
        if (j == 0) return false;
        j = n - 1;
        next = keys[j];
        while (j != 0) {
            address x = keys[j - 1];
            if (x < next) break;
            next = x;
            --j;
        }
        if (j == 0) {
            for (uint256 i; i < n / 2; ++i) {
                _swap(keys, values, i, n - 1 - i);
            }
            return false;
        }
        if (_groupFew(keys, values, n)) return true;
        _sort(keys, values, 0, n);
    }

    /// @dev Groups `n` keys of at most three distinct values in one read of
    /// the arrays, keeping each key and its sum on the stack, and writes the
    /// groups in key order. Returns false, with the arrays unchanged, at the
    /// first key past those. Keys order as `_sort` orders them.
    function _groupFew(address[] memory keys, uint256[] memory values, uint256 n)
        private
        pure
        returns (bool)
    {
        address k0 = keys[0];
        uint256 s0 = values[0];
        address k1;
        uint256 s1;
        address k2;
        uint256 s2;
        uint256 u = 1;
        for (uint256 i = 1; i < n; ++i) {
            address key = keys[i];
            if (key == k0) {
                s0 += values[i];
            } else if (u > 1 && key == k1) {
                s1 += values[i];
            } else if (u > 2 && key == k2) {
                s2 += values[i];
            } else if (u == 1) {
                (k1, s1, u) = (key, values[i], 2);
            } else if (u == 2) {
                (k2, s2, u) = (key, values[i], 3);
            } else {
                return false;
            }
        }
        if (u > 1) {
            if (k1 < k0) (k0, s0, k1, s1) = (k1, s1, k0, s0);
        }
        if (u > 2) {
            if (k2 < k1) (k1, s1, k2, s2) = (k2, s2, k1, s1);
            if (k1 < k0) (k0, s0, k1, s1) = (k1, s1, k0, s0);
        }
        keys[0] = k0;
        values[0] = s0;
        if (u > 1) {
            keys[1] = k1;
            values[1] = s1;
        }
        if (u > 2) {
            keys[2] = k2;
            values[2] = s2;
        }
        _truncate(keys, u);
        _truncate(values, u);
        return true;
    }

    /// @dev Sorts all of `a`, as the assembly does: an array already in order
    /// is left alone and one in reverse order is reversed, each found by one
    /// scan from the end, before the quicksort runs.
    function _sortAll(bytes32[] memory a) private pure {
        uint256 n = a.length;
        if (n < 2) return;
        uint256 j = n - 1;
        while (j != 0 && a[j - 1] <= a[j]) --j;
        if (j == 0) return;
        j = n - 1;
        while (j != 0 && a[j - 1] >= a[j]) --j;
        if (j == 0) {
            for (uint256 i; i < n / 2; ++i) {
                (a[i], a[n - 1 - i]) = (a[n - 1 - i], a[i]);
            }
            return;
        }
        _sort(a, 0, n);
    }

    /// @dev Sorts the `n >= 2` keys with each value moved alongside, as
    /// `_sortAll` sorts: keys already in order stay, keys in reverse order are
    /// reversed with their values, and any others go through the quicksort,
    /// unless they hold at most three distinct keys: those `_groupFew`
    /// groups without a sort, and `grouped` is true.
    function _sortAll(bytes32[] memory keys, uint256[] memory values, uint256 n)
        private
        pure
        returns (bool grouped)
    {
        uint256 j = n - 1;
        bytes32 next = keys[j];
        while (j != 0) {
            bytes32 x = keys[j - 1];
            if (x > next) break;
            next = x;
            --j;
        }
        if (j == 0) return false;
        j = n - 1;
        next = keys[j];
        while (j != 0) {
            bytes32 x = keys[j - 1];
            if (x < next) break;
            next = x;
            --j;
        }
        if (j == 0) {
            for (uint256 i; i < n / 2; ++i) {
                _swap(keys, values, i, n - 1 - i);
            }
            return false;
        }
        if (_groupFew(keys, values, n)) return true;
        _sort(keys, values, 0, n);
    }

    /// @dev Groups `n` keys of at most three distinct values in one read of
    /// the arrays, keeping each key and its sum on the stack, and writes the
    /// groups in key order. Returns false, with the arrays unchanged, at the
    /// first key past those. Keys order as `_sort` orders them.
    function _groupFew(bytes32[] memory keys, uint256[] memory values, uint256 n)
        private
        pure
        returns (bool)
    {
        bytes32 k0 = keys[0];
        uint256 s0 = values[0];
        bytes32 k1;
        uint256 s1;
        bytes32 k2;
        uint256 s2;
        uint256 u = 1;
        for (uint256 i = 1; i < n; ++i) {
            bytes32 key = keys[i];
            if (key == k0) {
                s0 += values[i];
            } else if (u > 1 && key == k1) {
                s1 += values[i];
            } else if (u > 2 && key == k2) {
                s2 += values[i];
            } else if (u == 1) {
                (k1, s1, u) = (key, values[i], 2);
            } else if (u == 2) {
                (k2, s2, u) = (key, values[i], 3);
            } else {
                return false;
            }
        }
        if (u > 1) {
            if (k1 < k0) (k0, s0, k1, s1) = (k1, s1, k0, s0);
        }
        if (u > 2) {
            if (k2 < k1) (k1, s1, k2, s2) = (k2, s2, k1, s1);
            if (k1 < k0) (k0, s0, k1, s1) = (k1, s1, k0, s0);
        }
        keys[0] = k0;
        values[0] = s0;
        if (u > 1) {
            keys[1] = k1;
            values[1] = s1;
        }
        if (u > 2) {
            keys[2] = k2;
            values[2] = s2;
        }
        _truncate(keys, u);
        _truncate(values, u);
        return true;
    }

    /// @dev Raises the `Panic(0x32)` an out-of-range index raises.
    function _outOfBounds() private pure returns (uint256) {
        return new uint256[](0)[0];
    }
}
