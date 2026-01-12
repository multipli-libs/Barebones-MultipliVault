// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title Errors
 * @notice Defines custom error types for various contract operations.
 * @dev This library provides reusable error messages for share operations, authorization checks, and vault interactions.
 */
library Errors {
    //============================== GENERICS ===============================

    /**
     * @notice Thrown when an unauthorized method to a target is called.
     * @dev The method must be authorized by setUserRole and setRoleCapability from RolesAuthority.
     * @param target The target address.
     * @param functionSig The function signature being called.
     */
    error TargetMethodNotAuthorized(address target, bytes4 functionSig);

    /**
     * @notice Thrown when insufficient shares balance is available to complete the operation.
     */
    error InsufficientShares();

    /**
     * @notice Thrown when the operation is called by a user that is not the owner of the shares.
     */
    error NotSharesOwner();

    /**
     * @notice Thrown when the input shares amount is zero.
     */
    error SharesAmountZero();

    /**
     * @notice Thrown when a claim request is fulfilled with an invalid shares amount.
     */
    error InvalidSharesAmount();

    /**
     * @notice Thrown receiver is invalid.
     */
    error InvalidReceiverAddress();

    /**
     * @notice Thrown receiver is invalid.
     */
    error InvalidOperatorAddress();

    /**
     * @notice Thrown owner is invalid.
     */
    error InvalidOwnerAddress();

    /**
     * @notice Thrown shares are not returned during flashRedeem
     */
    error SharesNotReturned();

    /**
     * @notice Thrown when the actual shares received is less than the minimum expected
     * @param actualShares The number of shares actually received
     * @param minShares The minimum number of shares expected
     */
    error InsufficientSharesReceived(uint256 actualShares, uint256 minShares);

    /**
     * @notice Thrown when the assets required exceeds the maximum the caller is willing to pay
     * @param actualAssets The number of assets actually required
     * @param maxAssets The maximum number of assets the caller is willing to pay
     */
    error ExcessiveAssetsRequired(uint256 actualAssets, uint256 maxAssets);

    /**
     * @notice Thrown there is a mismatch in Total Supply
     */
    error TotalSupplyMismatch();

    /**
     * @notice Thrown there is a asset balance mismatch in Vault
     */
    error AssetBalanceMismatch();

    /**
     * @notice Thrown when a withdraw is attempted with an amount different than the claimable assets.
     */
    error InvalidAssetsAmount();

    /**
     * @notice Thrown when the new max percentage is greater than the current max percentage.
     */
    error InvalidMaxPercentage();

    /**
     * @notice Thrown when the new fee is greater than the max allowed fee.
     */
    error InvalidFee();

    /**
     * @notice Thrown when the underlying balance has already been updated in the current block.
     */
    error UpdateAlreadyCompletedInThisBlock();

    /**
     * @notice Thrown when redeem() or withdraw() is called.
     */
    error UseRequestRedeem();

    /**
     * @notice Thrown when deposit / mint is with assets < minimum deposit amount
     */
    error DepositAmountLessThanThreshold(uint256 amount, uint256 minDepositAmount);

    /**
     * @notice Thrown when deposit / mint is with assets < minimum deposit amount
     */
    error UnsupportedRedeemType(uint8 redeemType);
}
