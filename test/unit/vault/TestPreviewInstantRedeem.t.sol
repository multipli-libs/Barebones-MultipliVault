// SPDX-License-Identifier: MIT


pragma solidity 0.8.30;

import {BaseTest} from "./Base.t.sol";
import {IVariableVaultFee} from "src/interfaces/IVariableVaultFee.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";


contract TestPreviewInstantRedeem is BaseTest {
    uint256 TINY_REDEEM_AMOUNT = 1;
    uint256 SMALL_REDEEM_AMOUNT;
    uint256 MEDIUM_REDEEM_AMOUNT;
    uint256 LARGE_REDEEM_AMOUNT;


    uint256 TINY_DEPOSIT_AMOUNT = 1;
    uint256 SMALL_DEPOSIT_AMOUNT;
    uint256 MEDIUM_DEPOSIT_AMOUNT;
    uint256 LARGE_DEPOSIT_AMOUNT;



    function setUp() public override {
        super.setUp();

        SMALL_REDEEM_AMOUNT = getQuantizedValue(100);
        MEDIUM_REDEEM_AMOUNT = getQuantizedValue(100_000);
        LARGE_REDEEM_AMOUNT = getQuantizedValue(1_000_000);

        SMALL_DEPOSIT_AMOUNT = getQuantizedValue(100); // 100
        MEDIUM_DEPOSIT_AMOUNT = getQuantizedValue(100_000); // 100K
        LARGE_DEPOSIT_AMOUNT = getQuantizedValue(1_000_000); // 1M

        vm.startPrank(users.alice);
        depositVault.deposit(MEDIUM_DEPOSIT_AMOUNT, users.alice); 
        vm.stopPrank();

        vm.startPrank(users.bob);
        depositVault.deposit(SMALL_DEPOSIT_AMOUNT, users.bob);
        vm.stopPrank();


        vm.startPrank(users.admin);
        feeContract.updateAssetFeeConfig(
            address(token),
            IVariableVaultFee.AssetFeeConfig({
                withdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: getQuantizedValue(1)}),
                instantWithdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 5e15}), // 0.5%
                depositFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 0}),
                flashRedeemFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.PERCENTAGE, feeAmount: 1e15}), // 0.1%
                feeRecipient: address(users.feeRecipient)
            })
        );

        vm.stopPrank();

    }

    function test_previewInstantRedeem_RevertsOnZeroShares() public {
        vm.expectRevert(IVariableVaultFee.IVariableVaultFee__ZeroAmount.selector);        
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
        uint256 expectedFee;

        if(config.tokenConfig.decimals == 6){
            expectedFee = 497_513; // (100e6 * 5e15) / (5e15 + 1e18) = 497512.437810945274
        } else if(config.tokenConfig.decimals == 8){
            expectedFee = 49751244; // (100e8 * 5e15) / (5e15 + 1e18) = 49751243.7810945274
        } else if(config.tokenConfig.decimals == 18){
            expectedFee = 497512437810945274; // (100e8 * 5e15) / (5e15 + 1e18) = 497512437810945274
        } else{
            revert('Condition not added for given decimals');
        }

        assertEq(fee, expectedFee, "fee mismatch");
        assertEq(assetsWithoutFee, assetsWithFee - fee, "previewInstantRedeem mismatch from expected value");
        
    }

    function test_previewInstantRedeem_SuccessOnMediumRedeemAmount() public {    
        uint256 assetsWithoutFee = depositVault.previewInstantRedeem(MEDIUM_REDEEM_AMOUNT);
        uint256 assetsWithFee = depositVault.convertToAssets(MEDIUM_REDEEM_AMOUNT);
        uint256 fee = assetsWithFee - assetsWithoutFee;
        uint256 expectedFee;

        if(config.tokenConfig.decimals == 6){
            expectedFee = 497_512_438; // (100_000e6 * 5e15) / (5e15+1e18) = 497512437.810945273632 (497.512438)
        } else if(config.tokenConfig.decimals == 8){
            expectedFee = 497_512_437_82; // (100_000e8 * 5e15) / (5e15+1e18) = 49751243781.0945273632 (497.512438)
        } else if(config.tokenConfig.decimals == 18){
            expectedFee = 497_512_437_810_945_273_632; // (100e18 * 5e15) / (5e15 + 1e18) = 497512437810945273632
        } else{
            revert('Condition not added for given decimals');
        }
        
        assertEq(fee, expectedFee, "fee mismatch");
        assertEq(assetsWithoutFee, assetsWithFee - fee, "previewInstantRedeem mismatch from expected value");
    }


    function test_previewInstantRedeem_SuccessWhenFeeIsIrrationalNumber() public {
        vm.startPrank(users.admin);
        feeContract.updateAssetFeeConfig(
            address(token),
            IVariableVaultFee.AssetFeeConfig({
                withdrawalFee: IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: getQuantizedValue(1)}),
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

        uint256 expectedFee;

        if(config.tokenConfig.decimals == 6){
            expectedFee = 332225914; // (100_000e6 * 3333333333333333)/(3333333333333333 + 1e18) = 332225913.6212625360 -> this value gets rounded up
        } else if(config.tokenConfig.decimals == 8){
            expectedFee = 33222591363; // (100_000e6 * 3333333333333333)/(3333333333333333 + 1e18) = 33222591362.1262425360 -> this value gets rounded up
        } else if(config.tokenConfig.decimals == 18){
            expectedFee = 332225913621262425360; // (100_000e6 * 3333333333333333)/(3333333333333333 + 1e18) = 332225913621262425360 -> this value gets rounded up
        } else{
            revert('Condition not added for given decimals');
        }

        assertEq(fee, expectedFee, "fee mismatch");
        assertEq(assetsWithoutFee, assetsWithFee - fee, "previewInstantRedeem mismatch from expected value");
    }

}