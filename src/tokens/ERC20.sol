// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Checked Solidity implementation of the pinned Solady ERC20 + EIP-2612 API.
/// @dev Every operation keeps the assembly's order of checks, custom errors and
/// events: `transferFrom` spends the allowance before it moves the balance, and
/// neither it nor `transfer` goes through the overridable `_spendAllowance` or
/// `_transfer`, as the assembly inlines them. Permit2's allowance is fixed at
/// infinity while `_givePermit2InfiniteAllowance` returns true.
///
/// Two deliberate differences from the assembly:
/// - State lives in ordinary Solidity variables: the total supply, then the
///   balance, allowance and nonce mappings, from slot 0. The assembly keeps
///   them at hashed slots of its own, so this token is not storage-compatible
///   with a deployed Solady ERC20, and an inheriting contract's own variables
///   start after these four slots. A mapping hashes a 64-byte key where the
///   assembly hashes a packed one, which costs 12 gas per balance slot and 42
///   per allowance slot.
/// - A recipient's balance, the supply a burn lowers and a nonce are updated
///   with checked arithmetic. Only an override that breaks the invariant that
///   balances sum to the total supply can make one wrap, which panics here
///   where the assembly wraps.
abstract contract ERC20 {
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

    /// @dev Emitted when `amount` tokens is transferred from `from` to `to`.
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @dev Emitted when `amount` tokens is approved by `owner` to be used by `spender`.
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /// @dev The amount of tokens in existence.
    uint256 private _totalSupply;

    /// @dev The amount of tokens each account owns.
    mapping(address => uint256) private _balances;

    /// @dev What each spender may still transfer of each owner's tokens.
    mapping(address => mapping(address => uint256)) private _allowances;

    /// @dev The next EIP-2612 permit nonce of each owner.
    mapping(address => uint256) private _nonces;

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

    /// @dev Returns the name of the token.
    function name() public view virtual returns (string memory);

    /// @dev Returns the symbol of the token.
    function symbol() public view virtual returns (string memory);

    /// @dev Returns the decimals places of the token.
    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    /// @dev Returns the amount of tokens in existence.
    function totalSupply() public view virtual returns (uint256 result) {
        return _totalSupply;
    }

    /// @dev Returns the amount of tokens owned by `owner`.
    function balanceOf(address owner) public view virtual returns (uint256 result) {
        return _balances[owner];
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
        return _allowances[owner][spender];
    }

    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    ///
    /// Emits a {Approval} event.
    function approve(address spender, uint256 amount) public virtual returns (bool) {
        _setAllowance(msg.sender, spender, amount);
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
        if (!_givePermit2InfiniteAllowance() || msg.sender != _PERMIT2) {
            _spend(from, msg.sender, amount);
        }
        _move(from, to, amount);
        _afterTokenTransfer(from, to, amount);
        return true;
    }

    /// @dev For more performance, override to return the constant value
    /// of `keccak256(bytes(name()))` if `name()` will never change.
    function _constantNameHash() internal view virtual returns (bytes32 result) {}

    /// @dev If you need a different value, override this function.
    function _versionHash() internal view virtual returns (bytes32 result) {
        result = _DEFAULT_VERSION_HASH;
    }

    /// @dev For inheriting contracts to increment the nonce.
    function _incrementNonce(address owner) internal virtual {
        _nonces[owner] += 1;
    }

    /// @dev Returns the current nonce for `owner`.
    /// This value is used to compute the signature for EIP-2612 permit.
    function nonces(address owner) public view virtual returns (uint256 result) {
        return _nonces[owner];
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
            if (spender == _PERMIT2 && value != type(uint256).max) {
                revert Permit2AllowanceIsFixedAtInfinity();
            }
        }
        bytes32 nameHash = _constantNameHash();
        //  We simply calculate it on-the-fly to allow for cases where the `name` may change.
        if (nameHash == bytes32(0)) nameHash = keccak256(bytes(name()));
        bytes32 versionHash = _versionHash();
        if (block.timestamp > deadline) revert PermitExpired();
        uint256 nonce = _nonces[owner];
        bytes32 digest = keccak256(
            abi.encodePacked(
                hex"1901",
                keccak256(
                    abi.encode(_DOMAIN_TYPEHASH, nameHash, versionHash, block.chainid, address(this))
                ),
                keccak256(abi.encode(_PERMIT_TYPEHASH, owner, spender, value, nonce, deadline))
            )
        );
        address recovered = ecrecover(digest, v, r, s);
        if (recovered == address(0) || recovered != owner) revert InvalidPermit();
        _nonces[owner] = nonce + 1;
        _allowances[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    /// @dev Returns the EIP-712 domain separator for the EIP-2612 permit.
    function DOMAIN_SEPARATOR() public view virtual returns (bytes32 result) {
        bytes32 nameHash = _constantNameHash();
        //  We simply calculate it on-the-fly to allow for cases where the `name` may change.
        if (nameHash == bytes32(0)) nameHash = keccak256(bytes(name()));
        return keccak256(
            abi.encode(_DOMAIN_TYPEHASH, nameHash, _versionHash(), block.chainid, address(this))
        );
    }

    /// @dev Mints `amount` tokens to `to`, increasing the total supply.
    ///
    /// Emits a {Transfer} event.
    function _mint(address to, uint256 amount) internal virtual {
        _beforeTokenTransfer(address(0), to, amount);
        uint256 supply = _totalSupply;
        if (amount > type(uint256).max - supply) revert TotalSupplyOverflow();
        _totalSupply = supply + amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
        _afterTokenTransfer(address(0), to, amount);
    }

    /// @dev Burns `amount` tokens from `from`, reducing the total supply.
    ///
    /// Emits a {Transfer} event.
    function _burn(address from, uint256 amount) internal virtual {
        _beforeTokenTransfer(from, address(0), amount);
        uint256 balance = _balances[from];
        if (amount > balance) revert InsufficientBalance();
        _balances[from] = balance - amount;
        _totalSupply -= amount;
        emit Transfer(from, address(0), amount);
        _afterTokenTransfer(from, address(0), amount);
    }

    /// @dev Moves `amount` of tokens from `from` to `to`.
    function _transfer(address from, address to, uint256 amount) internal virtual {
        _beforeTokenTransfer(from, to, amount);
        _move(from, to, amount);
        _afterTokenTransfer(from, to, amount);
    }

    /// @dev Updates the allowance of `owner` for `spender` based on spent `amount`.
    function _spendAllowance(address owner, address spender, uint256 amount) internal virtual {
        if (_givePermit2InfiniteAllowance()) {
            if (spender == _PERMIT2) return; // Do nothing, as allowance is infinite.
        }
        _spend(owner, spender, amount);
    }

    /// @dev Sets `amount` as the allowance of `spender` over the tokens of `owner`.
    ///
    /// Emits a {Approval} event.
    function _approve(address owner, address spender, uint256 amount) internal virtual {
        _setAllowance(owner, spender, amount);
    }

    /// @dev Hook that is called before any transfer of tokens.
    /// This includes minting and burning.
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual {}

    /// @dev Hook that is called after any transfer of tokens.
    /// This includes minting and burning.
    function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual {}

    /// @dev Returns whether to fix the Permit2 contract's allowance at infinity.
    ///
    /// This value should be kept constant after contract initialization,
    /// or else the actual allowance values may not match with the {Approval} events.
    /// For best performance, return a compile-time constant for zero-cost abstraction.
    function _givePermit2InfiniteAllowance() internal view virtual returns (bool) {
        return true;
    }

    /// @dev Moves `amount` from `from` to `to`, which may be the same account:
    /// the credit reads the balance the debit left.
    function _move(address from, address to, uint256 amount) private {
        uint256 balance = _balances[from];
        if (amount > balance) revert InsufficientBalance();
        _balances[from] = balance - amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    /// @dev Spends `amount` of `owner`'s allowance for `spender`, unless it is infinite.
    function _spend(address owner, address spender, uint256 amount) private {
        uint256 allowed = _allowances[owner][spender];
        if (allowed != type(uint256).max) {
            if (amount > allowed) revert InsufficientAllowance();
            _allowances[owner][spender] = allowed - amount;
        }
    }

    /// @dev Sets `amount` as `spender`'s allowance over `owner`'s tokens, which
    /// for Permit2 can only be infinite.
    function _setAllowance(address owner, address spender, uint256 amount) private {
        if (_givePermit2InfiniteAllowance()) {
            if (spender == _PERMIT2 && amount != type(uint256).max) {
                revert Permit2AllowanceIsFixedAtInfinity();
            }
        }
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
}
