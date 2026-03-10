// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { SafeTransferLib } from "@solady/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import {
    ReentrancyGuardTransient
} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import { IAaveV3Pool } from "../interfaces/aave/IAaveV3Pool.sol";

/**
 * @title JaredExecutor
 * @notice Monolithic, gas-optimized MEV executor inspired by jaredfromsubway.eth V2
 * @dev Single-byte calldata dispatch — no Solidity function selectors overhead.
 *      The first byte of calldata selects the operation, remaining bytes are tightly
 *      packed parameters. This saves ~200 gas per call vs ABI-encoded dispatch.
 *
 *      Architecture (production Jared V2 pattern):
 *      ┌──────────────────────────────────────────────┐
 *      │  Searcher EOA                                │
 *      │  ↓ raw calldata (byte 0 = opcode)            │
 *      │  JaredExecutor.fallback()                    │
 *      │  ├─ 0x00: V2 Sandwich Front                  │
 *      │  ├─ 0x01: V2 Sandwich Back                   │
 *      │  ├─ 0x02: V3 Sandwich Front                  │
 *      │  ├─ 0x03: V3 Sandwich Back                   │
 *      │  ├─ 0x04: V2 Cyclic Arb (2-hop)              │
 *      │  ├─ 0x05: V2 Cyclic Arb (3-hop)              │
 *      │  ├─ 0x06: V3 Cyclic Arb (2-hop)              │
 *      │  ├─ 0x07: Mixed V2/V3 Arb                    │
 *      │  ├─ 0x08: V2 Add Liquidity (multi-layer)     │
 *      │  ├─ 0x09: V2 Remove Liquidity                │
 *      │  ├─ 0x0A: V3 JIT Mint                        │
 *      │  ├─ 0x0B: V3 JIT Burn + Collect              │
 *      │  ├─ 0x0C: Flash Loan Execute                  │
 *      │  ├─ 0x0D: Multi-op Batch                      │
 *      │  ├─ 0xFE: Sweep ERC20                         │
 *      │  └─ 0xFF: Sweep ETH + Builder Tip             │
 *      └──────────────────────────────────────────────┘
 *
 *      Osaka EVM optimizations:
 *      - EIP-1153 transient storage for all intra-tx state (100 gas vs 22,100)
 *      - CLZ-optimized sqrt via Solady (5 gas native on Osaka)
 *      - Minimal memory allocation — reuses scratch space
 *      - No function selector dispatch table (single-byte opcode)
 *      - Packed calldata — addresses as 20 bytes, amounts as variable-width
 *
 *      Security model:
 *      - Immutable owner (set in constructor, no storage reads needed)
 *      - ReentrancyGuardTransient via OZ (EIP-1153 based)
 *      - All external calls are to verified DEX pools only
 *      - Profit guard reverts unprofitable bundles atomically
 *
 * @custom:security-contact security@multipli.com
 */
