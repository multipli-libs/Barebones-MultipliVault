// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/// @title IFlashLoanStrategy
/// @notice Callback interface for flash loan strategy execution
/// @dev Implementers receive borrowed funds from FlashLoanExecutor and must
///      return at least `amount + premium` of `asset` to the executor before returning.
///      Any excess is profit that the strategy can route to the vault or elsewhere.
interface IFlashLoanStrategy {
    /// @notice Execute the strategy with flash-borrowed funds
    /// @param asset The borrowed asset address
    /// @param amount The borrowed amount
    /// @param premium The Aave premium owed on top of the borrowed amount
    /// @param params Strategy-specific encoded parameters
    function execute(
        address asset,
        uint256 amount,
        uint256 premium,
        bytes calldata params
    )
        external;
}
