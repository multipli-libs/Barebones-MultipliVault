// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IVariableVaultFee } from "../interfaces/IVariableVaultFee.sol";

import { Authority } from "@solmate/auth/Auth.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title VaultFeeUpgradeable
 * @custom:security-contact security@multipli.com
 */
abstract contract VaultFeeUpgradeable is Initializable {
    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @custom:storage-location erc7201:multipli.storage.vaultfee
     * @dev Structure to hold Vault fee contract data
     */
    struct VaultFeeStorage {
        IVariableVaultFee feeContract;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    // Storage slot for the VaultFeeStorageLocation struct.
    // keccak256(abi.encode(uint256(keccak256("multipli.storage.vaultfeeV1")) - 1)) &
    // ~bytes32(uint256(0xff))
    bytes32 private constant VaultFeeStorageLocation =
        0x4e0114f5bb788bf295d0ab17f602045fbe9841605d1e05a2674fbfa584e94700;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when the fee contract is updated.
     * @param user The address initiating the update.
     * @param oldFeeContract The previous fee contract.
     * @param newFeeContract The new fee contract.
     */
    event FeeContractUpdated(address indexed user, address oldFeeContract, address newFeeContract);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error VaultFee__ConfiguredIncorrectly(bytes4 msgSig);

    /*//////////////////////////////////////////////////////////////
                  USER-FACING STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the fee contract. Developers are expected to add access control for this
     * method.
     * @param _feeContract The new fee contract.
     */
    function setFeeContract(IVariableVaultFee _feeContract) public virtual {
        VaultFeeStorage storage $ = _getVaultFeeStorage();
        IVariableVaultFee oldFeeContract = feeContract();
        $.feeContract = _feeContract;
        emit FeeContractUpdated(msg.sender, address(oldFeeContract), address(_feeContract));
    }

    /*//////////////////////////////////////////////////////////////
                    USER-FACING READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the current fee contract.
     * @return The current fee contract address.
     */
    function feeContract() public view virtual returns (IVariableVaultFee) {
        return _getVaultFeeStorage().feeContract;
    }

    /*//////////////////////////////////////////////////////////////
                      INTERNAL STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the contract with the vault fee contract.
     * @param _feeContract The initial fee contract.
     * @dev This function can only be called during contract initialization.
     */
    function __VaultFeeUpgreadable_init(IVariableVaultFee _feeContract) internal onlyInitializing {
        __VaultFeeUpgreadable_init_unchained(_feeContract);
    }

    function __VaultFeeUpgreadable_init_unchained(IVariableVaultFee _feeContract)
        internal
        onlyInitializing
    {
        VaultFeeStorage storage $ = _getVaultFeeStorage();
        $.feeContract = _feeContract;
        emit FeeContractUpdated(msg.sender, address(0), address(_feeContract));
    }

    /*//////////////////////////////////////////////////////////////
                      INTERNAL READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _getFeeRecipient(address asset) internal view virtual returns (address) {
        IVariableVaultFee feeContractAddr = feeContract();
        return feeContractAddr.getFeeRecipient(asset);
    }

    /**
     * @notice Internal function to calculate fees for operations.
     * @dev Refactored common logic for all fee calculation methods.
     * @param asset The asset address.
     * @param amount The amount to calculate fees for.
     * @param operation The fee operation type.
     * @param isRawAmount Whether the amount is raw (true) or total (false).
     * @return The calculated fee amount.
     */
    function _calculateFee(
        address asset,
        uint256 amount,
        IVariableVaultFee.FeeOperation operation,
        bool isRawAmount
    )
        internal
        view
        virtual
        returns (uint256)
    {
        IVariableVaultFee feeContractAddr = feeContract();

        if (address(feeContractAddr) == address(0)) {
            revert VaultFee__ConfiguredIncorrectly(msg.sig);
        }

        if (isRawAmount) {
            return feeContractAddr.feeOnRaw(asset, amount, operation);
        } else {
            return feeContractAddr.feeOnTotal(asset, amount, operation);
        }
    }

    /**
     * @notice Calculate fee on raw deposit amount.
     * @param asset The asset address.
     * @param amount The raw deposit amount.
     * @return The fee amount.
     */
    function _feeOnRawDeposit(
        address asset,
        uint256 amount
    )
        internal
        view
        virtual
        returns (uint256)
    {
        return _calculateFee(asset, amount, IVariableVaultFee.FeeOperation.DEPOSIT, true);
    }

    /**
     * @notice Calculate fee on raw withdrawal amount.
     * @param asset The asset address.
     * @param amount The raw withdrawal amount.
     * @return The fee amount.
     */
    function _feeOnRawWithdrawal(
        address asset,
        uint256 amount
    )
        internal
        view
        virtual
        returns (uint256)
    {
        return _calculateFee(asset, amount, IVariableVaultFee.FeeOperation.WITHDRAWAL, true);
    }

    /**
     * @notice Calculate fee on raw instant withdrawal amount.
     * @param asset The asset address.
     * @param amount The raw withdrawal amount.
     * @return The fee amount.
     */
    function _feeOnRawInstantWithdrawal(
        address asset,
        uint256 amount
    )
        internal
        view
        virtual
        returns (uint256)
    {
        return _calculateFee(asset, amount, IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL, true);
    }

    /**
     * @notice Calculate fee on total deposit amount.
     * @param asset The asset address.
     * @param amount The total deposit amount.
     * @return The fee amount.
     */
    function _feeOnTotalDeposit(
        address asset,
        uint256 amount
    )
        internal
        view
        virtual
        returns (uint256)
    {
        return _calculateFee(asset, amount, IVariableVaultFee.FeeOperation.DEPOSIT, false);
    }

    /**
     * @notice Calculate fee on total withdrawal amount.
     * @param asset The asset address.
     * @param amount The total withdrawal amount.
     * @return The fee amount.
     */
    function _feeOnTotalWithdrawal(
        address asset,
        uint256 amount
    )
        internal
        view
        virtual
        returns (uint256)
    {
        return _calculateFee(asset, amount, IVariableVaultFee.FeeOperation.WITHDRAWAL, false);
    }

    /**
     * @notice Calculate fee on total instant withdrawal amount.
     * @param asset The asset address.
     * @param amount The total withdrawal amount.
     * @return The fee amount.
     */
    function _feeOnTotalInstantWithdrawal(
        address asset,
        uint256 amount
    )
        internal
        view
        virtual
        returns (uint256)
    {
        return
            _calculateFee(asset, amount, IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL, false);
    }

    /**
     * @notice Calculate fee on total flash withdrawal amount.
     * @param asset The asset address.
     * @param amount The total withdrawal amount.
     * @return The fee amount.
     */
    function _feeOnTotalFlashWithdrawal(
        address asset,
        uint256 amount
    )
        internal
        view
        virtual
        returns (uint256)
    {
        return _calculateFee(asset, amount, IVariableVaultFee.FeeOperation.FLASH_REDEEM, false);
    }

    /*//////////////////////////////////////////////////////////////
                      PRIVATE READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns a reference to the VaultFeeStorage struct.
     * @return $ Reference to the VaultFeeStorage struct.
     */
    function _getVaultFeeStorage() private pure returns (VaultFeeStorage storage $) {
        assembly {
            $.slot := VaultFeeStorageLocation
        }
    }
}
