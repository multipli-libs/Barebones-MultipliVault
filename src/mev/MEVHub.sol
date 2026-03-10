// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {
    ReentrancyGuardTransient
} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { SafeTransferLib } from "@solady/utils/SafeTransferLib.sol";

import { IAaveV3Pool } from "../interfaces/aave/IAaveV3Pool.sol";
import { IMEVHub } from "./interfaces/IMEVHub.sol";
import { IMEVStrategy } from "./interfaces/IMEVStrategy.sol";
import { TransientLib } from "./libraries/TransientLib.sol";

/**
 * @title MEVHub
 * @notice Delegatecall hub for batched MEV strategy execution
 * @dev Dispatches operations via delegatecall to registered strategy modules.
 *      All intra-tx state uses EIP-1153 transient storage — no persistent state
 *      between transactions for detection resistance.
 *
 *      Execution flow:
 *      1. Searcher EOA calls execute() or executeWithFlashLoan()
 *      2. Hub iterates ops, delegatecalls each strategy module
 *      3. Strategies execute in hub's context (shared transient storage)
 *      4. Hub enforces minimum profit guard
 *      5. Hub tips block builder via coinbase transfer
 *
 *      Security model:
 *      - Immutable owner set in constructor (no storage slots)
 *      - Strategies must be explicitly registered
 *      - ReentrancyGuardTransient prevents reentry across execute paths
 *      - Aave callback validates msg.sender == pool and initiator == this
 *      - Profit guard reverts unprofitable bundles atomically
 *
 * @custom:security-contact security@multipli.com
 */
