// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @notice Relay proxy for upgradeable ERC6551 accounts.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/accounts/ERC6551Proxy.sol)
/// @author ERC6551 team (https://github.com/erc6551/reference/blob/main/src/examples/upgradeable/ERC6551AccountProxy.sol)
///
/// @dev Note: This relay proxy is required for upgradeable ERC6551 accounts.
///
/// ERC6551 clone -> ERC6551Proxy (relay) -> ERC6551 account implementation.
///
/// This relay proxy also allows for correctly revealing the
/// "Read as Proxy" and "Write as Proxy" tabs on Etherscan.
///
/// After using the registry to deploy a ERC6551 clone pointing to this relay proxy,
/// users must send 0 ETH to the clone before clicking on "Is this a proxy?" on Etherscan.
/// Verification of this relay proxy on Etherscan is optional.
///
/// The checked port delegates with Solidity's `delegatecall` of `msg.data`, then returns or
/// reverts with the implementation's return data through trusted helpers, since a fallback
/// that declares no return value cannot end the call with raw data in Solidity. Trusted
/// helpers also read and write the ERC-1967 implementation slot, which Solidity cannot name.
/// @custom:solar-safe memory arithmetic
contract ERC6551Proxy {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         IMMUTABLES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The default implementation.
    bytes32 internal immutable _defaultImplementation;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The ERC-1967 storage slot for the implementation in the proxy.
    /// `uint256(keccak256("eip1967.proxy.implementation")) - 1`.
    bytes32 internal constant _ERC1967_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    constructor(address defaultImplementation) payable {
        _defaultImplementation = bytes32(uint256(uint160(defaultImplementation)));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          FALLBACK                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    fallback() external payable virtual {
        bytes32 implementation = _erc6551ProxySload(_ERC1967_IMPLEMENTATION_SLOT);
        if (implementation == bytes32(0)) {
            implementation = _defaultImplementation;
            // Only initialize if the calldatasize is zero, so that staticcalls to
            // functions (which will have 4-byte function selectors) won't revert.
            // Some users may be fine without Etherscan proxy detection and thus may
            // choose to not initialize the ERC1967 implementation slot.
            if (msg.data.length == 0) {
                _erc6551ProxySstore(_ERC1967_IMPLEMENTATION_SLOT, implementation);
            }
        }
        (bool success,) = address(uint160(uint256(implementation))).delegatecall(msg.data);
        if (!success) _erc6551ProxyRevertReturndata();
        _erc6551ProxyReturnReturndata();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PRIVATE HELPERS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The word in storage slot `slot`. Solidity cannot name a slot it did not allocate.
    /// @custom:solar-trusted
    function _erc6551ProxySload(bytes32 slot) private view returns (bytes32 value) {
        /// @solidity memory-safe-assembly
        assembly {
            value := sload(slot)
        }
    }

    /// @dev Stores `value` in storage slot `slot`.
    /// @custom:solar-trusted
    function _erc6551ProxySstore(bytes32 slot, bytes32 value) private {
        /// @solidity memory-safe-assembly
        assembly {
            sstore(slot, value)
        }
    }

    /// @dev Ends the call, returning the last call's return data. Solidity returns data only
    /// from a function that declares it.
    /// @custom:solar-trusted
    function _erc6551ProxyReturnReturndata() private pure {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            returndatacopy(m, 0x00, returndatasize())
            return(m, returndatasize())
        }
    }

    /// @dev Reverts with the last call's return data, which Solidity holds only as a copy.
    /// @custom:solar-trusted
    function _erc6551ProxyRevertReturndata() private pure {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            returndatacopy(m, 0x00, returndatasize())
            revert(m, returndatasize())
        }
    }
}
