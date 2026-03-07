// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { IVariableVaultFee } from "src/interfaces/IVariableVaultFee.sol";

contract ZeroFeeRecipient is IVariableVaultFee {
    function getFeeRecipient(address /* asset */) external pure override returns (address) {
        return address(0);
    }

    function feeOnRaw(
        address, 
        uint256, 
        FeeOperation
    ) 
        external 
        pure 
        override 
        returns (uint256) 
    {
        return 0;
    }

    function feeOnTotal(
        address, 
        uint256, 
        FeeOperation
    ) 
        external 
        pure 
        override 
        returns (uint256) 
    {
        return 0;
    }
}
