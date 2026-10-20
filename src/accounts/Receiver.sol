// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @notice Receiver mixin for ETH and safe-transferred ERC721 and ERC1155 tokens.
/// @author Solady (https://github.com/Vectorized/solady/blob/main/src/accounts/Receiver.sol)
///
/// @dev Note:
/// - Handles all ERC721 and ERC1155 token safety callbacks.
/// - Collapses function table gas overhead and code size.
/// - Utilizes fallback so unknown calldata will pass on.
///
/// The checked port answers a token callback from the modifier with a trusted helper
/// that returns `msg.sig` as the call's whole return data, since a fallback that
/// declares no return value cannot return one in Solidity.
/// @custom:solar-safe memory arithmetic
abstract contract Receiver {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The function selector is not recognized.
    error FnSelectorNotRecognized();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     RECEIVE / FALLBACK                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev For receiving ETH.
    receive() external payable virtual {}

    /// @dev Fallback function with the `receiverFallback` modifier.
    fallback() external payable virtual receiverFallback {
        revert FnSelectorNotRecognized();
    }

    /// @dev Modifier for the fallback function to handle token callbacks.
    modifier receiverFallback() virtual {
        _beforeReceiverFallbackBody();
        if (_useReceiverFallbackBody()) {
            bytes4 s = msg.sig;
            // 0x150b7a02: `onERC721Received(address,address,uint256,bytes)`.
            // 0xf23a6e61: `onERC1155Received(address,address,uint256,uint256,bytes)`.
            // 0xbc197c81: `onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)`.
            if (s == 0x150b7a02 || s == 0xf23a6e61 || s == 0xbc197c81) {
                _receiverReturnWord(bytes32(s)); // Return `msg.sig`.
            }
        }
        _afterReceiverFallbackBody();
        _;
    }

    /// @dev Whether we want to use the body of the `receiverFallback` modifier.
    function _useReceiverFallbackBody() internal view virtual returns (bool) {
        return true;
    }

    /// @dev Called before the body of the `receiverFallback` modifier.
    function _beforeReceiverFallbackBody() internal virtual {}

    /// @dev Called after the body of the `receiverFallback` modifier.
    function _afterReceiverFallbackBody() internal virtual {}

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PRIVATE HELPERS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Ends the call, returning `word` as its whole return data. Solidity returns
    /// data only from a function that declares it.
    /// @custom:solar-trusted
    function _receiverReturnWord(bytes32 word) private pure {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, word)
            return(0x00, 0x20)
        }
    }
}
