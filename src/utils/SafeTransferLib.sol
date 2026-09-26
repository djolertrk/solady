// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Bytes} from "solar:core/v1/Bytes.sol";
import {Calls} from "solar:core/v1/Calls.sol";

/// @notice Checked Solidity implementation of part of the pinned Solady
/// SafeTransferLib API: ETH transfers, ERC20 transfers and approvals, and the
/// balance and supply queries.
/// @dev A token's answer is read with `Calls.callBounded`, at most one word of
/// it, so a token cannot make the caller copy more. A transfer or approval
/// succeeds when the call does and the token answers `true`, or answers
/// nothing and has code, as upstream decides it. The force transfers, the ETH
/// mover and the Permit2 helpers are not ported.
library SafeTransferLib {
    /// @dev The ETH transfer has failed.
    error ETHTransferFailed();

    /// @dev The ERC20 `transferFrom` has failed.
    error TransferFromFailed();

    /// @dev The ERC20 `transfer` has failed.
    error TransferFailed();

    /// @dev The ERC20 `approve` has failed.
    error ApproveFailed();

    /// @dev The ERC20 `totalSupply` query has failed.
    error TotalSupplyQueryFailed();

    /// @dev Suggested gas stipend for contract receiving ETH that disallows any storage writes.
    uint256 internal constant GAS_STIPEND_NO_STORAGE_WRITES = 2300;

    /// @dev Suggested gas stipend for contract receiving ETH to perform a few
    /// storage reads and writes, but low enough to prevent griefing.
    uint256 internal constant GAS_STIPEND_NO_GRIEF = 100000;

    /// @dev Sends `amount` (in wei) ETH to `to`.
    function safeTransferETH(address to, uint256 amount) internal {
        if (!_sendETH(to, amount, gasleft())) revert ETHTransferFailed();
    }

    /// @dev Sends all the ETH in the current contract to `to`.
    function safeTransferAllETH(address to) internal {
        if (!_sendETH(to, address(this).balance, gasleft())) revert ETHTransferFailed();
    }

    /// @dev Sends `amount` (in wei) ETH to `to`, with a `gasStipend`.
    function trySafeTransferETH(address to, uint256 amount, uint256 gasStipend)
        internal
        returns (bool success)
    {
        return _sendETH(to, amount, gasStipend);
    }

    /// @dev Sends all the ETH in the current contract to `to`, with a `gasStipend`.
    function trySafeTransferAllETH(address to, uint256 gasStipend) internal returns (bool success) {
        return _sendETH(to, address(this).balance, gasStipend);
    }

    /// @dev Sends `amount` of ERC20 `token` from `from` to `to`.
    /// Reverts upon failure.
    ///
    /// The `from` account must have at least `amount` approved for
    /// the current contract to manage.
    function safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        if (!trySafeTransferFrom(token, from, to, amount)) revert TransferFromFailed();
    }

    /// @dev Sends `amount` of ERC20 `token` from `from` to `to`.
    ///
    /// The `from` account must have at least `amount` approved for the current contract to manage.
    function trySafeTransferFrom(address token, address from, address to, uint256 amount)
        internal
        returns (bool success)
    {
        return _accepted(token, abi.encodeWithSelector(0x23b872dd, from, to, amount));
    }

    /// @dev Sends all of ERC20 `token` from `from` to `to`.
    /// Reverts upon failure.
    ///
    /// The `from` account must have their entire balance approved for the current contract to manage.
    function safeTransferAllFrom(address token, address from, address to)
        internal
        returns (uint256 amount)
    {
        bool implemented;
        (implemented, amount) = checkBalanceOf(token, from);
        if (!implemented) revert TransferFromFailed();
        safeTransferFrom(token, from, to, amount);
    }

    /// @dev Sends `amount` of ERC20 `token` from the current contract to `to`.
    /// Reverts upon failure.
    function safeTransfer(address token, address to, uint256 amount) internal {
        if (!_accepted(token, abi.encodeWithSelector(0xa9059cbb, to, amount))) {
            revert TransferFailed();
        }
    }

    /// @dev Sends all of ERC20 `token` from the current contract to `to`.
    /// Reverts upon failure.
    function safeTransferAll(address token, address to) internal returns (uint256 amount) {
        bool implemented;
        (implemented, amount) = checkBalanceOf(token, address(this));
        if (!implemented) revert TransferFailed();
        safeTransfer(token, to, amount);
    }

    /// @dev Sets `amount` of ERC20 `token` for `to` to manage on behalf of the current contract.
    /// Reverts upon failure.
    function safeApprove(address token, address to, uint256 amount) internal {
        if (!_accepted(token, abi.encodeWithSelector(0x095ea7b3, to, amount))) {
            revert ApproveFailed();
        }
    }

    /// @dev Sets `amount` of ERC20 `token` for `to` to manage on behalf of the current contract.
    /// If the initial attempt to approve fails, attempts to reset the approved amount to zero,
    /// then retries the approval again (some tokens, e.g. USDT, requires this).
    /// Reverts upon failure.
    function safeApproveWithRetry(address token, address to, uint256 amount) internal {
        if (_accepted(token, abi.encodeWithSelector(0x095ea7b3, to, amount))) return;
        // The reset's answer is ignored, as upstream ignores it.
        Calls.callBounded(token, 0, gasleft(), abi.encodeWithSelector(0x095ea7b3, to, 0), 0);
        if (!_accepted(token, abi.encodeWithSelector(0x095ea7b3, to, amount))) {
            revert ApproveFailed();
        }
    }

    /// @dev Returns the amount of ERC20 `token` owned by `account`.
    /// Returns zero if the `token` does not exist.
    function balanceOf(address token, address account) internal view returns (uint256 amount) {
        (, amount) = checkBalanceOf(token, account);
    }

    /// @dev Performs a `token.balanceOf(account)` check.
    /// `implemented` denotes whether the `token` implements `balanceOf`.
    /// `amount` is zero if the `token` does not implement `balanceOf`.
    function checkBalanceOf(address token, address account)
        internal
        view
        returns (bool implemented, uint256 amount)
    {
        (implemented, amount) = _word(token, abi.encodeWithSelector(0x70a08231, account));
    }

    /// @dev Returns the total supply of the `token`.
    /// Reverts if the token does not exist or does not implement `totalSupply()`.
    function totalSupply(address token) internal view returns (uint256 result) {
        bool implemented;
        (implemented, result) = _word(token, abi.encodeWithSelector(0x18160ddd));
        if (!implemented) revert TotalSupplyQueryFailed();
    }

    /// @dev Sends `amount` wei to `to` with `gasLimit` gas and no calldata,
    /// copying none of the answer.
    function _sendETH(address to, uint256 amount, uint256 gasLimit) private returns (bool success) {
        (success,,) = Calls.callBounded(to, amount, gasLimit, "", 0);
    }

    /// @dev Whether `token` accepted the call `payload`: the call succeeded and
    /// the token answered `true`, or answered nothing and has code.
    function _accepted(address token, bytes memory payload) private returns (bool) {
        (bool success, bytes memory answer, uint256 total) =
            Calls.callBounded(token, 0, gasleft(), payload, 32);
        if (!success) return false;
        if (total == 0) return token.code.length != 0;
        return answer.length == 32 && uint256(Bytes.readBytes32(answer, 0)) == 1;
    }

    /// @dev The first word `token` answers the static call `payload` with, and
    /// whether the call succeeded with a word at least.
    function _word(address token, bytes memory payload)
        private
        view
        returns (bool answered, uint256 word)
    {
        (bool success, bytes memory answer,) = Calls.staticCallBounded(token, gasleft(), payload, 32);
        if (!success || answer.length < 32) return (false, 0);
        return (true, uint256(Bytes.readBytes32(answer, 0)));
    }
}
