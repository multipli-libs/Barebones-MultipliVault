// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";

/**
 * @title DexLib
 * @notice Assembly-optimized DEX integration library for MEV execution
 * @dev All swap functions bypass routers and call pools/pairs directly in assembly
 *      to minimize gas overhead. Uses Solady FixedPointMathLib for CLZ-optimized
 *      sqrt/log2 (native CLZ on Osaka EVM, software fallback on Cancun).
 *
 *      Gas savings vs router:
 *      - Uni V2 direct swap: ~30k gas saved (no router overhead)
 *      - Uni V3 direct swap: ~25k gas saved (no router overhead)
 *      - Assembly getAmountOut: ~200 gas vs ~800 gas Solidity
 *
 * @custom:security-contact security@multipli.com
 */
library DexLib {
    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Uniswap V2 factory init code hash (UniswapV2Pair)
    bytes32 internal constant UNI_V2_INIT_CODE_HASH =
        0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f;

    /// @dev Trader Joe V1 factory init code hash (JoePair)
    bytes32 internal constant JOE_V1_INIT_CODE_HASH =
        0x0bbca9af0511ad1a1da383135cf3a8d2ac620e549ef9f6ae3a4c33c2fed0af91;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error DexLib__InsufficientInputAmount();
    error DexLib__InsufficientLiquidity();
    error DexLib__SwapFailed();

    /*//////////////////////////////////////////////////////////////
                         UNISWAP V2 OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Execute a direct Uniswap V2 pair swap in assembly
    /// @param pair The Uniswap V2 pair address
    /// @param amountIn The input amount (must already be transferred to pair)
    /// @param zeroForOne True if swapping token0 for token1
    /// @return amountOut The output amount received
    /// @dev Caller must transfer amountIn to the pair BEFORE calling this.
    ///      Skips the router entirely — calls pair.swap() directly.
    function swapV2(
        address pair,
        uint256 amountIn,
        bool zeroForOne
    )
        internal
        returns (uint256 amountOut)
    {
        // Get reserves from pair
        (uint256 reserveIn, uint256 reserveOut) = _getReservesOrdered(pair, zeroForOne);

        // Calculate output amount
        amountOut = getAmountOut(amountIn, reserveIn, reserveOut);

        // Execute swap
        assembly {
            // pair.swap(amount0Out, amount1Out, to, data)
            // selector: 0x022c0d9f
            let ptr := mload(0x40)
            mstore(ptr, 0x022c0d9f00000000000000000000000000000000000000000000000000000000)

            switch zeroForOne
            case 1 {
                // Swapping token0 → token1: amount0Out = 0, amount1Out = amountOut
                mstore(add(ptr, 0x04), 0)
                mstore(add(ptr, 0x24), amountOut)
            }
            default {
                // Swapping token1 → token0: amount0Out = amountOut, amount1Out = 0
                mstore(add(ptr, 0x04), amountOut)
                mstore(add(ptr, 0x24), 0)
            }

            // to = address(this)
            mstore(add(ptr, 0x44), address())
            // data offset (empty bytes)
            mstore(add(ptr, 0x64), 0x80)
            // data length = 0
            mstore(add(ptr, 0x84), 0)

            let success := call(gas(), pair, 0, ptr, 0xa4, 0, 0)
            if iszero(success) {
                // Revert with DexLib__SwapFailed()
                mstore(0x00, 0xde2a29e0) // selector
                revert(0x1c, 0x04)
            }
        }
    }

    /// @notice Calculate the optimal input amount for a V2 sandwich front-run
    /// @param reserveIn The reserve of the input token
    /// @param reserveOut The reserve of the output token
    /// @param victimAmountIn The victim's input amount
    /// @return optimalIn The optimal front-run input amount
    /// @dev Uses the constant-product formula to maximize extractable value.
    ///      sqrt() uses Solady CLZ-optimized implementation (5 gas on Osaka).
    function calcOptimalV2Input(
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 victimAmountIn
    )
        internal
        pure
        returns (uint256 optimalIn)
    {
        // Optimal sandwich input derived from constant-product AMM formula:
        // optimalIn = sqrt(reserveIn * (reserveIn + victimAmountIn * 997/1000)) - reserveIn
        // Simplified: maximize profit from price impact
        uint256 k = reserveIn * reserveOut;
        uint256 newReserveIn = reserveIn + (victimAmountIn * 997) / 1000;
        uint256 sqrtProduct = FixedPointMathLib.sqrt(reserveIn * newReserveIn);
        optimalIn = sqrtProduct > reserveIn ? sqrtProduct - reserveIn : 0;

        // Cap at available liquidity to avoid excessive slippage
        if (optimalIn > reserveIn / 3) {
            optimalIn = reserveIn / 3;
        }
    }

    /// @notice Constant-product getAmountOut in pure assembly
    /// @param amountIn The input amount
    /// @param reserveIn The input token reserve
    /// @param reserveOut The output token reserve
    /// @return amountOut The output amount after 0.3% fee
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    )
        internal
        pure
        returns (uint256 amountOut)
    {
        assembly {
            // Validate inputs
            if iszero(amountIn) {
                // DexLib__InsufficientInputAmount()
                mstore(0x00, 0x5c5989f4)
                revert(0x1c, 0x04)
            }
            if or(iszero(reserveIn), iszero(reserveOut)) {
                // DexLib__InsufficientLiquidity()
                mstore(0x00, 0xbb55fd27)
                revert(0x1c, 0x04)
            }

            // amountInWithFee = amountIn * 997
            let amountInWithFee := mul(amountIn, 997)
            // numerator = amountInWithFee * reserveOut
            let numerator := mul(amountInWithFee, reserveOut)
            // denominator = reserveIn * 1000 + amountInWithFee
            let denominator := add(mul(reserveIn, 1000), amountInWithFee)
            // amountOut = numerator / denominator
            amountOut := div(numerator, denominator)
        }
    }

    /// @notice Compute Uniswap V2 pair address via CREATE2
    /// @param factory The factory address
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @param initCodeHash The init code hash for the factory's pair contract
    /// @return pair The deterministic pair address
    function computePairAddress(
        address factory,
        address tokenA,
        address tokenB,
        bytes32 initCodeHash
    )
        internal
        pure
        returns (address pair)
    {
        assembly {
            // Sort tokens
            let token0 := tokenA
            let token1 := tokenB
            if lt(tokenB, tokenA) {
                token0 := tokenB
                token1 := tokenA
            }

            // salt = keccak256(abi.encodePacked(token0, token1))
            let ptr := mload(0x40)
            mstore(ptr, shl(96, token0))
            mstore(add(ptr, 0x14), shl(96, token1))
            let salt := keccak256(ptr, 0x28)

            // pair = address(keccak256(abi.encodePacked(0xff, factory, salt, initCodeHash)))
            mstore(ptr, shl(96, factory))
            mstore8(ptr, 0xff)
            mstore(add(ptr, 0x15), salt)
            mstore(add(ptr, 0x35), initCodeHash)
            pair := and(keccak256(ptr, 0x55), 0xffffffffffffffffffffffffffffffffffffffff)
        }
    }

    /*//////////////////////////////////////////////////////////////
                         UNISWAP V3 OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Execute a direct Uniswap V3 pool swap
    /// @param pool The Uniswap V3 pool address
    /// @param amountIn The input amount (signed — positive for exact input)
    /// @param zeroForOne True if swapping token0 for token1
    /// @param sqrtPriceLimitX96 The price limit for the swap (0 for max slippage)
    /// @return amount0 The delta of token0
    /// @return amount1 The delta of token1
    /// @dev Caller must implement the uniswapV3SwapCallback on the calling contract.
    ///      Since MEVHub calls strategies via delegatecall, the callback lands on MEVHub.
    function swapV3(
        address pool,
        int256 amountIn,
        bool zeroForOne,
        uint160 sqrtPriceLimitX96
    )
        internal
        returns (int256 amount0, int256 amount1)
    {
        // Set default price limits if none provided
        if (sqrtPriceLimitX96 == 0) {
            sqrtPriceLimitX96 = zeroForOne
                ? 4_295_128_739 + 1  // MIN_SQRT_RATIO + 1
                : 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342 - 1; // MAX - 1
        }

        assembly {
            // pool.swap(recipient, zeroForOne, amountSpecified, sqrtPriceLimitX96, data)
            // selector: 0x128acb08
            let ptr := mload(0x40)
            mstore(ptr, 0x128acb0800000000000000000000000000000000000000000000000000000000)
            // recipient = address(this)
            mstore(add(ptr, 0x04), address())
            // zeroForOne
            mstore(add(ptr, 0x24), zeroForOne)
            // amountSpecified
            mstore(add(ptr, 0x44), amountIn)
            // sqrtPriceLimitX96
            mstore(add(ptr, 0x64), sqrtPriceLimitX96)
            // data offset
            mstore(add(ptr, 0x84), 0xa0)
            // data length = 0
            mstore(add(ptr, 0xa4), 0)

            let success := call(gas(), pool, 0, ptr, 0xc4, ptr, 0x40)
            if iszero(success) {
                mstore(0x00, 0xde2a29e0) // DexLib__SwapFailed()
                revert(0x1c, 0x04)
            }

            amount0 := mload(ptr)
            amount1 := mload(add(ptr, 0x20))
        }
    }

    /*//////////////////////////////////////////////////////////////
                            MATH UTILITIES
    //////////////////////////////////////////////////////////////*/

    /// @notice Compute sqrtPriceX96 from a price ratio
    /// @param priceX96 The price as a Q96 fixed-point number
    /// @return sqrtPriceX96 The square root price in Q96 format
    /// @dev Uses Solady sqrt() which leverages native CLZ on Osaka EVM (5 gas)
    ///      and falls back to software binary-search CLZ on Cancun (~184 gas).
    function computeSqrtPriceX96(uint256 priceX96) internal pure returns (uint160 sqrtPriceX96) {
        // sqrtPriceX96 = sqrt(priceX96 * 2^96) = sqrt(priceX96) * 2^48
        // But we want sqrt of the full Q192 value for precision
        sqrtPriceX96 = uint160(FixedPointMathLib.sqrt(priceX96 << 96));
    }

    /// @notice Full-precision mulDiv for AMM calculations
    /// @param a First multiplicand
    /// @param b Second multiplicand
    /// @param denominator The divisor
    /// @return result The result of (a * b) / denominator with full precision
    function mulDiv(
        uint256 a,
        uint256 b,
        uint256 denominator
    )
        internal
        pure
        returns (uint256 result)
    {
        result = FixedPointMathLib.mulDiv(a, b, denominator);
    }

    /*//////////////////////////////////////////////////////////////
                       PRIVATE HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Get reserves from a Uni V2 pair, ordered by swap direction
    /// @param pair The pair address
    /// @param zeroForOne True if swapping token0→token1
    /// @return reserveIn The input token reserve
    /// @return reserveOut The output token reserve
    function _getReservesOrdered(
        address pair,
        bool zeroForOne
    )
        private
        view
        returns (uint256 reserveIn, uint256 reserveOut)
    {
        assembly {
            // pair.getReserves() — selector: 0x0902f1ac
            let ptr := mload(0x40)
            mstore(ptr, 0x0902f1ac00000000000000000000000000000000000000000000000000000000)

            let success := staticcall(gas(), pair, ptr, 0x04, ptr, 0x60)
            if iszero(success) {
                mstore(0x00, 0xde2a29e0) // DexLib__SwapFailed()
                revert(0x1c, 0x04)
            }

            let reserve0 := mload(ptr)
            let reserve1 := mload(add(ptr, 0x20))

            switch zeroForOne
            case 1 {
                reserveIn := reserve0
                reserveOut := reserve1
            }
            default {
                reserveIn := reserve1
                reserveOut := reserve0
            }
        }
    }
}
