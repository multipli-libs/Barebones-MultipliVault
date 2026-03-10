// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { MultipliVault } from "../vault/MultipliVault.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    ReentrancyGuardTransient
} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

/**
 * @title VaultFundManager
 * @notice A helper contract for managing vault fund operations including fund transfers and
 * redemption fulfillment
 * @dev This contract acts as an intermediary for vault operations that require careful balance
 * management.
 *      All functions are designed to be called through the vault's `manage` function,
 *      ensuring proper authorization (except `flashRedeem()`)
 *
 *      Key responsibilities:
 *      - Remove funds from vault while maintaining total asset consistency
 *      - Update underlying balance aggregations from strategies / exchanges.
 *      - Facilitate redemption fulfillment with proper balance adjustments
 *      - Handle flash redemptions for unwinding leveraged positions
 *
 *      Security model: Access control is enforced by requiring calls to originate from the vault
 * contract,
 *      which means they must go through the vault's `manage` function with proper authorization.
 *        Exception: `flashRedeem()`. For flashRedeem, the user and operator has to be added
 *        to the allowlist (`whitelistedUserOperator`)
 *
 * @custom:security-contact security@multipli.com
 */
contract VaultFundManager is ReentrancyGuardTransient {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Structure to capture vault state for validation
     * @dev Used to ensure state consistency before and after flash redemption operations
     * @param lastPricePerShare The last recorded price per share from vault
     * (`vault.lastPricePerShare()`)
     * @param priceOfOneShare Current price of one share calculated from convertToAssets
     * (`vault.convertToAssets(1e6)`)
     * @param totalAssets Total assets managed by the vault
     * @param totalSupply Total supply of vault shares
     * @param tokenBalance Current token balance held by the vault
     * @param aggregatedUnderlyingBalances Aggregated balances across external strategies
     */
    struct StateCheckVars {
        uint256 lastPricePerShare;
        uint256 priceOfOneShare;
        uint256 totalAssets;
        uint256 totalSupply;
        uint256 tokenBalance;
        uint256 aggregatedUnderlyingBalances;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The vault contract this manager is associated with
    MultipliVault public immutable vault;

    /// @notice The underlying asset managed by the vault
    address public immutable asset;

    /// @notice The mapping specifies if an address is a user is associated with an operator
    mapping(address user => mapping(address operator => bool enabled)) public
        whitelistedUserOperator;

    uint256 internal constant DENOMINATOR = 1e18;

    /// @notice Maximum total withdrawals allowed per epoch (24h) — anti-drainer cap
    uint256 public maxWithdrawalPerEpoch;

    /// @notice Running total of withdrawals in the current epoch
    uint256 public currentEpochWithdrawals;

    /// @notice Timestamp when the current epoch started
    uint256 public lastEpochReset;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when funds are removed from the vault
     * @param recipient The address receiving the funds
     * @param amount The amount of assets transferred
     * @param newAggregatedBalance The updated aggregated underlying balance
     */
    event FundsRemovedFromVault(
        address indexed recipient, uint256 amount, uint256 newAggregatedBalance
    );

    /**
     * @notice Emitted when underlying balance is updated
     * @param oldBalance The previous aggregated underlying balance
     * @param newBalance The updated aggregated underlying balance
     */
    event UnderlyingBalanceUpdated(uint256 oldBalance, uint256 newBalance);

    /**
     * @notice Emitted when funds are added and redemption is fulfilled
     * @param receiver The address receiving the redeemed assets
     * @param shares The amount of shares being redeemed
     * @param assetsWithFee The amount of assets transferred including fees
     * @param newAggregatedBalance The updated aggregated underlying balance
     */
    event FundsAddedAndRedemptionFulfilled(
        address indexed receiver,
        uint256 shares,
        uint256 assetsWithFee,
        uint256 newAggregatedBalance
    );

    /**
     * @notice Emitted when funds are added and redemption is fulfilled
     * @param initiator The address initiating the request
     * @param operator The address of the operator (responsible for paying back)
     * @param shares The amount of shares that were redeemed
     * @param assetsWithFee The amount that corresponds to the shares
     * @param newAggregatedBalance The updated aggregated underlying balance
     */
    event FundsAddedAndFlashRedemptionFulfilled(
        address indexed initiator,
        address indexed operator,
        uint256 shares,
        uint256 assetsWithFee,
        uint256 newAggregatedBalance
    );

    /**
     * @notice Emitted when an user operator whitelist is updated
     * @param user The address of the user
     * @param operator The address of the operator contract
     * @param enabled true/false -> specifies if the user is whitelisted or not.
     */
    event UpdateOperatorWhitelist(address user, address operator, bool enabled);

    /**
     * @notice Emitted when ERC20 assets are removed from the contract
     * @param to The address that received the funds
     * @param amount The amount of assets transferred
     */
    event RemoveFunds(address indexed to, uint256 amount);

    /**
     * @notice Emitted when the withdrawal cap is updated
     * @param oldCap The previous withdrawal cap
     * @param newCap The new withdrawal cap
     */
    event WithdrawalCapUpdated(uint256 oldCap, uint256 newCap);

    /**
     * @notice Emitted when native assets (ETH/AVAX) are removed from the contract
     * @param to The address that received the native funds
     * @param amount The amount of native assets transferred
     */
    event RemoveFundsNative(address indexed to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when an unauthorized address attempts to call a function
    error VaultFundManager__UnauthorizedCaller();

    /// @notice Thrown when the requested amount exceeds available balance
    error VaultFundManager__InsufficientBalance();

    /// @notice Thrown when the requested amount exceeds available balance
    error VaultFundManager__InsufficientAggregateUnderlyingBalance();

    /// @notice Thrown when total assets don't match before and after an operation
    error VaultFundManager__TotalAssetsMismatch();

    /// @notice Thrown when total assets don't match before and after an operation
    error VaultFundManager__TotalSupplyMismatch();

    /// @notice Thrown when expected aggregatedBalances does not match with current
    /// aggregatedBalances
    error VaultFundManager__AggregatedBalanceMismatch();

    /// @notice Thrown when a zero address is provided where it's not allowed
    error VaultFundManager__ZeroAddress();

    /// @notice Thrown when a zero amount is provided where it's not allowed
    error VaultFundManager__ZeroAmount();

    /// @notice Thrown when the aggregate balance invariant is violated
    error VaultFundManager__InvalidCurrentAggregateBalance();

    /// @notice Thrown when a native transfer fails
    error VaultFundManager__TransferFailed();

    /// @notice Thrown when lastPricePerShare slippage exceeds threshold after flash redemption
    error VaultFundManager__LastPricePerShareSlippageExceeded();

    /// @notice Thrown when priceOfOneShare slippage exceeds threshold after flash redemption
    error VaultFundManager__PriceOfOneShareSlippageExceeded();

    /// @notice Thrown when withdrawal amount exceeds the epoch cap
    error VaultFundManager__WithdrawalCapExceeded(uint256 requested, uint256 remaining);

    /// @notice Thrown when total assets are less than expected after flash redemption
    error VaultFundManager__TotalAssetsLessThanExpected();

    /// @notice Thrown when total supply is less than expected after flash redemption
    error VaultFundManager__TotalSupplyLessThanExpected();

    /// @notice Thrown when asset balance mismatches after flash redemption
    error VaultFundManager__AssetBalanceMismatch();

    /// @notice Thrown when underlying balance doesn't match expected after flash redemption
    error VaultFundManager__UnderlyingBalanceMismatch();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Ensures the function is called only through the vault's manage function
     * @dev This provides access control by leveraging the vault's authorization system
     */
    modifier onlyVault() {
        if (msg.sender != address(vault)) {
            revert VaultFundManager__UnauthorizedCaller();
        }
        _;
    }

    /**
     * @notice Ensures the user-operator combination is whitelisted
     * @param user The user address to check
     * @param operator The operator address to check
     * @dev Prevents unauthorized operators from being used by users
     */
    modifier isWhitelisted(address user, address operator) {
        if (!whitelistedUserOperator[user][operator]) {
            revert VaultFundManager__UnauthorizedCaller();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the VaultFundManager with the specified vault
     * @param _vaultAddr The address of the MultipliVault contract
     * @dev The vault address cannot be zero and must be a valid MultipliVault contract
     */
    constructor(address payable _vaultAddr) {
        if (_vaultAddr == address(0)) {
            revert VaultFundManager__ZeroAddress();
        }

        vault = MultipliVault(_vaultAddr);
        asset = vault.asset();
    }

    /*//////////////////////////////////////////////////////////////
                  USER-FACING STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the maximum withdrawal amount per 24-hour epoch
     * @param newCap The new max withdrawal per epoch (0 = no cap)
     * @dev Can only be called through the vault's manage function
     */
    function setMaxWithdrawalPerEpoch(uint256 newCap) external onlyVault {
        emit WithdrawalCapUpdated(maxWithdrawalPerEpoch, newCap);
        maxWithdrawalPerEpoch = newCap;
    }

    /**
     * @notice Updates the whitelist status for a user-operator combination
     * @param user The user address
     * @param operator The operator contract address
     * @param enable True to enable, false to disable the combination
     * @dev Can only be called through the vault's manage function
     * @custom:throws ZeroAddress if user or operator is address(0)
     */
    function updateUserOperatorWhitelist(
        address user,
        address operator,
        bool enable
    )
        external
        onlyVault
    {
        if (user == address(0) || operator == address(0)) {
            revert VaultFundManager__ZeroAddress();
        }

        whitelistedUserOperator[user][operator] = enable;
        emit UpdateOperatorWhitelist(user, operator, enable);
    }

    /**
     * @notice Removes funds from the vault while maintaining total asset consistency
     * @dev This function transfers assets from the vault to a recipient and updates the aggregated
     *      underlying balances to maintain the same total asset value. This is typically used when
     *      moving funds to exchange wallet.
     *
     *      The operation maintains the invariant: totalAssets(before) == totalAssets(after)
     *
     * @param recipient The address to receive the funds (must be whitelisted in vault)
     * @param amount The amount of assets to transfer
     *
     * @custom:throws ZeroAddress if recipient is address(0)
     * @custom:throws ZeroAmount if amount is 0
     * @custom:throws InsufficientBalance if amount exceeds vault balance
     * @custom:throws TotalAssetsMismatch if total assets change after operation
     *
     * Requirements:
     * - Can only be called through vault's manage function
     * - Amount must not exceed vault's asset balance
     * - Recipient must be whitelisted in the vault for fund transfers
     * - Total assets must remain constant after operation
     */
    function removeFundsFromVault(
        address recipient,
        uint256 amount
    )
        external
        nonReentrant
        onlyVault
    {
        if (recipient == address(0)) revert VaultFundManager__ZeroAddress();
        if (amount == 0) revert VaultFundManager__ZeroAmount();
        _enforceWithdrawalCap(amount);

        uint256 balance = IERC20(asset).balanceOf(address(vault));
        if (amount > balance) revert VaultFundManager__InsufficientBalance();

        uint256 oldAggregatedUnderlyingBalances = vault.aggregatedUnderlyingBalances();
        uint256 oldTotalAssetsValue = vault.totalAssets();
        uint256 oldTotalSupplyValue = vault.totalSupply();

        // Remove funds from vault and update aggregated balance to maintain total assets
        vault.removeFunds(amount, recipient);
        uint256 newAggregatedBalance = oldAggregatedUnderlyingBalances + amount;
        vault.onUnderlyingBalanceUpdate(newAggregatedBalance);

        // Verify total assets remain unchanged
        if (oldTotalAssetsValue != vault.totalAssets()) {
            revert VaultFundManager__TotalAssetsMismatch();
        }

        // sanity check: total number of shares must remain unchanged
        if (oldTotalSupplyValue != vault.totalSupply()) {
            revert VaultFundManager__TotalSupplyMismatch();
        }

        emit FundsRemovedFromVault(recipient, amount, newAggregatedBalance);
    }

    /**
     * @notice Updates the aggregated underlying balance with new values from external strategies
     * @dev This function is called periodically to update the vault's understanding of assets
     *      held in external strategies. The newAggregatedBalance should include both
     *      principal and any yield generated.
     *
     * @param oldAggregatedBalance The expected current balance (for safety check)
     * @param newAggregatedBalance The new total balance across all external strategies (principal +
     * yield)
     *
     * @custom:throws AggregatedBalanceMismatch if current balance doesn't match expected
     *
     * Requirements:
     * - Can only be called through vault's manage function
     * - Should be called periodically by authorized operators to reflect current external balances
     */
    function updateUnderlyingBalance(
        uint256 oldAggregatedBalance,
        uint256 newAggregatedBalance
    )
        external
        nonReentrant
        onlyVault
    {
        uint256 oldBalance = vault.aggregatedUnderlyingBalances();
        if (oldBalance != oldAggregatedBalance) {
            revert VaultFundManager__AggregatedBalanceMismatch();
        }

        vault.onUnderlyingBalanceUpdate(newAggregatedBalance);

        emit UnderlyingBalanceUpdated(oldBalance, newAggregatedBalance);
    }

    /**
     * @notice Adds funds to the vault and fulfills a pending redemption request
     * @dev This function facilitates redemption by first transferring the required assets to the
     * vault,
     *      updating the aggregated balance to account for the asset movement, and then fulfilling
     *      the redemption request. This three-step process ensures price stability and prevents
     *      sandwich attacks.
     *
     *      The operation flow:
     *      1. Transfer assets from this contract to the vault
     *      2. Fulfill the redemption request
     *      3. Update aggregated balance to reflect the asset movement from external strategies
     *
     *      This maintains the share price consistency throughout the operation.
     *
     * @param receiver The address that will receive the redeemed assets
     * @param shares The number of shares being redeemed
     * @param assetsWithFee The amount of assets to transfer (including any applicable fees)
     *
     * @custom:throws ZeroAddress if receiver is address(0)
     * @custom:throws ZeroAmount if shares or assetsWithFee is 0
     * @custom:throws InsufficientBalance if this contract doesn't have enough assets
     *
     * Requirements:
     * - Can only be called through vault's manage function
     * - This contract must hold sufficient assets for the transfer
     * - The receiver must have a valid pending redemption request in the vault
     * - Shares and assetsWithFee must match the pending redemption request
     */
    function addFundsAndFulfillRedeem(
        address receiver,
        uint256 shares,
        uint256 assetsWithFee
    )
        external
        nonReentrant
        onlyVault
    {
        if (receiver == address(0)) revert VaultFundManager__ZeroAddress();
        if (shares == 0 || assetsWithFee == 0) revert VaultFundManager__ZeroAmount();

        uint256 contractBalance = IERC20(asset).balanceOf(address(this));
        if (assetsWithFee > contractBalance) revert VaultFundManager__InsufficientBalance();

        uint256 oldAggregatedUnderlyingBalances = vault.aggregatedUnderlyingBalances();
        if (assetsWithFee > oldAggregatedUnderlyingBalances) {
            revert VaultFundManager__InsufficientAggregateUnderlyingBalance();
        }

        // Step 1: Transfer the required assets from this contract to the vault
        IERC20(asset).safeTransfer(address(vault), assetsWithFee);

        // Step 2: Fulfill the redemption request
        vault.fulfillRedeem(receiver, shares, assetsWithFee);

        // Step 3: Update the aggregated balance to reflect assets moved from external strategies
        uint256 newAggregatedBalance = oldAggregatedUnderlyingBalances - assetsWithFee;
        vault.onUnderlyingBalanceUpdate(newAggregatedBalance);

        emit FundsAddedAndRedemptionFulfilled(receiver, shares, assetsWithFee, newAggregatedBalance);
    }

    /**
     * @notice Executes a flash redemption for unwinding leveraged positions
     * @param operator The operator contract that will handle position unwinding
     * @param shares The number of shares to redeem via flash redemption
     * @param data Additional data to pass to the operator callback
     * @dev This function enables users to unwind leveraged positions by providing temporary
     *      liquidity to close positions on external protocols (like Euler). The operator
     *      receives USDC upfront and must return the equivalent vault shares.
     *
     *      Process:
     *      1. Validate user-operator whitelist
     *      2. Transfer USDC to vault
     *      3. Update underlying balance
     *      4. Call vault's flashRedeem which callbacks to operator
     *      5. Validate state changes within acceptable slippage
     *
     * @custom:throws ZeroAddress if operator is address(0)
     * @custom:throws ZeroAmount if shares or assetsWithFee is 0
     * @custom:throws InsufficientBalance if contract doesn't have enough assets
     * @custom:throws UnauthorizedCaller if user-operator combination not whitelisted
     *
     * Requirements:
     * - User-operator combination must be whitelisted
     * - Contract must have sufficient USDC balance
     * - Aggregated underlying balance must be sufficient
     * - State changes must be within 0.5% slippage tolerance
     */
    function flashRedeem(
        address operator,
        uint256 shares,
        bytes calldata data
    )
        external
        nonReentrant
        isWhitelisted(msg.sender, operator)
    {
        StateCheckVars memory initialStateVars;
        StateCheckVars memory finalStateVars;

        address initiator = msg.sender;

        if (operator == address(0)) revert VaultFundManager__ZeroAddress();

        uint256 assetsWithFee = vault.convertToAssets(shares);
        if (shares == 0 || assetsWithFee == 0) revert VaultFundManager__ZeroAmount();

        uint256 contractBalance = IERC20(asset).balanceOf(address(this));
        if (assetsWithFee > contractBalance) revert VaultFundManager__InsufficientBalance();

        // record the snapshot of the necessary state variables
        initialStateVars = _captureCurrentStateInformation();

        // When this happens, this means the vault is new (`onUnderlyingBalanceUpdate` has not been
        // called) or when the value of `onUnderlyingBalanceUpdate` was set as 0 which means the
        // vault has lost all it's value
        // Adding it here, so we fail fast. As part of step2: we deduct the totalAssets() value by
        // calling `onUnderlyingBalanceUpdate`
        if (
            initialStateVars.aggregatedUnderlyingBalances == 0
                || initialStateVars.aggregatedUnderlyingBalances < assetsWithFee
        ) {
            revert VaultFundManager__InvalidCurrentAggregateBalance();
        }

        // Step 1: Transfer the required assets from this contract to the vault
        IERC20(asset).safeTransfer(address(vault), assetsWithFee);

        // Step 2: Fulfill the redemption request
        vault.flashRedeem({
            initiator: initiator,
            operator: operator,
            receiver: operator,
            shares: shares,
            assetsWithFee: assetsWithFee,
            data: data
        });

        // Step 3: Update the aggregated balance to reflect assets moved from external strategies
        uint256 newAggregatedBalance = initialStateVars.aggregatedUnderlyingBalances - assetsWithFee;
        vault.onUnderlyingBalanceUpdate(newAggregatedBalance);

        emit FundsAddedAndFlashRedemptionFulfilled(
            initiator, operator, shares, assetsWithFee, newAggregatedBalance
        );

        finalStateVars = _captureCurrentStateInformation();
        _validateStateChanges(initialStateVars, finalStateVars, assetsWithFee, shares);
    }

    /**
     * @notice Removes ERC20 assets from the contract and transfers them to a specified address
     * @dev This function can only be called by the vault contract through the manage function.
     *      It's typically used to move funds to exchanges for delta neutral strategies or to
     *      whitelisted addresses for operational purposes. The initiator parameter allows
     *      tracking which authorized operator initiated the fund movement for audit purposes.
     *
     * @param to The address to receive the funds
     * @param amount The amount of assets to transfer
     *
     * @custom:throws ZeroAddress if `to` is the zero address
     * @custom:throws ZeroAmount if `amount` is zero
     *
     * Requirements:
     * - Can only be called by the vault contract
     * - `to` address must not be zero
     * - `amount` must be greater than zero
     * - Contract must have sufficient balance of the asset
     * - `to` address must be whitelisted by the vault for fund transfers
     *
     * @custom:emits RemoveFunds
     */
    function removeFunds(address to, uint256 amount) external onlyVault {
        if (to == address(0)) revert VaultFundManager__ZeroAddress();
        if (amount == 0) revert VaultFundManager__ZeroAmount();
        _enforceWithdrawalCap(amount);

        uint256 balance = IERC20(asset).balanceOf(address(this));
        if (balance < amount) revert VaultFundManager__InsufficientBalance();

        IERC20(asset).safeTransfer(to, amount);
        emit RemoveFunds(to, amount);
    }

    /**
     * @notice Removes native assets (ETH/AVAX) from the contract and transfers them to a specified
     * address
     * @dev This function can only be called by the vault contract through the manage function.
     *      It's used to transfer native blockchain assets
     *      for operational purposes such as paying gas fees or moving native assets to exchanges.
     *
     * @param to The address to receive the native funds (must be whitelisted by the vault)
     * @param amount The amount of native assets to transfer (in wei)
     *
     * @custom:throws ZeroAddress if `to` is the zero address
     * @custom:throws ZeroAmount if `amount` is zero
     *
     * Requirements:
     * - Can only be called by the vault contract
     * - `to` address must not be zero
     * - `amount` must be greater than zero
     * - Contract must have sufficient native asset balance
     * - `to` address must be whitelisted by the vault for fund transfers
     *
     * @custom:security Consider adding return value checking for the low-level call
     * @custom:emits RemoveFundsNative
     */
    function removeFundsNative(address to, uint256 amount) external onlyVault {
        if (to == address(0)) revert VaultFundManager__ZeroAddress();
        if (amount == 0) revert VaultFundManager__ZeroAmount();

        uint256 balance = address(this).balance;
        if (balance < amount) revert VaultFundManager__InsufficientBalance();

        (bool success,) = to.call{ value: amount }("");
        if (!success) revert VaultFundManager__TransferFailed();

        emit RemoveFundsNative(to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                    USER-FACING READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the current asset balance held by this contract
     * @return balance The amount of assets currently held by this contract
     */
    function getContractAssetBalance() external view returns (uint256 balance) {
        return IERC20(asset).balanceOf(address(this));
    }

    /**
     * @notice Returns the current aggregated underlying balances from the vault
     * @return aggregatedBalance The current aggregated underlying balances
     */
    function getAggregatedUnderlyingBalances() external view returns (uint256 aggregatedBalance) {
        return vault.aggregatedUnderlyingBalances();
    }

    /**
     * @notice Returns the total assets managed by the vault
     * @return totalAssets The total assets (vault balance + aggregated underlying balances)
     */
    function getTotalAssets() external view returns (uint256 totalAssets) {
        return vault.totalAssets();
    }

    /*//////////////////////////////////////////////////////////////
                      PRIVATE READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Enforce per-epoch withdrawal cap (anti-drainer protection)
     * @param amount The withdrawal amount to check
     * @dev Resets the epoch counter if 24 hours have passed since last reset.
     *      If maxWithdrawalPerEpoch is 0, the cap is disabled.
     */
    function _enforceWithdrawalCap(uint256 amount) private {
        uint256 cap = maxWithdrawalPerEpoch;
        if (cap == 0) return;

        if (block.timestamp > lastEpochReset + 24 hours) {
            currentEpochWithdrawals = 0;
            lastEpochReset = block.timestamp;
        }

        uint256 remaining = cap - currentEpochWithdrawals;
        if (amount > remaining) {
            revert VaultFundManager__WithdrawalCapExceeded(amount, remaining);
        }

        currentEpochWithdrawals += amount;
    }

    /**
     * @notice Calculate the percentage change between two prices
     * @param oldPrice The previous price
     * @param newPrice The new price
     * @return The percentage change (1e18 = 100%)
     * @dev Used to detect excessive price volatility and trigger emergency pause
     */
    function _calculatePercentageChange(
        uint256 oldPrice,
        uint256 newPrice
    )
        private
        pure
        returns (uint256)
    {
        if (oldPrice == 0) {
            return 0;
        }
        uint256 diff = newPrice > oldPrice ? newPrice - oldPrice : oldPrice - newPrice;
        return diff.mulDiv(DENOMINATOR, oldPrice, Math.Rounding.Ceil);
    }

    /**
     * @notice Captures current vault state information for validation
     * @return stateVars Struct containing current state variables
     * @dev Used to ensure state consistency before and after flash redemption operations
     */
    function _captureCurrentStateInformation()
        private
        view
        returns (StateCheckVars memory stateVars)
    {
        uint256 decimals = vault.decimals();

        // store the values before initiating the operation
        stateVars.lastPricePerShare = vault.lastPricePerShare();
        stateVars.priceOfOneShare = vault.convertToAssets(10 ** decimals); // Ideally,
        // lastPricePerShareBefore = priceOfOneShareBefore
        stateVars.totalAssets = vault.totalAssets();
        stateVars.totalSupply = vault.totalSupply();
        stateVars.tokenBalance = IERC20(asset).balanceOf(address(vault));
        stateVars.aggregatedUnderlyingBalances = vault.aggregatedUnderlyingBalances();
        return stateVars;
    }

    /**
     * @notice Validates state changes after flash redemption operations
     * @param initialState The state before the operation
     * @param finalState The state after the operation
     * @param assetsWithFee The amount of assets involved in the operation
     * @param shares The amount of shares involved in the operation
     * @dev Ensures that state changes are within acceptable tolerance (0.1% slippage)
     *      and that invariants are maintained
     *
     * Requirements:
     * - Price per share slippage must be < 0.1%
     * - Total assets must not decrease unexpectedly
     * - Total supply must not decrease unexpectedly
     * - Token balance must not decrease
     * - Underlying balance changes must match expected amounts
     */
    function _validateStateChanges(
        StateCheckVars memory initialState,
        StateCheckVars memory finalState,
        uint256 assetsWithFee,
        uint256 shares
    )
        private
        pure
    {
        // 1e15 => 0.1%
        if (
            _calculatePercentageChange(initialState.lastPricePerShare, finalState.lastPricePerShare)
                >= 1e15
        ) {
            revert VaultFundManager__LastPricePerShareSlippageExceeded();
        }

        if (
            _calculatePercentageChange(initialState.priceOfOneShare, finalState.priceOfOneShare)
                >= 1e15
        ) {
            revert VaultFundManager__PriceOfOneShareSlippageExceeded();
        }

        if (initialState.totalAssets - assetsWithFee > finalState.totalAssets) {
            revert VaultFundManager__TotalAssetsLessThanExpected();
        }

        if (initialState.totalSupply - shares > finalState.totalSupply) {
            revert VaultFundManager__TotalSupplyLessThanExpected();
        }

        // `tokenBalanceBefore` will always be equal to `tokenBalanceAfter`. But the operator can
        // decide to send in additional `assets` to the vault
        if (initialState.tokenBalance > finalState.tokenBalance) {
            revert VaultFundManager__AssetBalanceMismatch();
        }

        if (
            initialState.aggregatedUnderlyingBalances
                != finalState.aggregatedUnderlyingBalances + assetsWithFee
        ) {
            revert VaultFundManager__UnderlyingBalanceMismatch();
        }
    }
}
