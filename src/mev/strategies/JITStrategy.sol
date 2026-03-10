// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { SafeTransferLib } from "@solady/utils/SafeTransferLib.sol";

import { IMEVStrategy } from "../interfaces/IMEVStrategy.sol";
import { TransientLib } from "../libraries/TransientLib.sol";

/**
 * @title JITStrategy
 * @notice Just-In-Time liquidity provision strategy for Uniswap V3
 * @dev Executed via delegatecall from MEVHub — runs in hub's storage context.
 *
 *      JIT Liquidity Attack Flow:
 *      1. Add concentrated liquidity in tight tick range around victim's swap price
 *      2. (Victim swap executes, paying fees to our concentrated position)
 *      3. Remove liquidity immediately, collecting fees + original tokens
 *
 *      Key optimization (Jared V2 technique):
 *      - Skip NFT minting — call pool.mint() directly instead of
 *        NonfungiblePositionManager.mint() to avoid ~50k gas overhead
 *      - Use extremely tight tick ranges (1-2 ticks) for maximum fee capture
 *      - CLZ-optimized tick math via Solady FixedPointMathLib
 *
 *      All operations interact directly with V3 pools in assembly.
 *      Transient storage tracks position state between add/remove.
 *
 * @custom:security-contact security@multipli.com
 */
