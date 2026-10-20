// SPDX-License-Identifier: MIT
pragma solidity ^0.8.5;

/// @notice Library for interacting with ERC6551 accounts.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/accounts/LibERC6551.sol)
/// @author ERC6551 team (https://github.com/erc6551/reference/blob/main/src/lib/ERC6551AccountLib.sol)
///
/// The checked port writes the account's creation code with `abi.encodePacked`, hashes it with
/// `keccak256` and derives the account's CREATE2 address from the hash. Solidity can only copy a
/// whole account's code, so the trusted `_codeWord` reads one word of it through the scratch
/// space and the trusted `_codeCopyInto` copies the footer into a buffer it checks it fits, both
/// with zeros past the end of the code as the assembly reads it. `createAccount` calls the
/// registry with the trusted `_callBounded`, which copies at most the one word of the answer the
/// assembly reads. Addresses come back with their upper 96 bits clear, where the assembly can
/// return a whole word.
/// @custom:solar-safe memory arithmetic
library LibERC6551 {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Failed to create a ERC6551 account via the registry.
    error AccountCreationFailed();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The canonical ERC6551 registry address for EVM chains.
    address internal constant REGISTRY = 0x000000006551c19487814612e58FE06813775758;

    /// @dev The canonical ERC6551 registry bytecode for EVM chains.
    /// Useful for forge tests:
    /// `vm.etch(REGISTRY, REGISTRY_BYTECODE)`.
    bytes internal constant REGISTRY_BYTECODE =
        hex"608060405234801561001057600080fd5b50600436106100365760003560e01c8063246a00211461003b5780638a54c52f1461006a575b600080fd5b61004e6100493660046101b7565b61007d565b6040516001600160a01b03909116815260200160405180910390f35b61004e6100783660046101b7565b6100e1565b600060806024608c376e5af43d82803e903d91602b57fd5bf3606c5285605d52733d60ad80600a3d3981f3363d3d373d3d3d363d7360495260ff60005360b76055206035523060601b60015284601552605560002060601b60601c60005260206000f35b600060806024608c376e5af43d82803e903d91602b57fd5bf3606c5285605d52733d60ad80600a3d3981f3363d3d373d3d3d363d7360495260ff60005360b76055206035523060601b600152846015526055600020803b61018b578560b760556000f580610157576320188a596000526004601cfd5b80606c52508284887f79f19b3655ee38b1ce526556b7731a20c8f218fbda4a3990b6cc4172fdf887226060606ca46020606cf35b8060601b60601c60005260206000f35b80356001600160a01b03811681146101b257600080fd5b919050565b600080600080600060a086880312156101cf57600080fd5b6101d88661019b565b945060208601359350604086013592506101f46060870161019b565b94979396509194608001359291505056fea2646970667358221220ea2fe53af507453c64dd7c1db05549fa47a298dfb825d6d11e1689856135f16764736f6c63430008110033";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                ACCOUNT BYTECODE OPERATIONS                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns the initialization code of the ERC6551 account.
    function initCode(
        address implementation_,
        bytes32 salt_,
        uint256 chainId_,
        address tokenContract_,
        uint256 tokenId_
    ) internal pure returns (bytes memory result) {
        result = abi.encodePacked(
            hex"3d60ad80600a3d3981f3363d3d373d3d3d363d73",
            implementation_,
            hex"5af43d82803e903d91602b57fd5bf3",
            salt_,
            chainId_,
            uint256(uint160(tokenContract_)),
            tokenId_
        );
    }

    /// @dev Returns the initialization code hash of the ERC6551 account.
    function initCodeHash(
        address implementation_,
        bytes32 salt_,
        uint256 chainId_,
        address tokenContract_,
        uint256 tokenId_
    ) internal pure returns (bytes32 result) {
        result = keccak256(
            abi.encodePacked(
                hex"3d60ad80600a3d3981f3363d3d373d3d3d363d73",
                implementation_,
                hex"5af43d82803e903d91602b57fd5bf3",
                salt_,
                chainId_,
                uint256(uint160(tokenContract_)),
                tokenId_
            )
        );
    }

    /// @dev Creates an account via the ERC6551 registry.
    function createAccount(
        address implementation_,
        bytes32 salt_,
        uint256 chainId_,
        address tokenContract_,
        uint256 tokenId_
    ) internal returns (address result) {
        // `createAccount(address,bytes32,uint256,address,uint256)`.
        (bool success, bytes memory answer, uint256 answerSize) = _callBounded(
            REGISTRY,
            0,
            gasleft(),
            abi.encodeWithSelector(
                0x8a54c52f, implementation_, salt_, chainId_, tokenContract_, tokenId_
            ),
            0x20
        );
        if (!success || answerSize < 0x20) revert AccountCreationFailed();
        result = address(uint160(uint256(bytes32(answer))));
    }

    /// @dev Returns the address of the ERC6551 account.
    function account(
        address implementation_,
        bytes32 salt_,
        uint256 chainId_,
        address tokenContract_,
        uint256 tokenId_
    ) internal pure returns (address result) {
        result = _create2Address(
            salt_, initCodeHash(implementation_, salt_, chainId_, tokenContract_, tokenId_)
        );
    }

    /// @dev Returns if `a` is an ERC6551 account with `expectedImplementation`.
    function isERC6551Account(address a, address expectedImplementation)
        internal
        view
        returns (bool result)
    {
        // The account's code is 173 bytes: 10 bytes, the implementation, 15 bytes, then the salt,
        // chain ID, token contract and token ID words, which its creation code is built from.
        address implementation_ = implementation(a);
        if (
            implementation_.code.length == 0 || a.code.length != 0xad
                || implementation_ != expectedImplementation
        ) return false;
        bytes memory footer = _codeRead(a, 0x2d, 0x80);
        bytes32 hash = keccak256(
            abi.encodePacked(
                hex"3d60ad80600a3d3981f3363d3d373d3d3d363d73",
                implementation_,
                hex"5af43d82803e903d91602b57fd5bf3",
                footer
            )
        );
        result = a == _create2Address(bytes32(footer), hash);
    }

    /// @dev Returns the implementation of the ERC6551 account `a`.
    function implementation(address a) internal view returns (address result) {
        result = address(bytes20(_codeWord(a, 0x0a)));
    }

    /// @dev Returns the static variables of the ERC6551 account `a`.
    function context(address a)
        internal
        view
        returns (bytes32 salt_, uint256 chainId_, address tokenContract_, uint256 tokenId_)
    {
        uint256 tokenContractWord;
        (salt_, chainId_, tokenContractWord, tokenId_) =
            abi.decode(_codeRead(a, 0x2d, 0x80), (bytes32, uint256, uint256, uint256));
        tokenContract_ = address(uint160(tokenContractWord));
    }

    /// @dev Returns the salt of the ERC6551 account `a`.
    function salt(address a) internal view returns (bytes32 result) {
        result = _codeWord(a, 0x2d);
    }

    /// @dev Returns the chain ID of the ERC6551 account `a`.
    function chainId(address a) internal view returns (uint256 result) {
        result = uint256(_codeWord(a, 0x4d));
    }

    /// @dev Returns the token contract of the ERC6551 account `a`.
    function tokenContract(address a) internal view returns (address result) {
        result = address(uint160(uint256(_codeWord(a, 0x6d))));
    }

    /// @dev Returns the token ID of the ERC6551 account `a`.
    function tokenId(address a) internal view returns (uint256 result) {
        result = uint256(_codeWord(a, 0x8d));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PRIVATE HELPERS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The address the registry's CREATE2 deployment with `salt_` and creation code hashing
    /// to `hash` gets.
    function _create2Address(bytes32 salt_, bytes32 hash) private pure returns (address) {
        return
            address(
                uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), REGISTRY, salt_, hash))))
            );
    }

    /// @dev The `count` bytes of `a`'s code from `start`, as a new buffer.
    function _codeRead(address a, uint256 start, uint256 count)
        private
        view
        returns (bytes memory out)
    {
        out = new bytes(count);
        _codeCopyInto(out, 0, a, start, count);
    }

    /// @dev Copies `count` bytes of `target`'s code from `start` into `dst` at `dstOffset`, with
    /// zeros for the bytes past the end of the code. Solidity can only copy a whole account's code.
    /// @custom:solar-trusted
    function _codeCopyInto(
        bytes memory dst,
        uint256 dstOffset,
        address target,
        uint256 start,
        uint256 count
    ) private view {
        if (count > dst.length || dstOffset > dst.length - count) {
            count = _outOfBounds();
        }
        /// @solidity memory-safe-assembly
        assembly {
            extcodecopy(target, add(add(dst, 0x20), dstOffset), start, count)
        }
    }

    /// @dev The 32 bytes of `a`'s code from `start`, with zeros past the end of the code, read
    /// through the scratch space. Solidity can only copy a whole account's code.
    /// @custom:solar-trusted
    function _codeWord(address a, uint256 start) private view returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            extcodecopy(a, 0x00, start, 0x20)
            result := mload(0x00)
        }
    }

    /// @dev Calls `target` with `payload`, `value` wei and `gasLimit` gas, and
    /// copies at most `maxCopy` bytes of the response into a new buffer sized to
    /// what it holds, allocated after the call. `totalSize` is how many bytes
    /// there were.
    /// @custom:solar-trusted
    function _callBounded(
        address target,
        uint256 value,
        uint256 gasLimit,
        bytes memory payload,
        uint256 maxCopy
    ) private returns (bool success, bytes memory output, uint256 totalSize) {
        /// @solidity memory-safe-assembly
        assembly {
            success := call(gasLimit, target, value, add(payload, 0x20), mload(payload), 0x00, 0x00)
            totalSize := returndatasize()
            let copied := totalSize
            if gt(copied, maxCopy) { copied := maxCopy }
            output := mload(0x40)
            mstore(output, copied)
            returndatacopy(add(output, 0x20), 0x00, copied)
            mstore(0x40, and(add(add(output, 0x3f), copied), not(0x1f)))
        }
    }

    /// @dev Raises the `Panic(0x32)` an out-of-range index raises, which is the
    /// portable spelling of a failed range check.
    function _outOfBounds() private pure returns (uint256) {
        return new uint256[](0)[0];
    }
}
