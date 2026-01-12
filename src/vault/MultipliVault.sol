// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Errors } from "../libraries/Errors.sol";
import { IMultipliVault } from "../interfaces/IMultipliVault.sol";
import { IVariableVaultFee } from "../interfaces/IVariableVaultFee.sol";
import { IMultipliVaultCallee } from "../interfaces/IMultipliVaultCallee.sol";

import { VaultFeeUpgradeable } from "../base/VaultFeeUpgradeable.sol";
import { AuthUpgradeable, Authority } from "../base/AuthUpgradeable.sol";
import { FundMovementHelperUpgradeable } from "../base/FundMovementHelperUpgradeable.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    ERC4626Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {
    PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title MultipliVault
 * @author Multipli Team
 * @notice A vault contract that enables an operator to manage vault assets asynchronously
 * @dev Implements the ERC4626 standard with Auth contract for access control and ERC-7201 storage pattern
 *
 * The contract provides a redeem request mechanism that allows users to initiate a redeem request,
 * and the operator to fulfill it at a later time. This mechanism is particularly useful for scenarios
 * where the operator needs to move assets across chains or to different strategies before settling
 * the user's redemption request. Upon fulfillment, assets are transferred to the vault, and the request
 * is marked as complete.
 *
 * @custom:security-contact security@multipli.com
 */
