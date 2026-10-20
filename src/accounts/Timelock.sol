// SPDX-License-Identifier: MIT
pragma solidity ^0.8.5;

import {ERC7821} from "./ERC7821.sol";
import {LibERC7579} from "./LibERC7579.sol";
import {EnumerableRoles} from "../auth/EnumerableRoles.sol";

/// @notice Simple timelock.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/accounts/Timelock.sol)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/governance/TimelockController.sol)
///
/// @dev Note:
/// - This implementation only supports ERC7821 style execution.
/// - This implementation uses EnumerableRoles for better auditability.
/// - This implementation uses custom errors with arguments for easier debugging.
/// - `executionData` can be encoded in three different ways:
///   1. `abi.encode(calls)`.
///   2. `abi.encode(calls, abi.encode(predecessor))`.
///   3. `abi.encode(calls, abi.encode(predecessor, salt))`.
/// - Where `calls` is of type `(address,uint256,bytes)[]`, and
///   `predecessor` is the id of the proposal that is required to be already executed.
/// - If `predecessor` is `bytes32(0)`, it will be ignored (treated as if not required).
/// - The optional `salt` allows for multiple proposals representing the same payload.
/// - The proposal id is given by:
///   `keccak256(abi.encode(mode, keccak256(executionData)))`.
///
/// We recommended including the salt, even though it is optional for convenience.
///
/// Supported modes:
/// - `bytes32(0x01000000000000000000...)`: does not support optional `opData`.
/// - `bytes32(0x01000000000078210001...)`: supports optional `opData`.
/// Where `opData` is `abi.encode(predecessor)` or `abi.encode(predecessor, salt)`,
/// and `...` is the remaining 22 bytes which can be anything.
/// For ease of mind, just use:
/// `0x0100000000007821000100000000000000000000000000000000000000000000`.
///
/// The checked port keeps the minimum delay and the operations in the assembly's slots and
/// words: the negated minimum delay, and for each operation `keccak256` of its id and the 9 bytes
/// of `_TIMELOCK_SLOT`, holding its ready timestamp above its done bit. Solidity cannot name those
/// slots, so trusted helpers read and write them; the events are Solidity's `emit`, which logs
/// the assembly's words. `_bulkSetRole` reads each address as the word it is stored as, through
/// the trusted `_timelockToUints` view of the array, and passes on its low 160 bits, as the
/// assembly does, where Solidity would reject a word with upper bits set. One deliberate
/// difference, inherited from the checked `ERC7821`: `execute` with `executionData` that does
/// not fit itself reverts as it is read, before the role and operation checks the assembly
/// reaches with it; data that `propose` accepted always fits.
/// @custom:solar-safe memory arithmetic
contract Timelock is ERC7821, EnumerableRoles {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Role that can add / remove roles without wait time.
    /// This role cannot directly propose, execute, or cancel.
    /// This role is NOT exempt from the execution wait time.
    uint256 public constant ADMIN_ROLE = 0;

    /// @dev Role that can propose operations.
    uint256 public constant PROPOSER_ROLE = 1;

    /// @dev Role that can execute operations.
    uint256 public constant EXECUTOR_ROLE = 2;

    /// @dev Role that can cancel proposed operations.
    uint256 public constant CANCELLER_ROLE = 3;

    /// @dev The maximum role.
    uint256 public constant MAX_ROLE = 3;

    /// @dev Assign this holder to a role to allow anyone to call
    /// the function guarded by `onlyRoleOrOpenRole`.
    address public constant OPEN_ROLE_HOLDER = 0x0303030303030303030303030303030303030303;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ENUMS                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Represents the state of an operation.
    enum OperationState {
        Unset, // 0.
        Waiting, // 1.
        Ready, // 2.
        Done // 3.
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The proposed operation has insufficient delay.
    error TimelockInsufficientDelay(uint256 delay, uint256 minDelay);

    /// @dev The operation cannot be performed.
    /// The `expectedStates` is a bitmap with the bits enabled for
    /// each enum position, starting from the least significant bit.
    error TimelockInvalidOperation(bytes32 id, uint256 expectedStates);

    /// @dev The operation has a predecessor that has not been executed.
    error TimelockUnexecutedPredecessor(bytes32 predecessor);

    /// @dev Unauthorized to call the function.
    error TimelockUnauthorized();

    /// @dev The delay cannot be greater than `2 ** 254 - 1`.
    error TimelockDelayOverflow();

    /// @dev The timelock has already been initialized.
    error TimelockAlreadyInitialized();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The storage slot for the timelock's minimum delay.
    /// We restrict the `minDelay` to be less than `2 ** 254 - 1`, and store the negation of it.
    /// This allows us to check if it has been initialized via a non-zero check.
    /// Slot of operation `id` is given by:
    /// ```
    ///     mstore(0x09, _TIMELOCK_SLOT)
    ///     mstore(0x00, id)
    ///     let operationIdSlot := keccak256(0x00, 0x29)
    /// ```
    /// Bits layout:
    /// - [0]       `done`.
    /// - [1..255]  `readyTimestamp`.
    uint256 private constant _TIMELOCK_SLOT = 0x477f2812565c76a73f;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         IMMUTABLES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev For guarding `initialize` if not via a delegate call.
    uint256 private immutable __timelockSelf = uint256(uint160(address(this)));

    /// @dev For guarding `initialize` if not via a delegate call.
    uint256 private immutable __timelockDeployer = uint256(uint160(address(msg.sender)));

    /// @dev For guarding `initialize` if not via a delegate call.
    uint256 private immutable __timelockDeployerOrigin = uint256(uint160(address(tx.origin)));

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The proposal `id` has been created.
    event Proposed(bytes32 indexed id, bytes32 mode, bytes executionData, uint256 readyTimestamp);

    /// @dev The proposal `id` has been executed.
    event Executed(bytes32 indexed id, bytes32 mode, bytes executionData);

    /// @dev The proposal `id` has been cancelled.
    event Cancelled(bytes32 indexed id);

    /// @dev The minimum delay has been set to `newMinDelay`.
    event MinDelaySet(uint256 newMinDelay);

    /// @dev `keccak256(bytes("Proposed(bytes32,bytes32,bytes,uint256)"))`.
    uint256 private constant _PROPOSED_EVENT_SIGNATURE =
        0x9b40ebcd599cbeb62eedb5e0c1db0879688a09d169ab92dbed4957d49a44b671;

    /// @dev `keccak256(bytes("Executed(bytes32,bytes32,bytes)"))`.
    uint256 private constant _EXECUTED_EVENT_SIGNATURE =
        0xb1fdd61c3a5405a73ea1f8fb29bfd62c6152241cb59843d3def17bfadb7cb0bf;

    /// @dev `keccak256(bytes("Cancelled(bytes32)"))`.
    uint256 private constant _CANCELLED_EVENT_SIGNATURE =
        0xbaa1eb22f2a492ba1a5fea61b8df4d27c6c8b5f3971e63bb58fa14ff72eedb70;

    /// @dev `keccak256(bytes("MinDelaySet(uint256)"))`.
    uint256 private constant _MIN_DELAY_SET_EVENT_SIGNATURE =
        0x496c64b8781f4ad77f1c285beea54cc413b72276389ad6dd916ea2841395e63d;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        INITIALIZER                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Initializes the timelock contract.
    function initialize(
        uint256 initialMinDelay,
        address initialAdmin,
        address[] calldata proposers,
        address[] calldata executors,
        address[] calldata cancellers
    ) public virtual {
        _initializeTimelockAuthorizationCheck();
        if (initialMinDelay >> 254 != 0) revert TimelockDelayOverflow();
        if (_timelockSload(_TIMELOCK_SLOT) != 0) revert TimelockAlreadyInitialized();
        _timelockSstore(_TIMELOCK_SLOT, ~initialMinDelay);
        emit MinDelaySet(initialMinDelay);
        if (initialAdmin != address(0)) {
            _setRole(initialAdmin, ADMIN_ROLE, true);
        }
        _bulkSetRole(proposers, PROPOSER_ROLE, true);
        _bulkSetRole(executors, EXECUTOR_ROLE, true);
        _bulkSetRole(cancellers, CANCELLER_ROLE, true);
    }

    /// @dev The Timelock is best used via a minimal proxy.
    /// But in case it is not, we want to guard `initialize` from frontrun griefing.
    /// Authorizing both `msg.sender` and `tx.origin` caters to the use case where
    /// the Timelock is being deployed via a factory (e.g. Nicks, CreateX).
    ///
    /// Always call `initialize` as soon as possible after deployment.
    /// In the rare case where `msg.sender` or `tx.origin` are untrusted
    /// and abused to frontrun, `initialize` will revert on reinitialization,
    /// so you will know that the deployment is compromised and must be discarded.
    function _initializeTimelockAuthorizationCheck() internal virtual {
        uint256 self = __timelockSelf;
        uint256 deployer = __timelockDeployer;
        uint256 deployerOrigin = __timelockDeployerOrigin;
        if (self == uint256(uint160(address(this)))) {
            uint256 sender = uint256(uint160(msg.sender));
            if (sender != deployer && sender != deployerOrigin) revert TimelockUnauthorized();
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  PUBLIC UPDATE FUNCTIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Proposes an execute payload (`mode`, `executionData`) with `delay`.
    /// Emits a {Proposed} event.
    function propose(bytes32 mode, bytes calldata executionData, uint256 delay)
        public
        virtual
        onlyRole(PROPOSER_ROLE)
        returns (bytes32 id)
    {
        LibERC7579.decodeBatchAndOpData(executionData); // Check if properly encoded.
        uint256 t = minDelay();
        if (delay >> 254 != 0) revert TimelockDelayOverflow();
        if (delay < t) revert TimelockInsufficientDelay(delay, t);
        id = keccak256(abi.encode(mode, keccak256(executionData)));
        uint256 s = _timelockOperationSlot(id); // Operation slot.
        if (_timelockSload(s) != 0) revert TimelockInvalidOperation(id, 1); // `1 << OperationState.Unset`
        uint256 r = delay + block.timestamp; // `readyTimestamp`.
        _timelockSstore(s, r << 1); // Update the operation in the storage.
        emit Proposed(id, mode, executionData, r);
    }

    /// @dev Cancels the operation with `id`.
    /// Emits a {Cancelled} event.
    function cancel(bytes32 id) public virtual onlyRole(CANCELLER_ROLE) {
        uint256 s = _timelockOperationSlot(id); // Operation slot.
        uint256 p = _timelockSload(s);
        if (p & 1 != 0 || p == 0) {
            // `(1 << OperationState.Waiting) | (1 << OperationState.Ready)`
            revert TimelockInvalidOperation(id, 6);
        }
        _timelockSstore(s, 0); // Clears the operation's storage slot.
        emit Cancelled(id);
    }

    /// @dev Allows the timelock itself to set the minimum delay.
    /// Emits a {MinDelaySet} event.
    function setMinDelay(uint256 newMinDelay) public virtual {
        if (msg.sender != address(this)) revert TimelockUnauthorized();
        if (newMinDelay >> 254 != 0) revert TimelockDelayOverflow();
        _timelockSstore(_TIMELOCK_SLOT, ~newMinDelay);
        emit MinDelaySet(newMinDelay);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   PUBLIC VIEW FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns the minimum delay.
    function minDelay() public view virtual returns (uint256 result) {
        result = ~_timelockSload(_TIMELOCK_SLOT);
    }

    /// @dev Returns the ready timestamp for `id`.
    function readyTimestamp(bytes32 id) public view virtual returns (uint256 result) {
        result = _timelockSload(_timelockOperationSlot(id)) >> 1;
    }

    /// @dev Returns the current operation state of `id`.
    function operationState(bytes32 id) public view virtual returns (OperationState result) {
        uint256 p = _timelockSload(_timelockOperationSlot(id));
        if (p != 0) {
            result = OperationState((p & 1) + 2 - (block.timestamp < p >> 1 ? 1 : 0));
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INTERNAL HELPERS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Helper to set roles in bulk.
    function _bulkSetRole(address[] calldata addresses, uint256 role, bool active)
        internal
        virtual
    {
        uint256[] calldata words = _timelockToUints(addresses);
        for (uint256 i; i != words.length; ++i) {
            _setRole(address(uint160(words[i])), role, active);
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         OVERRIDES                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev For ERC7821.
    /// To ensure that the function can only be called by the proper role holder.
    /// To ensure that the operation is ready to be executed.
    /// Updates the operation state and emits a {Executed} event after the calls.
    function _execute(
        bytes32 mode,
        bytes calldata executionData,
        Call[] calldata calls,
        bytes calldata opData
    ) internal virtual override(ERC7821) {
        if (!hasRole(OPEN_ROLE_HOLDER, EXECUTOR_ROLE)) {
            _checkRole(EXECUTOR_ROLE);
        }
        bytes32 id = keccak256(abi.encode(mode, keccak256(executionData)));
        uint256 s = _timelockOperationSlot(id);
        uint256 p = _timelockSload(s);
        if (p & 1 != 0 || p == 0 || block.timestamp < p >> 1) {
            revert TimelockInvalidOperation(id, 4); // `1 << OperationState.Ready`
        }
        // Check if optional predecessor has been executed.
        if (opData.length >= 0x20) {
            bytes32 b = bytes32(opData[:0x20]); // Predecessor's id.
            if (b != bytes32(0) && _timelockSload(_timelockOperationSlot(b)) & 1 == 0) {
                revert TimelockUnexecutedPredecessor(b);
            }
        }
        _execute(calls, id);
        // Recheck the operation after the calls, in case of reentrancy.
        p = _timelockSload(s);
        if (p & 1 != 0 || p == 0 || block.timestamp < p >> 1) {
            revert TimelockInvalidOperation(id, 4); // `1 << OperationState.Ready`
        }
        emit Executed(id, mode, executionData);
        _timelockSstore(s, p | 1); // Set the operation as executed in the storage.
    }

    /// @dev This guards the public `setRole` function,
    /// such that it can only be called by the timelock itself, or an admin.
    function _authorizeSetRole(address, uint256, bool) internal virtual override(EnumerableRoles) {
        if (msg.sender != address(this)) _checkRole(ADMIN_ROLE);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PRIVATE HELPERS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The slot of operation `id`: `keccak256` of `id` and the 9 bytes of `_TIMELOCK_SLOT`.
    function _timelockOperationSlot(bytes32 id) private pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(id, uint72(_TIMELOCK_SLOT))));
    }

    /// @dev The word in storage slot `slot`. Solidity cannot name a slot it did not allocate.
    /// @custom:solar-trusted
    function _timelockSload(uint256 slot) private view returns (uint256 value) {
        /// @solidity memory-safe-assembly
        assembly {
            value := sload(slot)
        }
    }

    /// @dev Stores `value` in storage slot `slot`.
    /// @custom:solar-trusted
    function _timelockSstore(uint256 slot, uint256 value) private {
        /// @solidity memory-safe-assembly
        assembly {
            sstore(slot, value)
        }
    }

    /// @dev Views `a` as the words its addresses are stored as. Solidity reads an address from
    /// calldata only after checking its upper bits are clear.
    /// @custom:solar-trusted
    function _timelockToUints(address[] calldata a)
        private
        pure
        returns (uint256[] calldata words)
    {
        /// @solidity memory-safe-assembly
        assembly {
            words.offset := a.offset
            words.length := a.length
        }
    }
}
