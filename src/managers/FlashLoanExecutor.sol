// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    ReentrancyGuardTransient
} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import { IAaveV3Pool } from "../interfaces/aave/IAaveV3Pool.sol";
import { IFlashLoanStrategy } from "../interfaces/IFlashLoanStrategy.sol";

/**
 * @title FlashLoanExecutor
 * @notice Executes flash loan strategies through the vault's manage() pipeline
 * @dev Borrows from Aave V3 via flashLoanSimple, delegates execution to a whitelisted
 *      strategy contract, and repays atomically within a single transaction.
 *
 *      Execution flow:
 *      1. Fund manager calls vault.manage(executor, executeFlashLoan(...))
 *      2. Executor borrows from Aave V3
 *      3. Aave callbacks executeOperation on this contract
 *      4. Executor delegates to whitelisted strategy
 *      5. Strategy executes and returns funds + premium to executor
 *      6. Executor approves Aave to pull repayment
 *
 *      Security model:
 *      - All entry points gated by onlyVault (calls must originate from vault.manage())
 *      - Strategies must be explicitly whitelisted
 *      - Aave callback validates msg.sender == pool and initiator == this
 *      - nonReentrant on executeFlashLoan prevents reentry from malicious strategies
 *
 * @custom:security-contact security@multipli.com
 */
contract FlashLoanExecutor is ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The vault this executor is wired into
    address public immutable vault;

    /// @notice The Aave V3 Pool used for flash loans
    IAaveV3Pool public immutable aavePool;

    /// @notice Whitelisted strategy contracts
    mapping(address => bool) public whitelistedStrategies;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event FlashLoanExecuted(
        address indexed strategy, address indexed asset, uint256 amount, uint256 premium
    );

    event StrategyWhitelistUpdated(address indexed strategy, bool enabled);

    event TokensSwept(address indexed token, address indexed to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error FlashLoanExecutor__UnauthorizedCaller();
    error FlashLoanExecutor__InvalidInitiator();
    error FlashLoanExecutor__StrategyNotWhitelisted();
    error FlashLoanExecutor__ZeroAddress();
    error FlashLoanExecutor__ZeroAmount();
    error FlashLoanExecutor__InsufficientRepayment();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Restricts calls to the vault's manage() pipeline
    modifier onlyVault() {
        if (msg.sender != vault) {
            revert FlashLoanExecutor__UnauthorizedCaller();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @param _vault The MultipliVault address (calls arrive through vault.manage())
    /// @param _aavePool The Aave V3 Pool address on this chain
    constructor(address _vault, address _aavePool) {
        if (_vault == address(0) || _aavePool == address(0)) {
            revert FlashLoanExecutor__ZeroAddress();
        }

        vault = _vault;
        aavePool = IAaveV3Pool(_aavePool);
    }

    /*//////////////////////////////////////////////////////////////
                  USER-FACING STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Execute a flash loan strategy through Aave V3
     * @param asset The asset to flash borrow
     * @param amount The amount to flash borrow
     * @param strategy The whitelisted strategy contract to execute
     * @param params Strategy-specific encoded parameters
     * @dev Called via vault.manage(executor, abi.encodeCall(...), 0)
     *      The strategy receives borrowed funds and must return amount + premium
     *      to this contract before its execute() returns.
     */
    function executeFlashLoan(
        address asset,
        uint256 amount,
        address strategy,
        bytes calldata params
    )
        external
        nonReentrant
        onlyVault
    {
        if (asset == address(0) || strategy == address(0)) {
            revert FlashLoanExecutor__ZeroAddress();
        }
        if (amount == 0) revert FlashLoanExecutor__ZeroAmount();
        if (!whitelistedStrategies[strategy]) {
            revert FlashLoanExecutor__StrategyNotWhitelisted();
        }

        bytes memory callbackParams = abi.encode(strategy, params);

        aavePool.flashLoanSimple({
            receiverAddress: address(this),
            asset: asset,
            amount: amount,
            params: callbackParams,
            referralCode: 0
        });

        emit FlashLoanExecuted(strategy, asset, amount, _lastPremium(amount));
    }

    /**
     * @notice Aave V3 flash loan callback
     * @param asset The borrowed asset
     * @param amount The borrowed amount
     * @param premium The premium owed to Aave
     * @param initiator The address that initiated the flash loan (must be this contract)
     * @param params Encoded (strategy, strategyParams) from executeFlashLoan
     * @return true if execution succeeded (required by Aave)
     * @dev Only callable by the Aave pool during an active flash loan.
     *      Do NOT add nonReentrant here — this is called within the nonReentrant
     *      context of executeFlashLoan via the Aave pool callback.
     */
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    )
        external
        returns (bool)
    {
        if (msg.sender != address(aavePool)) {
            revert FlashLoanExecutor__UnauthorizedCaller();
        }
        if (initiator != address(this)) {
            revert FlashLoanExecutor__InvalidInitiator();
        }

        (address strategy, bytes memory strategyParams) = abi.decode(params, (address, bytes));

        // Transfer borrowed funds to strategy
        IERC20(asset).safeTransfer(strategy, amount);

        // Execute strategy — strategy must return amount + premium to this contract
        IFlashLoanStrategy(strategy).execute(asset, amount, premium, strategyParams);

        // Verify repayment funds are available
        uint256 amountOwed = amount + premium;
        uint256 balance = IERC20(asset).balanceOf(address(this));
        if (balance < amountOwed) {
            revert FlashLoanExecutor__InsufficientRepayment();
        }

        // Approve Aave pool to pull repayment
        IERC20(asset).forceApprove(address(aavePool), amountOwed);

        return true;
    }

    /**
     * @notice Update the whitelist status of a strategy contract
     * @param strategy The strategy contract address
     * @param enabled True to whitelist, false to remove
     * @dev Called via vault.manage(executor, abi.encodeCall(...), 0)
     */
    function updateStrategyWhitelist(address strategy, bool enabled) external onlyVault {
        if (strategy == address(0)) revert FlashLoanExecutor__ZeroAddress();

        whitelistedStrategies[strategy] = enabled;
        emit StrategyWhitelistUpdated(strategy, enabled);
    }

    /**
     * @notice Sweep tokens from the executor to a destination
     * @param token The ERC20 token to sweep
     * @param to The destination address
     * @param amount The amount to sweep
     * @dev Used to recover leftover tokens or extract profit.
     *      Called via vault.manage(executor, abi.encodeCall(...), 0)
     */
    function sweepTokens(address token, address to, uint256 amount) external onlyVault {
        if (to == address(0)) revert FlashLoanExecutor__ZeroAddress();
        if (amount == 0) revert FlashLoanExecutor__ZeroAmount();

        IERC20(token).safeTransfer(to, amount);
        emit TokensSwept(token, to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                      PRIVATE READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Estimate premium for event emission (actual premium determined by Aave callback)
    function _lastPremium(uint256 amount) private view returns (uint256) {
        uint128 premiumBps = aavePool.FLASHLOAN_PREMIUM_TOTAL();
        return (amount * premiumBps) / 10_000;
    }
}
