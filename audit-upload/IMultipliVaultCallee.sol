// SPDX-License-Identifier: MIT

pragma solidity ^0.8.34;

interface IMultipliVaultCallee {
    /// @notice This function is called by the Multipli vault, which sends in flash
    /// loaned amount beforehand. The Multipli vault expects the specified shares
    /// to be returned by the contract at the end of the call.
    /// @param _initiator The address that initiated the flashRedeem request
    /// @param _asset The asset to return to Multipli.
    /// @param _underlyingAsset The underlying asset sent by Multipli in the flash loan.
    /// @param _shares The amount of asset to return.
    /// @param _underlyingAmount The amount of flash loaned underlying asset sent by
    /// Multipli.
    /// @param _additionalData Any additional data for the flash loan.
    function onRedemptionFlashLoan(
        address _initiator,
        address _asset,
        address _underlyingAsset,
        uint256 _shares,
        uint256 _underlyingAmount,
        bytes memory _additionalData
    )
        external;
}
