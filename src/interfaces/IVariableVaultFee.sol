// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/**
 * @title IVariableVaultFee
 * @notice Interface for managing variable fees on vault operations
 * @dev Supports both flat and percentage-based fees for deposits and withdrawals
 */
interface IVariableVaultFee {
    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/

    enum FeeType {
        FLAT,
        PERCENTAGE
    }

    enum FeeOperation {
        DEPOSIT,
        WITHDRAWAL,
        INSTANT_WITHDRAWAL,
        FLASH_REDEEM
    }

    struct FeeConfig {
        FeeType feeType;
        uint256 feeAmount; // Either percentage (1e17 = 10%) or flat amount (e.g., 100e18)
    }

    struct AssetFeeConfig {
        FeeConfig withdrawalFee;
        FeeConfig depositFee;
        FeeConfig instantWithdrawalFee;
        FeeConfig flashRedeemFee;
        address feeRecipient;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event RegisterAsset(address indexed user, address indexed asset, AssetFeeConfig config);
    event DeregisterAsset(address indexed user, address indexed asset);
    event UpdateAssetFeeConfig(
        address indexed user,
        address indexed asset,
        AssetFeeConfig oldConfig,
        AssetFeeConfig newConfig
    );

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when an invalid asset address is provided or asset is not registered
    error IVariableVaultFee__InvalidAsset();

    /// @notice Thrown when asset configuration parameters are invalid
    error IVariableVaultFee__InvalidAssetConfig();

    /// @notice Thrown when attempting to register an asset that is already registered
    error IVariableVaultFee__AssetAlreadyRegistered();

    /// @notice Thrown when amount is insufficient for the operation
    error IVariableVaultFee__ZeroAmount();

    /// @notice Thrown when amount is insufficient for the operation
    error IVariableVaultFee__InsufficientAmount();

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculate fee on raw amount (amount without fees included)
     * @param asset The asset address
     * @param amount The raw amount
     * @param operation The fee operation type (deposit/withdrawal)
     * @return The fee amount to be added
     */
    function feeOnRaw(
        address asset,
        uint256 amount,
        FeeOperation operation
    )
        external
        view
        returns (uint256);

    /**
     * @notice Calculate fee on total amount (amount with fees already included)
     * @param asset The asset address
     * @param amount The total amount including fees
     * @param operation The fee operation type (deposit/withdrawal)
     * @return The fee portion of the total amount
     */
    function feeOnTotal(
        address asset,
        uint256 amount,
        FeeOperation operation
    )
        external
        view
        returns (uint256);

    /**
     * @notice Return the Fee Recipient
     * @param asset The asset address
     * @return The address to which the fee should be sent
     */
    function getFeeRecipient(address asset) external view returns (address);
}
