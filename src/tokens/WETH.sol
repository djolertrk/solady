// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "./ERC20.sol";

/// @notice Simple Wrapped Ether implementation.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/tokens/WETH.sol)
/// @author Solmate (https://github.com/transmissions11/solmate/blob/main/src/tokens/WETH.sol)
/// @author Inspired by WETH9 (https://github.com/dapphub/ds-weth/blob/master/src/weth9.sol)
/// @dev The checked port sends withdrawn ETH with a plain call, which forwards all
/// the gas and ignores what the recipient returns, as the assembly does.
/// @custom:solar-safe memory arithmetic
contract WETH is ERC20 {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The ETH transfer has failed.
    error ETHTransferFailed();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ERC20 METADATA                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns the name of the token.
    function name() public view virtual override returns (string memory) {
        return "Wrapped Ether";
    }

    /// @dev Returns the symbol of the token.
    function symbol() public view virtual override returns (string memory) {
        return "WETH";
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                            WETH                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Deposits `amount` ETH of the caller and mints `amount` WETH to the caller.
    function deposit() public payable virtual {
        _mint(msg.sender, msg.value);
    }

    /// @dev Burns `amount` WETH of the caller and sends `amount` ETH to the caller.
    function withdraw(uint256 amount) public virtual {
        _burn(msg.sender, amount);
        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) revert ETHTransferFailed();
    }

    /// @dev Equivalent to `deposit()`.
    receive() external payable virtual {
        deposit();
    }
}
