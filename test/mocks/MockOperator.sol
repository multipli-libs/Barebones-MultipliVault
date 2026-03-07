// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import {IMultipliVaultCallee} from "src/interfaces/IMultipliVaultCallee.sol";
import {MultipliVault} from "src/vault/MultipliVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Errors} from "src/libraries/Errors.sol";
import {console} from "forge-std/console.sol";

// Third party controlled Operator
abstract contract _BaseMockOperator is IMultipliVaultCallee {
    MultipliVault vault;

    function onRedemptionFlashLoan(
        address initiator,
        address _asset,
        address _underlyingAsset,
        uint256 _shares,
        uint256 _underlyingAmount,
        bytes memory _additionalData
    ) external virtual;

    // helper function for tests
    function mint(uint256 shares) virtual public {
        require(address(vault) != address(0), "use `setVault()` before calling this method");
        
        // set allowance
        address asset = vault.asset();
        uint256 allowance = IERC20(asset).allowance({owner: address(this), spender: address(vault)});
        // if allowance is 0, set to max
        if (allowance == 0) {
            // approve 
            IERC20(asset).approve(address(vault), type(uint256).max);
        }

        // mint
        vault.mint(shares, address(this));
    }

    function setVault(MultipliVault vault_) public {
        vault = vault_;
    }
}

contract MockOperator is _BaseMockOperator {

    function onRedemptionFlashLoan(
        address initiator,
        address _asset,
        address _underlyingAsset,
        uint256 _shares,
        uint256 _underlyingAmount,
        bytes memory _additionalData
    ) external override {
        if (IERC20(_asset).balanceOf(address(this)) < _shares) {
            revert Errors.Errors__InsufficientShares();
        }
        
        // transfer the shares back to the vault
        IERC20(_asset).transfer(_asset, _shares);
    }

}

contract MockMaliciousOperator is _BaseMockOperator {

    function onRedemptionFlashLoan(
        address initiator,
        address _asset,
        address _underlyingAsset,
        uint256 _shares,
        uint256 _underlyingAmount,
        bytes memory _additionalData
    ) external override {
        // do not return funds
    }

}