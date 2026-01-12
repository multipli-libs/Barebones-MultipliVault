// SPDX-License-Identifier: MIT


pragma solidity 0.8.30;

import {BaseTest} from "./Base.t.sol";
import {IVariableVaultFee} from "src/interfaces/IVariableVaultFee.sol";


contract TestPreviewInstantRedeem is BaseTest {
    uint256 TINY_REDEEM_AMOUNT = 1;
    uint256 SMALL_REDEEM_AMOUNT = 100e6;
    uint256 MEDIUM_REDEEM_AMOUNT = 100_000e6;
    uint256 LARGE_REDEEM_AMOUNT = 1_000_000e6;


    uint256 TINY_DEPOSIT_AMOUNT = 1;
    uint256 SMALL_DEPOSIT_AMOUNT = 100e6; // 100
    uint256 MEDIUM_DEPOSIT_AMOUNT = 100_000e6; // 100K
    uint256 LARGE_DEPOSIT_AMOUNT = 1_000_000e6; // 1M



    function setUp() public override {
        super.setUp();

        vm.startPrank(users.alice);
        depositVault.deposit(MEDIUM_DEPOSIT_AMOUNT, users.alice); 
        vm.stopPrank();

        vm.startPrank(users.bob);
        depositVault.deposit(SMALL_DEPOSIT_AMOUNT, users.bob);
        vm.stopPrank();


        vm.startPrank(users.admin);
        feeContract.updateAssetFeeConfig(
            address(usdc),
            IVariableVaultFee.AssetFeeConfig({
                withdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 1e6}),
                instantWithdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 5e15}), // 0.5%
                depositFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 0}),
                flashRedeemFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 1e15}), // 0.1%
                feeRecipient: address(users.feeRecipient)
            })
        );

        vm.stopPrank();

    }

    function test_previewInstantRedeem_RevertsOnZeroShares() public {
        vm.expectRevert(IVariableVaultFee.ZeroAmount.selector);        
        uint256 assetsWithoutFee = depositVault.previewInstantRedeem(0);

    }

    function test_previewInstantRedeem_SuccessOnTinyRedeemAmount() public {    
        uint256 assetsWithoutFee = depositVault.previewInstantRedeem(TINY_REDEEM_AMOUNT);
        uint256 assetsWithFee = depositVault.convertToAssets(TINY_REDEEM_AMOUNT);
        
        // Assets that can be received is rounded down to zero
        assertEq(assetsWithoutFee, 0);
        // Fee is rounded up to 1
        assertEq(assetsWithFee - assetsWithoutFee, 1);

    }

    function test_previewInstantRedeem_SuccessOnSmallRedeemAmount() public {    
        uint256 assetsWithoutFee = depositVault.previewInstantRedeem(SMALL_REDEEM_AMOUNT);
        uint256 assetsWithFee = depositVault.convertToAssets(SMALL_REDEEM_AMOUNT);
        uint256 fee = assetsWithFee - assetsWithoutFee;

        uint256 expectedFee = 497_513; // (100e6 * 5e15) / (5e15 + 1e18) = 497512.43781094527

        assertEq(fee, expectedFee, "fee mismatch");
        assertEq(assetsWithoutFee, assetsWithFee - fee, "previewInstantRedeem mismatch from expected value");
        
    }

    function test_previewInstantRedeem_SuccessOnMediumRedeemAmount() public {    
        uint256 assetsWithoutFee = depositVault.previewInstantRedeem(MEDIUM_REDEEM_AMOUNT);
        uint256 assetsWithFee = depositVault.convertToAssets(MEDIUM_REDEEM_AMOUNT);
        uint256 fee = assetsWithFee - assetsWithoutFee;

        uint256 expectedFee = 497_512_438; // (100_000e6 * 5e15) / (5e15+1e18) = 497512437.8109453 (497.512438 USDC)

        assertEq(fee, expectedFee, "fee mismatch");
        assertEq(assetsWithoutFee, assetsWithFee - fee, "previewInstantRedeem mismatch from expected value");
    }


    function test_previewInstantRedeem_SuccessWhenFeeIsIrrationalNumber() public {
        vm.startPrank(users.admin);
        feeContract.updateAssetFeeConfig(
            address(usdc),
            IVariableVaultFee.AssetFeeConfig({
                withdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 1e6}),
                instantWithdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 3333333333333333}), // 0.333...%
                depositFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 0}),
                flashRedeemFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 0}),
                feeRecipient: address(users.feeRecipient)
            })
        );

        vm.stopPrank();    
        uint256 assetsWithoutFee = depositVault.previewInstantRedeem(MEDIUM_REDEEM_AMOUNT);
        uint256 assetsWithFee = depositVault.convertToAssets(MEDIUM_REDEEM_AMOUNT);
        uint256 fee = assetsWithFee - assetsWithoutFee;

        uint256 expectedFee = 332225914; // (100_000e6 * 3333333333333333)/(3333333333333333 + 1e18) = 332225913.62126243 -> this value gets rounded up

        assertEq(fee, expectedFee, "fee mismatch");
        assertEq(assetsWithoutFee, assetsWithFee - fee, "previewInstantRedeem mismatch from expected value");
    }

}