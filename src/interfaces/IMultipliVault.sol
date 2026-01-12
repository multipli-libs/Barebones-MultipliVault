// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title MultipliVault
 * @notice Interface for the Multipli vault
 * @dev Defines events and functions related to redeem requests, fee updates, and balance tracking.
 */
interface IMultipliVault {
    /**
     * @dev Structure to store pending redeem requests.
     * @param assets The amount of assets to be redeemed.
     * @param shares The amount of shares to be redeemed.
     */
    struct PendingRedeem {
        uint256 assets;
        uint256 shares;
    }

    /**
     * @notice Emitted when the withdraw fee is updated.
     * @param lastFee The previous fee value.
     * @param newFee The new fee value.
     */
    event WithdrawFeeUpdated(uint256 lastFee, uint256 newFee);

    /**
     * @notice Emitted when the deposit fee is updated.
     * @param lastFee The previous fee value.
     * @param newFee The new fee value.
     */
    event DepositFeeUpdated(uint256 lastFee, uint256 newFee);

    /**
     * @notice Emitted when the fee recipient is updated.
     * @param lastFeeRecipient The previous fee recipient address.
     * @param newFeeRecipient The new fee recipient address.
     */
    event FeeRecipientUpdated(address lastFeeRecipient, address newFeeRecipient);

    /**
     * @notice Emitted when the max percentage is updated.
     * @param lastMaxPercentage The previous max percentage.
     * @param newMaxPercentage The new max percentage.
     */
    event MaxPercentageUpdated(uint256 lastMaxPercentage, uint256 newMaxPercentage);

    event MinDepositAmountUpdated(uint256 minDepositAmount, uint256 newMinDepositAmount);

    /**
     * @notice Emitted when the underlying balance is updated by the oracle.
     * @param lastUnderlyingBalance The previous underlying balance.
     * @param newUnderlyingBalance The new underlying balance.
     */
    event UnderlyingBalanceUpdated(uint256 lastUnderlyingBalance, uint256 newUnderlyingBalance);

    /**
     * @notice Emitted when a new redeem request is created.
     * @param receiver The receiving address.
     * @param owner The owner address.
     * @param assets The assets amount.
     * @param shares The shares amount.
     */
    event RedeemRequest(
        address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    /**
     * @notice Emitted when a new instant redeem request is created.
     * @param receiver The receiving address.
     * @param owner The owner address.
     * @param assets The assets amount.
     * @param shares The shares amount.
     */
    event InstantRedeemRequest(
        address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    /**
     * @notice Emitted when a redeem request is fulfilled.
     * @param receiver The receiving address.
     * @param shares The shares amount.
     * @param assets The assets amount.
     */
    event RequestFulfilled(address indexed receiver, uint256 shares, uint256 assets);

    /**
     * @notice Emitted when a instant redeem request is fulfilled.
     * @param receiver The receiving address.
     * @param shares The shares amount.
     * @param assets The assets amount.
     */
    event InstantRequestFulfilled(address indexed receiver, uint256 shares, uint256 assets);

    /**
     * @notice Emitted when a flash redeem request is fulfilled.
     * @param initiator The address that originally initiated the flashRedeem request
     * @param operator The contract that is responsible for paying back the shares
     * @param receiver The address that will receive the assets (usdc, wbtc, etc)
     * @param shares The amount of shares to redeem (total position size)
     * @param assetsWithoutFee The amount of assets excluding fee
     * @param fee The amount of assets paid as fee
     */
    event FlashRedeemFulfilled(
        address indexed initiator,
        address indexed operator,
        address indexed receiver,
        uint256 shares,
        uint256 assetsWithoutFee,
        uint256 fee
    );

    /**
     * @notice Emitted when a redeem request is cancelled.
     * @param receiver The receiving address.
     * @param shares The shares amount.
     * @param assets The assets amount.
     */
    event RequestCancelled(address indexed receiver, uint256 shares, uint256 assets);

    /**
     * @notice Requests a redeem operation for the specified shares.
     * @param shares The number of shares to redeem.
     * @param receiver The address to receive the assets.
     * @param owner The address of the owner of the shares.
     * @return requestId The ID of the created redeem request.
     */
    function requestRedeem(
        uint256 shares,
        address receiver,
        address owner
    )
        external
        returns (uint256 requestId);

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
        returns (uint256);

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
        uint256 assetsWithFee,
        bytes calldata data
    )
        external;
}
