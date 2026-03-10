// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { SafeTransferLib } from "@solady/utils/SafeTransferLib.sol";

import { IMEVStrategy } from "../interfaces/IMEVStrategy.sol";
import { DexLib } from "../libraries/DexLib.sol";
import { TransientLib } from "../libraries/TransientLib.sol";

/**
 * @title ArbitrageStrategy
 * @notice Multi-hop cyclic arbitrage strategy across DEX pools
 * @dev Executed via delegatecall from MEVHub — runs in hub's storage context.
 *
 *      Supports:
 *      - 2-hop cyclic arb: A→B→A across different pools
 *      - 3-hop cyclic arb: A→B→C→A across different pools/DEXes
 *      - Mixed V2/V3 paths: any combination of pool types per hop
 *      - Flash-loan backed: zero capital requirement via MEVHub.executeWithFlashLoan
 *
 *      Execution flow:
 *      1. Offchain: Bellman-Ford detects negative cycle in price graph
 *      2. Offchain: Encode optimal path as Hop[] array
 *      3. Onchain: Strategy iterates hops, executing each swap
 *      4. Onchain: Profit = final balance - initial balance of start token
 *
 *      All swaps use DexLib assembly-optimized direct pool calls.
 *      Transient storage tracks intermediate balances between hops.
 *
 * @custom:security-contact security@multipli.com
 */
contract ArbitrageStrategy is IMEVStrategy {
    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Pool type for a hop
    enum PoolType {
        UNI_V2,
        UNI_V3
    }

    /// @dev A single hop in the arbitrage path
    struct Hop {
        PoolType poolType;
        address pool; // V2 pair or V3 pool address
        address tokenIn; // Input token for this hop
        address tokenOut; // Output token for this hop
        bool zeroForOne; // Swap direction
        uint160 sqrtPriceLimitX96; // V3 only — 0 for V2 or max slippage
    }

    /// @dev Full arbitrage execution parameters
    struct ArbParams {
        Hop[] hops;
        uint256 amountIn; // Starting amount for first hop
        address startToken; // Token we start and end with (cyclic)
    }

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error ArbitrageStrategy__NoHops();
    error ArbitrageStrategy__NotCyclic();
    error ArbitrageStrategy__InvalidPoolType();

    /*//////////////////////////////////////////////////////////////
              USER-FACING STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IMEVStrategy
    /// @dev Decodes params as ArbParams and executes the multi-hop path.
    ///      Returns net profit in startToken. Called via delegatecall.
    function execute(bytes calldata params) external override returns (int256 profit) {
        ArbParams memory p = abi.decode(params, (ArbParams));

        if (p.hops.length == 0) revert ArbitrageStrategy__NoHops();

        // Validate cyclic: last hop's tokenOut must equal startToken
        Hop memory lastHop = p.hops[p.hops.length - 1];
        if (lastHop.tokenOut != p.startToken) {
            revert ArbitrageStrategy__NotCyclic();
        }

        // Track initial balance of start token
        uint256 balanceBefore = _selfBalance(p.startToken);

        // Execute each hop
        uint256 currentAmount = p.amountIn;

        uint256 length = p.hops.length;
        for (uint256 i; i < length;) {
            Hop memory hop = p.hops[i];

            if (hop.poolType == PoolType.UNI_V2) {
                currentAmount = _executeV2Hop(hop, currentAmount);
            } else if (hop.poolType == PoolType.UNI_V3) {
                currentAmount = _executeV3Hop(hop, currentAmount);
            } else {
                revert ArbitrageStrategy__InvalidPoolType();
            }

            // Store intermediate balance in transient storage
            TransientLib.setBalance(i, currentAmount);

            unchecked {
                ++i;
            }
        }

        // Calculate profit: final balance - initial balance
        uint256 balanceAfter = _selfBalance(p.startToken);
        profit = int256(balanceAfter) - int256(balanceBefore);
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Execute a single V2 hop
    /// @param hop The hop parameters
    /// @param amountIn The input amount for this hop
    /// @return amountOut The output amount from this hop
    function _executeV2Hop(Hop memory hop, uint256 amountIn) internal returns (uint256 amountOut) {
        // Transfer tokens to the pair
        SafeTransferLib.safeTransfer(hop.tokenIn, hop.pool, amountIn);

        // Execute direct V2 swap
        amountOut = DexLib.swapV2(hop.pool, amountIn, hop.zeroForOne);
    }

    /// @dev Execute a single V3 hop
    /// @param hop The hop parameters
    /// @param amountIn The input amount for this hop
    /// @return amountOut The output amount from this hop
    function _executeV3Hop(Hop memory hop, uint256 amountIn) internal returns (uint256 amountOut) {
        // V3 swaps pull tokens via callback (uniswapV3SwapCallback on hub)
        (int256 amount0, int256 amount1) =
            DexLib.swapV3(hop.pool, int256(amountIn), hop.zeroForOne, hop.sqrtPriceLimitX96);

        // Output is the negative delta
        if (hop.zeroForOne) {
            amountOut = uint256(-amount1);
        } else {
            amountOut = uint256(-amount0);
        }
    }

    /*//////////////////////////////////////////////////////////////
                      PRIVATE VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Get the balance of a token held by this contract (hub via delegatecall)
    /// @param token The token address
    /// @return bal The token balance
    function _selfBalance(address token) private view returns (uint256 bal) {
        assembly {
            // IERC20(token).balanceOf(address(this))
            let ptr := mload(0x40)
            mstore(ptr, 0x70a0823100000000000000000000000000000000000000000000000000000000)
            mstore(add(ptr, 0x04), address())

            let success := staticcall(gas(), token, ptr, 0x24, ptr, 0x20)
            if iszero(success) { bal := 0 }
            if success { bal := mload(ptr) }
        }
    }
}