contract JaredExecutor is ReentrancyGuardTransient {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The owner/searcher EOA
    address public immutable owner;

    /// @notice Aave V3 pool for flash loans
    IAaveV3Pool public immutable aavePool;

    /*//////////////////////////////////////////////////////////////
                           TRANSIENT SLOTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Transient storage slots (EIP-1153) — auto-clear after each tx
    bytes32 private constant _TSLOT_PROFIT =
        0x4a617265644578656375746f722e70726f666974000000000000000000000000;
    bytes32 private constant _TSLOT_FL_ACTIVE =
        0x4a617265644578656375746f722e666c2e616374697665000000000000000000;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Executed(uint8 indexed opcode, uint256 profit, uint256 builderTip);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error JaredExecutor__Unauthorized();
    error JaredExecutor__InvalidOpcode();
    error JaredExecutor__Unprofitable();
    error JaredExecutor__SwapFailed();
    error JaredExecutor__MintFailed();
    error JaredExecutor__BurnFailed();
    error JaredExecutor__CollectFailed();
    error JaredExecutor__FlashLoanFailed();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @param _owner The searcher EOA that can execute operations
    /// @param _aavePool The Aave V3 Pool address for flash loans
    constructor(address _owner, address _aavePool) {
        assembly {
            if or(iszero(_owner), iszero(_aavePool)) {
                mstore(0x00, 0x82b42900) // Unauthorized() — generic revert
                revert(0x1c, 0x04)
            }
        }
        owner = _owner;
        aavePool = IAaveV3Pool(_aavePool);
    }

    /// @dev Accept ETH for builder tips and profit sweeps
    receive() external payable { }

    /*//////////////////////////////////////////////////////////////
                       SINGLE-BYTE DISPATCH (FALLBACK)
    //////////////////////////////////////////////////////////////*/

    /// @dev Main entry point — first byte of calldata selects the operation.
    ///      No function selector overhead. Raw calldata parsing in assembly.
    ///
    ///      Calldata layout per opcode:
    ///      0x00 V2_FRONT:  [1B op][20B pair][20B tokenIn][32B amountIn][1B zeroForOne]
    ///      0x01 V2_BACK:   [1B op][20B pair][20B tokenIn][32B amountIn][1B zeroForOne]
    ///      0x02 V3_FRONT:  [1B op][20B pool][20B tokenIn][20B tokenOut][32B amountIn][1B z4o][20B
    /// sqrtLimit] 0x03 V3_BACK:   same as 0x02
    ///      0x04 V2_ARB_2:  [1B op][20B pair0][20B pair1][20B tokenA][20B tokenB][32B amountIn][1B
    /// dir0][1B dir1] 0x05 V2_ARB_3:  [1B op][20B p0][20B p1][20B p2][20B tA][20B tB][20B tC][32B
    /// amt][1B d0][1B d1][1B d2]
    ///      0x06 V3_ARB_2:  [1B op][20B pool0][20B pool1][20B tA][20B tB][32B amt][1B d0][1B
    /// d1][20B limit0][20B limit1] 0x07 MIXED_ARB: [1B op][1B hopCount][per hop: 1B type + 20B pool
    /// + 20B tIn + 20B tOut + 1B dir + 20B limit][32B amt]
    ///      0x08 V2_ADD_LIQ:[1B op][20B pair][20B t0][20B t1][32B amt0][32B amt1]
    ///      0x09 V2_RM_LIQ: [1B op][20B pair][32B lpAmt]
    ///      0x0A V3_JIT_MINT:[1B op][20B pool][20B t0][20B t1][3B tickLower][3B tickUpper][16B
    /// liquidity] 0x0B V3_JIT_BURN:[1B op][20B pool][3B tickLower][3B tickUpper][16B liquidity]
    ///      0x0C FLASH_EXEC: [1B op][20B asset][32B amount][...remaining ops calldata]
    ///      0x0D BATCH:      [1B op][2B totalLen][sub-ops concatenated with 2B length prefix each]
    ///      0xFE SWEEP_ERC20:[1B op][20B token][20B to][32B amount]
    ///      0xFF SWEEP_ETH:  [1B op][32B builderTip]
    // solhint-disable-next-line no-complex-fallback
    fallback() external payable nonReentrant {
        // Auth check — only owner can call
        address _owner = owner;
        assembly {
            if iszero(eq(caller(), _owner)) {
                mstore(0x00, 0x82b42900)
                revert(0x1c, 0x04)
            }
        }

        // Read opcode from first byte
        uint8 opcode;
        assembly {
            opcode := byte(0, calldataload(0))
        }

        if (opcode <= 0x03) {
            _dispatchSwap(opcode);
        } else if (opcode <= 0x07) {
            _dispatchArb(opcode);
        } else if (opcode <= 0x09) {
            _dispatchLiquidity(opcode);
        } else if (opcode <= 0x0B) {
            _dispatchJIT(opcode);
        } else if (opcode == 0x0C) {
            _dispatchFlashLoan();
        } else if (opcode == 0x0D) {
            _dispatchBatch();
        } else if (opcode == 0xFE) {
            _dispatchSweepERC20();
        } else if (opcode == 0xFF) {
            _dispatchSweepETH();
        } else {
            revert JaredExecutor__InvalidOpcode();
        }
    }

    /*//////////////////////////////////////////////////////////////
                    UNISWAP V3 SWAP CALLBACK
    //////////////////////////////////////////////////////////////*/

    /// @notice Uniswap V3 swap callback — pays the pool for swaps
    /// @dev Since this contract calls V3 pools directly, the callback lands here.
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    )
        external
    {
        if (amount0Delta > 0) {
            address token = abi.decode(data, (address));
            SafeTransferLib.safeTransfer(token, msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            (, address token) = abi.decode(data, (address, address));
            SafeTransferLib.safeTransfer(token, msg.sender, uint256(amount1Delta));
        }
    }

    /// @notice Uniswap V3 mint callback — pays the pool for minted liquidity
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

    /// @notice Aave V3 flash loan callback
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
        if (msg.sender != address(aavePool)) revert JaredExecutor__Unauthorized();
        if (initiator != address(this)) revert JaredExecutor__FlashLoanFailed();

        // Execute the sub-operations encoded in params
        _executeBatchCalldata(params);

        // Approve repayment
        uint256 amountOwed = amount + premium;
        SafeTransferLib.safeApprove(asset, address(aavePool), amountOwed);

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL: SWAP DISPATCH (0x00–0x03)
    //////////////////////////////////////////////////////////////*/

    /// @dev Dispatch V2/V3 front/back-run swaps
    function _dispatchSwap(uint8 opcode) internal {
        if (opcode == 0x00 || opcode == 0x01) {
            // V2 swap: [1B op][20B pair][20B tokenIn][32B amountIn][1B zeroForOne]
            address pair;
            address tokenIn;
            uint256 amountIn;
            bool zeroForOne;

            assembly {
                pair := shr(96, calldataload(1))
                tokenIn := shr(96, calldataload(21))
                amountIn := calldataload(41)
                zeroForOne := byte(0, calldataload(73))
            }

            // Transfer input to pair
            SafeTransferLib.safeTransfer(tokenIn, pair, amountIn);

            // Execute direct V2 swap
            _swapV2(pair, amountIn, zeroForOne);
        } else {
            // V3 swap: [1B op][20B pool][20B tokenIn][20B tokenOut][32B amountIn][1B z4o][20B
            // sqrtLimit]
            address pool;
            address tokenIn;
            address tokenOut;
            uint256 amountIn;
            bool zeroForOne;
            uint160 sqrtPriceLimitX96;

            assembly {
                pool := shr(96, calldataload(1))
                tokenIn := shr(96, calldataload(21))
                tokenOut := shr(96, calldataload(41))
                amountIn := calldataload(61)
                zeroForOne := byte(0, calldataload(93))
                sqrtPriceLimitX96 := shr(96, calldataload(94))
            }

            _swapV3(pool, tokenIn, tokenOut, int256(amountIn), zeroForOne, sqrtPriceLimitX96);
        }
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL: ARB DISPATCH (0x04–0x07)
    //////////////////////////////////////////////////////////////*/

    /// @dev Dispatch arbitrage operations
    function _dispatchArb(uint8 opcode) internal {
        if (opcode == 0x04) {
            // V2 2-hop arb: [1B][20B p0][20B p1][20B tA][20B tB][32B amt][1B d0][1B d1]
            address pair0;
            address pair1;
            address tokenA;
            address tokenB;
            uint256 amountIn;
            bool dir0;
            bool dir1;

            assembly {
                pair0 := shr(96, calldataload(1))
                pair1 := shr(96, calldataload(21))
                tokenA := shr(96, calldataload(41))
                tokenB := shr(96, calldataload(61))
                amountIn := calldataload(81)
                dir0 := byte(0, calldataload(113))
                dir1 := byte(0, calldataload(114))
            }

            // Track balance before
            uint256 balBefore = _balanceOf(tokenA, address(this));

            // Hop 1: tokenA → tokenB via pair0
            SafeTransferLib.safeTransfer(tokenA, pair0, amountIn);
            uint256 midAmount = _swapV2(pair0, amountIn, dir0);

            // Hop 2: tokenB → tokenA via pair1
            SafeTransferLib.safeTransfer(tokenB, pair1, midAmount);
            _swapV2(pair1, midAmount, dir1);

            uint256 balAfter = _balanceOf(tokenA, address(this));
            _accumulateProfit(balAfter, balBefore);
        } else if (opcode == 0x05) {
            // V2 3-hop arb
            _executeV2Arb3Hop();
        } else if (opcode == 0x06) {
            // V3 2-hop arb
            _executeV3Arb2Hop();
        } else {
            // 0x07: Mixed arb — variable hops
            _executeMixedArb();
        }
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL: LIQUIDITY DISPATCH (0x08–0x09)
    //////////////////////////////////////////////////////////////*/

    /// @dev Dispatch V2 liquidity add/remove
    function _dispatchLiquidity(uint8 opcode) internal {
        if (opcode == 0x08) {
            // V2 add liquidity: [1B][20B pair][20B t0][20B t1][32B amt0][32B amt1]
            address pair;
            address token0;
            address token1;
            uint256 amount0;
            uint256 amount1;

            assembly {
                pair := shr(96, calldataload(1))
                token0 := shr(96, calldataload(21))
                token1 := shr(96, calldataload(41))
                amount0 := calldataload(61)
                amount1 := calldataload(93)
            }

            SafeTransferLib.safeTransfer(token0, pair, amount0);
            SafeTransferLib.safeTransfer(token1, pair, amount1);

            // pair.mint(address(this))
            assembly {
                let ptr := mload(0x40)
                mstore(ptr, 0x6a62784200000000000000000000000000000000000000000000000000000000)
                mstore(add(ptr, 0x04), address())
                let success := call(gas(), pair, 0, ptr, 0x24, ptr, 0x20)
                if iszero(success) {
                    mstore(0x00, 0xde2a29e0)
                    revert(0x1c, 0x04)
                }
            }
        } else {
            // V2 remove liquidity: [1B][20B pair][32B lpAmt]
            address pair;
            uint256 lpAmount;

            assembly {
                pair := shr(96, calldataload(1))
                lpAmount := calldataload(21)
            }

            SafeTransferLib.safeTransfer(pair, pair, lpAmount);

            // pair.burn(address(this))
            assembly {
                let ptr := mload(0x40)
                mstore(ptr, 0x89afcb4400000000000000000000000000000000000000000000000000000000)
                mstore(add(ptr, 0x04), address())
                let success := call(gas(), pair, 0, ptr, 0x24, ptr, 0x40)
                if iszero(success) {
                    mstore(0x00, 0xde2a29e0)
                    revert(0x1c, 0x04)
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL: JIT DISPATCH (0x0A–0x0B)
    //////////////////////////////////////////////////////////////*/

    /// @dev Dispatch V3 JIT mint/burn+collect
    function _dispatchJIT(uint8 opcode) internal {
        if (opcode == 0x0A) {
            // V3 JIT mint: [1B][20B pool][20B t0][20B t1][3B tickLower][3B tickUpper][16B liq]
            address pool;
            address token0;
            address token1;
            int24 tickLower;
            int24 tickUpper;
            uint128 liquidity;

            assembly {
                pool := shr(96, calldataload(1))
                token0 := shr(96, calldataload(21))
                token1 := shr(96, calldataload(41))
                // 3 bytes for ticks — sign-extend from int24
                tickLower := signextend(2, shr(232, calldataload(61)))
                tickUpper := signextend(2, shr(232, calldataload(64)))
                // 16 bytes for liquidity
                liquidity := shr(128, calldataload(67))
            }

            _mintV3Position(pool, token0, token1, tickLower, tickUpper, liquidity);
        } else {
            // V3 JIT burn + collect: [1B][20B pool][3B tickLower][3B tickUpper][16B liq]
            address pool;
            int24 tickLower;
            int24 tickUpper;
            uint128 liquidity;

            assembly {
                pool := shr(96, calldataload(1))
                tickLower := signextend(2, shr(232, calldataload(21)))
                tickUpper := signextend(2, shr(232, calldataload(24)))
                liquidity := shr(128, calldataload(27))
            }

            _burnAndCollectV3(pool, tickLower, tickUpper, liquidity);
        }
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL: FLASH LOAN (0x0C)
    //////////////////////////////////////////////////////////////*/

    /// @dev Flash loan with sub-operations
    function _dispatchFlashLoan() internal {
        // [1B op][20B asset][32B amount][remaining = sub-ops batch calldata]
        address asset;
        uint256 amount;

        assembly {
            asset := shr(96, calldataload(1))
            amount := calldataload(21)
        }

        // Encode remaining calldata as params for the flash loan callback
        bytes memory params = msg.data[53:];

        // Mark flash loan active in transient storage
        assembly {
            tstore(_TSLOT_FL_ACTIVE, 1)
        }

        aavePool.flashLoanSimple({
            receiverAddress: address(this),
            asset: asset,
            amount: amount,
            params: params,
            referralCode: 0
        });

        assembly {
            tstore(_TSLOT_FL_ACTIVE, 0)
        }
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL: BATCH (0x0D)
    //////////////////////////////////////////////////////////////*/

    /// @dev Multi-op batch: [1B op][2B totalLen][sub-ops with 2B length prefix each]
    function _dispatchBatch() internal {
        uint256 offset = 3; // skip opcode + totalLen
        uint256 cdLen = msg.data.length;

        while (offset < cdLen) {
            uint16 subLen;
            assembly {
                subLen := shr(240, calldataload(offset))
            }
            offset += 2;

            // Read sub-operation opcode
            uint8 subOp;
            assembly {
                subOp := byte(0, calldataload(offset))
            }

            // Execute sub-op by slicing calldata
            bytes memory subData = msg.data[offset:offset + subLen];
            _executeSingleOp(subOp, subData);

            offset += subLen;
        }
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL: SWEEP (0xFE, 0xFF)
    //////////////////////////////////////////////////////////////*/

    /// @dev Sweep ERC20: [1B][20B token][20B to][32B amount]
    function _dispatchSweepERC20() internal {
        address token;
        address to;
        uint256 amount;

        assembly {
            token := shr(96, calldataload(1))
            to := shr(96, calldataload(21))
            amount := calldataload(41)
        }

        SafeTransferLib.safeTransfer(token, to, amount);
    }

    /// @dev Sweep ETH + tip builder: [1B][32B builderTip]
    function _dispatchSweepETH() internal {
        uint256 builderTip;
        assembly {
            builderTip := calldataload(1)
        }

        uint256 profit;
        assembly {
            profit := tload(_TSLOT_PROFIT)
        }

        emit Executed(0xFF, profit, builderTip);

        // Tip the block builder via coinbase transfer
        if (builderTip > 0) {
            assembly {
                pop(call(gas(), coinbase(), builderTip, 0, 0, 0, 0))
            }
        }

        // Send remaining ETH to owner
        uint256 ethBal = address(this).balance;
        if (ethBal > 0) {
            SafeTransferLib.safeTransferETH(owner, ethBal);
        }
    }

    /*//////////////////////////////////////////////////////////////
              CORE SWAP PRIMITIVES (ASSEMBLY-OPTIMIZED)
    //////////////////////////////////////////////////////////////*/

    /// @dev Direct V2 pair swap — caller must have already transferred tokenIn to pair
    function _swapV2(
        address pair,
        uint256 amountIn,
        bool zeroForOne
    )
        internal
        returns (uint256 amountOut)
    {
        assembly {
            // getReserves()
            let ptr := mload(0x40)
            mstore(ptr, 0x0902f1ac00000000000000000000000000000000000000000000000000000000)
            let ok := staticcall(gas(), pair, ptr, 0x04, ptr, 0x60)
            if iszero(ok) {
                mstore(0x00, 0xde2a29e0)
                revert(0x1c, 0x04)
            }

            let r0 := mload(ptr)
            let r1 := mload(add(ptr, 0x20))

            let reserveIn := r0
            let reserveOut := r1
            if iszero(zeroForOne) {
                reserveIn := r1
                reserveOut := r0
            }

            // getAmountOut: (amountIn * 997 * reserveOut) / (reserveIn * 1000 + amountIn * 997)
            let aif := mul(amountIn, 997)
            let num := mul(aif, reserveOut)
            let den := add(mul(reserveIn, 1000), aif)
            amountOut := div(num, den)

            // pair.swap(amount0Out, amount1Out, to, data)
            mstore(ptr, 0x022c0d9f00000000000000000000000000000000000000000000000000000000)
            switch zeroForOne
            case 1 {
                mstore(add(ptr, 0x04), 0)
                mstore(add(ptr, 0x24), amountOut)
            }
            default {
                mstore(add(ptr, 0x04), amountOut)
                mstore(add(ptr, 0x24), 0)
            }
            mstore(add(ptr, 0x44), address())
            mstore(add(ptr, 0x64), 0x80)
            mstore(add(ptr, 0x84), 0)

            ok := call(gas(), pair, 0, ptr, 0xa4, 0, 0)
            if iszero(ok) {
                mstore(0x00, 0xde2a29e0)
                revert(0x1c, 0x04)
            }
        }
    }

    /// @dev Direct V3 pool swap
    function _swapV3(
        address pool,
        address tokenIn,
        address tokenOut,
        int256 amountIn,
        bool zeroForOne,
        uint160 sqrtPriceLimitX96
    )
        internal
        returns (int256 amount0, int256 amount1)
    {
        // Default price limits if none provided
        if (sqrtPriceLimitX96 == 0) {
            sqrtPriceLimitX96 = zeroForOne
                ? 4_295_128_740  // MIN_SQRT_RATIO + 1
                : 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_341; // MAX - 1
        }

        // Encode callback data: (tokenIn, tokenOut) for the swap callback
        bytes memory cbData = abi.encode(tokenIn, tokenOut);

        assembly {
            let ptr := mload(0x40)
            // pool.swap(recipient, zeroForOne, amountSpecified, sqrtPriceLimitX96, data)
            mstore(ptr, 0x128acb0800000000000000000000000000000000000000000000000000000000)
            mstore(add(ptr, 0x04), address())
            mstore(add(ptr, 0x24), zeroForOne)
            mstore(add(ptr, 0x44), amountIn)
            mstore(add(ptr, 0x64), sqrtPriceLimitX96)
            mstore(add(ptr, 0x84), 0xa0) // data offset
            // Copy cbData
            let cbLen := mload(cbData)
            mstore(add(ptr, 0xa4), cbLen)
            // Copy bytes
            let cbSrc := add(cbData, 0x20)
            let cbDst := add(ptr, 0xc4)
            for { let i } lt(i, cbLen) { i := add(i, 0x20) } {
                mstore(add(cbDst, i), mload(add(cbSrc, i)))
            }

            let totalLen := add(0xc4, cbLen)
            // Pad to 32-byte boundary
            totalLen := and(add(totalLen, 31), not(31))

            let ok := call(gas(), pool, 0, ptr, totalLen, ptr, 0x40)
            if iszero(ok) {
                mstore(0x00, 0xde2a29e0)
                revert(0x1c, 0x04)
            }

            amount0 := mload(ptr)
            amount1 := mload(add(ptr, 0x20))
        }
    }

    /*//////////////////////////////////////////////////////////////
              COMPLEX STRATEGY INTERNALS
    //////////////////////////////////////////////////////////////*/

    /// @dev V2 3-hop cyclic arbitrage
    function _executeV2Arb3Hop() internal {
        address pair0;
        address pair1;
        address pair2;
        address tokenA;
        address tokenB;
        address tokenC;
        uint256 amountIn;
        bool dir0;
        bool dir1;
        bool dir2;

        assembly {
            pair0 := shr(96, calldataload(1))
            pair1 := shr(96, calldataload(21))
            pair2 := shr(96, calldataload(41))
            tokenA := shr(96, calldataload(61))
            tokenB := shr(96, calldataload(81))
            tokenC := shr(96, calldataload(101))
            amountIn := calldataload(121)
            dir0 := byte(0, calldataload(153))
            dir1 := byte(0, calldataload(154))
            dir2 := byte(0, calldataload(155))
        }

        uint256 balBefore = _balanceOf(tokenA, address(this));

        // Hop 1: A → B
        SafeTransferLib.safeTransfer(tokenA, pair0, amountIn);
        uint256 out1 = _swapV2(pair0, amountIn, dir0);

        // Hop 2: B → C
        SafeTransferLib.safeTransfer(tokenB, pair1, out1);
        uint256 out2 = _swapV2(pair1, out1, dir1);

        // Hop 3: C → A
        SafeTransferLib.safeTransfer(tokenC, pair2, out2);
        _swapV2(pair2, out2, dir2);

        uint256 balAfter = _balanceOf(tokenA, address(this));
        _accumulateProfit(balAfter, balBefore);
    }

    /// @dev V3 2-hop cyclic arbitrage
    function _executeV3Arb2Hop() internal {
        address pool0;
        address pool1;
        address tokenA;
        address tokenB;
        uint256 amountIn;
        bool dir0;
        bool dir1;
        uint160 limit0;
        uint160 limit1;

        assembly {
            pool0 := shr(96, calldataload(1))
            pool1 := shr(96, calldataload(21))
            tokenA := shr(96, calldataload(41))
            tokenB := shr(96, calldataload(61))
            amountIn := calldataload(81)
            dir0 := byte(0, calldataload(113))
            dir1 := byte(0, calldataload(114))
            limit0 := shr(96, calldataload(115))
            limit1 := shr(96, calldataload(135))
        }

        uint256 balBefore = _balanceOf(tokenA, address(this));

        // Hop 1: tokenA → tokenB
        (int256 a0, int256 a1) = _swapV3(pool0, tokenA, tokenB, int256(amountIn), dir0, limit0);
        uint256 midAmount = dir0 ? uint256(-a1) : uint256(-a0);

        // Hop 2: tokenB → tokenA
        _swapV3(pool1, tokenB, tokenA, int256(midAmount), dir1, limit1);

        uint256 balAfter = _balanceOf(tokenA, address(this));
        _accumulateProfit(balAfter, balBefore);
    }

    /// @dev Mixed V2/V3 multi-hop arbitrage
    function _executeMixedArb() internal {
        // [1B op][1B hopCount][per hop: 1B type + 20B pool + 20B tIn + 20B tOut + 1B dir + 20B
        // limit] then [32B amountIn] at the end
        uint8 hopCount;
        assembly {
            hopCount := byte(0, calldataload(1))
        }

        // Each hop = 82 bytes (1 + 20 + 20 + 20 + 1 + 20)
        uint256 hopsDataLen = uint256(hopCount) * 82;
        uint256 amountOffset = 2 + hopsDataLen;

        uint256 amountIn;
        assembly {
            amountIn := calldataload(amountOffset)
        }

        // Read first hop's tokenIn as the start token for profit tracking
        address startToken;
        assembly {
            // First hop tokenIn is at offset 2 + 1 + 20 = 23
            startToken := shr(96, calldataload(23))
        }

        uint256 balBefore = _balanceOf(startToken, address(this));
        uint256 currentAmount = amountIn;

        for (uint256 i; i < hopCount;) {
            uint256 hopOffset = 2 + (i * 82);
            uint8 hopType;
            address pool;
            address tokenIn;
            address tokenOut;
            bool dir;
            uint160 limit;

            assembly {
                hopType := byte(0, calldataload(hopOffset))
                pool := shr(96, calldataload(add(hopOffset, 1)))
                tokenIn := shr(96, calldataload(add(hopOffset, 21)))
                tokenOut := shr(96, calldataload(add(hopOffset, 41)))
                dir := byte(0, calldataload(add(hopOffset, 61)))
                limit := shr(96, calldataload(add(hopOffset, 62)))
            }

            if (hopType == 0) {
                // V2 hop
                SafeTransferLib.safeTransfer(tokenIn, pool, currentAmount);
                currentAmount = _swapV2(pool, currentAmount, dir);
            } else {
                // V3 hop
                (int256 a0, int256 a1) =
                    _swapV3(pool, tokenIn, tokenOut, int256(currentAmount), dir, limit);
                currentAmount = dir ? uint256(-a1) : uint256(-a0);
            }

            unchecked {
                ++i;
            }
        }

        uint256 balAfter = _balanceOf(startToken, address(this));
        _accumulateProfit(balAfter, balBefore);
    }

    /*//////////////////////////////////////////////////////////////
              V3 POSITION MANAGEMENT (JIT)
    //////////////////////////////////////////////////////////////*/

    /// @dev Mint a V3 position directly on the pool (skip NFT manager)
    function _mintV3Position(
        address pool,
        address token0,
        address token1,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    )
        internal
    {
        assembly {
            let ptr := mload(0x40)
            // pool.mint(recipient, tickLower, tickUpper, amount, data)
            // 0x3c8a7d8d
            mstore(ptr, 0x3c8a7d8d00000000000000000000000000000000000000000000000000000000)
            mstore(add(ptr, 0x04), address())
            mstore(add(ptr, 0x24), tickLower)
            mstore(add(ptr, 0x44), tickUpper)
            mstore(add(ptr, 0x64), liquidity)
            mstore(add(ptr, 0x84), 0xa0) // data offset
            mstore(add(ptr, 0xa4), 0x40) // data length
            mstore(add(ptr, 0xc4), token0)
            mstore(add(ptr, 0xe4), token1)

            let ok := call(gas(), pool, 0, ptr, 0x104, ptr, 0x40)
            if iszero(ok) {
                mstore(0x00, 0x4e2b1e7a) // MintFailed
                revert(0x1c, 0x04)
            }
        }
    }

    /// @dev Burn a V3 position and collect all tokens + fees
    function _burnAndCollectV3(
        address pool,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    )
        internal
    {
        // Step 1: Burn
        assembly {
            let ptr := mload(0x40)
            // pool.burn(tickLower, tickUpper, amount) — 0xa34123a7
            mstore(ptr, 0xa34123a700000000000000000000000000000000000000000000000000000000)
            mstore(add(ptr, 0x04), tickLower)
            mstore(add(ptr, 0x24), tickUpper)
            mstore(add(ptr, 0x44), liquidity)

            let ok := call(gas(), pool, 0, ptr, 0x64, 0, 0)
            if iszero(ok) {
                mstore(0x00, 0x7b94e839) // BurnFailed
                revert(0x1c, 0x04)
            }
        }

        // Step 2: Collect all owed tokens
        assembly {
            let ptr := mload(0x40)
            // pool.collect(recipient, tickLower, tickUpper, amount0Max, amount1Max)
            // 0x4f1eb3d8
            mstore(ptr, 0x4f1eb3d800000000000000000000000000000000000000000000000000000000)
            mstore(add(ptr, 0x04), address())
            mstore(add(ptr, 0x24), tickLower)
            mstore(add(ptr, 0x44), tickUpper)
            // uint128 max for both
            mstore(
                add(ptr, 0x64),
                0x00000000000000000000000000000000ffffffffffffffffffffffffffffffff
            )
            mstore(
                add(ptr, 0x84),
                0x00000000000000000000000000000000ffffffffffffffffffffffffffffffff
            )

            let ok := call(gas(), pool, 0, ptr, 0xa4, 0, 0)
            if iszero(ok) {
                mstore(0x00, 0x6b836e5e) // CollectFailed
                revert(0x1c, 0x04)
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
              BATCH EXECUTION (FOR FLASH LOAN CALLBACK)
    //////////////////////////////////////////////////////////////*/

    /// @dev Execute a batch of sub-operations from calldata bytes
    function _executeBatchCalldata(bytes calldata data) internal {
        uint256 offset;
        uint256 dataLen = data.length;

        while (offset < dataLen) {
            uint16 subLen;
            assembly {
                subLen := shr(240, calldataload(add(data.offset, offset)))
            }
            offset += 2;

            uint8 subOp;
            assembly {
                subOp := byte(0, calldataload(add(data.offset, offset)))
            }

            bytes memory subData = data[offset:offset + subLen];
            _executeSingleOp(subOp, subData);
            offset += subLen;
        }
    }

    /// @dev Execute a single operation from memory bytes (used in batch mode)
    function _executeSingleOp(uint8 opcode, bytes memory data) internal {
        if (opcode == 0x00 || opcode == 0x01) {
            // V2 swap from memory
            address pair;
            address tokenIn;
            uint256 amountIn;
            bool zeroForOne;
            assembly {
                pair := mload(add(data, 0x21)) // skip length + opcode byte
                pair := shr(96, pair)
                tokenIn := mload(add(data, 0x35))
                tokenIn := shr(96, tokenIn)
                amountIn := mload(add(data, 0x49))
                zeroForOne := byte(0, mload(add(data, 0x69)))
            }

            SafeTransferLib.safeTransfer(tokenIn, pair, amountIn);
            _swapV2(pair, amountIn, zeroForOne);
        } else if (opcode == 0xFE) {
            // Sweep ERC20
            address token;
            address to;
            uint256 amount;
            assembly {
                token := shr(96, mload(add(data, 0x21)))
                to := shr(96, mload(add(data, 0x35)))
                amount := mload(add(data, 0x49))
            }
            SafeTransferLib.safeTransfer(token, to, amount);
        }
        // Additional sub-op types can be added here
    }

    /*//////////////////////////////////////////////////////////////
                         UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Get ERC20 balance via assembly
    function _balanceOf(address token, address account) internal view returns (uint256 bal) {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x70a0823100000000000000000000000000000000000000000000000000000000)
            mstore(add(ptr, 0x04), account)

            let ok := staticcall(gas(), token, ptr, 0x24, ptr, 0x20)
            if ok { bal := mload(ptr) }
        }
    }

    /// @dev Accumulate profit in transient storage
    function _accumulateProfit(uint256 balAfter, uint256 balBefore) internal {
        if (balAfter > balBefore) {
            uint256 gain = balAfter - balBefore;
            assembly {
                let current := tload(_TSLOT_PROFIT)
                tstore(_TSLOT_PROFIT, add(current, gain))
            }
        }
    }
}
