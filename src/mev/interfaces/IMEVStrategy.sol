// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IMEVStrategy
 * @notice Interface for MEV strategy modules executed via delegatecall from MEVHub
 * @dev Strategies are called via delegatecall — they execute in the hub's storage context.
 *      All transient state (TSTORE/TLOAD) is shared with the hub.
 *      Strategies MUST NOT use persistent storage (SSTORE) to remain detection-resistant.
 *
 * @custom:security-contact security@multipli.com
 */
interface IMEVStrategy {
    /**
     * @notice Execute a strategy operation via delegatecall
     * @param params Strategy-specific ABI-encoded parameters
     * @return profit Net profit (positive) or loss (negative) from this operation
     * @dev Called by MEVHub via delegatecall. The strategy executes in the hub's
     *      context and has access to hub's transient storage slots.
     *      Must return the net profit so the hub can enforce the profit guard.
     */
    function execute(bytes calldata params) external returns (int256 profit);
}
