// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @notice Deployless queryer for predeploys.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/DeploylessPredeployQueryer.sol)
/// @author Wilson Cusack (Coinbase)
/// (https://github.com/coinbase/smart-wallet/blob/main/src/utils/ERC1271InputGenerator.sol)
/// (https://github.com/wilsoncusack/scw-tx/blob/main/utils/ERC1271.ts)
///
/// @dev
/// This contract is not meant to ever actually be deployed,
/// only mock deployed and used via a static `eth_call`.
///
/// Creation code (hex-encoded):
/// `3860b63d393d516020805190606051833b15607e575b5059926040908285528351938460051b9459523d604087015260005b858103603e578680590390f35b6000828683820101510138908688820151910147875af115607457603f19875903018482890101523d59523d6000593e84016031565b3d6000803e3d6000fd5b816000828193519083479101906040515af11560ad5783815114601f3d111660155763d1f6b81290526004601cfd5b3d81803e3d90fdfe`
/// See: https://gist.github.com/Vectorized/f77fce00a03dfa99aee526d2a77fd2aa
///
/// May be useful for generating ERC-6492 compliant signatures.
/// Inspired by Ambire's DeploylessUniversalSigValidator
/// (https://github.com/AmbireTech/signature-validator/blob/main/contracts/DeploylessUniversalSigValidator.sol)
///
/// The checked port makes the factory call and the queries as plain calls with the value and
/// gas the assembly passes, and `abi.encode`s the results, which is the encoding the assembly
/// builds. A constructor can only return its contract's runtime code in Solidity, so the
/// trusted `_deploylessPredeployQueryerReturnRaw` returns the encoding as the deployed code,
/// and the trusted `_deploylessPredeployQueryerRevertRaw` bubbles up a failed call's revert.
/// @custom:solar-safe memory arithmetic
contract DeploylessPredeployQueryer {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The returned address by the factory does not match the provided address.
    error ReturnedAddressMismatch();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The code of the deployed contract can be `abi.decoded` into an array of bytes,
    /// where each entry can be `abi.decoded` into the required variables.
    ///
    /// For example, if `targetQueryCalldata`'s 0th call is expected to return a `uint256`,
    /// you will use `abi.decode(abi.decode(deployed.code, (bytes[]))[0], (uint256))` to
    /// get the returned `uint256`.
    constructor(
        address target,
        bytes[] memory targetQueryCalldata,
        address factory,
        bytes memory factoryCalldata
    ) payable {
        // If the target does not exist, deploy it.
        if (target.code.length == 0) {
            (bool success, bytes memory result) =
                factory.call{value: address(this).balance}(factoryCalldata);
            if (!success) _deploylessPredeployQueryerRevertRaw(result);
            if (result.length < 0x20 || abi.decode(result, (uint256)) != uint160(target)) {
                revert ReturnedAddressMismatch();
            }
        }
        // Each query's result takes its place in `targetQueryCalldata`.
        for (uint256 i; i < targetQueryCalldata.length; ++i) {
            (bool success, bytes memory result) =
                target.call{value: address(this).balance}(targetQueryCalldata[i]);
            if (!success) _deploylessPredeployQueryerRevertRaw(result);
            targetQueryCalldata[i] = result;
        }
        _deploylessPredeployQueryerReturnRaw(abi.encode(targetQueryCalldata));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PRIVATE HELPERS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Reverts the current call with exactly `data`. Solidity can only revert with an
    /// error or a reason string.
    /// @custom:solar-trusted
    function _deploylessPredeployQueryerRevertRaw(bytes memory data) private pure {
        /// @solidity memory-safe-assembly
        assembly {
            revert(add(data, 0x20), mload(data))
        }
    }

    /// @dev Ends the creation with exactly `data` as the deployed code. Solidity deploys the
    /// contract's own runtime code.
    /// @custom:solar-trusted
    function _deploylessPredeployQueryerReturnRaw(bytes memory data) private pure {
        /// @solidity memory-safe-assembly
        assembly {
            return(add(data, 0x20), mload(data))
        }
    }
}
