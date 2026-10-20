// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @notice Simple ERC20 + EIP-2612 implementation.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/tokens/ERC20.sol)
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC20.sol)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol)
///
/// @dev Note:
/// - The ERC20 standard allows minting and transferring to and from the zero address,
///   minting and transferring zero tokens, as well as self-approvals.
///   For performance, this implementation WILL NOT revert for such actions.
///   Please add any checks with overrides if desired.
/// - The `permit` function uses the ecrecover precompile (0x1).
///
/// If you are overriding:
/// - NEVER violate the ERC20 invariant:
///   the total sum of all balances must be equal to `totalSupply()`.
/// - Check that the overridden function is actually used in the function you want to
///   change the behavior of. Much of the code has been manually inlined for performance.
///
/// The checked port keeps upstream's storage slots and words, so it is storage-compatible
/// with it: the total supply at its fixed slot, and the balance, allowance and nonce slots
/// hashed from the packed seeds, read and written through the trusted `_sload` and `_sstore`.
/// Every operation keeps the assembly's order of checks, custom errors and events:
/// `transferFrom` spends the allowance before it moves the balance, and neither it nor
/// `transfer` goes through the overridable `_spendAllowance` or `_transfer`, as the assembly
/// inlines them. A credit and a nonce add with wrap-around through the trusted `_add`, and a
/// burn lowers the total supply through the trusted `_sub`, as the assembly does; only an
/// override that breaks the invariant above can make them wrap. One deliberate difference:
/// `permit` recovers through the `ecrecover` builtin, which reverts if the precompile call
/// itself fails, where the assembly reverts with `InvalidPermit()`.
/// @custom:solar-safe memory arithmetic
abstract contract ERC20 {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The total supply has overflowed.
    error TotalSupplyOverflow();

    /// @dev The allowance has overflowed.
    error AllowanceOverflow();

    /// @dev The allowance has underflowed.
    error AllowanceUnderflow();

    /// @dev Insufficient balance.
    error InsufficientBalance();

    /// @dev Insufficient allowance.
    error InsufficientAllowance();

    /// @dev The permit is invalid.
    error InvalidPermit();

    /// @dev The permit has expired.
    error PermitExpired();

    /// @dev The allowance of Permit2 is fixed at infinity.
    error Permit2AllowanceIsFixedAtInfinity();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Emitted when `amount` tokens is transferred from `from` to `to`.
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @dev Emitted when `amount` tokens is approved by `owner` to be used by `spender`.
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /// @dev `keccak256(bytes("Transfer(address,address,uint256)"))`.
    uint256 private constant _TRANSFER_EVENT_SIGNATURE =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;

    /// @dev `keccak256(bytes("Approval(address,address,uint256)"))`.
    uint256 private constant _APPROVAL_EVENT_SIGNATURE =
        0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The storage slot for the total supply.
    uint256 private constant _TOTAL_SUPPLY_SLOT = 0x05345cdf77eb68f44c;

    /// @dev The balance slot of `owner` is given by:
    /// ```
    ///     mstore(0x0c, _BALANCE_SLOT_SEED)
    ///     mstore(0x00, owner)
    ///     let balanceSlot := keccak256(0x0c, 0x20)
    /// ```
    uint256 private constant _BALANCE_SLOT_SEED = 0x87a211a2;

    /// @dev The allowance slot of (`owner`, `spender`) is given by:
    /// ```
    ///     mstore(0x20, spender)
    ///     mstore(0x0c, _ALLOWANCE_SLOT_SEED)
    ///     mstore(0x00, owner)
    ///     let allowanceSlot := keccak256(0x0c, 0x34)
    /// ```
    uint256 private constant _ALLOWANCE_SLOT_SEED = 0x7f5e9f20;

    /// @dev The nonce slot of `owner` is given by:
    /// ```
    ///     mstore(0x0c, _NONCES_SLOT_SEED)
    ///     mstore(0x00, owner)
    ///     let nonceSlot := keccak256(0x0c, 0x20)
    /// ```
    uint256 private constant _NONCES_SLOT_SEED = 0x38377508;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev `(_NONCES_SLOT_SEED << 16) | 0x1901`.
    uint256 private constant _NONCES_SLOT_SEED_WITH_SIGNATURE_PREFIX = 0x383775081901;

    /// @dev `keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")`.
    bytes32 private constant _DOMAIN_TYPEHASH =
        0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    /// @dev `keccak256("1")`.
    /// If you need to use a different version, override `_versionHash`.
    bytes32 private constant _DEFAULT_VERSION_HASH =
        0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6;

    /// @dev `keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")`.
    bytes32 private constant _PERMIT_TYPEHASH =
        0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    /// @dev The canonical Permit2 address.
    /// For signature-based allowance granting for single transaction ERC20 `transferFrom`.
    /// Enabled by default. To disable, override `_givePermit2InfiniteAllowance()`.
    /// [Github](https://github.com/Uniswap/permit2)
    /// [Etherscan](https://etherscan.io/address/0x000000000022D473030F116dDEE9F6B43aC78BA3)
    address internal constant _PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ERC20 METADATA                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns the name of the token.
    function name() public view virtual returns (string memory);

    /// @dev Returns the symbol of the token.
    function symbol() public view virtual returns (string memory);

    /// @dev Returns the decimals places of the token.
    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERC20                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns the amount of tokens in existence.
    function totalSupply() public view virtual returns (uint256 result) {
        result = _sload(_TOTAL_SUPPLY_SLOT);
    }

    /// @dev Returns the amount of tokens owned by `owner`.
    function balanceOf(address owner) public view virtual returns (uint256 result) {
        result = _sload(_balanceSlot(owner));
    }

    /// @dev Returns the amount of tokens that `spender` can spend on behalf of `owner`.
    function allowance(address owner, address spender)
        public
        view
        virtual
        returns (uint256 result)
    {
        if (_givePermit2InfiniteAllowance()) {
            if (spender == _PERMIT2) return type(uint256).max;
        }
        result = _sload(_allowanceSlot(owner, spender));
    }

    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    ///
    /// Emits a {Approval} event.
    function approve(address spender, uint256 amount) public virtual returns (bool) {
        if (_givePermit2InfiniteAllowance()) {
            // If `spender == _PERMIT2 && amount != type(uint256).max`.
            if (spender == _PERMIT2 && amount != type(uint256).max) {
                revert Permit2AllowanceIsFixedAtInfinity();
            }
        }
        // Compute the allowance slot and store the amount.
        _sstore(_allowanceSlot(msg.sender, spender), amount);
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @dev Transfer `amount` tokens from the caller to `to`.
    ///
    /// Requirements:
    /// - `from` must at least have `amount`.
    ///
    /// Emits a {Transfer} event.
    function transfer(address to, uint256 amount) public virtual returns (bool) {
        _beforeTokenTransfer(msg.sender, to, amount);
        _move(msg.sender, to, amount);
        emit Transfer(msg.sender, to, amount);
        _afterTokenTransfer(msg.sender, to, amount);
        return true;
    }

    /// @dev Transfers `amount` tokens from `from` to `to`.
    ///
    /// Note: Does not update the allowance if it is the maximum uint256 value.
    ///
    /// Requirements:
    /// - `from` must at least have `amount`.
    /// - The caller must have at least `amount` of allowance to transfer the tokens of `from`.
    ///
    /// Emits a {Transfer} event.
    function transferFrom(address from, address to, uint256 amount) public virtual returns (bool) {
        _beforeTokenTransfer(from, to, amount);
        // Permit2's allowance is infinite while it is fixed.
        if (!_givePermit2InfiniteAllowance() || msg.sender != _PERMIT2) {
            _use(from, msg.sender, amount);
        }
        _move(from, to, amount);
        emit Transfer(from, to, amount);
        _afterTokenTransfer(from, to, amount);
        return true;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          EIP-2612                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev For more performance, override to return the constant value
    /// of `keccak256(bytes(name()))` if `name()` will never change.
    function _constantNameHash() internal view virtual returns (bytes32 result) {}

    /// @dev If you need a different value, override this function.
    function _versionHash() internal view virtual returns (bytes32 result) {
        result = _DEFAULT_VERSION_HASH;
    }

    /// @dev For inheriting contracts to increment the nonce.
    function _incrementNonce(address owner) internal virtual {
        uint256 nonceSlot = _nonceSlot(owner);
        _sstore(nonceSlot, _add(1, _sload(nonceSlot)));
    }

    /// @dev Returns the current nonce for `owner`.
    /// This value is used to compute the signature for EIP-2612 permit.
    function nonces(address owner) public view virtual returns (uint256 result) {
        // Compute the nonce slot and load its value.
        result = _sload(_nonceSlot(owner));
    }

    /// @dev Sets `value` as the allowance of `spender` over the tokens of `owner`,
    /// authorized by a signed approval by `owner`.
    ///
    /// Emits a {Approval} event.
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        if (_givePermit2InfiniteAllowance()) {
            // If `spender == _PERMIT2 && value != type(uint256).max`.
            if (spender == _PERMIT2 && value != type(uint256).max) {
                revert Permit2AllowanceIsFixedAtInfinity();
            }
        }
        bytes32 nameHash = _constantNameHash();
        //  We simply calculate it on-the-fly to allow for cases where the `name` may change.
        if (nameHash == bytes32(0)) nameHash = keccak256(bytes(name()));
        bytes32 versionHash = _versionHash();
        // Revert if the block timestamp is greater than `deadline`.
        if (block.timestamp > deadline) revert PermitExpired();
        // Compute the nonce slot and load its value.
        uint256 nonceSlot = _nonceSlot(owner);
        uint256 nonceValue = _sload(nonceSlot);
        bytes32 domainSeparator = keccak256(
            abi.encode(_DOMAIN_TYPEHASH, nameHash, versionHash, block.chainid, address(this))
        );
        bytes32 structHash =
            keccak256(abi.encode(_PERMIT_TYPEHASH, owner, spender, value, nonceValue, deadline));
        address recovered =
            ecrecover(keccak256(abi.encodePacked(hex"1901", domainSeparator, structHash)), v, r, s);
        // A failed recovery gives zero, which no signer recovers to.
        if (recovered == address(0) || recovered != owner) revert InvalidPermit();
        // Increment and store the updated nonce.
        _sstore(nonceSlot, _add(nonceValue, 1));
        // Compute the allowance slot and store the value.
        _sstore(_allowanceSlot(owner, spender), value);
        emit Approval(owner, spender, value);
    }

    /// @dev Returns the EIP-712 domain separator for the EIP-2612 permit.
    function DOMAIN_SEPARATOR() public view virtual returns (bytes32 result) {
        bytes32 nameHash = _constantNameHash();
        //  We simply calculate it on-the-fly to allow for cases where the `name` may change.
        if (nameHash == bytes32(0)) nameHash = keccak256(bytes(name()));
        bytes32 versionHash = _versionHash();
        result = keccak256(
            abi.encode(_DOMAIN_TYPEHASH, nameHash, versionHash, block.chainid, address(this))
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  INTERNAL MINT FUNCTIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Mints `amount` tokens to `to`, increasing the total supply.
    ///
    /// Emits a {Transfer} event.
    function _mint(address to, uint256 amount) internal virtual {
        _beforeTokenTransfer(address(0), to, amount);
        uint256 totalSupplyBefore = _sload(_TOTAL_SUPPLY_SLOT);
        uint256 totalSupplyAfter = _add(totalSupplyBefore, amount);
        // Revert if the total supply overflows.
        if (totalSupplyAfter < totalSupplyBefore) revert TotalSupplyOverflow();
        // Store the updated total supply.
        _sstore(_TOTAL_SUPPLY_SLOT, totalSupplyAfter);
        // Compute the balance slot, then add and store the updated balance.
        uint256 toBalanceSlot = _balanceSlot(to);
        _sstore(toBalanceSlot, _add(_sload(toBalanceSlot), amount));
        emit Transfer(address(0), to, amount);
        _afterTokenTransfer(address(0), to, amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  INTERNAL BURN FUNCTIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Burns `amount` tokens from `from`, reducing the total supply.
    ///
    /// Emits a {Transfer} event.
    function _burn(address from, uint256 amount) internal virtual {
        _beforeTokenTransfer(from, address(0), amount);
        // Compute the balance slot and load its value.
        uint256 fromBalanceSlot = _balanceSlot(from);
        uint256 fromBalance = _sload(fromBalanceSlot);
        // Revert if insufficient balance.
        if (amount > fromBalance) revert InsufficientBalance();
        // Subtract and store the updated balance.
        _sstore(fromBalanceSlot, fromBalance - amount);
        // Subtract and store the updated total supply.
        _sstore(_TOTAL_SUPPLY_SLOT, _sub(_sload(_TOTAL_SUPPLY_SLOT), amount));
        emit Transfer(from, address(0), amount);
        _afterTokenTransfer(from, address(0), amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                INTERNAL TRANSFER FUNCTIONS                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Moves `amount` of tokens from `from` to `to`.
    function _transfer(address from, address to, uint256 amount) internal virtual {
        _beforeTokenTransfer(from, to, amount);
        _move(from, to, amount);
        emit Transfer(from, to, amount);
        _afterTokenTransfer(from, to, amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                INTERNAL ALLOWANCE FUNCTIONS                */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Updates the allowance of `owner` for `spender` based on spent `amount`.
    function _spendAllowance(address owner, address spender, uint256 amount) internal virtual {
        if (_givePermit2InfiniteAllowance()) {
            if (spender == _PERMIT2) return; // Do nothing, as allowance is infinite.
        }
        _use(owner, spender, amount);
    }

    /// @dev Sets `amount` as the allowance of `spender` over the tokens of `owner`.
    ///
    /// Emits a {Approval} event.
    function _approve(address owner, address spender, uint256 amount) internal virtual {
        if (_givePermit2InfiniteAllowance()) {
            // If `spender == _PERMIT2 && amount != type(uint256).max`.
            if (spender == _PERMIT2 && amount != type(uint256).max) {
                revert Permit2AllowanceIsFixedAtInfinity();
            }
        }
        // Compute the allowance slot and store the amount.
        _sstore(_allowanceSlot(owner, spender), amount);
        emit Approval(owner, spender, amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     HOOKS TO OVERRIDE                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Hook that is called before any transfer of tokens.
    /// This includes minting and burning.
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual {}

    /// @dev Hook that is called after any transfer of tokens.
    /// This includes minting and burning.
    function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual {}

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          PERMIT2                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns whether to fix the Permit2 contract's allowance at infinity.
    ///
    /// This value should be kept constant after contract initialization,
    /// or else the actual allowance values may not match with the {Approval} events.
    /// For best performance, return a compile-time constant for zero-cost abstraction.
    function _givePermit2InfiniteAllowance() internal view virtual returns (bool) {
        return true;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PRIVATE HELPERS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Moves `amount` from the balance of `from` to that of `to`, as `transfer`,
    /// `transferFrom` and `_transfer` do.
    function _move(address from, address to, uint256 amount) private {
        // Compute the balance slot and load its value.
        uint256 fromBalanceSlot = _balanceSlot(from);
        uint256 fromBalance = _sload(fromBalanceSlot);
        // Revert if insufficient balance.
        if (amount > fromBalance) revert InsufficientBalance();
        // Subtract and store the updated balance.
        _sstore(fromBalanceSlot, fromBalance - amount);
        // Compute the balance slot of `to`, then add and store its updated balance.
        // Will not overflow because the sum of all user balances
        // cannot exceed the maximum uint256 value.
        uint256 toBalanceSlot = _balanceSlot(to);
        _sstore(toBalanceSlot, _add(_sload(toBalanceSlot), amount));
    }

    /// @dev Spends `amount` of the allowance of `spender` over the tokens of `owner`, as
    /// `transferFrom` and `_spendAllowance` do. A maximal allowance is never spent.
    function _use(address owner, address spender, uint256 amount) private {
        // Compute the allowance slot and load its value.
        uint256 allowanceSlot = _allowanceSlot(owner, spender);
        uint256 allowance_ = _sload(allowanceSlot);
        // If the allowance is not the maximum uint256 value.
        if (allowance_ != type(uint256).max) {
            // Revert if the amount to be transferred exceeds the allowance.
            if (amount > allowance_) revert InsufficientAllowance();
            // Subtract and store the updated allowance.
            _sstore(allowanceSlot, allowance_ - amount);
        }
    }

    /// @dev The balance slot of `owner`: the hash of its address over `_BALANCE_SLOT_SEED`.
    function _balanceSlot(address owner) private pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(owner, uint96(_BALANCE_SLOT_SEED))));
    }

    /// @dev The allowance slot of (`owner`, `spender`): the hash of the owner's address over
    /// `_ALLOWANCE_SLOT_SEED`, followed by the spender's address.
    function _allowanceSlot(address owner, address spender) private pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(owner, uint96(_ALLOWANCE_SLOT_SEED), spender)));
    }

    /// @dev The nonce slot of `owner`: the hash of its address over `_NONCES_SLOT_SEED`.
    function _nonceSlot(address owner) private pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(owner, uint96(_NONCES_SLOT_SEED))));
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

    /// @dev `a + b` modulo `2**256`, as the assembly adds.
    /// @custom:solar-trusted
    function _add(uint256 a, uint256 b) private pure returns (uint256 c) {
        unchecked {
            c = a + b;
        }
    }

    /// @dev `a - b` modulo `2**256`, as the assembly subtracts.
    /// @custom:solar-trusted
    function _sub(uint256 a, uint256 b) private pure returns (uint256 c) {
        unchecked {
            c = a - b;
        }
    }
}
