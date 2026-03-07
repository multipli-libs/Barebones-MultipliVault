// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title Errors
 * @notice Defines custom error types for various contract operations.
 * @dev This library provides reusable error messages for share operations, authorization checks, and vault interactions.
 */
library Errors {
    /*//////////////////////////////////////////////////////////////
                              GENERIC ERRORS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Thrown when an unauthorized method to a target is called.
     * @dev The method must be authorized by setUserRole and setRoleCapability from RolesAuthority.
     * @param target The target address.
     * @param functionSig The function signature being called.
     */
    error Errors__TargetMethodNotAuthorized(address target, bytes4 functionSig);

    /**
     * @notice Thrown when array lengths do not match in batch operations.
     */
    error Errors__ArrayLengthsMismatch();

    /**
     * @notice Thrown when insufficient shares balance is available to complete the operation.
     */
    error Errors__InsufficientShares();

    /**
     * @notice Thrown when the operation is called by a user that is not the owner of the shares.
     */
    error Errors__NotSharesOwner();

    /**
     * @notice Thrown when the input shares amount is zero.
     */
    error Errors__SharesAmountZero();

    /**
     * @notice Thrown when a claim request is fulfilled with an invalid shares amount.
     */
    error Errors__InvalidSharesAmount();

    /**
     * @notice Thrown receiver is invalid.
     */
    error Errors__InvalidReceiverAddress();

    /**
     * @notice Thrown receiver is invalid.
     */
    error Errors__InvalidOperatorAddress();

    /**
     * @notice Thrown owner is invalid.
     */
    error Errors__InvalidOwnerAddress();

    /**
     * @notice Thrown shares are not returned during flashRedeem
     */
    error Errors__SharesNotReturned();

    /**
     * @notice Thrown when the actual shares received is less than the minimum expected
     * @param actualShares The number of shares actually received
     * @param minShares The minimum number of shares expected
     */
    error Errors__InsufficientSharesReceived(uint256 actualShares, uint256 minShares);

    /**
     * @notice Thrown when the assets required exceeds the maximum the caller is willing to pay
     * @param actualAssets The number of assets actually required
     * @param maxAssets The maximum number of assets the caller is willing to pay
     */
    error Errors__ExcessiveAssetsRequired(uint256 actualAssets, uint256 maxAssets);

    /**
     * @notice Thrown there is a mismatch in Total Supply
     */
    error Errors__TotalSupplyMismatch();

    /**
     * @notice Thrown there is a asset balance mismatch in Vault
     */
    error Errors__AssetBalanceMismatch();

    /**
     * @notice Thrown when a withdraw is attempted with an amount different than the claimable assets.
     */
    error Errors__InvalidAssetsAmount();

    /**
     * @notice Thrown when the new max percentage is greater than the current max percentage.
     */
    error Errors__InvalidMaxPercentage();

    /**
     * @notice Thrown when the new fee is greater than the max allowed fee.
     */
    error Errors__InvalidFee();

    /**
     * @notice Thrown when the underlying balance has already been updated in the current block.
     */
    error Errors__UpdateAlreadyCompletedInThisBlock();

    /**
     * @notice Thrown when redeem() or withdraw() is called.
     */
    error Errors__UseRequestRedeem();

    /**
     * @notice Thrown when deposit / mint is with assets < minimum deposit amount
     */
    error Errors__DepositAmountLessThanThreshold(uint256 amount, uint256 minDepositAmount);

    /**
     * @notice Thrown when deposit / mint is with assets < minimum deposit amount
     */
    error Errors__UnsupportedRedeemType(uint8 redeemType);
}
