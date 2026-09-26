// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Checked Solidity implementation of the pinned Solady MerkleProofLib API.
/// @dev A proof is folded one sibling at a time, hashing the smaller word of
/// each pair first, as the assembly orders the two words in scratch space.
///
/// A multiproof rebuilds the root through a queue that starts with the leaves
/// and grows by one hash per flag; each hash takes its second input from the
/// queue or from the proof, as its flag says. The assembly reads its queue and
/// its proof without bounds, and its final check that every proof element was
/// used turns any read past either into `false`. This port returns `false` as
/// soon as a read would pass the written queue or the proof, which gives the
/// same result without reading memory nothing wrote. The queue is a new array,
/// where the assembly uses free memory without reserving it.
///
/// Two deliberate differences from the assembly: a calldata flag is read as a
/// `bool`, so a flag word other than zero or one reverts where the assembly
/// treats it as true, and `emptyProof`, `emptyLeaves` and `emptyFlags` are left
/// out, since no Solidity expression is an empty calldata array.
library MerkleProofLib {
    /// @dev Returns whether `leaf` exists in the Merkle tree with `root`, given `proof`.
    function verify(bytes32[] memory proof, bytes32 root, bytes32 leaf)
        internal
        pure
        returns (bool isValid)
    {
        for (uint256 i; i < proof.length; ++i) {
            bytes32 a = leaf;
            bytes32 b = proof[i];
            if (a > b) (a, b) = (b, a);
            leaf = keccak256(abi.encode(a, b));
        }
        return leaf == root;
    }

    /// @dev Returns whether `leaf` exists in the Merkle tree with `root`, given `proof`.
    function verifyCalldata(bytes32[] calldata proof, bytes32 root, bytes32 leaf)
        internal
        pure
        returns (bool isValid)
    {
        for (uint256 i; i < proof.length; ++i) {
            bytes32 a = leaf;
            bytes32 b = proof[i];
            if (a > b) (a, b) = (b, a);
            leaf = keccak256(abi.encode(a, b));
        }
        return leaf == root;
    }

    /// @dev Returns whether all `leaves` exist in the Merkle tree with `root`,
    /// given `proof` and `flags`.
    ///
    /// Note:
    /// - Breaking the invariant `flags.length == (leaves.length - 1) + proof.length`
    ///   will always return false.
    /// - Any non-zero word in the `flags` array is treated as true.
    function verifyMultiProof(
        bytes32[] memory proof,
        bytes32 root,
        bytes32[] memory leaves,
        bool[] memory flags
    ) internal pure returns (bool isValid) {
        if (leaves.length + proof.length != flags.length + 1) return false;
        if (flags.length == 0) return (proof.length == 1 ? proof[0] : leaves[0]) == root;
        bytes32[] memory hashes = new bytes32[](leaves.length + flags.length);
        for (uint256 i; i < leaves.length; ++i) {
            hashes[i] = leaves[i];
        }
        (bool complete, bytes32 computed) = _rebuild(hashes, leaves.length, proof, flags);
        return complete && computed == root;
    }

    /// @dev Returns whether all `leaves` exist in the Merkle tree with `root`,
    /// given `proof` and `flags`.
    ///
    /// Note:
    /// - Breaking the invariant `flags.length == (leaves.length - 1) + proof.length`
    ///   will always return false.
    /// - A flag word other than zero or one reverts.
    function verifyMultiProofCalldata(
        bytes32[] calldata proof,
        bytes32 root,
        bytes32[] calldata leaves,
        bool[] calldata flags
    ) internal pure returns (bool isValid) {
        if (leaves.length + proof.length != flags.length + 1) return false;
        if (flags.length == 0) return (proof.length == 1 ? proof[0] : leaves[0]) == root;
        bytes32[] memory hashes = new bytes32[](leaves.length + flags.length);
        for (uint256 i; i < leaves.length; ++i) {
            hashes[i] = leaves[i];
        }
        (bool complete, bytes32 computed) = _rebuildCalldata(hashes, leaves.length, proof, flags);
        return complete && computed == root;
    }

    /// @dev Runs the queue whose first `back` entries `hashes` holds, one hash
    /// per flag, and returns the last hash and whether every read stayed in the
    /// written queue and the proof, and every proof element was used.
    function _rebuild(
        bytes32[] memory hashes,
        uint256 back,
        bytes32[] memory proof,
        bool[] memory flags
    ) private pure returns (bool complete, bytes32 computed) {
        uint256 front;
        uint256 used;
        for (uint256 i; i < flags.length; ++i) {
            if (front == back) return (false, 0);
            bytes32 a = hashes[front++];
            bytes32 b;
            if (flags[i]) {
                if (front == back) return (false, 0);
                b = hashes[front++];
            } else {
                if (used == proof.length) return (false, 0);
                b = proof[used++];
            }
            if (a > b) (a, b) = (b, a);
            hashes[back++] = keccak256(abi.encode(a, b));
        }
        return (used == proof.length, hashes[back - 1]);
    }

    /// @dev `_rebuild` for a proof and flags in calldata.
    function _rebuildCalldata(
        bytes32[] memory hashes,
        uint256 back,
        bytes32[] calldata proof,
        bool[] calldata flags
    ) private pure returns (bool complete, bytes32 computed) {
        uint256 front;
        uint256 used;
        for (uint256 i; i < flags.length; ++i) {
            if (front == back) return (false, 0);
            bytes32 a = hashes[front++];
            bytes32 b;
            if (flags[i]) {
                if (front == back) return (false, 0);
                b = hashes[front++];
            } else {
                if (used == proof.length) return (false, 0);
                b = proof[used++];
            }
            if (a > b) (a, b) = (b, a);
            hashes[back++] = keccak256(abi.encode(a, b));
        }
        return (used == proof.length, hashes[back - 1]);
    }
}
