// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title FundMovementHelperUpgradeable
 * @notice Abstract contract providing fund transfer functionality with recipient whitelisting
 * @dev This contract implements a whitelist-based fund transfer system for upgradeable contracts.
 * It allows authorized users to transfer funds only to pre-approved recipients.
 *
 * Key features:
 * - Recipient whitelisting mechanism
 * - Safe ERC20 token transfers
 * - Upgradeable storage pattern using ERC-7201
 * - Event emission for transparency
 *
 * @custom:security-contact security@multipli.com
 */
abstract contract FundMovementHelperUpgradeable is Initializable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/

    /// @custom:storage-location erc7201:multipli.storage.FundMovementHelperStorage
    struct FundMovementHelperStorage {
        /// @dev Mapping to track whitelisted fund transfer recipients
        mapping(address => bool) whitelistedRecipients;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    // Storage slot for the FundMovementHelperStorage struct.
    // keccak256(abi.encode(uint256(keccak256("multipli.storage.FundMovementHelperStorage")) - 1)) &
    // ~bytes32(uint256(0xff))
    bytes32 private constant FUND_MOVEMENT_STORAGE_LOCATION =
        0x2bbdf87c296f0fc445d947563c77d7b805fc738a2e220084769a264d45deaf00;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when funds are removed from the contract
     * @param initiator The address that initiated the fund removal
     * @param asset The address of the asset being transferred
     * @param amount The amount of assets transferred
     * @param recipient The address receiving the funds
     */
    event FundsRemoved(
        address indexed initiator, address indexed asset, uint256 amount, address indexed recipient
    );

    /**
     * @notice Emitted when a user's whitelist status is updated
     * @param initiator The address that initiated the whitelist update
     * @param recipient The address whose whitelist status was updated
     * @param isWhitelisted The new whitelist status (true = whitelisted, false = removed)
     */
    event WhitelistUpdated(
        address indexed initiator, address indexed recipient, bool isWhitelisted
    );

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when attempting to set the same whitelist status for a user
    error FundMovementHelper__NoChangeInWhitelistStatus();

    /// @notice Thrown when attempting to transfer zero amount
    error FundMovementHelper__AmountZero();

    /// @notice Thrown when attempting to transfer to a non-whitelisted recipient
    error FundMovementHelper__RecipientNotWhitelisted();

    /// @notice Thrown when address is 0 (address(0))
    error FundMovementHelper__AddressZero();

    /*//////////////////////////////////////////////////////////////
                    USER-FACING READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Checks if a user is whitelisted as a fund transfer recipient
     * @param user The address to check
     * @return isWhitelisted True if the user is whitelisted, false otherwise
     */
    function isRecipientWhitelisted(address user) public view returns (bool isWhitelisted) {
        FundMovementHelperStorage storage $ = _getFundMovementHelperStorage();
        return $.whitelistedRecipients[user];
    }

    /*//////////////////////////////////////////////////////////////
                      INTERNAL STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the FundMovementHelper contract
     * @dev This function should be called during contract initialization
     */
    function __FundMovementHelper_init() internal onlyInitializing {
        __FundMovementHelper_init_unchained();
    }

    /**
     * @notice Unchained initializer for FundMovementHelper
     * @dev Contains the actual initialization logic
     */
    function __FundMovementHelper_init_unchained() internal onlyInitializing {
        // No initialization logic needed currently
    }

    /**
     * @notice Updates the whitelist status of a fund transfer recipient
     * @dev This method is expected to be called from the inheriting contract with proper access
     * controls
     * @param user The address to update whitelist status for
     * @param isWhitelisted True to whitelist the user, false to remove from whitelist
     */
    function _whitelistFundTransferRecipient(address user, bool isWhitelisted) internal virtual {
        FundMovementHelperStorage storage $ = _getFundMovementHelperStorage();

        if (user == address(0)) {
            revert FundMovementHelper__AddressZero();
        }

        if ($.whitelistedRecipients[user] == isWhitelisted) {
            revert FundMovementHelper__NoChangeInWhitelistStatus();
        }

        $.whitelistedRecipients[user] = isWhitelisted;
        emit WhitelistUpdated(msg.sender, user, isWhitelisted);
    }

    /**
     * @notice Removes funds from the contract and transfers them to a whitelisted recipient
     * @dev This method should be called from the inheriting contract with proper access controls
     * @param asset The address of the ERC20 token to transfer
     * @param amount The amount of tokens to transfer
     * @param recipient The address to receive the funds (must be whitelisted)
     */
    function _removeFunds(address asset, uint256 amount, address recipient) internal virtual {
        if (amount == 0) {
            revert FundMovementHelper__AmountZero();
        }
        if (!isRecipientWhitelisted(recipient)) {
            revert FundMovementHelper__RecipientNotWhitelisted();
        }

        IERC20(asset).safeTransfer(recipient, amount);
        emit FundsRemoved(msg.sender, asset, amount, recipient);
    }

    /*//////////////////////////////////////////////////////////////
                      PRIVATE READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns a reference to the FundMovementHelperStorage struct
     * @return $ Reference to the FundMovementHelperStorage struct
     */
    function _getFundMovementHelperStorage()
        private
        pure
        returns (FundMovementHelperStorage storage $)
    {
        assembly {
            $.slot := FUND_MOVEMENT_STORAGE_LOCATION
        }
    }
}
