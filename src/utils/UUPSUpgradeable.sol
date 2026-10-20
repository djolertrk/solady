// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {CallContextChecker} from "./CallContextChecker.sol";

/// @notice UUPS proxy mixin.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/UUPSUpgradeable.sol)
/// @author Modified from OpenZeppelin
/// (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/proxy/utils/UUPSUpgradeable.sol)
///
/// @dev Note:
/// - This implementation is intended to be used with ERC1967 proxies.
/// See: `LibClone.deployERC1967` and related functions.
/// - This implementation is NOT compatible with legacy OpenZeppelin proxies
/// which do not store the implementation at `_ERC1967_IMPLEMENTATION_SLOT`.
///
/// The checked port checks `proxiableUUID` with a trusted static call that copies at most
/// one word of the answer, as the assembly reads it, stores the implementation with a trusted
/// helper, since Solidity cannot name the ERC-1967 slot, and bubbles a failed delegatecall's
/// revert data with a trusted helper; the event is an ordinary emit. The helpers' names carry
/// a `_uupsUpgradeable` prefix, so that a contract can inherit this alongside other ports.
/// @custom:solar-safe memory arithmetic
abstract contract UUPSUpgradeable is CallContextChecker {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The upgrade failed.
    error UpgradeFailed();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Emitted when the proxy's implementation is upgraded.
    event Upgraded(address indexed implementation);

    /// @dev `keccak256(bytes("Upgraded(address)"))`.
    uint256 private constant _UPGRADED_EVENT_SIGNATURE =
        0xbc7cd75a20ee27fd9adebab32041f755214dbc6bffa90cc0225b39da2e5c2d3b;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The ERC-1967 storage slot for the implementation in the proxy.
    /// `uint256(keccak256("eip1967.proxy.implementation")) - 1`.
    bytes32 internal constant _ERC1967_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      UUPS OPERATIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Please override this function to check if `msg.sender` is authorized
    /// to upgrade the proxy to `newImplementation`, reverting if not.
    /// ```
    ///     function _authorizeUpgrade(address) internal override onlyOwner {}
    /// ```
    function _authorizeUpgrade(address newImplementation) internal virtual;

    /// @dev Returns the storage slot used by the implementation,
    /// as specified in [ERC1822](https://eips.ethereum.org/EIPS/eip-1822).
    ///
    /// Note: The `notDelegated` modifier prevents accidental upgrades to
    /// an implementation that is a proxy contract.
    function proxiableUUID() public view virtual notDelegated returns (bytes32) {
        // This function must always return `_ERC1967_IMPLEMENTATION_SLOT` to comply with ERC1967.
        return _ERC1967_IMPLEMENTATION_SLOT;
    }

    /// @dev Upgrades the proxy's implementation to `newImplementation`.
    /// Emits a {Upgraded} event.
    ///
    /// Note: Passing in empty `data` skips the delegatecall to `newImplementation`.
    function upgradeToAndCall(address newImplementation, bytes calldata data)
        public
        payable
        virtual
        onlyProxy
    {
        _authorizeUpgrade(newImplementation);
        // Check if `newImplementation` implements `proxiableUUID` correctly.
        // A failed call or an answer shorter than a word never matches the slot.
        bytes memory payload = abi.encodeWithSelector(0x52d1902d); // `proxiableUUID()`.
        (bool success, bytes memory answer, uint256 answerSize) =
            _uupsUpgradeableStaticCallBounded(newImplementation, gasleft(), payload, 0x20);
        if (
            !success || answerSize < 0x20
                || abi.decode(answer, (bytes32)) != _ERC1967_IMPLEMENTATION_SLOT
        ) revert UpgradeFailed();
        // Emit the {Upgraded} event.
        emit Upgraded(newImplementation);
        // Updates the implementation.
        _uupsUpgradeableSstore(
            uint256(_ERC1967_IMPLEMENTATION_SLOT), uint256(uint160(newImplementation))
        );

        // Perform a delegatecall to `newImplementation` if `data` is non-empty.
        if (data.length != 0) {
            // Forwards the `data` to `newImplementation` via delegatecall.
            bytes memory result;
            (success, result) = newImplementation.delegatecall(data);
            // Bubble up the revert if the call reverts.
            if (!success) _uupsUpgradeableRevertRaw(result);
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PRIVATE HELPERS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Stores `value` in storage slot `slot`. Solidity cannot name a slot it did not
    /// allocate.
    /// @custom:solar-trusted
    function _uupsUpgradeableSstore(uint256 slot, uint256 value) private {
        /// @solidity memory-safe-assembly
        assembly {
            sstore(slot, value)
        }
    }

    /// @dev Static-calls `target` with `payload` and `gasLimit` gas, and copies at most
    /// `maxCopy` bytes of the response into a new buffer sized to what it holds, allocated
    /// after the call. `totalSize` is how many bytes there were.
    /// @custom:solar-trusted
    function _uupsUpgradeableStaticCallBounded(
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
    function _uupsUpgradeableRevertRaw(bytes memory data) private pure {
        /// @solidity memory-safe-assembly
        assembly {
            revert(add(data, 0x20), mload(data))
        }
    }
}
