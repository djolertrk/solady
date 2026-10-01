// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Bytes} from "solar:core/Bytes.sol";
import {Calls} from "solar:core/Calls.sol";
import {ECDSA} from "./ECDSA.sol";

/// @notice Checked Solidity implementation of the pinned Solady SignatureCheckerLib API.
/// @dev A signer without code is checked with the `ecrecover` builtin, for
/// 65-byte and EIP-2098 64-byte signatures alike; a signer with code with
/// ERC1271. The ERC1271 call sends the calldata the assembly builds, unpadded,
/// through `Calls.staticCallBounded`, which copies at most the one word of the
/// answer that is checked against the magic value.
///
/// An ERC6492 signature ends with the 32-byte magic suffix. Its inner signature
/// is the third field of the wrapped encoding; one whose range lies past the
/// signature counts as rejected by ERC1271, where the assembly reads whatever
/// memory follows. The verifiers are called through `Calls.callBounded`, which
/// copies nothing of their answer.
library SignatureCheckerLib {
    /// @dev `bytes4(keccak256("isValidSignature(bytes32,bytes)"))`.
    bytes4 private constant _ERC1271_MAGIC = 0x1626ba7e;

    /// @dev The suffix of an ERC6492 signature.
    bytes32 private constant _ERC6492_DETECTION_SUFFIX =
        0x6492649264926492649264926492649264926492649264926492649264926492;

    /// @dev The non-reverting ERC6492 verifier.
    address private constant _VERIFIER = 0x0000bc370E4DC924F427d84e2f4B9Ec81626ba7E;

    /// @dev The reverting ERC6492 verifier.
    address private constant _REVERTING_VERIFIER = 0x00007bd799e4A591FeA53f8A8a3E9f931626Ba7e;

    /// @dev Returns whether `signature` is valid for `signer` and `hash`.
    /// If `signer.code.length == 0`, then validate with `ecrecover`, else
    /// it will validate with ERC1271 on `signer`.
    function isValidSignatureNow(address signer, bytes32 hash, bytes memory signature)
        internal
        view
        returns (bool isValid)
    {
        if (signer == address(0)) return isValid;
        if (signer.code.length == 0) return _recovers(signer, hash, signature);
        return isValidERC1271SignatureNow(signer, hash, signature);
    }

    /// @dev Returns whether `signature` is valid for `signer` and `hash`.
    /// If `signer.code.length == 0`, then validate with `ecrecover`, else
    /// it will validate with ERC1271 on `signer`.
    function isValidSignatureNowCalldata(address signer, bytes32 hash, bytes calldata signature)
        internal
        view
        returns (bool isValid)
    {
        if (signer == address(0)) return isValid;
        if (signer.code.length == 0) {
            address recovered = ECDSA.tryRecoverCalldata(hash, signature);
            return recovered != address(0) && recovered == signer;
        }
        return isValidERC1271SignatureNowCalldata(signer, hash, signature);
    }

    /// @dev Returns whether the signature (`r`, `vs`) is valid for `signer` and `hash`.
    /// If `signer.code.length == 0`, then validate with `ecrecover`, else
    /// it will validate with ERC1271 on `signer`.
    function isValidSignatureNow(address signer, bytes32 hash, bytes32 r, bytes32 vs)
        internal
        view
        returns (bool isValid)
    {
        if (signer == address(0)) return isValid;
        if (signer.code.length == 0) {
            address recovered = ECDSA.tryRecover(hash, r, vs);
            return recovered != address(0) && recovered == signer;
        }
        return isValidERC1271SignatureNow(signer, hash, r, vs);
    }

    /// @dev Returns whether the signature (`v`, `r`, `s`) is valid for `signer` and `hash`.
    /// If `signer.code.length == 0`, then validate with `ecrecover`, else
    /// it will validate with ERC1271 on `signer`.
    function isValidSignatureNow(address signer, bytes32 hash, uint8 v, bytes32 r, bytes32 s)
        internal
        view
        returns (bool isValid)
    {
        if (signer == address(0)) return isValid;
        if (signer.code.length == 0) {
            address recovered = ecrecover(hash, v, r, s);
            return recovered != address(0) && recovered == signer;
        }
        return isValidERC1271SignatureNow(signer, hash, v, r, s);
    }

    // Note: These ERC1271 operations do NOT have an ECDSA fallback.

    /// @dev Returns whether `signature` is valid for `hash` for an ERC1271 `signer` contract.
    function isValidERC1271SignatureNow(address signer, bytes32 hash, bytes memory signature)
        internal
        view
        returns (bool isValid)
    {
        return _erc1271(
            signer,
            abi.encodePacked(_ERC1271_MAGIC, hash, uint256(0x40), signature.length, signature)
        );
    }

    /// @dev Returns whether `signature` is valid for `hash` for an ERC1271 `signer` contract.
    function isValidERC1271SignatureNowCalldata(
        address signer,
        bytes32 hash,
        bytes calldata signature
    ) internal view returns (bool isValid) {
        return _erc1271(
            signer,
            abi.encodePacked(_ERC1271_MAGIC, hash, uint256(0x40), signature.length, signature)
        );
    }

    /// @dev Returns whether the signature (`r`, `vs`) is valid for `hash`
    /// for an ERC1271 `signer` contract.
    function isValidERC1271SignatureNow(address signer, bytes32 hash, bytes32 r, bytes32 vs)
        internal
        view
        returns (bool isValid)
    {
        return _erc1271(
            signer,
            abi.encodePacked(
                _ERC1271_MAGIC,
                hash,
                uint256(0x40),
                uint256(65),
                r,
                (uint256(vs) << 1) >> 1,
                uint8(27 + (uint256(vs) >> 255))
            )
        );
    }

    /// @dev Returns whether the signature (`v`, `r`, `s`) is valid for `hash`
    /// for an ERC1271 `signer` contract.
    function isValidERC1271SignatureNow(address signer, bytes32 hash, uint8 v, bytes32 r, bytes32 s)
        internal
        view
        returns (bool isValid)
    {
        return _erc1271(
            signer, abi.encodePacked(_ERC1271_MAGIC, hash, uint256(0x40), uint256(65), r, s, v)
        );
    }

    // Note: These ERC6492 operations now include an ECDSA fallback at the very end.
    // The calldata variants are excluded for brevity.

    /// @dev Returns whether `signature` is valid for `hash`.
    /// If the signature is postfixed with the ERC6492 magic number, it will attempt to
    /// deploy / prepare the `signer` smart account before doing a regular ERC1271 check.
    /// Note: This function is NOT reentrancy safe.
    /// The verifier must be deployed.
    /// Otherwise, the function will return false if `signer` is not yet deployed / prepared.
    /// See: https://gist.github.com/Vectorized/011d6becff6e0a73e42fe100f8d7ef04
    /// With a dedicated verifier, this function is safe to use in contracts
    /// that have been granted special permissions.
    function isValidERC6492SignatureNowAllowSideEffects(
        address signer,
        bytes32 hash,
        bytes memory signature
    ) internal returns (bool isValid) {
        bool noCode = signer.code.length == 0;
        if (_isERC6492(signature)) {
            if (!noCode && _innerERC1271(signer, hash, signature)) return true;
            (,, uint256 answered) = Calls.callBounded(
                _VERIFIER, 0, gasleft(), abi.encodePacked(uint256(uint160(signer)), hash, signature), 0
            );
            isValid = answered != 0;
        } else if (!noCode) {
            isValid = isValidERC1271SignatureNow(signer, hash, signature);
        }
        if (noCode && !isValid) isValid = _recovers(signer, hash, signature);
    }

    /// @dev Returns whether `signature` is valid for `hash`.
    /// If the signature is postfixed with the ERC6492 magic number, it will attempt
    /// to use a reverting verifier to deploy / prepare the `signer` smart account
    /// and do a `isValidSignature` check via the reverting verifier.
    /// Note: This function is reentrancy safe.
    /// The reverting verifier must be deployed.
    /// Otherwise, the function will return false if `signer` is not yet deployed / prepared.
    /// See: https://gist.github.com/Vectorized/846a474c855eee9e441506676800a9ad
    function isValidERC6492SignatureNow(address signer, bytes32 hash, bytes memory signature)
        internal
        returns (bool isValid)
    {
        bool noCode = signer.code.length == 0;
        if (_isERC6492(signature)) {
            if (!noCode && _innerERC1271(signer, hash, signature)) return true;
            // The reverting verifier always reverts, with the result as its answer.
            (bool succeeded,, uint256 answered) = Calls.callBounded(
                _REVERTING_VERIFIER,
                0,
                gasleft(),
                abi.encodePacked(uint256(uint160(signer)), hash, signature),
                0
            );
            isValid = answered > (succeeded ? 1 : 0);
        } else if (!noCode) {
            isValid = isValidERC1271SignatureNow(signer, hash, signature);
        }
        if (noCode && !isValid) isValid = _recovers(signer, hash, signature);
    }

    /// @dev Returns an Ethereum Signed Message, created from a `hash`.
    /// This produces a hash corresponding to the one signed with the
    /// [`eth_sign`](https://eth.wiki/json-rpc/API#eth_sign)
    /// JSON-RPC method as part of EIP-191.
    function toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32 result) {
        return ECDSA.toEthSignedMessageHash(hash);
    }

    /// @dev Returns an Ethereum Signed Message, created from `s`.
    /// This produces a hash corresponding to the one signed with the
    /// [`eth_sign`](https://eth.wiki/json-rpc/API#eth_sign)
    /// JSON-RPC method as part of EIP-191.
    /// Note: Supports lengths of `s` up to 999999 bytes.
    function toEthSignedMessageHash(bytes memory s) internal pure returns (bytes32 result) {
        return ECDSA.toEthSignedMessageHash(s);
    }

    /// @dev Returns an empty calldata bytes.
    function emptySignature() internal pure returns (bytes calldata signature) {
        return msg.data[0:0];
    }

    /// @dev Whether `signature` recovers to `signer`, which a failed recovery never does.
    function _recovers(address signer, bytes32 hash, bytes memory signature)
        private
        view
        returns (bool)
    {
        address recovered = ECDSA.tryRecover(hash, signature);
        return recovered != address(0) && recovered == signer;
    }

    /// @dev Whether `signer` answers the ERC1271 call `payload` with at least a
    /// word, the first of which is the magic value.
    function _erc1271(address signer, bytes memory payload) private view returns (bool) {
        (bool success, bytes memory answer,) = Calls.staticCallBounded(signer, gasleft(), payload, 32);
        return success && answer.length == 32
            && Bytes.readBytes32(answer, 0) == bytes32(_ERC1271_MAGIC);
    }

    /// @dev Whether `signature` ends with the ERC6492 magic suffix.
    function _isERC6492(bytes memory signature) private pure returns (bool) {
        uint256 n = signature.length;
        return n >= 32 && Bytes.readBytes32(signature, n - 32) == _ERC6492_DETECTION_SUFFIX;
    }

    /// @dev Whether `signer` accepts, with ERC1271, the inner signature of the
    /// ERC6492 `signature`: the `bytes` at the offset its third word gives.
    function _innerERC1271(address signer, bytes32 hash, bytes memory signature)
        private
        view
        returns (bool)
    {
        uint256 n = signature.length;
        if (n < 96) return false;
        uint256 offset = uint256(Bytes.readBytes32(signature, 64));
        if (offset > n - 32) return false;
        uint256 length = uint256(Bytes.readBytes32(signature, offset));
        if (length > n - 32 - offset) return false;
        /// @custom:solar-view
        bytes memory inner = Bytes.slice(signature, offset + 32, length);
        return _erc1271(signer, abi.encodePacked(_ERC1271_MAGIC, hash, uint256(0x40), length, inner));
    }
}