contract MultipliVault is
    UUPSUpgradeable,
    ERC4626Upgradeable,
    IMultipliVault,
    AuthUpgradeable,
    PausableUpgradeable,
    VaultFeeUpgradeable,
    FundMovementHelperUpgradeable,
    ReentrancyGuardUpgradeable
{
    using Math for uint256;
    using Address for address;
    using SafeERC20 for IERC20;

    //============================== TYPES ===============================

    /**
     * @notice Enum defining different types of redemption requests
     * @dev Used to handle different redemption flows with varying fee structures and processing methods
     */
    enum RedeemType {
        NORMAL, // Standard redemption with regular fees
        INSTANT // Fast-forward redemption with higher fees
    }

    /**
     * @notice Internal struct for request parameters
     * @dev Used to pass redemption request data between functions
     * @param shares The amount of shares to redeem
     * @param receiver The address that will receive the assets
     * @param owner The address that owns the shares
     * @param redeemType The type of redemption (NORMAL or INSTANT)
     */
    struct RedeemParams {
        uint256 shares;
        address receiver;
        address owner;
        RedeemType redeemType;
    }

    /**
     * @notice Internal struct for fulfillment parameters
     * @dev Used to pass fulfillment data between functions
     * @param receiver The address that will receive the assets
     * @param shares The amount of shares being fulfilled
     * @param assetsWithFee The amount of assets including fees
     * @param redeemType The type of redemption being fulfilled
     */
    struct FulfillParams {
        address receiver;
        uint256 shares;
        uint256 assetsWithFee;
        RedeemType redeemType;
    }

    /**
     * @custom:storage-location erc7201:multipli.storage.MultipliVaultStorage
     * @dev Structure to hold MultipliVault storage data following ERC-7201 standard
     */
    struct MultipliVaultStorage {
        /// @dev The aggregated underlying balances across all strategies/chains, reported by an oracle
        uint256 aggregatedUnderlyingBalances;
        /// @dev The last block number when the aggregated underlying balances were updated
        uint256 lastBlockUpdated;
        /// @dev The last price per share calculated after the aggregated underlying balances are reported
        uint256 lastPricePerShare;
        /// @dev The total amount of assets that are pending redemption
        uint256 totalPendingAssets;
        /// @dev The maximum percentage change allowed before the vault is paused
        uint256 maxPercentageChange;
        /// @dev Minimum deposit amount required for deposits and mints
        uint256 minDepositAmount;
        /// @dev Mapping to store pending redemption requests for each user
        mapping(address user => PendingRedeem redeem) pendingRedeem;
    }

    //============================== CONSTANTS ===============================

    /// @dev Assume requests are non-fungible and all have ID = 0, so we can differentiate between a request ID and the assets amount
    uint256 internal constant REQUEST_ID = 0;

    /// @dev The denominator used for precision calculations (1e18 = 100%)
    uint256 internal constant DENOMINATOR = 1e18;

    /// @dev The maximum percentage that can be set as a threshold for the percentage change (1e17 = 10%)
    uint256 internal constant MAX_PERCENTAGE_THRESHOLD = 1e17;

    //============================== STORAGE ===============================

    // Storage slot for the MultipliVaultStorage struct.
    // keccak256(abi.encode(uint256(keccak256("multipli.storage.MultipliVaultStorage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MULTIPLI_VAULT_STORAGE_LOCATION =
        0x5c514b81e93a4e64ed3b3d78d8355319d5f0f527b3964e825d59f3a9d74af900;

    //============================== CONSTRUCTOR ===============================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    //============================== INITIALIZER ===============================

    /**
     * @notice Initializes the MultipliVault contract
     * @param _asset The underlying ERC20 asset for the vault
     * @param _owner The initial owner of the vault
     * @param _name The name of the vault token
     * @param _symbol The symbol of the vault token
     */
    function initialize(
        IERC20 _asset,
        address _owner,
        string memory _name,
        string memory _symbol
    )
        public
        initializer
    {
        __MultipliVault_init(_asset, _owner, _name, _symbol);
    }

    /**
     * @notice Initializes the MultipliVault contract
     * @dev This function should be called during contract initialization
     * @param _asset The underlying ERC20 asset for the vault
     * @param _owner The initial owner of the vault
     * @param _name The name of the vault token
     * @param _symbol The symbol of the vault token
     */
    function __MultipliVault_init(
        IERC20 _asset,
        address _owner,
        string memory _name,
        string memory _symbol
    )
        internal
        onlyInitializing
    {
        __ERC20_init(_name, _symbol);
        __ERC4626_init(_asset);
        __Auth_init(_owner, Authority(address(0)));
        __Pausable_init();
        __VaultFeeUpgreadable_init(IVariableVaultFee(address(0)));
        __FundMovementHelper_init();
        __ReentrancyGuard_init();
        __MultipliVault_init_unchained();
    }

    /**
     * @notice Unchained initializer for MultipliVault
     * @dev Contains the actual initialization logic for MultipliVault-specific storage
     */
    /// @custom:oz-upgrades-unsafe-allow missing-initializer-call
    // reference: https://forum.openzeppelin.com/t/potential-false-positive-missing-initializer-calls-for-one-or-more-parent-contracts/43911/3
    function __MultipliVault_init_unchained() internal onlyInitializing {
        MultipliVaultStorage storage $ = _getMultipliVaultStorage();
        $.maxPercentageChange = 1e16; // 1%
        $.minDepositAmount = 0;
    }

    //============================== PUBLIC FUNCTIONS ===============================

    /**
     * @notice Allows the vault operator to manage the vault by calling external contracts
     * @param target The target contract to make a call to
     * @param data The data to send to the target contract
     * @param value The amount of native assets to send with the call
     * @return result The return data from the external call
     * @dev Requires authorization and target method must be authorized by the authority
     */
    function manage(
        address target,
        bytes calldata data,
        uint256 value
    )
        external
        requiresAuth
        returns (bytes memory result)
    {
        bytes4 functionSig = bytes4(data);
        require(
            authority().canCall(msg.sender, target, functionSig),
            Errors.TargetMethodNotAuthorized(target, functionSig)
        );

        result = target.functionCallWithValue(data, value);
    }

    /**
     * @notice Same as `manage` but allows for multiple calls in a single transaction
     * @param targets The target contracts to make calls to
     * @param data The data to send to the target contracts
     * @param values The amounts of native assets to send with the calls
     * @return results Array of return data from the external calls
     * @dev Requires authorization and all target methods must be authorized by the authority
     */
    function manage(
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values
    )
        external
        requiresAuth
        returns (bytes[] memory results)
    {
        uint256 targetsLength = targets.length;
        require(
            targetsLength == data.length && data.length == values.length, "Array lengths must match"
        );
        results = new bytes[](targetsLength);
        for (uint256 i; i < targetsLength; ++i) {
            bytes4 functionSig = bytes4(data[i]);
            require(
                authority().canCall(msg.sender, targets[i], functionSig),
                Errors.TargetMethodNotAuthorized(targets[i], functionSig)
            );
            results[i] = targets[i].functionCallWithValue(data[i], values[i]);
        }
    }

    /**
     * @notice Pause the contract to prevent any further deposits, withdrawals, or transfers
     * @dev Can only be called by authorized users
     */
    function pause() public requiresAuth {
        _pause();
    }

    /**
     * @notice Unpause the contract to allow deposits, withdrawals, and transfers
     * @dev Can only be called by authorized users
     */
    function unpause() public requiresAuth {
        _unpause();
    }

    /**
     * @notice Whitelist or remove a user from the fund transfer recipient list
     * @param user The address to update whitelist status for
     * @param status True to whitelist, false to remove from whitelist
     * @dev Can only be called by authorized users
     */
    function whitelistFundTransferRecipient(address user, bool status) public requiresAuth {
        _whitelistFundTransferRecipient(user, status);
    }

    /**
     * @notice Remove funds from the vault to a whitelisted recipient
     * @param amount The amount of assets to transfer
     * @param to The address to receive the funds (must be whitelisted)
     * @dev Can only be called by authorized users
     */
    function removeFunds(uint256 amount, address to) public requiresAuth {
        _removeFunds(asset(), amount, to);
    }

    /**
     * @notice Request a standard redemption of shares
     * @param shares The amount of shares to redeem
     * @param receiver The address that will receive the assets
     * @param owner The address that owns the shares
     * @return requestId The ID of the request (always 0)
     * @dev Transfers shares to the vault and stores the request for later fulfillment
     */
    function requestRedeem(
        uint256 shares,
        address receiver,
        address owner
    )
        external
        whenNotPaused
        returns (uint256)
    {
        return _processRedeemRequest(RedeemParams(shares, receiver, owner, RedeemType.NORMAL));
    }

    /**
     * @notice Request an instant redemption of shares (requires authorization)
     * @param shares The amount of shares to redeem instantly
     * @param receiver The address that will receive the assets
     * @param owner The address that owns the shares
     * @return requestId The ID of the request (always 0)
     * @dev Only authorized users (external curators) can call this function
     */
    function requestInstantRedeem(
        uint256 shares,
        address receiver,
        address owner
    )
        external
        whenNotPaused
        requiresAuth
        returns (uint256)
    {
        return _processRedeemRequest(RedeemParams(shares, receiver, owner, RedeemType.INSTANT));
    }

    /**
     * @notice Fulfill a standard redemption request
     * @param receiver The address that will receive the assets
     * @param shares The amount of shares to fulfill
     * @param assetsWithFee The amount of assets to transfer (including fees)
     * @dev Can only be called by authorized operators
     */
    function fulfillRedeem(
        address receiver,
        uint256 shares,
        uint256 assetsWithFee
    )
        external
        requiresAuth
    {
        _processFulfillment(FulfillParams(receiver, shares, assetsWithFee, RedeemType.NORMAL));
    }

    /**
     * @notice Fulfill an instant redemption request
     * @param receiver The address that will receive the assets
     * @param shares The amount of shares to fulfill
     * @param assetsWithFee The amount of assets to transfer (including fees)
     * @dev Can only be called by authorized operators
     */
    function fulfillInstantRedeem(
        address receiver,
        uint256 shares,
        uint256 assetsWithFee
    )
        external
        requiresAuth
    {
        _processFulfillment(FulfillParams(receiver, shares, assetsWithFee, RedeemType.INSTANT));
    }

    /**
     * @notice Flash redemption for unwinding leveraged positions
     * @dev Provides USDC upfront, expects equivalent xUSDC shares back after external operator call
     * @param initiator The address that originally initiated the request
     * @param operator The contract that will handle position unwinding on Euler
     * @param receiver The address that will receive the USDC (usually the user)
     * @param shares The amount of shares to redeem (total position size)
     * @param data Additional data for the operator callback
     */
    function flashRedeem(
        address initiator,
        address operator,
        address receiver,
        uint256 shares,
        bytes calldata data
    )
        external
        whenNotPaused
        requiresAuth
        nonReentrant
    {
        // Input validation
        require(shares > 0, Errors.SharesAmountZero());
        require(receiver != address(0), Errors.InvalidReceiverAddress());
        require(operator != address(0), Errors.InvalidOperatorAddress());

        address token = asset();

        // Calculate assets and fees
        uint256 assetsWithFee = convertToAssets(shares);
        uint256 fee = _feeOnTotalFlashWithdrawal(token, assetsWithFee); // Use flash Redeem withdrawal fee
        uint256 assetsWithoutFee = assetsWithFee - fee;

        // Check vault has sufficient liquidity
        uint256 vaultBalance = IERC20(token).balanceOf(address(this));
        require(vaultBalance >= assetsWithFee, Errors.InvalidAssetsAmount());

        uint256 shareBalanceBefore = balanceOf(address(this));
        uint256 totalSupplyBefore = totalSupply();

        // Transfer USDC to receiver pre-emptively
        IERC20(token).safeTransfer(receiver, assetsWithoutFee);

        // Invoke the operator to transfer the shares back to the vault
        IMultipliVaultCallee(operator)
            .onRedemptionFlashLoan(initiator, address(this), token, shares, assetsWithoutFee, data);

        {
            // Verify the operator returned the required shares
            uint256 shareBalanceAfter = balanceOf(address(this));
            require(shareBalanceAfter >= shareBalanceBefore + shares, Errors.SharesNotReturned());
        }

        // Burn the returned shares (completing the redemption)
        _burn(address(this), shares);

        {
            // note: totalSupply check was added before re-entrancy
            // guard was added to `flashRedeem` method, is this still required?

            // Verify total supply decreased correctly
            require(totalSupply() == totalSupplyBefore - shares, Errors.TotalSupplyMismatch());

            // Verify the `asset` balance after redemption
            uint256 tokenBalanceAfter = IERC20(token).balanceOf(address(this));
            require(
                vaultBalance - assetsWithFee <= tokenBalanceAfter, Errors.AssetBalanceMismatch()
            );
        }

        // Transfer fee to fee recipient
        address feeRecipient = _getFeeRecipient(token);
        if (fee > 0 && feeRecipient != address(0)) {
            IERC20(token).safeTransfer(feeRecipient, fee);
        }

        emit FlashRedeemFulfilled(initiator, operator, receiver, shares, assetsWithoutFee, fee);
    }

    /**
     * @notice Cancel a redemption request in case of a black swan event.
     * @param receiver The address that had the pending request.
     * @param shares The amount of shares to cancel.
     * @param assetsWithFee The amount of assets to cancel (including fees)
     * @dev Returns shares back to the receiver and updates pending amounts
     */
    function cancelRedeem(
        address receiver,
        uint256 shares,
        uint256 assetsWithFee
    )
        external
        requiresAuth
    {
        MultipliVaultStorage storage $ = _getMultipliVaultStorage();
        PendingRedeem storage pending = $.pendingRedeem[receiver];

        require(pending.shares != 0 && shares <= pending.shares, Errors.InvalidSharesAmount());
        require(
            pending.assets != 0 && assetsWithFee <= pending.assets, Errors.InvalidAssetsAmount()
        );

        pending.shares -= shares;
        pending.assets -= assetsWithFee;
        $.totalPendingAssets -= assetsWithFee;

        emit RequestCancelled(receiver, shares, assetsWithFee);
        // Transfer the shares back to the receiver
        IERC20(address(this)).safeTransfer(receiver, shares);
    }

    /**
     * @notice Update the aggregated underlying balances across all strategies/chains
     * @param newAggregatedBalance The new aggregated underlying balances
     * @dev Can be called only once per block to prevent oracle abuse and flash loan attacks
     * @dev Automatically pauses the vault if price change exceeds the maximum threshold
     */
    function onUnderlyingBalanceUpdate(uint256 newAggregatedBalance) external requiresAuth {
        MultipliVaultStorage storage $ = _getMultipliVaultStorage();

        // Fail fast - ensure this is the first update in this block
        require(block.number > $.lastBlockUpdated, Errors.UpdateAlreadyCompletedInThisBlock());

        emit UnderlyingBalanceUpdated($.aggregatedUnderlyingBalances, newAggregatedBalance);
        $.aggregatedUnderlyingBalances = newAggregatedBalance;

        // Calculate new price per share and check for excessive volatility
        // todo: should this be replaced with `convertToAssets(1e6)`?
        uint256 newPricePerShare = totalAssets().mulDiv(DENOMINATOR, totalSupply());

        uint256 percentageChange = _calculatePercentageChange($.lastPricePerShare, newPricePerShare);

        // Pause the vault if the percentage change exceeds the threshold (works in both directions)
        if (percentageChange > $.maxPercentageChange) {
            _pause();
        }

        $.lastPricePerShare = newPricePerShare;
        $.lastBlockUpdated = block.number;
    }

    /**
     * @notice Set the fee contract for the vault
     * @param _feeContract The new fee contract address
     * @dev Overrides the base implementation to add authorization requirement
     */
    function setFeeContract(IVariableVaultFee _feeContract) public override requiresAuth {
        super.setFeeContract(_feeContract);
    }

    /**
     * @notice Get the fee recipient address for the vault's asset
     * @return The address that receives fees
     */
    function getFeeRecipient() public view returns (address) {
        return _getFeeRecipient(asset());
    }

    /**
     * @notice Update the maximum percentage change allowed before the vault is paused
     * @param newMaxPercentageChange The new maximum percentage change (max value is 1e17 = 10%)
     * @dev Used to protect against oracle manipulation and excessive volatility
     */
    function updateMaxPercentageChange(uint256 newMaxPercentageChange) external requiresAuth {
        require(newMaxPercentageChange < MAX_PERCENTAGE_THRESHOLD, Errors.InvalidMaxPercentage());

        MultipliVaultStorage storage $ = _getMultipliVaultStorage();

        emit MaxPercentageUpdated($.maxPercentageChange, newMaxPercentageChange);
        $.maxPercentageChange = newMaxPercentageChange;
    }

    /**
     * @notice Update the minimum deposit amount required for deposits and mints
     * @param newMinDepositAmount The new minimum deposit amount
     * @dev Used to prevent dust deposits and ensure economic viability
     */
    function updateMinDepositAmount(uint256 newMinDepositAmount) external requiresAuth {
        MultipliVaultStorage storage $ = _getMultipliVaultStorage();
        emit MinDepositAmountUpdated($.minDepositAmount, newMinDepositAmount);
        $.minDepositAmount = newMinDepositAmount;
    }

    //============================== VIEW FUNCTIONS ===============================

    /**
     * @notice Get the pending redemption request details for a user
     * @param user The address to check
     * @return assets The amount of assets pending redemption
     * @return pendingShares The amount of shares pending redemption
     */
    function pendingRedeemRequest(address user)
        public
        view
        returns (uint256 assets, uint256 pendingShares)
    {
        MultipliVaultStorage storage $ = _getMultipliVaultStorage();
        return ($.pendingRedeem[user].assets, $.pendingRedeem[user].shares);
    }

    /**
     * @notice Get the aggregated underlying balances across all strategies
     * @return The total underlying balances
     */
    function aggregatedUnderlyingBalances() public view returns (uint256) {
        return _getMultipliVaultStorage().aggregatedUnderlyingBalances;
    }

    /**
     * @notice Get the last block number when underlying balances were updated
     * @return The last update block number
     */
    function lastBlockUpdated() public view returns (uint256) {
        return _getMultipliVaultStorage().lastBlockUpdated;
    }

    /**
     * @notice Get the last calculated price per share
     * @return The last price per share
     */
    function lastPricePerShare() public view returns (uint256) {
        return _getMultipliVaultStorage().lastPricePerShare;
    }

    /**
     * @notice Get the total amount of assets pending redemption
     * @return The total pending assets
     */
    function totalPendingAssets() public view returns (uint256) {
        return _getMultipliVaultStorage().totalPendingAssets;
    }

    /**
     * @notice Get the maximum percentage change allowed before pausing
     * @return The maximum percentage change threshold
     */
    function maxPercentageChange() public view returns (uint256) {
        return _getMultipliVaultStorage().maxPercentageChange;
    }

    /**
     * @notice Get the minimum deposit amount required
     * @return The minimum deposit amount
     */
    function minDepositAmount() public view returns (uint256) {
        return _getMultipliVaultStorage().minDepositAmount;
    }

    //============================== OVERRIDES ===============================

    /**
     * @notice Override the default `totalAssets` function to include aggregated underlying balances
     * @return The total assets held by the vault and across all strategies
     */
    function totalAssets() public view override returns (uint256) {
        MultipliVaultStorage storage $ = _getMultipliVaultStorage();
        return IERC20(asset()).balanceOf(address(this)) + $.aggregatedUnderlyingBalances;
    }

    /**
     * @notice Override the default `deposit` function with additional checks
     * @param assets The amount of assets to deposit
     * @param receiver The address that will receive the shares
     * @return shares The amount of shares minted
     * @dev Adds pause protection and minimum deposit amount validation
     */
    function deposit(
        uint256 assets,
        address receiver
    )
        public
        override
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }

        MultipliVaultStorage storage $ = _getMultipliVaultStorage();
        uint256 currentMinDepositAmount = $.minDepositAmount;

        if (assets < currentMinDepositAmount) {
            revert Errors.DepositAmountLessThanThreshold(assets, currentMinDepositAmount);
        }

        uint256 shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);

        return shares;
    }

    /**
     * @notice Deposit assets with slippage protection (ERC-5143 compatible)
     * @dev This function extends the standard ERC-4626 deposit function with slippage protection
     *      as specified in ERC-5143: Slippage Protection for Tokenized Vault and introduces additional checks.
     *      Reverts if the number of shares received is less than the minimum expected.
     * @param assets The amount of assets to deposit
     * @param receiver The address that will receive the vault shares
     * @param minShares The minimum number of shares the caller is willing to accept
     * @return shares The actual number of shares minted to the receiver
     * @custom:security Protects against MEV attacks and exchange rate manipulation
     */
    function deposit(
        uint256 assets,
        address receiver,
        uint256 minShares
    )
        public
        whenNotPaused
        returns (uint256)
    {
        uint256 shares = deposit(assets, receiver);
        if (shares < minShares) {
            revert Errors.InsufficientSharesReceived(shares, minShares);
        }
        return shares;
    }

    /**
     * @notice Override the default `mint` function with additional checks
     * @param shares The amount of shares to mint
     * @param receiver The address that will receive the shares
     * @return assets The amount of assets required
     * @dev Adds pause protection and minimum deposit amount validation
     */
    function mint(
        uint256 shares,
        address receiver
    )
        public
        override
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        uint256 maxShares = maxMint(receiver);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxMint(receiver, shares, maxShares);
        }
        uint256 assets = previewMint(shares);

        MultipliVaultStorage storage $ = _getMultipliVaultStorage();
        uint256 currentMinDepositAmount = $.minDepositAmount;

        if (assets < currentMinDepositAmount) {
            revert Errors.DepositAmountLessThanThreshold(assets, currentMinDepositAmount);
        }

        _deposit(_msgSender(), receiver, assets, shares);

        return assets;
    }

    /**
     * @notice Mint shares with slippage protection (ERC-5143 compatible)
     * @dev This function extends the standard ERC-4626 mint function with slippage protection
     *      as specified in ERC-5143: Slippage Protection for Tokenized Vault.
     *      Reverts if the number of assets required exceeds the maximum the caller is willing to pay.
     * @param shares The exact number of shares to mint
     * @param receiver The address that will receive the vault shares
     * @param maxAssets The maximum number of assets the caller is willing to pay
     * @return assets The actual number of assets transferred from the caller
     * @custom:security Protects against MEV attacks and exchange rate manipulation
     */
    function mint(
        uint256 shares,
        address receiver,
        uint256 maxAssets
    )
        public
        whenNotPaused
        returns (uint256)
    {
        uint256 assets = mint(shares, receiver);
        if (assets > maxAssets) {
            revert Errors.ExcessiveAssetsRequired(assets, maxAssets);
        }
        return assets;
    }

    /**
     * @notice Disabled - use requestRedeem instead
     * @dev This function is disabled to enforce the asynchronous redemption flow
     */
    function withdraw(uint256, address, address) public override whenNotPaused returns (uint256) {
        revert Errors.UseRequestRedeem();
    }

    /**
     * @notice Disabled - use requestRedeem instead
     * @dev This function is disabled to enforce the asynchronous redemption flow
     */
    function redeem(uint256, address, address) public override whenNotPaused returns (uint256) {
        revert Errors.UseRequestRedeem();
    }

    /**
     * @notice Override the default `_update` function to add pause protection
     * @dev The _update function is called on all transfers, mints and burns
     */
    function _update(address from, address to, uint256 value) internal override whenNotPaused {
        super._update(from, to, value);
    }

    /**
     * @notice Preview the shares received for a deposit after fees
     * @param assets The amount of assets to deposit
     * @return The amount of shares that would be received
     */
    function previewDeposit(uint256 assets) public view virtual override returns (uint256) {
        uint256 fee = _feeOnTotalDeposit(asset(), assets);
        return super.previewDeposit(assets - fee);
    }

    /**
     * @notice Preview the assets required for minting shares including fees
     * @param shares The amount of shares to mint
     * @return The amount of assets required
     */
    function previewMint(uint256 shares) public view virtual override returns (uint256) {
        uint256 assets = super.previewMint(shares);
        return assets + _feeOnRawDeposit(asset(), assets);
    }

    /**
     * @notice Preview the shares required for withdrawing assets including fees
     * @param assets The amount of assets to withdraw
     * @return The amount of shares required
     */
    function previewWithdraw(uint256 assets) public view virtual override returns (uint256) {
        uint256 fee = _feeOnRawWithdrawal(asset(), assets);
        return super.previewWithdraw(assets + fee);
    }

    /**
     * @notice Preview the assets received for redeeming shares after fees
     * @param shares The amount of shares to redeem
     * @return The amount of assets that would be received
     */
    function previewRedeem(uint256 shares) public view virtual override returns (uint256) {
        uint256 assets = super.previewRedeem(shares);
        return assets - _feeOnTotalWithdrawal(asset(), assets);
    }

    /**
     * @notice Preview the assets received for instant redeeming shares after fees
     * @param shares The amount of shares to redeem instantly
     * @return The amount of assets that would be received
     */
    function previewInstantRedeem(uint256 shares) public view virtual returns (uint256) {
        uint256 assets = super.previewRedeem(shares);
        return assets - _feeOnTotalInstantWithdrawal(asset(), assets);
    }

    /**
     * @notice Preview the assets received for flash redeeming shares after fees
     * @param shares The amount of shares to redeem instantly
     * @return The amount of assets that would be received
     */
    function previewFlashRedeem(uint256 shares) public view virtual returns (uint256) {
        uint256 assets = convertToAssets(shares);
        return assets - _feeOnTotalFlashWithdrawal(asset(), assets);
    }

    //============================== INTERNAL FUNCTIONS ===============================

    /**
     * @notice Internal deposit function with fee handling
     * @param caller The address calling the deposit
     * @param receiver The address receiving the shares
     * @param assets The amount of assets being deposited
     * @param shares The amount of shares being minted
     * @dev Handles fee collection and transfer to fee recipient
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    )
        internal
        override
    {
        address token = asset();
        uint256 feeAmount = _feeOnTotalDeposit(token, assets);

        address recipient = _getFeeRecipient(token);

        super._deposit(caller, receiver, assets, shares);

        if (feeAmount > 0 && recipient != address(0)) {
            IERC20(token).safeTransfer(recipient, feeAmount);
        }
    }

    /**
     * @notice Internal function to handle redeem request logic for all redeem types
     * @param params The redemption parameters
     * @return requestId The request ID (always 0)
     * @dev Validates ownership, transfers shares to vault, and stores pending request
     */
    function _processRedeemRequest(RedeemParams memory params) internal virtual returns (uint256) {
        require(params.shares > 0, Errors.SharesAmountZero());
        require(params.owner == msg.sender, Errors.NotSharesOwner());
        require(balanceOf(params.owner) >= params.shares, Errors.InsufficientShares());

        uint256 assetsWithFee = super.previewRedeem(params.shares);

        // Emit appropriate event based on redemption type
        _emitRedeemRequestEvent(
            params.receiver, params.owner, assetsWithFee, params.shares, params.redeemType
        );

        // Store the redemption request
        MultipliVaultStorage storage $ = _getMultipliVaultStorage();

        _transfer(params.owner, address(this), params.shares);
        $.totalPendingAssets += assetsWithFee;
        $.pendingRedeem[params.receiver] = PendingRedeem({
            shares: $.pendingRedeem[params.receiver].shares + params.shares,
            assets: $.pendingRedeem[params.receiver].assets + assetsWithFee
        });

        return REQUEST_ID;
    }

    /**
     * @notice Internal function to emit appropriate events based on redeem type
     * @param receiver The address that will receive the assets
     * @param owner The address that owns the shares
     * @param assetsWithFee The amount of assets including fees
     * @param shares The amount of shares being redeemed
     * @param redeemType The type of redemption
     */
    function _emitRedeemRequestEvent(
        address receiver,
        address owner,
        uint256 assetsWithFee,
        uint256 shares,
        RedeemType redeemType
    )
        internal
    {
        if (redeemType == RedeemType.NORMAL) {
            emit RedeemRequest(receiver, owner, assetsWithFee, shares);
        } else if (redeemType == RedeemType.INSTANT) {
            emit InstantRedeemRequest(receiver, owner, assetsWithFee, shares);
        } else {
            revert Errors.UnsupportedRedeemType(uint8(redeemType));
        }
    }

    /**
     * @notice Internal function to emit fulfillment events
     * @param receiver The address receiving the assets
     * @param shares The amount of shares being fulfilled
     * @param assetsWithFee The amount of assets including fees
     * @param redeemType The type of redemption being fulfilled
     */
    function _emitFulfillmentEvent(
        address receiver,
        uint256 shares,
        uint256 assetsWithFee,
        RedeemType redeemType
    )
        internal
    {
        if (redeemType == RedeemType.NORMAL) {
            emit RequestFulfilled(receiver, shares, assetsWithFee);
        } else if (redeemType == RedeemType.INSTANT) {
            emit InstantRequestFulfilled(receiver, shares, assetsWithFee);
        } else {
            revert Errors.UnsupportedRedeemType(uint8(redeemType));
        }
    }

    /**
     * @notice Internal function to handle fulfillment logic for all redeem types
     * @param params The fulfillment parameters
     * @dev Validates pending request, updates state, and executes withdrawal
     */
    function _processFulfillment(FulfillParams memory params) internal {
        MultipliVaultStorage storage $ = _getMultipliVaultStorage();

        PendingRedeem storage pending = $.pendingRedeem[params.receiver];
        require(
            pending.shares != 0 && params.shares <= pending.shares, Errors.InvalidSharesAmount()
        );
        require(
            pending.assets != 0 && params.assetsWithFee <= pending.assets,
            Errors.InvalidAssetsAmount()
        );

        pending.shares -= params.shares;
        pending.assets -= params.assetsWithFee;
        $.totalPendingAssets -= params.assetsWithFee;

        // Emit appropriate event based on redemption type
        _emitFulfillmentEvent(
            params.receiver, params.shares, params.assetsWithFee, params.redeemType
        );

        // Execute the withdrawal with appropriate fee handling
        _executeWithdrawal(params.receiver, params.assetsWithFee, params.shares, params.redeemType);
    }

    /**
     * @notice Internal function to execute withdrawal with fee handling
     * @param receiver The address receiving the assets
     * @param assetsWithFee The total amount of assets including fees
     * @param shares The amount of shares being burned
     * @param redeemType The type of redemption (affects fee calculation)
     * @dev Calculates fees based on redemption type and transfers assets to receiver
     */
    function _executeWithdrawal(
        address receiver,
        uint256 assetsWithFee,
        uint256 shares,
        RedeemType redeemType
    )
        internal
    {
        address token = asset();
        uint256 feeAmount;

        // Calculate fee based on redemption type
        if (redeemType == RedeemType.NORMAL) {
            feeAmount = _feeOnTotalWithdrawal(token, assetsWithFee);
        } else if (redeemType == RedeemType.INSTANT) {
            feeAmount = _feeOnTotalInstantWithdrawal(token, assetsWithFee);
        } else {
            revert Errors.UnsupportedRedeemType(uint8(redeemType));
        }

        uint256 assets = assetsWithFee - feeAmount;
        address recipient = _getFeeRecipient(token);

        // Execute the withdrawal
        super._withdraw(address(this), receiver, address(this), assets, shares);

        // Transfer fees to fee recipient if applicable
        if (feeAmount > 0 && recipient != address(0)) {
            IERC20(token).safeTransfer(recipient, feeAmount);
        }
    }

    //============================== PRIVATE FUNCTIONS ===============================

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
     * @notice Returns a reference to the MultipliVaultStorage struct
     * @return $ Reference to the MultipliVaultStorage struct
     * @dev Uses ERC-7201 storage pattern to prevent storage collisions
     */
    function _getMultipliVaultStorage() private pure returns (MultipliVaultStorage storage $) {
        assembly {
            $.slot := MULTIPLI_VAULT_STORAGE_LOCATION
        }
    }

    /**
     * @notice Authorize contract upgrades (UUPS pattern)
     * @dev Only owner or authorized roles can upgrade the implementation
     * @param newImplementation The new implementation contract address
     * @custom:security Prevents unauthorized upgrades that could compromise the protocol
     */
    function _authorizeUpgrade(address newImplementation) internal virtual override requiresAuth { }
}
