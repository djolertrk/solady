// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Checked Solidity sorting without type punning or sentinel reads.
/// @dev Each element type has its own implementation, so no array is read as
/// another type. Sorting is a median-of-three quicksort with insertion-sort
/// leaves. Shrinking an array in place has no Solidity spelling, so the APIs
/// that do it, and the set operations that build a result at its largest
/// size, go through `_truncate`, the library's only trusted code.
/// @custom:solar-safe memory arithmetic
library LibSort {
    function insertionSort(uint256[] memory a) internal pure {
        _sortAll(a);
    }

    function sort(uint256[] memory a) internal pure {
        _sortAll(a);
    }

    function reverse(uint256[] memory a) internal pure {
        if (a.length < 2) return;
        for (uint256 i; i < a.length / 2; ++i) {
            uint256 j = a.length - 1 - i;
            (a[i], a[j]) = (a[j], a[i]);
        }
    }

    function copy(uint256[] memory a) internal pure returns (uint256[] memory result) {
        return _copy(a);
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
        return _hasDuplicate(a);
    }

    /// @dev Removes duplicate elements from a ascendingly sorted memory array.
    function uniquifySorted(uint256[] memory a) internal pure {
        _uniquifySorted(a);
    }

    function insertionSort(int256[] memory a) internal pure {
        _sortAll(a);
    }

    function sort(int256[] memory a) internal pure {
        _sortAll(a);
    }

    function reverse(int256[] memory a) internal pure {
        if (a.length < 2) return;
        for (uint256 i; i < a.length / 2; ++i) {
            uint256 j = a.length - 1 - i;
            (a[i], a[j]) = (a[j], a[i]);
        }
    }

    function copy(int256[] memory a) internal pure returns (int256[] memory result) {
        return _copy(a);
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
        return _hasDuplicate(a);
    }

    /// @dev Removes duplicate elements from a ascendingly sorted memory array.
    function uniquifySorted(int256[] memory a) internal pure {
        _uniquifySorted(a);
    }

    function insertionSort(address[] memory a) internal pure {
        _sortAll(a);
    }

    function sort(address[] memory a) internal pure {
        _sortAll(a);
    }

    function reverse(address[] memory a) internal pure {
        if (a.length < 2) return;
        for (uint256 i; i < a.length / 2; ++i) {
            uint256 j = a.length - 1 - i;
            (a[i], a[j]) = (a[j], a[i]);
        }
    }

    function copy(address[] memory a) internal pure returns (address[] memory result) {
        return _copy(a);
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
        return _hasDuplicate(a);
    }

    /// @dev Removes duplicate elements from a ascendingly sorted memory array.
    function uniquifySorted(address[] memory a) internal pure {
        _uniquifySorted(a);
    }

    function insertionSort(bytes32[] memory a) internal pure {
        _sortAll(a);
    }

    function sort(bytes32[] memory a) internal pure {
        _sortAll(a);
    }

    function reverse(bytes32[] memory a) internal pure {
        if (a.length < 2) return;
        for (uint256 i; i < a.length / 2; ++i) {
            uint256 j = a.length - 1 - i;
            (a[i], a[j]) = (a[j], a[i]);
        }
    }

    function copy(bytes32[] memory a) internal pure returns (bytes32[] memory result) {
        return _copy(a);
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
        return _hasDuplicate(a);
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

    /// @dev Returns the sorted set difference of `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function difference(uint256[] memory a, uint256[] memory b)
        internal
        pure
        returns (uint256[] memory c)
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

    /// @dev Returns the sorted set union of `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function union(uint256[] memory a, uint256[] memory b)
        internal
        pure
        returns (uint256[] memory c)
    {
        c = _union(a, b);
    }

    /// @dev Returns the sorted set difference of `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function difference(int256[] memory a, int256[] memory b)
        internal
        pure
        returns (int256[] memory c)
    {
        c = _difference(a, b);
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

    /// @dev Returns the sorted set union of `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function union(int256[] memory a, int256[] memory b)
        internal
        pure
        returns (int256[] memory c)
    {
        c = _union(a, b);
    }

    /// @dev Returns the sorted set difference of `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function difference(address[] memory a, address[] memory b)
        internal
        pure
        returns (address[] memory c)
    {
        c = _difference(a, b);
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

    /// @dev Returns the sorted set union of `a` and `b`.
    /// Note: Behaviour is undefined if inputs are not sorted and uniquified.
    function union(address[] memory a, address[] memory b)
        internal
        pure
        returns (address[] memory c)
    {
        c = _union(a, b);
    }

    /// @dev Returns the sorted set difference of `a` and `b`.
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
    function intersection(bytes32[] memory a, bytes32[] memory b)
        internal
        pure
        returns (bytes32[] memory c)
    {
        c = _intersection(a, b);
    }

    /// @dev Returns the sorted set union of `a` and `b`.
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
            uint256 slot = mulmod(a[i], 0x100000000000000000000000000000051, ~uint256(0xbc))
                & mask;
            while (seen[slot] != 0) {
                if (a[seen[slot] - 1] == a[i]) return true;
                slot = (slot + 1) & mask;
            }
            seen[slot] = i + 1;
        }
        return false;
    }

    /// @dev A new array holding the elements of `a`.
    function _copy(uint256[] memory a) private pure returns (uint256[] memory c) {
        c = new uint256[](a.length);
        for (uint256 i; i < a.length; ++i) {
            c[i] = a[i];
        }
    }

    /// @dev Removes adjacent duplicates from sorted `a` in place.
    function _uniquifySorted(uint256[] memory a) private pure {
        if (a.length < 2) return;
        uint256 write = 1;
        for (uint256 read = 1; read < a.length; ++read) {
            if (a[read] != a[write - 1]) a[write++] = a[read];
        }
        _truncate(a, write);
    }

    /// @dev The sorted union of sorted, duplicate-free `a` and `b`.
    function _union(uint256[] memory a, uint256[] memory b) private pure returns (uint256[] memory c) {
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
        while (i < a.length) c[k++] = a[i++];
        while (j < b.length) c[k++] = b[j++];
        _truncate(c, k);
    }

    /// @dev The sorted intersection of sorted, duplicate-free `a` and `b`.
    function _intersection(uint256[] memory a, uint256[] memory b) private pure returns (uint256[] memory c) {
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
    function _difference(uint256[] memory a, uint256[] memory b) private pure returns (uint256[] memory c) {
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
        while (i < a.length) c[k++] = a[i++];
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
        _sort(keys, values, 0, n);
        uint256 kept;
        uint256 sum = values[0];
        for (uint256 i = 1; i < n; ++i) {
            if (keys[i] == keys[kept]) {
                sum += values[i];
            } else {
                values[kept] = sum;
                keys[++kept] = keys[i];
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
        assembly ("memory-safe") {
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
            uint256 slot = mulmod(uint256(a[i]), 0x100000000000000000000000000000051, ~uint256(0xbc))
                & mask;
            while (seen[slot] != 0) {
                if (a[seen[slot] - 1] == a[i]) return true;
                slot = (slot + 1) & mask;
            }
            seen[slot] = i + 1;
        }
        return false;
    }

    /// @dev A new array holding the elements of `a`.
    function _copy(int256[] memory a) private pure returns (int256[] memory c) {
        c = new int256[](a.length);
        for (uint256 i; i < a.length; ++i) {
            c[i] = a[i];
        }
    }

    /// @dev Removes adjacent duplicates from sorted `a` in place.
    function _uniquifySorted(int256[] memory a) private pure {
        if (a.length < 2) return;
        uint256 write = 1;
        for (uint256 read = 1; read < a.length; ++read) {
            if (a[read] != a[write - 1]) a[write++] = a[read];
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
        while (i < a.length) c[k++] = a[i++];
        while (j < b.length) c[k++] = b[j++];
        _truncate(c, k);
    }

    /// @dev The sorted intersection of sorted, duplicate-free `a` and `b`.
    function _intersection(int256[] memory a, int256[] memory b) private pure returns (int256[] memory c) {
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
    function _difference(int256[] memory a, int256[] memory b) private pure returns (int256[] memory c) {
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
        while (i < a.length) c[k++] = a[i++];
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
        _sort(keys, values, 0, n);
        uint256 kept;
        uint256 sum = values[0];
        for (uint256 i = 1; i < n; ++i) {
            if (keys[i] == keys[kept]) {
                sum += values[i];
            } else {
                values[kept] = sum;
                keys[++kept] = keys[i];
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
        assembly ("memory-safe") {
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
            uint256 slot = mulmod(uint256(uint160(a[i])), 0x100000000000000000000000000000051, ~uint256(0xbc))
                & mask;
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
        c = new address[](a.length);
        for (uint256 i; i < a.length; ++i) {
            c[i] = a[i];
        }
    }

    /// @dev Removes adjacent duplicates from sorted `a` in place.
    function _uniquifySorted(address[] memory a) private pure {
        if (a.length < 2) return;
        uint256 write = 1;
        for (uint256 read = 1; read < a.length; ++read) {
            if (a[read] != a[write - 1]) a[write++] = a[read];
        }
        _truncate(a, write);
    }

    /// @dev The sorted union of sorted, duplicate-free `a` and `b`.
    function _union(address[] memory a, address[] memory b) private pure returns (address[] memory c) {
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
    function _intersection(address[] memory a, address[] memory b) private pure returns (address[] memory c) {
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
    function _difference(address[] memory a, address[] memory b) private pure returns (address[] memory c) {
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
        _sort(keys, values, 0, n);
        uint256 kept;
        uint256 sum = values[0];
        for (uint256 i = 1; i < n; ++i) {
            if (keys[i] == keys[kept]) {
                sum += values[i];
            } else {
                values[kept] = sum;
                keys[++kept] = keys[i];
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
        assembly ("memory-safe") {
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
            uint256 slot = mulmod(uint256(a[i]), 0x100000000000000000000000000000051, ~uint256(0xbc))
                & mask;
            while (seen[slot] != 0) {
                if (a[seen[slot] - 1] == a[i]) return true;
                slot = (slot + 1) & mask;
            }
            seen[slot] = i + 1;
        }
        return false;
    }

    /// @dev A new array holding the elements of `a`.
    function _copy(bytes32[] memory a) private pure returns (bytes32[] memory c) {
        c = new bytes32[](a.length);
        for (uint256 i; i < a.length; ++i) {
            c[i] = a[i];
        }
    }

    /// @dev Removes adjacent duplicates from sorted `a` in place.
    function _uniquifySorted(bytes32[] memory a) private pure {
        if (a.length < 2) return;
        uint256 write = 1;
        for (uint256 read = 1; read < a.length; ++read) {
            if (a[read] != a[write - 1]) a[write++] = a[read];
        }
        _truncate(a, write);
    }

    /// @dev The sorted union of sorted, duplicate-free `a` and `b`.
    function _union(bytes32[] memory a, bytes32[] memory b) private pure returns (bytes32[] memory c) {
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
        while (i < a.length) c[k++] = a[i++];
        while (j < b.length) c[k++] = b[j++];
        _truncate(c, k);
    }

    /// @dev The sorted intersection of sorted, duplicate-free `a` and `b`.
    function _intersection(bytes32[] memory a, bytes32[] memory b) private pure returns (bytes32[] memory c) {
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
    function _difference(bytes32[] memory a, bytes32[] memory b) private pure returns (bytes32[] memory c) {
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
        while (i < a.length) c[k++] = a[i++];
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
        _sort(keys, values, 0, n);
        uint256 kept;
        uint256 sum = values[0];
        for (uint256 i = 1; i < n; ++i) {
            if (keys[i] == keys[kept]) {
                sum += values[i];
            } else {
                values[kept] = sum;
                keys[++kept] = keys[i];
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
        assembly ("memory-safe") {
            mstore(a, n)
        }
    }

    /// @dev Sorts all of `a`.
    function _sortAll(uint256[] memory a) private pure {
        if (a.length > 1) _sort(a, 0, a.length);
    }

    /// @dev Sorts all of `a`.
    function _sortAll(int256[] memory a) private pure {
        if (a.length > 1) _sort(a, 0, a.length);
    }

    /// @dev Sorts all of `a`.
    function _sortAll(address[] memory a) private pure {
        if (a.length > 1) _sort(a, 0, a.length);
    }

    /// @dev Sorts all of `a`.
    function _sortAll(bytes32[] memory a) private pure {
        if (a.length > 1) _sort(a, 0, a.length);
    }

    /// @dev Raises the `Panic(0x32)` an out-of-range index raises.
    function _outOfBounds() private pure returns (uint256) {
        return new uint256[](0)[0];
    }
}
