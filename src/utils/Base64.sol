// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Base64 as CoreBase64} from "solar:core/v1/codecs/Base64.sol";

/// @notice Checked Solidity implementation of the pinned Solady Base64 API.
/// @dev Decode accepts the documented standard, URL and IMAP alphabets and
/// padding modes. Malformed input reverts with the core InvalidBase64 error;
/// its output is unspecified in the upstream API.
library Base64 {
    function encode(bytes memory data, bool fileSafe, bool noPadding)
        internal
        pure
        returns (string memory)
    {
        return CoreBase64.encode(data, fileSafe, noPadding);
    }

    function encode(bytes memory data) internal pure returns (string memory) {
        return CoreBase64.encode(data);
    }

    function encode(bytes memory data, bool fileSafe) internal pure returns (string memory) {
        return CoreBase64.encode(data, fileSafe);
    }

    function decode(string memory data) internal pure returns (bytes memory) {
        return CoreBase64.decode(data, true);
    }
}
