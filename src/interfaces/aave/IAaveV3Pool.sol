// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/// @title IAaveV3Pool
/// @notice Minimal Aave V3 Pool interface for flash loan operations
interface IAaveV3Pool {
    /// @notice Execute a flash loan on a single asset
    /// @param receiverAddress The contract receiving the funds and the callback
    /// @param asset The address of the asset to flash borrow
    /// @param amount The amount to flash borrow
    /// @param params Arbitrary data passed to the receiver's executeOperation callback
    /// @param referralCode Referral code (0 if none)
    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    )
        external;

    /// @notice Returns the total flash loan premium (in bps, e.g. 5 = 0.05%)
    function FLASHLOAN_PREMIUM_TOTAL() external view returns (uint128);
}
