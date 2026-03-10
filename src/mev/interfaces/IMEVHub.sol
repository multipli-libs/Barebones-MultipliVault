// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IMEVHub
 * @notice Interface for the MEV execution hub
 * @dev The hub dispatches batched operations via delegatecall to registered strategy modules.
 *      All intra-tx state uses EIP-1153 transient storage. No persistent state between txs.
 *
 * @custom:security-contact security@multipli.com
 */
interface IMEVHub {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event MEVExecuted(uint256 indexed operationCount, uint256 profit, uint256 builderTip);
    event StrategyRegistered(address indexed strategy, bool enabled);
    event ProfitTaken(address indexed token, address indexed to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error MEVHub__Unprofitable();
    error MEVHub__InvalidStrategy();
    error MEVHub__UnauthorizedCaller();
    error MEVHub__ZeroAddress();
    error MEVHub__ZeroAmount();
    error MEVHub__DelegatecallFailed();
    error MEVHub__FlashLoanCallbackFailed();

    /*//////////////////////////////////////////////////////////////
                          EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Execute a batch of MEV operations via delegatecall to strategy modules
     * @param ops Array of ABI-encoded (strategy, params) tuples
     * @param minProfit Minimum net profit required or tx reverts
     * @param builderTip Amount to tip the block builder via coinbase transfer
     */
    function execute(bytes[] calldata ops, uint256 minProfit, uint256 builderTip) external payable;

    /**
     * @notice Execute MEV operations backed by an Aave V3 flash loan
     * @param asset The asset to flash borrow
     * @param amount The flash loan amount
     * @param ops Array of ABI-encoded (strategy, params) tuples
     * @param minProfit Minimum net profit required or tx reverts
     * @param builderTip Amount to tip the block builder via coinbase transfer
     */
    function executeWithFlashLoan(
        address asset,
        uint256 amount,
        bytes[] calldata ops,
        uint256 minProfit,
        uint256 builderTip
    )
        external
        payable;

    /**
     * @notice Register or deregister a strategy module
     * @param strategy The strategy contract address
     * @param enabled True to register, false to deregister
     */
    function setStrategy(address strategy, bool enabled) external;

    /**
     * @notice Sweep tokens from the hub to a destination
     * @param token The ERC20 token to sweep
     * @param to The destination address
     * @param amount The amount to sweep
     */
    function sweep(address token, address to, uint256 amount) external;
}
