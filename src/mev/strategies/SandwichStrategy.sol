// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { SafeTransferLib } from "@solady/utils/SafeTransferLib.sol";

import { IMEVStrategy } from "../interfaces/IMEVStrategy.sol";
import { DexLib } from "../libraries/DexLib.sol";
import { TransientLib } from "../libraries/TransientLib.sol";

/**
 * @title SandwichStrategy
 * @notice Multi-layer sandwich attack strategy for Uniswap V2/V3
 * @dev Executed via delegatecall from MEVHub — runs in hub's storage context.
 *      Supports 1-layer (classic), 3-layer, 5-layer, and 7-layer sandwiches.
 *
 *      Classic 1-layer sandwich:
 *      1. Front-run: buy tokenOut before victim
 *      2. (Victim tx executes at worse price)
 *      3. Back-run: sell tokenOut after victim
 *
 *      Multi-layer sandwich (Jared V2 technique):
 *      - Interleave swap layers with liquidity add/remove
 *      - Each layer amplifies price impact on the victim
 *      - Liquidity layers reduce slippage for the attacker's own swaps
 *
 *      All operations use assembly-optimized DexLib for direct pool interaction.
 *      Transient storage (EIP-1153) tracks intermediate balances between layers.
 *
 * @custom:security-contact security@multipli.com
 */