contract JITStrategy is IMEVStrategy {
    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Parameters for JIT liquidity provision
    struct JITParams {
        address pool; // V3 pool address
        address token0; // Pool's token0
        address token1; // Pool's token1
        int24 tickLower; // Lower tick of the position
        int24 tickUpper; // Upper tick of the position
        uint128 liquidity; // Liquidity amount to provide
        bool collectAfter; // Whether to collect and burn immediately
    }

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error JITStrategy__MintFailed();
    error JITStrategy__BurnFailed();
    error JITStrategy__CollectFailed();

    /*//////////////////////////////////////////////////////////////
              USER-FACING STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IMEVStrategy
    /// @dev Decodes params as JITParams and executes add/remove liquidity.
    ///      Returns net profit from fee capture. Called via delegatecall.
    function execute(bytes calldata params) external override returns (int256 profit) {
        JITParams memory p = abi.decode(params, (JITParams));

        // Phase 1: Add concentrated liquidity
        (uint256 amount0Used, uint256 amount1Used) = _mintPosition(p);

        // Store amounts used for profit calculation
        TransientLib.setBalance(0, amount0Used);
        TransientLib.setBalance(1, amount1Used);

        if (p.collectAfter) {
            // Phase 2: Remove liquidity and collect fees
            (uint256 amount0Received, uint256 amount1Received) = _burnAndCollect(p);

            // Profit = received - used (in token0 terms for simplicity)
            // The caller should price these correctly offchain
            int256 profit0 = int256(amount0Received) - int256(amount0Used);
            int256 profit1 = int256(amount1Received) - int256(amount1Used);

            profit = profit0 + profit1;
        }
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Mint a concentrated liquidity position directly on the V3 pool
    /// @param p JIT parameters
    /// @return amount0 Token0 amount deposited
    /// @return amount1 Token1 amount deposited
    function _mintPosition(JITParams memory p) internal returns (uint256 amount0, uint256 amount1) {
        // pool.mint(recipient, tickLower, tickUpper, amount, data)
        // We are the recipient — tokens are pulled via mintCallback
        assembly {
            let ptr := mload(0x40)
            // selector: mint(address,int24,int24,uint128,bytes)
            // 0x3c8a7d8d
            mstore(ptr, 0x3c8a7d8d00000000000000000000000000000000000000000000000000000000)
            mstore(add(ptr, 0x04), address()) // recipient = this (hub)
            mstore(add(ptr, 0x24), mload(add(p, 0x60))) // tickLower
            mstore(add(ptr, 0x44), mload(add(p, 0x80))) // tickUpper
            mstore(add(ptr, 0x64), mload(add(p, 0xa0))) // liquidity
            mstore(add(ptr, 0x84), 0xa0) // data offset
            mstore(add(ptr, 0xa4), 0x40) // data length (2 addresses)
            mstore(add(ptr, 0xc4), mload(add(p, 0x20))) // token0
            mstore(add(ptr, 0xe4), mload(add(p, 0x40))) // token1

            let success :=
                call(
                    gas(),
                    mload(p), // pool
                    0,
                    ptr,
                    0x104,
                    ptr,
                    0x40
                )

            if iszero(success) {
                // JITStrategy__MintFailed()
                mstore(0x00, 0x4e2b1e7a)
                revert(0x1c, 0x04)
            }

            amount0 := mload(ptr)
            amount1 := mload(add(ptr, 0x20))
        }
    }

    /// @dev Burn a liquidity position and collect all tokens + fees
    /// @param p JIT parameters (same position to burn)
    /// @return amount0 Total token0 received (principal + fees)
    /// @return amount1 Total token1 received (principal + fees)
    function _burnAndCollect(JITParams memory p)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        // Step 1: Burn the position
        assembly {
            let ptr := mload(0x40)
            // pool.burn(tickLower, tickUpper, amount)
            // selector: 0xa34123a7
            mstore(ptr, 0xa34123a700000000000000000000000000000000000000000000000000000000)
            mstore(add(ptr, 0x04), mload(add(p, 0x60))) // tickLower
            mstore(add(ptr, 0x24), mload(add(p, 0x80))) // tickUpper
            mstore(add(ptr, 0x44), mload(add(p, 0xa0))) // liquidity

            let success :=
                call(
                    gas(),
                    mload(p), // pool
                    0,
                    ptr,
                    0x64,
                    0,
                    0
                )

            if iszero(success) {
                // JITStrategy__BurnFailed()
                mstore(0x00, 0x7b94e839)
                revert(0x1c, 0x04)
            }
        }

        // Step 2: Collect all owed tokens (principal + fees)
        assembly {
            let ptr := mload(0x40)
            // pool.collect(recipient, tickLower, tickUpper, amount0Requested, amount1Requested)
            // selector: 0x4f1eb3d8
            mstore(ptr, 0x4f1eb3d800000000000000000000000000000000000000000000000000000000)
            mstore(add(ptr, 0x04), address()) // recipient = this (hub)
            mstore(add(ptr, 0x24), mload(add(p, 0x60))) // tickLower
            mstore(add(ptr, 0x44), mload(add(p, 0x80))) // tickUpper
            // Request max uint128 for both to collect everything
            mstore(
                add(ptr, 0x64),
                0x00000000000000000000000000000000ffffffffffffffffffffffffffffffff
            )
            mstore(
                add(ptr, 0x84),
                0x00000000000000000000000000000000ffffffffffffffffffffffffffffffff
            )

            let success :=
                call(
                    gas(),
                    mload(p), // pool
                    0,
                    ptr,
                    0xa4,
                    ptr,
                    0x40
                )

            if iszero(success) {
                // JITStrategy__CollectFailed()
                mstore(0x00, 0x6b836e5e)
                revert(0x1c, 0x04)
            }

            amount0 := mload(ptr)
            amount1 := mload(add(ptr, 0x20))
        }
    }

    /*//////////////////////////////////////////////////////////////
                        V3 MINT CALLBACK
    //////////////////////////////////////////////////////////////*/

    /// @notice Uniswap V3 mint callback — pays the pool for minted liquidity
    /// @param amount0Owed Token0 amount owed to the pool
    /// @param amount1Owed Token1 amount owed to the pool
    /// @param data Encoded (token0, token1) addresses
    /// @dev Called by the V3 pool during mint(). Since JITStrategy is delegatecalled,
    ///      this callback actually executes on the MEVHub. The hub must implement
    ///      uniswapV3MintCallback or this function via delegatecall context.
    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    )
        external
    {
        (address token0, address token1) = abi.decode(data, (address, address));

        if (amount0Owed > 0) {
            SafeTransferLib.safeTransfer(token0, msg.sender, amount0Owed);
        }
        if (amount1Owed > 0) {
            SafeTransferLib.safeTransfer(token1, msg.sender, amount1Owed);
        }
    }
}
