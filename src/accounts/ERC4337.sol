// SPDX-License-Identifier: MIT
pragma solidity ^0.8.5;

import {Receiver} from "./Receiver.sol";
import {LibZip} from "../utils/LibZip.sol";
import {Ownable} from "../auth/Ownable.sol";
import {UUPSUpgradeable} from "../utils/UUPSUpgradeable.sol";
import {SignatureCheckerLib, ERC1271} from "../accounts/ERC1271.sol";

/// @notice Simple ERC4337 account implementation.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/accounts/ERC4337.sol)
/// @author Infinitism (https://github.com/eth-infinitism/account-abstraction/blob/develop/contracts/samples/SimpleAccount.sol)
///
/// @dev Recommended usage:
/// 1. Deploy the ERC4337 as an implementation contract, and verify it on Etherscan.
/// 2. Create a factory that uses `LibClone.deployERC1967` or
///    `LibClone.deployDeterministicERC1967` to clone the implementation.
///    See: `ERC4337Factory.sol`.
///
/// Note:
/// ERC4337 is a very complicated standard with many potential gotchas.
/// Also, it is subject to change and has not been finalized
/// (so accounts are encouraged to be upgradeable).
/// Usually, ERC4337 account implementations are developed by companies with ample funds
/// for security reviews. This implementation is intended to serve as a base reference
/// for smart account developers working in such companies. If you are using this
/// implementation, please do get one or more security reviews before deployment.
///
/// The checked port makes the calls with Solidity's calls, or with trusted calls that copy no
/// more of the answer than the assembly reads, and bubbles a revert with a trusted helper. It
/// reads and writes the raw storage slots with trusted helpers, since Solidity cannot name
/// them. `executeBatch` reads the calls as the assembly does, following their offsets with
/// wrap-around additions and without the checks of Solidity's accessors, which would reject
/// dirty addresses and offsets past the calldata; a trusted helper reads the array's calldata
/// offset, which Solidity cannot. Reads past the calldata give zeros, as `CALLDATALOAD` does;
/// call data that runs past it is copied with the zeros, and a length no gas could copy halts
/// with a trusted `invalid()`, as the copy would run out of gas. The helpers' names carry an
/// `_erc4337` prefix, so that a contract can inherit this alongside other ports.
/// @custom:solar-safe memory arithmetic
abstract contract ERC4337 is Ownable, UUPSUpgradeable, Receiver, ERC1271 {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STRUCTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The packed ERC4337 user operation (userOp) struct.
    struct PackedUserOperation {
        address sender;
        uint256 nonce;
        bytes initCode; // Factory address and `factoryData` (or empty).
        bytes callData;
        bytes32 accountGasLimits; // `verificationGas` (16 bytes) and `callGas` (16 bytes).
        uint256 preVerificationGas;
        bytes32 gasFees; // `maxPriorityFee` (16 bytes) and `maxFeePerGas` (16 bytes).
        bytes paymasterAndData; // Paymaster fields (or empty).
        bytes signature;
    }

    /// @dev Call struct for the `executeBatch` function.
    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Deploys this ERC4337 account implementation and disables initialization (see below).
    constructor() payable {
        _disableERC4337ImplementationInitializer();
    }

    /// @dev Automatically initializes the owner for the implementation. This blocks someone
    /// from initializing the implementation and doing a delegatecall to SELFDESTRUCT.
    /// Proxies to the implementation will still be able to initialize as per normal.
    function _disableERC4337ImplementationInitializer() internal virtual {
        // Note that `Ownable._guardInitializeOwner` has been and must be overridden
        // to return true, to block double-initialization. We'll initialize to `address(1)`,
        // so that it's easier to verify that the implementation has been initialized.
        _initializeOwner(address(1));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        INITIALIZER                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Initializes the account with the owner. Can only be called once.
    function initialize(address newOwner) public payable virtual {
        _initializeOwner(newOwner);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        ENTRY POINT                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns the canonical ERC4337 EntryPoint contract (0.7).
    /// Override this function to return a different EntryPoint.
    function entryPoint() public view virtual returns (address) {
        return 0x0000000071727De22E5E9d8BAf0edAc6f37da032;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   VALIDATION OPERATIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Validates the signature and nonce.
    /// The EntryPoint will make the call to the recipient only if
    /// this validation call returns successfully.
    ///
    /// Signature failure should be reported by returning 1 (see: `_validateSignature`).
    /// This allows making a "simulation call" without a valid signature.
    /// Other failures (e.g. nonce mismatch, or invalid signature format)
    /// should still revert to signal failure.
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    )
        external
        payable
        virtual
        onlyEntryPoint
        payPrefund(missingAccountFunds)
        returns (uint256 validationData)
    {
        validationData = _validateSignature(userOp, userOpHash);
        _validateNonce(userOp.nonce);
    }

    /// @dev Validate `userOp.signature` for the `userOpHash`.
    function _validateSignature(PackedUserOperation calldata userOp, bytes32 userOpHash)
        internal
        virtual
        returns (uint256 validationData)
    {
        bool success = SignatureCheckerLib.isValidSignatureNowCalldata(
            owner(), SignatureCheckerLib.toEthSignedMessageHash(userOpHash), userOp.signature
        );
        // Returns 0 if the recovered address matches the owner.
        // Else returns 1, which is equivalent to:
        // `(success ? 0 : 1) | (uint256(validUntil) << 160) | (uint256(validAfter) << (160 + 48))`
        // where `validUntil` is 0 (indefinite) and `validAfter` is 0.
        validationData = success ? 0 : 1;
    }

    /// @dev Override to validate the nonce of the userOp.
    /// This method may validate the nonce requirement of this account.
    /// e.g.
    /// To limit the nonce to use sequenced userOps only (no "out of order" userOps):
    ///      `require(nonce < type(uint64).max)`
    /// For a hypothetical account that *requires* the nonce to be out-of-order:
    ///      `require(nonce & type(uint64).max == 0)`
    ///
    /// The actual nonce uniqueness is managed by the EntryPoint, and thus no other
    /// action is needed by the account itself.
    function _validateNonce(uint256 nonce) internal virtual {
        nonce = nonce; // Silence unused variable warning.
    }

    /// @dev Sends to the EntryPoint (i.e. `msg.sender`) the missing funds for this transaction.
    /// Subclass MAY override this modifier for better funds management.
    /// (e.g. send to the EntryPoint more than the minimum required, so that in future transactions
    /// it will not be required to send again)
    ///
    /// `missingAccountFunds` is the minimum value this modifier should send the EntryPoint,
    /// which MAY be zero, in case there is enough deposit, or the userOp has a paymaster.
    modifier payPrefund(uint256 missingAccountFunds) virtual {
        _;
        if (missingAccountFunds != 0) {
            // Ignore failure (it's EntryPoint's job to verify, not the account's).
            _erc4337CallBounded(msg.sender, missingAccountFunds, gasleft(), "", 0);
        }
    }

    /// @dev Requires that the caller is the EntryPoint.
    modifier onlyEntryPoint() virtual {
        if (msg.sender != entryPoint()) revert Unauthorized();
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    EXECUTION OPERATIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Execute a call from this account.
    function execute(address target, uint256 value, bytes calldata data)
        public
        payable
        virtual
        onlyEntryPointOrOwner
        returns (bytes memory result)
    {
        bool success;
        (success, result) = target.call{value: value}(data);
        // Bubble up the revert if the call reverts.
        if (!success) _erc4337RevertRaw(result);
    }

    /// @dev Execute a sequence of calls from this account.
    function executeBatch(Call[] calldata calls)
        public
        payable
        virtual
        onlyEntryPointOrOwner
        returns (bytes[] memory results)
    {
        // Each call is `(target, value, data)` at the offset its head word gives from `calls`,
        // read as the assembly reads it, following the offsets unchecked.
        uint256 offset = _erc4337CalldataOffset(calls);
        results = new bytes[](calls.length);
        for (uint256 i; i < calls.length; ++i) {
            uint256 p = offset + (i << 5);
            (uint256 target, uint256 value, uint256 start, uint256 length) =
                _erc4337ReadCall(_erc4337Add(offset, uint256(bytes32(msg.data[p:p + 0x20]))));
            bool success;
            bytes memory result;
            if (start <= msg.data.length && length <= msg.data.length - start) {
                bytes calldata data = msg.data[start:start + length];
                (success, result) = address(uint160(target)).call{value: value}(data);
            } else {
                // The data runs past the calldata, which reads as zeros there.
                bytes memory data = _erc4337CalldataPadded(start, length);
                (success, result) = address(uint160(target)).call{value: value}(data);
            }
            // Bubble up the revert if the call reverts.
            if (!success) _erc4337RevertRaw(result);
            results[i] = result; // Append the returndata into `results`.
        }
    }

    /// @dev Execute a delegatecall with `delegate` on this account.
    function delegateExecute(address delegate, bytes calldata data)
        public
        payable
        virtual
        onlyEntryPointOrOwner
        delegateExecuteGuard
        returns (bytes memory result)
    {
        bool success;
        // Forwards the `data` to `delegate` via delegatecall.
        (success, result) = delegate.delegatecall(data);
        // Bubble up the revert if the call reverts.
        if (!success) _erc4337RevertRaw(result);
    }

    /// @dev Ensures that the owner and implementation slots' values aren't changed.
    /// You can override this modifier to ensure the sanctity of other storage slots too.
    modifier delegateExecuteGuard() virtual {
        bytes32 ownerSlotValue;
        bytes32 implementationSlotValue;
        implementationSlotValue = bytes32(_erc4337Sload(uint256(_ERC1967_IMPLEMENTATION_SLOT)));
        ownerSlotValue = bytes32(_erc4337Sload(uint256(_OWNER_SLOT)));
        _;
        bool kept = implementationSlotValue
            == bytes32(_erc4337Sload(uint256(_ERC1967_IMPLEMENTATION_SLOT)));
        kept = kept && ownerSlotValue == bytes32(_erc4337Sload(uint256(_OWNER_SLOT)));
        if (!kept) revert();
    }

    /// @dev Requires that the caller is the EntryPoint, the owner, or the account itself.
    modifier onlyEntryPointOrOwner() virtual {
        if (msg.sender != entryPoint()) _checkOwner();
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 DIRECT STORAGE OPERATIONS                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns the raw storage value at `storageSlot`.
    function storageLoad(bytes32 storageSlot) public view virtual returns (bytes32 result) {
        result = bytes32(_erc4337Sload(uint256(storageSlot)));
    }

    /// @dev Writes the raw storage value at `storageSlot`.
    function storageStore(bytes32 storageSlot, bytes32 storageValue)
        public
        payable
        virtual
        onlyEntryPointOrOwner
        storageStoreGuard(storageSlot)
    {
        _erc4337Sstore(uint256(storageSlot), uint256(storageValue));
    }

    /// @dev Ensures that the `storageSlot` is prohibited for direct storage writes.
    /// You can override this modifier to ensure the sanctity of other storage slots too.
    modifier storageStoreGuard(bytes32 storageSlot) virtual {
        if (storageSlot == _OWNER_SLOT || storageSlot == _ERC1967_IMPLEMENTATION_SLOT) revert();
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     DEPOSIT OPERATIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns the account's balance on the EntryPoint.
    function getDeposit() public view virtual returns (uint256 result) {
        address ep = entryPoint();
        // `balanceOf(address)`, with the `account` argument.
        bytes memory payload = abi.encodeWithSelector(0x70a08231, address(this));
        (bool success, bytes memory answer, uint256 answerSize) =
            _erc4337StaticCallBounded(ep, gasleft(), payload, 0x20);
        // Returns 0 if the EntryPoint does not exist.
        // At least 32 bytes returned.
        if (success && answerSize > 0x1f) result = abi.decode(answer, (uint256));
    }

    /// @dev Deposit more funds for this account in the EntryPoint.
    function addDeposit() public payable virtual {
        address ep = entryPoint();
        // The EntryPoint has balance accounting logic in the `receive()` function, as defined in ERC-4337.
        (bool success,,) = _erc4337CallBounded(ep, msg.value, gasleft(), "", 0);
        if (!success || ep.code.length == 0) revert(); // For gas estimation.
    }

    /// @dev Withdraw ETH from the account's deposit on the EntryPoint.
    function withdrawDepositTo(address to, uint256 amount) public payable virtual onlyOwner {
        address ep = entryPoint();
        // `withdrawTo(address,uint256)`, with the `to` and `amount` arguments.
        (bool success, bytes memory result) =
            ep.call(abi.encodeWithSelector(0x205c2878, to, amount));
        if (!success || ep.code.length == 0) _erc4337RevertRaw(result);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         OVERRIDES                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Requires that the caller is the owner or the account itself.
    /// This override affects the `onlyOwner` modifier.
    function _checkOwner() internal view virtual override(Ownable) {
        if (msg.sender != owner()) if (msg.sender != address(this)) revert Unauthorized();
    }

    /// @dev To prevent double-initialization (reuses the owner storage slot for efficiency).
    function _guardInitializeOwner() internal pure virtual override(Ownable) returns (bool) {
        return true;
    }

    /// @dev Uses the `owner` as the ERC1271 signer.
    function _erc1271Signer() internal view virtual override(ERC1271) returns (address) {
        return owner();
    }

    /// @dev Allow the entry point to skip the ERC7739 nested typed data workflow.
    /// This is safe as the entry point already includes the smart account in the user op digest.
    function _erc1271CallerIsSafe() internal view virtual override(ERC1271) returns (bool) {
        return msg.sender == entryPoint() || ERC1271._erc1271CallerIsSafe();
    }

    /// @dev To ensure that only the owner or the account itself can upgrade the implementation.
    function _authorizeUpgrade(address) internal virtual override(UUPSUpgradeable) onlyOwner {}

    /// @dev If you don't need to use `LibZip.cdFallback`, override this function to return false.
    function _useLibZipCdFallback() internal view virtual returns (bool) {
        return true;
    }

    /// @dev Handle token callbacks. If no token callback is triggered,
    /// use `LibZip.cdFallback` for generalized calldata decompression.
    fallback() external payable virtual override(Receiver) receiverFallback {
        if (_useLibZipCdFallback()) {
            // Reverts with out-of-gas by recursing infinitely if the first 4 bytes
            // of the decompressed `msg.data` doesn't match any function selector.
            LibZip.cdFallback();
        } else {
            revert FnSelectorNotRecognized();
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PRIVATE HELPERS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The word of calldata at `offset`, zero-padded past the end of the calldata, as
    /// `CALLDATALOAD` reads it.
    function _erc4337CalldataWord(uint256 offset) private pure returns (bytes32) {
        uint256 n = msg.data.length;
        if (offset >= n) return bytes32(0);
        if (n - offset < 0x20) return bytes32(msg.data[offset:]);
        return bytes32(msg.data[offset:offset + 0x20]);
    }

    /// @dev `a + b` modulo `2**256`, as the assembly adds calldata offsets. Solidity's
    /// addition reverts where this wraps around.
    /// @custom:solar-trusted
    function _erc4337Add(uint256 a, uint256 b) private pure returns (uint256 c) {
        unchecked {
            c = a + b;
        }
    }

    /// @dev The target, value, data offset and data length of the call whose head is at `e`.
    function _erc4337ReadCall(uint256 e)
        private
        pure
        returns (uint256 target, uint256 value, uint256 start, uint256 length)
    {
        uint256 n = msg.data.length;
        uint256 o;
        if (n >= 0x60 && e <= n - 0x60) {
            (target, value, o) = abi.decode(msg.data[e:e + 0x60], (uint256, uint256, uint256));
        } else {
            target = uint256(_erc4337CalldataWord(e));
            value = uint256(_erc4337CalldataWord(_erc4337Add(e, 0x20)));
            o = uint256(_erc4337CalldataWord(_erc4337Add(e, 0x40)));
        }
        o = _erc4337Add(e, o);
        if (n >= 0x20 && o <= n - 0x20) length = uint256(bytes32(msg.data[o:o + 0x20]));
        else length = uint256(_erc4337CalldataWord(o));
        start = _erc4337Add(o, 0x20);
    }

    /// @dev The `length` bytes of calldata at `start`, which run past its end, zero-padded as
    /// `CALLDATACOPY` pads them. A length no gas could copy halts, as the copy would.
    function _erc4337CalldataPadded(uint256 start, uint256 length)
        private
        pure
        returns (bytes memory)
    {
        if (length >> 63 != 0) _erc4337Invalid();
        uint256 n = msg.data.length;
        if (start >= n) return new bytes(length);
        return bytes.concat(msg.data[start:], new bytes(length - (n - start)));
    }

    /// @dev The word in storage slot `slot`. Solidity cannot name a slot it did not allocate.
    /// @custom:solar-trusted
    function _erc4337Sload(uint256 slot) private view returns (uint256 value) {
        /// @solidity memory-safe-assembly
        assembly {
            value := sload(slot)
        }
    }

    /// @dev Stores `value` in storage slot `slot`.
    /// @custom:solar-trusted
    function _erc4337Sstore(uint256 slot, uint256 value) private {
        /// @solidity memory-safe-assembly
        assembly {
            sstore(slot, value)
        }
    }

    /// @dev The calldata offset of `calls`. Solidity cannot read a calldata array's offset.
    /// @custom:solar-trusted
    function _erc4337CalldataOffset(Call[] calldata calls) private pure returns (uint256 offset) {
        /// @solidity memory-safe-assembly
        assembly {
            offset := calls.offset
        }
    }

    /// @dev Calls `target` with `payload`, `value` wei and `gasLimit` gas, and copies at most
    /// `maxCopy` bytes of the response into a new buffer sized to what it holds, allocated
    /// after the call. `totalSize` is how many bytes there were.
    /// @custom:solar-trusted
    function _erc4337CallBounded(
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

    /// @dev Static-calls `target` with `payload` and `gasLimit` gas, and copies at most
    /// `maxCopy` bytes of the response into a new buffer, as `_erc4337CallBounded` does.
    /// @custom:solar-trusted
    function _erc4337StaticCallBounded(
        address target,
        uint256 gasLimit,
        bytes memory payload,
        uint256 maxCopy
    ) private view returns (bool success, bytes memory output, uint256 totalSize) {
        /// @solidity memory-safe-assembly
        assembly {
            success := staticcall(gasLimit, target, add(payload, 0x20), mload(payload), 0x00, 0x00)
            totalSize := returndatasize()
            let copied := totalSize
            if gt(copied, maxCopy) { copied := maxCopy }
            output := mload(0x40)
            mstore(output, copied)
            returndatacopy(add(output, 0x20), 0x00, copied)
            mstore(0x40, and(add(add(output, 0x3f), copied), not(0x1f)))
        }
    }

    /// @dev Reverts the current call with exactly `data`.
    /// @custom:solar-trusted
    function _erc4337RevertRaw(bytes memory data) private pure {
        /// @solidity memory-safe-assembly
        assembly {
            revert(add(data, 0x20), mload(data))
        }
    }

    /// @dev Halts with the designated invalid instruction, which consumes all the gas left, as
    /// running out of gas does. Solidity cannot spell it: its failures revert.
    /// @custom:solar-trusted
    function _erc4337Invalid() private pure {
        /// @solidity memory-safe-assembly
        assembly {
            invalid()
        }
    }
}