contract SandwichStrategy is IMEVStrategy {
    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Operation types within a sandwich
    enum OpType {
        SWAP_V2_FRONT, // Front-run swap on V2
        SWAP_V2_BACK, // Back-run swap on V2
        SWAP_V3_FRONT, // Front-run swap on V3
        SWAP_V3_BACK, // Back-run swap on V3
        ADD_LIQUIDITY_V2, // Add liquidity layer (Jared technique)
        REMOVE_LIQUIDITY_V2 // Remove liquidity layer
    }

    /// @dev Packed parameters for a V2 swap operation
    struct V2SwapParams {
        address pair;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        bool zeroForOne;
    }

    /// @dev Packed parameters for a V3 swap operation
    struct V3SwapParams {
        address pool;
        address tokenIn;
        address tokenOut;
        int256 amountIn;
        bool zeroForOne;
        uint160 sqrtPriceLimitX96;
    }

    /// @dev Parameters for a single sandwich layer
    struct SandwichLayer {
        OpType opType;
        bytes params;
    }

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error SandwichStrategy__InvalidOpType();
    error SandwichStrategy__NoLayers();

    /*//////////////////////////////////////////////////////////////
              USER-FACING STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IMEVStrategy
    /// @dev Decodes params as SandwichLayer[] and executes each layer sequentially.
    ///      Returns net profit across all layers. Called via delegatecall from MEVHub.
    function execute(bytes calldata params) external override returns (int256 profit) {
        SandwichLayer[] memory layers = abi.decode(params, (SandwichLayer[]));
        if (layers.length == 0) revert SandwichStrategy__NoLayers();

        uint256 totalIn;
        uint256 totalOut;

        uint256 length = layers.length;
        for (uint256 i; i < length;) {
            SandwichLayer memory layer = layers[i];

            if (layer.opType == OpType.SWAP_V2_FRONT || layer.opType == OpType.SWAP_V2_BACK) {
                (uint256 amountIn, uint256 amountOut) = _executeV2Swap(layer.params);
                totalIn += amountIn;
                totalOut += amountOut;

                // Store intermediate balance for next layer
                TransientLib.setBalance(i, amountOut);
            } else if (layer.opType == OpType.SWAP_V3_FRONT || layer.opType == OpType.SWAP_V3_BACK)
            {
                (uint256 amountIn, uint256 amountOut) = _executeV3Swap(layer.params);
                totalIn += amountIn;
                totalOut += amountOut;

                TransientLib.setBalance(i, amountOut);
            } else if (layer.opType == OpType.ADD_LIQUIDITY_V2) {
                _executeAddLiquidity(layer.params);
            } else if (layer.opType == OpType.REMOVE_LIQUIDITY_V2) {
                _executeRemoveLiquidity(layer.params);
            } else {
                revert SandwichStrategy__InvalidOpType();
            }

            unchecked {
                ++i;
            }
        }

        // Net profit = total output - total input (in base token terms)
        // Caller is responsible for ensuring tokens are comparable
        profit = int256(totalOut) - int256(totalIn);
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Execute a Uniswap V2 direct swap
    /// @param params ABI-encoded V2SwapParams
    /// @return amountIn The input amount used
    /// @return amountOut The output amount received
    function _executeV2Swap(bytes memory params)
        internal
        returns (uint256 amountIn, uint256 amountOut)
    {
        V2SwapParams memory p = abi.decode(params, (V2SwapParams));
        amountIn = p.amountIn;

        // Transfer input tokens to the pair
        SafeTransferLib.safeTransfer(p.tokenIn, p.pair, amountIn);

        // Execute direct pair swap via assembly
        amountOut = DexLib.swapV2(p.pair, amountIn, p.zeroForOne);
    }

    /// @dev Execute a Uniswap V3 direct swap
    /// @param params ABI-encoded V3SwapParams
    /// @return amountIn The input amount used
    /// @return amountOut The output amount received
    function _executeV3Swap(bytes memory params)
        internal
        returns (uint256 amountIn, uint256 amountOut)
    {
        V3SwapParams memory p = abi.decode(params, (V3SwapParams));
        amountIn = uint256(p.amountIn > 0 ? p.amountIn : -p.amountIn);

        // V3 swaps use callback to pay — tokens are pulled by the pool
        // The hub's uniswapV3SwapCallback handles payment
        (int256 amount0, int256 amount1) =
            DexLib.swapV3(p.pool, p.amountIn, p.zeroForOne, p.sqrtPriceLimitX96);

        // Output is the negative delta (tokens received)
        if (p.zeroForOne) {
            amountOut = uint256(-amount1);
        } else {
            amountOut = uint256(-amount0);
        }
    }

    /// @dev Add liquidity to a V2 pair (multi-layer sandwich technique)
    /// @param params ABI-encoded (pair, token0, token1, amount0, amount1)
    function _executeAddLiquidity(bytes memory params) internal {
        (address pair, address token0, address token1, uint256 amount0, uint256 amount1) =
            abi.decode(params, (address, address, address, uint256, uint256));

        // Transfer tokens to pair
        SafeTransferLib.safeTransfer(token0, pair, amount0);
        SafeTransferLib.safeTransfer(token1, pair, amount1);

        // Mint LP tokens to this contract (hub via delegatecall)
        assembly {
            // pair.mint(to) — selector: 0x6a627842
            let ptr := mload(0x40)
            mstore(ptr, 0x6a62784200000000000000000000000000000000000000000000000000000000)
            mstore(add(ptr, 0x04), address())

            let success := call(gas(), pair, 0, ptr, 0x24, ptr, 0x20)
            if iszero(success) {
                mstore(0x00, 0xde2a29e0) // DexLib__SwapFailed() reuse
                revert(0x1c, 0x04)
            }
            // LP tokens minted — stored in hub's balance
        }
    }

    /// @dev Remove liquidity from a V2 pair
    /// @param params ABI-encoded (pair, lpAmount)
    function _executeRemoveLiquidity(bytes memory params) internal {
        (address pair, uint256 lpAmount) = abi.decode(params, (address, uint256));

        // Transfer LP tokens to the pair for burning
        SafeTransferLib.safeTransfer(pair, pair, lpAmount);

        // Burn LP tokens, receiving underlying tokens
        assembly {
            // pair.burn(to) — selector: 0x89afcb44
            let ptr := mload(0x40)
            mstore(ptr, 0x89afcb4400000000000000000000000000000000000000000000000000000000)
            mstore(add(ptr, 0x04), address())

            let success := call(gas(), pair, 0, ptr, 0x24, ptr, 0x40)
            if iszero(success) {
                mstore(0x00, 0xde2a29e0)
                revert(0x1c, 0x04)
            }
            // Underlying tokens returned to hub
        }
    }
}