contract MEVHub is IMEVHub, ReentrancyGuardTransient {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The owner/searcher who can execute operations
    address public immutable owner;

    /// @notice The Aave V3 Pool for flash loan operations
    IAaveV3Pool public immutable aavePool;

    /// @notice Registered strategy modules (address → enabled)
    mapping(address => bool) public strategies;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Restricts calls to the contract owner
    modifier onlyOwner() {
        if (msg.sender != owner) revert MEVHub__UnauthorizedCaller();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @param _owner The searcher EOA that can execute operations
    /// @param _aavePool The Aave V3 Pool address for flash loans
    constructor(address _owner, address _aavePool) {
        if (_owner == address(0) || _aavePool == address(0)) {
            revert MEVHub__ZeroAddress();
        }

        owner = _owner;
        aavePool = IAaveV3Pool(_aavePool);
    }

    /// @dev Accept ETH for builder tips and profit extraction
    receive() external payable { }

    /*//////////////////////////////////////////////////////////////
              USER-FACING STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IMEVHub
    function execute(
        bytes[] calldata ops,
        uint256 minProfit,
        uint256 builderTip
    )
        external
        payable
        nonReentrant
        onlyOwner
    {
        _executeOps(ops);
        _enforceProfitAndTip(minProfit, builderTip);
    }

    /// @inheritdoc IMEVHub
    function executeWithFlashLoan(
        address asset,
        uint256 amount,
        bytes[] calldata ops,
        uint256 minProfit,
        uint256 builderTip
    )
        external
        payable
        nonReentrant
        onlyOwner
    {
        if (asset == address(0)) revert MEVHub__ZeroAddress();
        if (amount == 0) revert MEVHub__ZeroAmount();

        // Store ops in transient storage for the flash loan callback
        // We encode ops + minProfit + builderTip as callback params
        bytes memory callbackParams = abi.encode(ops, minProfit, builderTip);

        // Store flash loan params in transient storage for callback validation
        TransientLib.setFlashLoanParams(asset, amount, 0);

        aavePool.flashLoanSimple({
            receiverAddress: address(this),
            asset: asset,
            amount: amount,
            params: callbackParams,
            referralCode: 0
        });
    }

    /**
     * @notice Aave V3 flash loan callback
     * @param asset The borrowed asset
     * @param amount The borrowed amount
     * @param premium The premium owed to Aave
     * @param initiator The flash loan initiator (must be this contract)
     * @param params Encoded (ops, minProfit, builderTip)
     * @return true on success
     * @dev Only callable by the Aave pool during an active flash loan.
     *      Do NOT add nonReentrant — called within the nonReentrant
     *      context of executeWithFlashLoan.
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
            revert MEVHub__UnauthorizedCaller();
        }
        if (initiator != address(this)) {
            revert MEVHub__FlashLoanCallbackFailed();
        }

        // Update flash loan params with actual premium
        TransientLib.setFlashLoanParams(asset, amount, premium);

        // Decode and execute operations
        (bytes[] memory ops, uint256 minProfit, uint256 builderTip) =
            abi.decode(params, (bytes[], uint256, uint256));

        _executeOpsMemory(ops);
        _enforceProfitAndTip(minProfit, builderTip);

        // Approve Aave to pull repayment (amount + premium)
        uint256 amountOwed = amount + premium;
        SafeTransferLib.safeApprove(asset, address(aavePool), amountOwed);

        // Clear flash loan transient state
        TransientLib.clearFlashLoanParams();

        return true;
    }

    /// @inheritdoc IMEVHub
    function setStrategy(address strategy, bool enabled) external onlyOwner {
        if (strategy == address(0)) revert MEVHub__ZeroAddress();

        strategies[strategy] = enabled;
        emit StrategyRegistered(strategy, enabled);
    }

    /// @inheritdoc IMEVHub
    function sweep(address token, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert MEVHub__ZeroAddress();
        if (amount == 0) revert MEVHub__ZeroAmount();

        SafeTransferLib.safeTransfer(token, to, amount);
        emit ProfitTaken(token, to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Execute batched operations from calldata via delegatecall
    /// @param ops Array of ABI-encoded (strategy address, params) tuples
    function _executeOps(bytes[] calldata ops) internal {
        // Reset profit accumulator
        TransientLib.resetProfit();

        uint256 length = ops.length;
        for (uint256 i; i < length;) {
            (address strategy, bytes memory params) = abi.decode(ops[i], (address, bytes));

            if (!strategies[strategy]) revert MEVHub__InvalidStrategy();

            // Delegatecall strategy — executes in our storage context
            (bool success, bytes memory result) =
                strategy.delegatecall(abi.encodeCall(IMEVStrategy.execute, (params)));

            if (!success) revert MEVHub__DelegatecallFailed();

            // Decode profit and accumulate
            int256 profit = abi.decode(result, (int256));
            if (profit > 0) {
                TransientLib.addProfit(uint256(profit));
            } else if (profit < 0) {
                TransientLib.subProfit(uint256(-profit));
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @dev Execute batched operations from memory (used in flash loan callback)
    /// @param ops Array of ABI-encoded (strategy address, params) tuples
    function _executeOpsMemory(bytes[] memory ops) internal {
        // Reset profit accumulator
        TransientLib.resetProfit();

        uint256 length = ops.length;
        for (uint256 i; i < length;) {
            (address strategy, bytes memory params) = abi.decode(ops[i], (address, bytes));

            if (!strategies[strategy]) revert MEVHub__InvalidStrategy();

            (bool success, bytes memory result) =
                strategy.delegatecall(abi.encodeCall(IMEVStrategy.execute, (params)));

            if (!success) revert MEVHub__DelegatecallFailed();

            int256 profit = abi.decode(result, (int256));
            if (profit > 0) {
                TransientLib.addProfit(uint256(profit));
            } else if (profit < 0) {
                TransientLib.subProfit(uint256(-profit));
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @dev Enforce minimum profit and send builder tip via coinbase transfer
    /// @param minProfit The minimum net profit required
    /// @param builderTip The amount to tip the block builder
    function _enforceProfitAndTip(uint256 minProfit, uint256 builderTip) internal {
        uint256 profit = TransientLib.getProfit();

        if (profit < minProfit) revert MEVHub__Unprofitable();

        // Emit before tip to capture gross profit
        emit MEVExecuted(0, profit, builderTip);

        // Tip the block builder via coinbase transfer in assembly
        if (builderTip > 0) {
            assembly {
                let success := call(gas(), coinbase(), builderTip, 0, 0, 0, 0)
                // Don't revert on failed tip — builder may not accept ETH
            }
        }

        // Reset transient state for cleanliness
        TransientLib.resetProfit();
    }

    /*//////////////////////////////////////////////////////////////
                    UNISWAP V3 SWAP CALLBACK
    //////////////////////////////////////////////////////////////*/

    /// @notice Uniswap V3 swap callback — pays the pool for swaps
    /// @param amount0Delta The amount of token0 owed to the pool (positive = owed)
    /// @param amount1Delta The amount of token1 owed to the pool (positive = owed)
    /// @param data Encoded token address for payment
    /// @dev Called by V3 pools during swap execution. Since strategies run via
    ///      delegatecall, the callback lands here on the hub.
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    )
        external
    {
        // Only pay the positive delta (amount owed to pool)
        if (amount0Delta > 0) {
            address token = abi.decode(data, (address));
            SafeTransferLib.safeTransfer(token, msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            (, address token) = abi.decode(data, (address, address));
            SafeTransferLib.safeTransfer(token, msg.sender, uint256(amount1Delta));
        }
    }
}
