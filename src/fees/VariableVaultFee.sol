// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IVariableVaultFee } from "../interfaces/IVariableVaultFee.sol";

/**
 * @title VariableVaultFee
 * @author Bhavesh Praveen
 * @notice A contract for managing variable fees on vault operations
 * @dev This contract allows registration and management of assets with configurable fees.
 *      Supports both flat and percentage-based fees for deposits and withdrawals.
 *      Fees can be calculated on raw amounts (before fees) or total amounts (including fees).
 * @custom:security-contact security@multipli.com
 */
contract VariableVaultFee is Ownable, IVariableVaultFee {
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Mapping to track which assets are registered
    /// @dev asset address => registration status
    mapping(address => bool) public isAssetRegistered;

    /// @notice Mapping to store fee configuration for each registered asset
    /// @dev asset address => AssetFeeConfig struct containing fee details
    mapping(address => AssetFeeConfig) public assetFee;

    /// @notice Denominator used for percentage fee calculations (1e18 = 100%)
    uint256 internal constant FEE_DENOMINATOR = 1e18;

    /// @notice Maximum allowed percentage fee (5e16 = 5%)
    uint256 internal constant MAX_PERCENTAGE_FEE = 5e16; // 5%
    //  1e18 => 100%
    // 1e17 => 10%
    // 1e16 => 1%
    // 1e15 => 0.1%

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the contract with the specified owner
     * @param owner The address that will be granted ownership of the contract
     */
    constructor(address owner) Ownable(owner) { }

    /*//////////////////////////////////////////////////////////////
                  USER-FACING STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Registers a new asset with fee configuration
     * @dev Only callable by the contract owner. Asset must not be already registered.
     * @param asset The address of the asset to register
     * @param config The fee configuration for the asset including deposit/withdrawal fees and fee
     * recipient
     * @custom:throws InvalidAsset if asset address is zero
     * @custom:throws AssetAlreadyRegistered if asset is already registered
     * @custom:throws InvalidAssetConfig if configuration is invalid
     * @custom:emits RegisterAsset
     */
    function registerAsset(address asset, AssetFeeConfig memory config) public onlyOwner {
        if (asset == address(0)) revert IVariableVaultFee__InvalidAsset();
        if (isAssetRegistered[asset]) revert IVariableVaultFee__AssetAlreadyRegistered();

        _validateAssetConfig(config);

        isAssetRegistered[asset] = true;
        assetFee[asset] = config;

        emit RegisterAsset(_msgSender(), asset, config);
    }

    /**
     * @notice Deregisters an asset and clears its fee configuration
     * @dev Only callable by the contract owner. Resets all fee configuration to zero values.
     * @param asset The address of the asset to deregister
     * @custom:throws InvalidAsset if asset address is zero or asset is not registered
     * @custom:emits DeregisterAsset
     */
    function deregisterAsset(address asset) external onlyOwner {
        if (asset == address(0) || !isAssetRegistered[asset]) {
            revert IVariableVaultFee__InvalidAsset();
        }

        isAssetRegistered[asset] = false;
        delete assetFee[asset];

        emit DeregisterAsset(_msgSender(), asset);
    }

    /**
     * @notice Updates the fee configuration for an existing registered asset
     * @dev Only callable by the contract owner. Asset must be already registered.
     * @param asset The address of the asset to update
     * @param config The new fee configuration for the asset
     * @custom:throws InvalidAsset if asset address is zero or asset is not registered
     * @custom:throws InvalidAssetConfig if new configuration is invalid
     * @custom:emits UpdateAssetFeeConfig
     */
    function updateAssetFeeConfig(address asset, AssetFeeConfig memory config) external onlyOwner {
        if (asset == address(0) || !isAssetRegistered[asset]) {
            revert IVariableVaultFee__InvalidAsset();
        }

        _validateAssetConfig(config);

        AssetFeeConfig memory oldConfig = _getAssetConfig(asset);
        assetFee[asset] = config;

        emit UpdateAssetFeeConfig(_msgSender(), asset, oldConfig, config);
    }

    /*//////////////////////////////////////////////////////////////
                    USER-FACING READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getFeeRecipient(address asset) external view returns (address) {
        AssetFeeConfig memory assetConfig = _getAssetConfig(asset);
        return assetConfig.feeRecipient;
    }

    /**
     * @notice Calculates the fee to be added to a raw amount (amount without fees)
     * @dev Responsibility of the calling contract to ensure that the user holds assets + fee.
     *      This method simply returns the fee for the asset amount, and does not revert if fee >
     * amount
     * @param asset The address of the asset
     * @param amount The raw amount (without fees included)
     * @param operation The type of operation (DEPOSIT or WITHDRAWAL)
     * @return fee The fee amount to be added to the raw amount
     * @custom:throws InvalidAsset if asset is zero address or not registered
     * @custom:throws InsufficientAmount if amount is zero
     */
    function feeOnRaw(
        address asset,
        uint256 amount,
        FeeOperation operation
    )
        external
        view
        returns (uint256)
    {
        if (asset == address(0) || !isAssetRegistered[asset]) {
            revert IVariableVaultFee__InvalidAsset();
        }
        if (amount == 0) revert IVariableVaultFee__ZeroAmount();

        FeeConfig memory feeConfig = _getFeeConfig(asset, operation);
        return _feeOnRaw(amount, feeConfig);
    }

    /**
     * @notice Calculates the fee portion of a total amount (amount that includes fees)
     * @dev Used when the total amount already includes fees and you need to extract the fee portion
     * @param asset The address of the asset
     * @param amount The total amount (including fees)
     * @param operation The type of operation (DEPOSIT or WITHDRAWAL)
     * @return fee The fee portion of the total amount
     * @custom:throws InvalidAsset if asset is zero address or not registered
     * @custom:throws InsufficientAmount if amount is zero or if flat fee amount exceeds total
     * assets
     */
    function feeOnTotal(
        address asset,
        uint256 amount,
        FeeOperation operation
    )
        external
        view
        returns (uint256)
    {
        if (asset == address(0) || !isAssetRegistered[asset]) {
            revert IVariableVaultFee__InvalidAsset();
        }
        if (amount == 0) revert IVariableVaultFee__ZeroAmount();

        FeeConfig memory feeConfig = _getFeeConfig(asset, operation);
        return _feeOnTotal(amount, feeConfig);
    }

    /*//////////////////////////////////////////////////////////////
                      INTERNAL READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Validates the asset fee configuration
     * @dev Internal function to ensure fee configuration is valid before setting
     * @param config The asset fee configuration to validate
     * @custom:throws InvalidAssetConfig if fee recipient is zero address or percentage fees exceed
     * maximum
     */
    function _validateAssetConfig(AssetFeeConfig memory config) internal pure {
        if (config.feeRecipient == address(0)) revert IVariableVaultFee__InvalidAssetConfig();
        if (
            (config.depositFee.feeType == FeeType.PERCENTAGE
                    && config.depositFee.feeAmount > MAX_PERCENTAGE_FEE)
                || (config.withdrawalFee.feeType == FeeType.PERCENTAGE
                    && config.withdrawalFee.feeAmount > MAX_PERCENTAGE_FEE)
                || (config.instantWithdrawalFee.feeType == FeeType.PERCENTAGE
                    && config.instantWithdrawalFee.feeAmount > MAX_PERCENTAGE_FEE)
                || (config.flashRedeemFee.feeType == FeeType.PERCENTAGE
                    && config.flashRedeemFee.feeAmount > MAX_PERCENTAGE_FEE)
        ) {
            revert IVariableVaultFee__InvalidAssetConfig();
        }
    }

    function _getAssetConfig(address asset) internal view returns (AssetFeeConfig memory) {
        if (asset == address(0) || !isAssetRegistered[asset]) {
            revert IVariableVaultFee__InvalidAsset();
        }
        return assetFee[asset];
    }

    /**
     * @notice Retrieves the fee configuration for a specific operation on an asset
     * @dev Internal function to get deposit or withdrawal fee configuration
     * @param asset The asset address
     * @param operation The type of operation (DEPOSIT or WITHDRAWAL)
     * @return FeeConfig The fee configuration for the specified operation
     */
    function _getFeeConfig(
        address asset,
        FeeOperation operation
    )
        internal
        view
        returns (FeeConfig memory)
    {
        AssetFeeConfig memory assetConfig = _getAssetConfig(asset);
        if (operation == FeeOperation.DEPOSIT) {
            return assetConfig.depositFee;
        }
        if (operation == FeeOperation.WITHDRAWAL) {
            return assetConfig.withdrawalFee;
        }
        if (operation == FeeOperation.FLASH_REDEEM) {
            return assetConfig.flashRedeemFee;
        }
        return assetConfig.instantWithdrawalFee;
    }

    /**
     * @notice Internal function to calculate fees on raw amounts
     * @dev Calculates the fees that should be added to an amount `assets` that does not already
     * include fees.
     *      Used in {IERC4626-mint} and {IERC4626-withdraw} operations.
     * @param assets The raw asset amount
     * @param feeConfig The fee configuration to apply
     * @return fee The calculated fee amount
     */
    function _feeOnRaw(uint256 assets, FeeConfig memory feeConfig) internal pure returns (uint256) {
        if (feeConfig.feeType == FeeType.FLAT) {
            return feeConfig.feeAmount;
        }

        if (feeConfig.feeAmount == 0) {
            return 0;
        }

        return assets.mulDiv(feeConfig.feeAmount, FEE_DENOMINATOR, Math.Rounding.Ceil);
    }

    /**
     * @notice Internal function to calculate fees on total amounts
     * @dev Calculates the fee part of an amount `assets` that already includes fees.
     *      Used in {IERC4626-deposit} and {IERC4626-redeem} operations.
     * @param assets The total asset amount (including fees)
     * @param feeConfig The fee configuration to apply
     * @return fee The calculated fee portion
     * @custom:throws InsufficientAmount if flat fee amount exceeds total assets
     */
    function _feeOnTotal(
        uint256 assets,
        FeeConfig memory feeConfig
    )
        internal
        pure
        returns (uint256)
    {
        if (feeConfig.feeType == FeeType.FLAT) {
            if (feeConfig.feeAmount > assets) revert IVariableVaultFee__InsufficientAmount();
            return feeConfig.feeAmount;
        }

        if (feeConfig.feeAmount == 0) {
            return 0;
        }

        return assets.mulDiv(
            feeConfig.feeAmount, feeConfig.feeAmount + FEE_DENOMINATOR, Math.Rounding.Ceil
        );
    }
}
