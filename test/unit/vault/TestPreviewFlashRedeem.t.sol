// SPDX-License-Identifier: MIT


pragma solidity 0.8.30;

import {BaseTest} from "./Base.t.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IVariableVaultFee} from "src/interfaces/IVariableVaultFee.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TestPreviewFlashRedeem is BaseTest {

    uint256 DEPOSIT_AMOUNT_MEDIUM = 100e6;
    uint256 DEPOSIT_AMOUNT_SMALL = 1;

    function setUp() override public {
        super.setUp();

        vm.startPrank(users.alice);
        depositVault.deposit(DEPOSIT_AMOUNT_MEDIUM, users.alice);
        vm.stopPrank();

        // increase the share price to 2
        // + 1 is required here to make the share price 2
        updateUnderlyingBalance(DEPOSIT_AMOUNT_MEDIUM + 1);

        vm.startPrank(users.admin);
        feeContract.updateAssetFeeConfig(
            address(usdc),
            IVariableVaultFee.AssetFeeConfig({
                withdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 1e6}),
                instantWithdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 1e15}), // 0.1%
                depositFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 0}),
                flashRedeemFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 5e15}), // 0.5%
                feeRecipient: address(users.feeRecipient)
            })
        );

        vm.stopPrank();

        vm.roll(block.number + 1);

    }

    function test_previewFlashRedeem_isSuccess_OnMediumDepositAmount() public {
        uint256 shareAmount = DEPOSIT_AMOUNT_MEDIUM;
        
        uint256 previewRes = depositVault.previewFlashRedeem(shareAmount);

        uint256 assetAmount = depositVault.convertToAssets(shareAmount);
        uint256 expectedFee = Math.mulDiv(assetAmount, 5e15, 1e18 + 5e15, Math.Rounding.Ceil);

        assertEq(expectedFee, 995025, "expected fee mismatch"); // (200e6 * 5e15) / (1e18 + 5e15) = 995024.8756218905
        assertEq(assetAmount, 200e6, "expected asset amount mismatch"); // verify share price = 2
        assertEq(previewRes, assetAmount - expectedFee, "expected previewFlashRedeem value mismatch");

    }

    function test_previewFlashRedeem_isSuccess_OnSmallDepositAmount() public {
        uint256 shareAmount = DEPOSIT_AMOUNT_MEDIUM; // initial deposit
        
        // check value on small deposit
        uint256 previewRes = depositVault.previewFlashRedeem(DEPOSIT_AMOUNT_SMALL);

        uint256 assetAmount = depositVault.convertToAssets(DEPOSIT_AMOUNT_SMALL);
        uint256 expectedFee = Math.mulDiv(assetAmount, 5e15, 1e18 + 5e15, Math.Rounding.Ceil); // (1 * 5e15) / (1e18 + 5e15) = 0.004975124378109453

        assertEq(expectedFee, 1, "expected fee mismatch"); // (1 * 5e15) / (1e18 + 5e15) = 0.004975124378109453
        assertEq(assetAmount, 2, "expected asset amount mismatch"); // verify share price = 2
        assertEq(previewRes, assetAmount - expectedFee, "expected previewFlashRedeem value mismatch");

    }

    function test_previewFlashRedeem_Reverts_OnZeroShares() public {
        uint256 shareAmount = 0;

        vm.expectRevert(abi.encodeWithSelector(IVariableVaultFee.ZeroAmount.selector));
        depositVault.previewFlashRedeem(shareAmount);

    }

    function test_previewFlashRedeem_Success_WhenAssetsEqualFee() public {
        // Before we start the test, ensure the price of 1 share = 1 USDC (this is for the ease of testing)
        // remove usdc from vault
        moveAssetsFromVault(IERC20(usdc).balanceOf(address(depositVault)));
        // update underlying assets to make sure that the price of share = 1
        updateUnderlyingBalance(depositVault.totalSupply());

        uint256 shares = 1;

        // ensure the price of 1 share is 1 USDC
        assertEq(depositVault.convertToAssets(shares), 1, "share number invariant broken");
        assertEq(depositVault.lastPricePerShare(), 1e18, "lastPricePerShare incorrect"); // lastPricePerSare
        
        uint256 assetsWithoutFee = depositVault.previewFlashRedeem(1);
        uint256 expectedFee = Math.mulDiv(shares, 5e15, 1e18 + 5e15, Math.Rounding.Ceil); // (1 * 5e15) / (1e18 + 5e15) = 0.004975124378109453

        assertEq(expectedFee, 1);
        assertEq(assetsWithoutFee, 0); // value should be 0 here

    }

}