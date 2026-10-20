// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @notice Simple ERC2981 NFT Royalty Standard implementation.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/tokens/ERC2981.sol)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/common/ERC2981.sol)
///
/// @dev The checked port keeps the royalties in the assembly's slots and words, so it is
/// storage-compatible with it: the default royalty at the seed's slot and a token's at the
/// `abi.encode` hash of its id and the seed. Solidity cannot name those slots, so two
/// trusted helpers read and write a slot; they carry the contract's name, so that it
/// still combines with ERC721. Every check keeps its order and custom error. A royalty
/// whose product overflows reverts with no data, as the assembly's out-of-gas revert
/// does, without using up the remaining gas.
/// @custom:solar-safe memory arithmetic
abstract contract ERC2981 {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The royalty fee numerator exceeds the fee denominator.
    error RoyaltyOverflow();

    /// @dev The royalty receiver cannot be the zero address.
    error RoyaltyReceiverIsZeroAddress();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The default royalty info is given by:
    /// ```
    ///     let packed := sload(_ERC2981_MASTER_SLOT_SEED)
    ///     let receiver := shr(96, packed)
    ///     let royaltyFraction := xor(packed, shl(96, receiver))
    /// ```
    ///
    /// The per token royalty info is given by.
    /// ```
    ///     mstore(0x00, tokenId)
    ///     mstore(0x20, _ERC2981_MASTER_SLOT_SEED)
    ///     let packed := sload(keccak256(0x00, 0x40))
    ///     let receiver := shr(96, packed)
    ///     let royaltyFraction := xor(packed, shl(96, receiver))
    /// ```
    uint256 private constant _ERC2981_MASTER_SLOT_SEED = 0xaa4ec00224afccfdb7;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          ERC2981                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Checks that `_feeDenominator` is non-zero.
    constructor() {
        require(_feeDenominator() != 0, "Fee denominator cannot be zero.");
    }

    /// @dev Returns the denominator for the royalty amount.
    /// Defaults to 10000, which represents fees in basis points.
    /// Override this function to return a custom amount if needed.
    function _feeDenominator() internal pure virtual returns (uint96) {
        return 10000;
    }

    /// @dev Returns true if this contract implements the interface defined by `interfaceId`.
    /// See: https://eips.ethereum.org/EIPS/eip-165
    /// This function call must use less than 30000 gas.
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool result) {
        // ERC165: 0x01ffc9a7, ERC2981: 0x2a55205a.
        result = interfaceId == 0x01ffc9a7 || interfaceId == 0x2a55205a;
    }

    /// @dev Returns the `receiver` and `royaltyAmount` for `tokenId` sold at `salePrice`.
    function royaltyInfo(uint256 tokenId, uint256 salePrice)
        public
        view
        virtual
        returns (address receiver, uint256 royaltyAmount)
    {
        uint256 feeDenominator = _feeDenominator();
        uint256 packed = _erc2981Sload(_erc2981TokenSlot(tokenId));
        receiver = address(uint160(packed >> 96));
        if (receiver == address(0)) {
            packed = _erc2981Sload(_ERC2981_MASTER_SLOT_SEED);
            receiver = address(uint160(packed >> 96));
        }
        uint256 x = salePrice;
        uint256 y = uint96(packed); // `feeNumerator`.
        // Overflow check, equivalent to `require(y == 0 || x <= type(uint256).max / y)`.
        // Should not be triggered in practice, but included for safety. The assembly's
        // out-of-gas revert and this one both return no data.
        if (y != 0 && x > type(uint256).max / y) revert();
        // The assembly's division by a zero denominator gives zero.
        if (feeDenominator != 0) royaltyAmount = x * y / feeDenominator;
    }

    /// @dev Sets the default royalty `receiver` and `feeNumerator`.
    ///
    /// Requirements:
    /// - `receiver` must not be the zero address.
    /// - `feeNumerator` must not be greater than the fee denominator.
    function _setDefaultRoyalty(address receiver, uint96 feeNumerator) internal virtual {
        uint256 feeDenominator = _feeDenominator();
        if (feeNumerator > feeDenominator) revert RoyaltyOverflow();
        if (receiver == address(0)) revert RoyaltyReceiverIsZeroAddress();
        _erc2981Sstore(
            _ERC2981_MASTER_SLOT_SEED, uint256(uint160(receiver)) << 96 | uint256(feeNumerator)
        );
    }

    /// @dev Sets the default royalty `receiver` and `feeNumerator` to zero.
    function _deleteDefaultRoyalty() internal virtual {
        _erc2981Sstore(_ERC2981_MASTER_SLOT_SEED, 0);
    }

    /// @dev Sets the royalty `receiver` and `feeNumerator` for `tokenId`.
    ///
    /// Requirements:
    /// - `receiver` must not be the zero address.
    /// - `feeNumerator` must not be greater than the fee denominator.
    function _setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator)
        internal
        virtual
    {
        uint256 feeDenominator = _feeDenominator();
        if (feeNumerator > feeDenominator) revert RoyaltyOverflow();
        if (receiver == address(0)) revert RoyaltyReceiverIsZeroAddress();
        _erc2981Sstore(
            _erc2981TokenSlot(tokenId), uint256(uint160(receiver)) << 96 | uint256(feeNumerator)
        );
    }

    /// @dev Sets the royalty `receiver` and `feeNumerator` for `tokenId` to zero.
    function _resetTokenRoyalty(uint256 tokenId) internal virtual {
        _erc2981Sstore(_erc2981TokenSlot(tokenId), 0);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PRIVATE HELPERS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The royalty slot of `tokenId`.
    /// @custom:solar-inline
    function _erc2981TokenSlot(uint256 tokenId) private pure returns (uint256) {
        return uint256(keccak256(abi.encode(tokenId, _ERC2981_MASTER_SLOT_SEED)));
    }

    /// @dev Returns the word in storage slot `slot`. Solidity cannot name a slot it did not
    /// allocate.
    /// @custom:solar-trusted
    function _erc2981Sload(uint256 slot) private view returns (uint256 value) {
        /// @solidity memory-safe-assembly
        assembly {
            value := sload(slot)
        }
    }

    /// @dev Stores `value` in storage slot `slot`. Solidity cannot name a slot it did not
    /// allocate.
    /// @custom:solar-trusted
    function _erc2981Sstore(uint256 slot, uint256 value) private {
        /// @solidity memory-safe-assembly
        assembly {
            sstore(slot, value)
        }
    }
}
