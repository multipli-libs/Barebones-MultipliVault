// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {MultipliVault} from "src/vault/MultipliVault.sol";

/// @custom:oz-upgrades-from MultipliVault
contract MockMultipliVaultV2 is MultipliVault{
    uint256 public newVariable;

    function newMethod() public returns(string memory) {
        return "new method";
    }

    function setNewVariable(uint256 value) public {
        newVariable = value;
    }
}