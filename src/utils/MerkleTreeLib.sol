// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @notice Library for generating Merkle trees.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/MerkleTreeLib.sol)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/merkle-tree/blob/master/src/core.ts)
/// @dev Note:
/// - Leaves are NOT auto hashed. Note that some libraries hash the leaves by default.
///   We leave it up to you to decide if this is needed.
///   If your leaves are 64 bytes long, do hash them first for safety.
///   See: https://www.rareskills.io/post/merkle-tree-second-preimage-attack
/// - Leaves are NOT auto globally sorted. Note that some libraries sort the leaves by default.
/// - The pair hash is pair-sorted-keccak256, which works out-of-the-box with `MerkleProofLib`.
/// - This library is NOT equivalent to OpenZeppelin or Murky.
///   Equivalence is NOT required if you are just using this for pure Solidity testing.
///   May be relevant for differential testing between Solidity vs external libraries.
///
/// The checked port builds and reads the tree with checked indexing, and hashes each pair as
/// `keccak256(abi.encode(min, max))`, the words the assembly hashes in scratch space.
/// `nodeProof` counts a node's depth before it allocates the proof. `multiProofForLeaves`
/// checks the leaf indices first, then runs the assembly's circular queue twice in one array
/// sized to the leaf indices, first to size the proof and the flags, then to fill them; the
/// assembly runs the first pass before it checks the indices. A sibling past the end of
/// `tree`, which only a tree of even length has, reverts with `Panic(0x32)` where the assembly
/// reads the word after `tree`. No helper is trusted.
/// @custom:solar-safe memory arithmetic
library MerkleTreeLib {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev At least 1 leaf is required to build the tree.
    error MerkleTreeLeavesEmpty();

    /// @dev Attempt to access a node with an out-of-bounds index.
    /// Check if the tree has been built and has sufficient leaves and nodes.
    error MerkleTreeOutOfBoundsAccess();

    /// @dev Leaf indices for multi proof must be strictly ascending and not empty.
    error MerkleTreeInvalidLeafIndices();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   MERKLE TREE OPERATIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Builds and return a complete Merkle tree.
    /// To make it a full Merkle tree, use `build(pad(leaves))`.
    function build(bytes32[] memory leaves) internal pure returns (bytes32[] memory tree) {
        uint256 l = leaves.length;
        if (l == 0) revert MerkleTreeLeavesEmpty();
        uint256 n = l + l - 1;
        tree = new bytes32[](n);
        // The leaves, in reverse order, end the tree.
        uint256 k = n;
        for (uint256 i; i < l; ++i) {
            --k;
            tree[k] = leaves[i];
        }
        // Each internal node, from the last, hashes its two children, `k - 2` and `k - 1`.
        for (k = n; k > 1; k -= 2) {
            tree[(k >> 1) - 1] = _hashPair(tree[k - 2], tree[k - 1]);
        }
    }

    /// @dev Returns the root.
    function root(bytes32[] memory tree) internal pure returns (bytes32 result) {
        if (tree.length == 0) revert MerkleTreeOutOfBoundsAccess();
        result = tree[0];
    }

    /// @dev Returns the number of leaves.
    function numLeaves(bytes32[] memory tree) internal pure returns (uint256) {
        return tree.length - (tree.length >> 1);
    }

    /// @dev Returns the number of internal nodes.
    function numInternalNodes(bytes32[] memory tree) internal pure returns (uint256) {
        return tree.length >> 1;
    }

    /// @dev Returns the leaf at `leafIndex`.
    function leaf(bytes32[] memory tree, uint256 leafIndex) internal pure returns (bytes32 result) {
        uint256 n = tree.length;
        if (leafIndex >= n - (n >> 1)) revert MerkleTreeOutOfBoundsAccess();
        result = tree[n - 1 - leafIndex];
    }

    /// @dev Returns the leaves at `leafIndices`.
    function gatherLeaves(bytes32[] memory tree, uint256[] memory leafIndices)
        internal
        pure
        returns (bytes32[] memory result)
    {
        uint256 n = tree.length;
        uint256 l = leafIndices.length;
        result = new bytes32[](l);
        for (uint256 i; i < l; ++i) {
            uint256 leafIndex = leafIndices[i];
            if (leafIndex >= n - (n >> 1)) revert MerkleTreeOutOfBoundsAccess();
            result[i] = tree[n - 1 - leafIndex];
        }
    }

    /// @dev Returns the proof for the leaf at `leafIndex`.
    function leafProof(bytes32[] memory tree, uint256 leafIndex)
        internal
        pure
        returns (bytes32[] memory result)
    {
        uint256 n = tree.length;
        uint256 nodeIndex = type(uint256).max;
        if (leafIndex < n - (n >> 1)) nodeIndex = n - 1 - leafIndex;
        result = nodeProof(tree, nodeIndex);
    }

    /// @dev Returns the proof for the node at `nodeIndex`.
    /// This function can be used to prove the existence of internal nodes.
    function nodeProof(bytes32[] memory tree, uint256 nodeIndex)
        internal
        pure
        returns (bytes32[] memory result)
    {
        if (nodeIndex >= tree.length) revert MerkleTreeOutOfBoundsAccess();
        uint256 depth;
        for (uint256 i = nodeIndex; i != 0; i = (i - 1) >> 1) {
            ++depth;
        }
        result = new bytes32[](depth);
        uint256 o;
        // Each sibling on the way up: the next node for an odd one, the previous for an even.
        for (uint256 i = nodeIndex; i != 0; i = (i - 1) >> 1) {
            result[o] = tree[(i & 1) == 0 ? i - 1 : i + 1];
            ++o;
        }
    }

    /// @dev Returns proof and corresponding flags for multiple leaves.
    /// The `leafIndices` must be non-empty and sorted in strictly ascending order.
    function multiProofForLeaves(bytes32[] memory tree, uint256[] memory leafIndices)
        internal
        pure
        returns (bytes32[] memory proof, bool[] memory flags)
    {
        uint256 c = leafIndices.length;
        if (c == 0) revert MerkleTreeInvalidLeafIndices();
        uint256 n = tree.length;
        uint256 l = n - (n >> 1); // Num leaves.
        uint256 p;
        for (uint256 i; i < c; ++i) {
            uint256 j = leafIndices[i]; // Leaf index.
            if (j >= l) revert MerkleTreeOutOfBoundsAccess();
            if (i != 0 && j <= p) revert MerkleTreeInvalidLeafIndices();
            p = j;
        }
        uint256[] memory q = new uint256[](c); // Circular buffer.
        (uint256 flagsLen, uint256 proofLen) = _gen(leafIndices, tree, q, proof, flags, false);
        proof = new bytes32[](proofLen);
        flags = new bool[](flagsLen);
        _gen(leafIndices, tree, q, proof, flags, true);
    }

    /// @dev Returns a copy of leaves, with the length padded to a power of 2.
    function pad(bytes32[] memory leaves, bytes32 defaultFill)
        internal
        pure
        returns (bytes32[] memory result)
    {
        uint256 l = leaves.length;
        if (l == 0) revert MerkleTreeLeavesEmpty();
        // If `p > 2**32 - 1`, revert with empty.
        if (l - 1 >= 0xffffffff) revert();
        uint256 p = l - 1;
        p = (p >> 1) | p;
        p = (p >> 2) | p;
        p = (p >> 4) | p;
        p = (p >> 8) | p;
        p = ((p >> 16) | p) + 1; // Supports up to `2**32 - 1`.
        result = new bytes32[](p);
        for (uint256 i; i < l; ++i) {
            result[i] = leaves[i];
        }
        for (uint256 i = l; i < p; ++i) {
            result[i] = defaultFill;
        }
    }

    /// @dev Equivalent to `pad(leaves, bytes32(0))`.
    function pad(bytes32[] memory leaves) internal pure returns (bytes32[] memory result) {
        result = pad(leaves, bytes32(0));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PRIVATE HELPERS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The hash of `a` and `b`, the smaller first.
    /// @custom:solar-inline
    function _hashPair(bytes32 a, bytes32 b) private pure returns (bytes32) {
        if (b < a) (a, b) = (b, a);
        return keccak256(abi.encode(a, b));
    }

    /// @dev The assembly's `gen`: runs the circular buffer `q` of node indices, from the
    /// leaves' up to the root, and counts the flags and the proof elements, which with
    /// `fill` it writes into `proof` and `flags`. A node takes its sibling from the queue
    /// when it is next, with the flag true, and from `tree` otherwise.
    /// @custom:solar-inline
    function _gen(
        uint256[] memory leafIndices,
        bytes32[] memory tree,
        uint256[] memory q,
        bytes32[] memory proof,
        bool[] memory flags,
        bool fill
    ) private pure returns (uint256 flagsLen, uint256 proofLen) {
        uint256 c = q.length; // Capacity of circular buffer.
        uint256 n = tree.length; // Num nodes.
        for (uint256 i; i < c; ++i) {
            q[i] = n - 1 - leafIndices[i];
        }
        uint256 b; // Start index of circular buffer.
        uint256 e = c; // End index of circular buffer.
        while (b < e) {
            uint256 j = q[b % c]; // Current.
            if (j == 0) break;
            ++b;
            uint256 s = (j & 1) == 0 ? j - 1 : j + 1; // Sibling.
            ++flagsLen;
            bool f = b < e && q[b % c] == s;
            if (f) ++b;
            else ++proofLen;
            if (fill) {
                flags[flagsLen - 1] = f;
                if (!f) proof[proofLen - 1] = tree[s];
            }
            q[e % c] = (j - 1) >> 1;
            ++e;
        }
    }
}
