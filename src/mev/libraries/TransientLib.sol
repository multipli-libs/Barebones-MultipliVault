// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title TransientLib
 * @notice EIP-1153 transient storage helpers for MEV execution state
 * @dev All functions use TSTORE/TLOAD for intra-transaction state that auto-clears.
 *      Slots are keccak256-derived constants to avoid collisions with OZ's
 *      ReentrancyGuardTransient and other transient storage users.
 *
 *      Gas: TSTORE = 100 gas, TLOAD = 100 gas (vs SSTORE cold = 22,100 gas)
 *
 * @custom:security-contact security@multipli.com
 */
library TransientLib {
    /*//////////////////////////////////////////////////////////////
                            SLOT CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev keccak256("mevhub.transient.profit") - 1
    bytes32 private constant _PROFIT_SLOT =
        0x6d65766875622e7472616e7369656e742e70726f666974000000000000000000;

    /// @dev keccak256("mevhub.transient.flashloan.asset") - 1
    bytes32 private constant _FL_ASSET_SLOT =
        0x6d65766875622e7472616e7369656e742e666c2e617373657400000000000000;

    /// @dev keccak256("mevhub.transient.flashloan.amount") - 1
    bytes32 private constant _FL_AMOUNT_SLOT =
        0x6d65766875622e7472616e7369656e742e666c2e616d6f756e74000000000000;

    /// @dev keccak256("mevhub.transient.flashloan.premium") - 1
    bytes32 private constant _FL_PREMIUM_SLOT =
        0x6d65766875622e7472616e7369656e742e666c2e7072656d69756d0000000000;

    /// @dev Base slot for indexed intermediate balances: keccak256("mevhub.transient.balance")
    bytes32 private constant _BALANCE_BASE_SLOT =
        0x6d65766875622e7472616e7369656e742e62616c616e63650000000000000000;

    /*//////////////////////////////////////////////////////////////
                          PROFIT ACCUMULATOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Add profit from a strategy execution
    /// @param amount The profit amount to add (can be negative via int256 cast)
    function addProfit(uint256 amount) internal {
        assembly {
            let current := tload(_PROFIT_SLOT)
            tstore(_PROFIT_SLOT, add(current, amount))
        }
    }

    /// @notice Subtract a cost from the profit accumulator
    /// @param amount The cost to subtract
    function subProfit(uint256 amount) internal {
        assembly {
            let current := tload(_PROFIT_SLOT)
            tstore(_PROFIT_SLOT, sub(current, amount))
        }
    }

    /// @notice Get the current accumulated profit
    /// @return profit The total accumulated profit
    function getProfit() internal view returns (uint256 profit) {
        assembly {
            profit := tload(_PROFIT_SLOT)
        }
    }

    /// @notice Reset the profit accumulator to zero
    function resetProfit() internal {
        assembly {
            tstore(_PROFIT_SLOT, 0)
        }
    }

    /*//////////////////////////////////////////////////////////////
                        FLASH LOAN STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Store flash loan parameters for callback validation
    /// @param asset The flash-borrowed asset address
    /// @param amount The flash-borrowed amount
    /// @param premium The premium owed to Aave
    function setFlashLoanParams(address asset, uint256 amount, uint256 premium) internal {
        assembly {
            tstore(_FL_ASSET_SLOT, asset)
            tstore(_FL_AMOUNT_SLOT, amount)
            tstore(_FL_PREMIUM_SLOT, premium)
        }
    }

    /// @notice Retrieve stored flash loan parameters
    /// @return asset The flash-borrowed asset
    /// @return amount The flash-borrowed amount
    /// @return premium The premium owed
    function getFlashLoanParams()
        internal
        view
        returns (address asset, uint256 amount, uint256 premium)
    {
        assembly {
            asset := tload(_FL_ASSET_SLOT)
            amount := tload(_FL_AMOUNT_SLOT)
            premium := tload(_FL_PREMIUM_SLOT)
        }
    }

    /// @notice Clear flash loan parameters after repayment
    function clearFlashLoanParams() internal {
        assembly {
            tstore(_FL_ASSET_SLOT, 0)
            tstore(_FL_AMOUNT_SLOT, 0)
            tstore(_FL_PREMIUM_SLOT, 0)
        }
    }

    /*//////////////////////////////////////////////////////////////
                      INTERMEDIATE BALANCES
    //////////////////////////////////////////////////////////////*/

    /// @notice Store an intermediate balance at an indexed slot
    /// @param index The balance index (0-255)
    /// @param bal The balance value
    function setBalance(uint256 index, uint256 bal) internal {
        assembly {
            let slot := add(_BALANCE_BASE_SLOT, index)
            tstore(slot, bal)
        }
    }

    /// @notice Retrieve an intermediate balance from an indexed slot
    /// @param index The balance index (0-255)
    /// @return bal The stored balance value
    function getBalance(uint256 index) internal view returns (uint256 bal) {
        assembly {
            let slot := add(_BALANCE_BASE_SLOT, index)
            bal := tload(slot)
        }
    }
}
