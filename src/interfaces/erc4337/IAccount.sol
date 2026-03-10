// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/**
 * @notice Minimal ERC-4337 v0.7 user operation used by SovereignAccount.
 * @custom:security-contact security@multipli.com
 */
struct PackedUserOperation {
    address sender;
    uint256 nonce;
    bytes initCode;
    bytes callData;
    bytes32 accountGasLimits;
    uint256 preVerificationGas;
    bytes32 gasFees;
    bytes paymasterAndData;
    bytes signature;
}

/**
 * @notice Minimal ERC-4337 account interface used by SovereignAccount.
 * @custom:security-contact security@multipli.com
 */
interface IAccount {
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    )
        external
        returns (uint256 validationData);
}

