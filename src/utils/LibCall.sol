// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Bytes} from "solar:core/v1/Bytes.sol";
import {Calls} from "solar:core/v1/Calls.sol";
import {Revert} from "solar:core/v1/Revert.sol";

/// @notice Checked Solidity implementation of the pinned Solady LibCall API.
/// @dev The contract calls copy the whole response, as `address.call` does,
/// bubble a revert with `Revert.raw`, and reject an empty response from an
/// account without code. The try calls copy at most `maxCopy` bytes of the
/// response with `Calls.callBounded`, into a buffer allocated once its size is
/// known, so a callee cannot make the caller copy more than it asked for.
library LibCall {
    /// @dev The target of the call is not a contract.
    error TargetIsNotContract();

    /// @dev The data is too short to contain a function selector.
    error DataTooShort();

    /// @dev Makes a call to `target`, with `data` and `value`.
    function callContract(address target, uint256 value, bytes memory data)
        internal
        returns (bytes memory result)
    {
        bool success;
        (success, result) = target.call{value: value}(data);
        _check(target, success, result);
    }

    /// @dev Makes a call to `target`, with `data`.
    function callContract(address target, bytes memory data)
        internal
        returns (bytes memory result)
    {
        bool success;
        (success, result) = target.call(data);
        _check(target, success, result);
    }

    /// @dev Makes a static call to `target`, with `data`.
    function staticCallContract(address target, bytes memory data)
        internal
        view
        returns (bytes memory result)
    {
        bool success;
        (success, result) = target.staticcall(data);
        _check(target, success, result);
    }

    /// @dev Makes a delegate call to `target`, with `data`.
    function delegateCallContract(address target, bytes memory data)
        internal
        returns (bytes memory result)
    {
        bool success;
        (success, result) = target.delegatecall(data);
        _check(target, success, result);
    }

    /// @dev Makes a call to `target`, with `data` and `value`.
    /// The call is given a gas limit of `gasStipend`,
    /// and up to `maxCopy` bytes of return data can be copied.
    function tryCall(
        address target,
        uint256 value,
        uint256 gasStipend,
        uint16 maxCopy,
        bytes memory data
    ) internal returns (bool success, bool exceededMaxCopy, bytes memory result) {
        uint256 total;
        (success, result, total) = Calls.callBounded(target, value, gasStipend, data, maxCopy);
        exceededMaxCopy = total > maxCopy;
    }

    /// @dev Makes a call to `target`, with `data`.
    /// The call is given a gas limit of `gasStipend`,
    /// and up to `maxCopy` bytes of return data can be copied.
    function tryStaticCall(address target, uint256 gasStipend, uint16 maxCopy, bytes memory data)
        internal
        view
        returns (bool success, bool exceededMaxCopy, bytes memory result)
    {
        uint256 total;
        (success, result, total) = Calls.staticCallBounded(target, gasStipend, data, maxCopy);
        exceededMaxCopy = total > maxCopy;
    }

    /// @dev Bubbles up the revert.
    function bubbleUpRevert(bytes memory revertReturnData) internal pure {
        Revert.raw(revertReturnData);
    }

    /// @dev In-place replaces the function selector of encoded contract call data.
    function setSelector(bytes4 newSelector, bytes memory data) internal pure {
        if (data.length < 4) revert DataTooShort();
        Bytes.writeBytes4(data, 0, newSelector);
    }

    /// @dev Bubbles a failed call's revert, and rejects an empty response from
    /// an account without code, which a call to it succeeds with.
    function _check(address target, bool success, bytes memory result) private view {
        if (!success) Revert.raw(result);
        if (result.length == 0 && target.code.length == 0) revert TargetIsNotContract();
    }
}
