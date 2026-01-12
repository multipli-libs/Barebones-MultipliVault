// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {FeeBase} from "./Base.t.sol";
import {IVariableVaultFee} from "src/interfaces/IVariableVaultFee.sol";

contract TestFeeOnTotal is FeeBase {
    function setUp() public virtual override {
        super.setUp();
    }

    function testFeeOnTotalFlatHappyFlow() public {
        IVariableVaultFee.AssetFeeConfig memory config = IVariableVaultFee.AssetFeeConfig({
            withdrawalFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.FLAT, 10e6),
            depositFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.FLAT, 5e6),
            instantWithdrawalFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.FLAT, 15e6),
            flashRedeemFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.FLAT, 20e6),
            feeRecipient: feeRecipient
        });

        vm.prank(naruto);
        feeContract.registerAsset(address(USDC), config);

        uint256 withdrawalFee = feeContract.feeOnTotal(address(USDC), 100e6, IVariableVaultFee.FeeOperation.WITHDRAWAL);
        uint256 depositFee = feeContract.feeOnTotal(address(USDC), 100e6, IVariableVaultFee.FeeOperation.DEPOSIT);
        uint256 instantWithdrawalFee = feeContract.feeOnTotal(address(USDC), 100e6, IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);
        uint256 flashRedeemFee = feeContract.feeOnTotal(address(USDC), 100e6, IVariableVaultFee.FeeOperation.FLASH_REDEEM);

        assertEq(withdrawalFee, 10e6);
        assertEq(instantWithdrawalFee, 15e6);
        assertEq(depositFee, 5e6);
        assertEq(flashRedeemFee, 20e6);
    }

    function testFeeOnTotalPercentageHappyFlow() public {
        IVariableVaultFee.AssetFeeConfig memory config = IVariableVaultFee.AssetFeeConfig({
            withdrawalFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, 1e16), // 1%
            depositFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, 2e16), // 2%
            instantWithdrawalFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, 3e16), // 3%
            flashRedeemFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, 4e16), // 4%,
            feeRecipient: feeRecipient
        });

        vm.prank(naruto);
        feeContract.registerAsset(address(USDC), config);

        uint256 depositFee = feeContract.feeOnTotal(address(USDC), 100e6, IVariableVaultFee.FeeOperation.DEPOSIT);
        uint256 withdrawalFee = feeContract.feeOnTotal(address(USDC), 100e6, IVariableVaultFee.FeeOperation.WITHDRAWAL);
        uint256 instantWithdrawalFee = feeContract.feeOnTotal(address(USDC), 100e6, IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);
        uint256 flashRedeemFee = feeContract.feeOnTotal(address(USDC), 100e6, IVariableVaultFee.FeeOperation.FLASH_REDEEM);

        assertEq(depositFee, 1_960_785); // ≈ 2% of total including fees (1960784.3137254901 -> 1_960_785)
        assertEq(withdrawalFee, 990_100); // ≈ 1% of total including fees (990_099.0099009901 -> 990_100)
        assertEq(instantWithdrawalFee, 2_912_622); // ≈ 3% of total including fees (2_912_621.359223301 -> 2_912_622)
        assertEq(flashRedeemFee, 3_846_154); // ≈ 4% of total including fees (3_846_153.846153846 -> 3_846_154)
    }

    function testFeeOnTotalRevertsIfAmountIsZero() public {
        IVariableVaultFee.AssetFeeConfig memory config = IVariableVaultFee.AssetFeeConfig({
            withdrawalFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.FLAT, 1e6),
            depositFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.FLAT, 0),
            instantWithdrawalFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.FLAT, 3e6), 
            flashRedeemFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, 4e16), // 4%,
            feeRecipient: feeRecipient
        });

        vm.prank(naruto);
        feeContract.registerAsset(address(USDC), config);

        vm.expectRevert(IVariableVaultFee.ZeroAmount.selector);
        feeContract.feeOnTotal(address(USDC), 0, IVariableVaultFee.FeeOperation.WITHDRAWAL);

        vm.expectRevert(IVariableVaultFee.ZeroAmount.selector);
        feeContract.feeOnTotal(address(USDC), 0, IVariableVaultFee.FeeOperation.DEPOSIT);

        vm.expectRevert(IVariableVaultFee.ZeroAmount.selector);
        feeContract.feeOnTotal(address(USDC), 0, IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);

        vm.expectRevert(IVariableVaultFee.ZeroAmount.selector);
        feeContract.feeOnTotal(address(USDC), 0, IVariableVaultFee.FeeOperation.FLASH_REDEEM);
    }

    function testFeeOnTotalRevertsIfFlatFeeExceedsAmount() public {
        IVariableVaultFee.AssetFeeConfig memory config = IVariableVaultFee.AssetFeeConfig({
            withdrawalFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.FLAT, 200e6),
            instantWithdrawalFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.FLAT, 200e6),
            depositFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.FLAT, 200e6),
            flashRedeemFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.FLAT, 200e6), 
            feeRecipient: feeRecipient
        });

        vm.prank(naruto);
        feeContract.registerAsset(address(USDC), config);

        vm.expectRevert(IVariableVaultFee.InsufficientAmount.selector);
        feeContract.feeOnTotal(address(USDC), 100e6, IVariableVaultFee.FeeOperation.WITHDRAWAL);

        vm.expectRevert(IVariableVaultFee.InsufficientAmount.selector);
        feeContract.feeOnTotal(address(USDC), 100e6, IVariableVaultFee.FeeOperation.DEPOSIT);

        vm.expectRevert(IVariableVaultFee.InsufficientAmount.selector);
        feeContract.feeOnTotal(address(USDC), 100e6, IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);

        vm.expectRevert(IVariableVaultFee.InsufficientAmount.selector);
        feeContract.feeOnTotal(address(USDC), 100e6, IVariableVaultFee.FeeOperation.FLASH_REDEEM);
    }

    function testFeeOnTotalWithFeeZeroPercentageFee() public {
        IVariableVaultFee.FeeConfig memory percentageFee = IVariableVaultFee.FeeConfig({
            feeType: IVariableVaultFee.FeeType.PERCENTAGE,
            feeAmount: 0
        });
        IVariableVaultFee.FeeConfig memory instantWithdrawalPercentageFee = IVariableVaultFee.FeeConfig({
            feeType: IVariableVaultFee.FeeType.PERCENTAGE,
            feeAmount: 0
        });
        IVariableVaultFee.FeeConfig memory flashRedeemPercentageFee = IVariableVaultFee.FeeConfig({
            feeType: IVariableVaultFee.FeeType.PERCENTAGE,
            feeAmount: 0
        });

        IVariableVaultFee.AssetFeeConfig memory config = IVariableVaultFee.AssetFeeConfig({
            withdrawalFee: percentageFee,
            depositFee: percentageFee,
            instantWithdrawalFee: instantWithdrawalPercentageFee,
            flashRedeemFee: flashRedeemPercentageFee,
            feeRecipient: feeRecipient
        });

        vm.prank(naruto);
        feeContract.registerAsset(address(USDC), config);

        uint256 depositFee = feeContract.feeOnTotal(address(USDC), 100e6, IVariableVaultFee.FeeOperation.DEPOSIT);
        assertEq(depositFee, 0);

        uint256 withdrawalFee = feeContract.feeOnTotal(address(USDC), 100e6, IVariableVaultFee.FeeOperation.WITHDRAWAL);
        assertEq(withdrawalFee, 0);

        uint256 instantWithdrawalFee = feeContract.feeOnTotal(address(USDC), 100e6, IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);
        assertEq(instantWithdrawalFee, 0);

        uint256 flashRedeemFee = feeContract.feeOnTotal(address(USDC), 100e6, IVariableVaultFee.FeeOperation.FLASH_REDEEM);
        assertEq(flashRedeemFee, 0);

    }

    function testFeeOnTotalWithFeeZeroFlatFee() public {
        IVariableVaultFee.FeeConfig memory flatFee = IVariableVaultFee.FeeConfig({
            feeType: IVariableVaultFee.FeeType.FLAT,
            feeAmount: 0
        });
        IVariableVaultFee.FeeConfig memory instantWithdrawalFee = IVariableVaultFee.FeeConfig({
            feeType: IVariableVaultFee.FeeType.FLAT,
            feeAmount: 0
        });
        IVariableVaultFee.FeeConfig memory flashRedeemFee = IVariableVaultFee.FeeConfig({
            feeType: IVariableVaultFee.FeeType.FLAT,
            feeAmount: 0
        });

        IVariableVaultFee.AssetFeeConfig memory config = IVariableVaultFee.AssetFeeConfig({
            withdrawalFee: flatFee,
            depositFee: flatFee,
            instantWithdrawalFee: instantWithdrawalFee,
            flashRedeemFee: flashRedeemFee,
            feeRecipient: feeRecipient
        });

        vm.prank(naruto);
        feeContract.registerAsset(address(USDC), config);

        uint256 dFee = feeContract.feeOnTotal(address(USDC), 100e6, IVariableVaultFee.FeeOperation.DEPOSIT);
        assertEq(dFee, 0, "depositFee mismatch");

        uint256 wFee = feeContract.feeOnTotal(address(USDC), 100e6, IVariableVaultFee.FeeOperation.WITHDRAWAL);
        assertEq(wFee, 0, "withdrawalFee mismatch");

        uint256 iwFee = feeContract.feeOnTotal(address(USDC), 100e6, IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);
        assertEq(iwFee, 0, "instantWithdrawalFee mismatch");

        uint256 frFee = feeContract.feeOnTotal(address(USDC), 100e6, IVariableVaultFee.FeeOperation.FLASH_REDEEM);
        assertEq(frFee, 0, "flashRedeemFee mismatch");

    }

    function testFeeOnTotalRevertsIfAssetIsZeroAddress() public {
        vm.expectRevert(IVariableVaultFee.InvalidAsset.selector);
        feeContract.feeOnTotal(address(0), 1e6, IVariableVaultFee.FeeOperation.WITHDRAWAL);

        vm.expectRevert(IVariableVaultFee.InvalidAsset.selector);
        feeContract.feeOnTotal(address(0), 1e6, IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);

        vm.expectRevert(IVariableVaultFee.InvalidAsset.selector);
        feeContract.feeOnTotal(address(0), 1e6, IVariableVaultFee.FeeOperation.DEPOSIT);

        vm.expectRevert(IVariableVaultFee.InvalidAsset.selector);
        feeContract.feeOnTotal(address(0), 1e6, IVariableVaultFee.FeeOperation.FLASH_REDEEM);
    }

    function testFeeOnTotalRevertsIfAssetNotRegistered() public {
        vm.expectRevert(IVariableVaultFee.InvalidAsset.selector);
        feeContract.feeOnTotal(address(USDC), 1e6, IVariableVaultFee.FeeOperation.WITHDRAWAL);

        vm.expectRevert(IVariableVaultFee.InvalidAsset.selector);
        feeContract.feeOnTotal(address(USDC), 1e6, IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);

        vm.expectRevert(IVariableVaultFee.InvalidAsset.selector);
        feeContract.feeOnTotal(address(USDC), 1e6, IVariableVaultFee.FeeOperation.DEPOSIT);

        vm.expectRevert(IVariableVaultFee.InvalidAsset.selector);
        feeContract.feeOnTotal(address(USDC), 1e6, IVariableVaultFee.FeeOperation.FLASH_REDEEM);
    }

    function testFeeOnTotalMaxPercentage() public {
        uint256 maxFee = 5e16; // 5%

        IVariableVaultFee.AssetFeeConfig memory config = IVariableVaultFee.AssetFeeConfig({
            withdrawalFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, maxFee),
            instantWithdrawalFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, maxFee),
            depositFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, maxFee),
            flashRedeemFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, maxFee),
            feeRecipient: feeRecipient
        });

        vm.prank(naruto);
        feeContract.registerAsset(address(USDC), config);

        uint256 total = 105e6;
        uint256 depositFee = feeContract.feeOnTotal(address(USDC), total, IVariableVaultFee.FeeOperation.DEPOSIT);
        uint256 withdrawalFee = feeContract.feeOnTotal(address(USDC), total, IVariableVaultFee.FeeOperation.WITHDRAWAL);
        uint256 iwithdrawalFee = feeContract.feeOnTotal(address(USDC), total, IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);
        uint256 iFlashRedeemFee = feeContract.feeOnTotal(address(USDC), total, IVariableVaultFee.FeeOperation.FLASH_REDEEM);

        assertEq(depositFee, 5_000_000);
        assertEq(withdrawalFee, 5_000_000);
        assertEq(iwithdrawalFee, 5_000_000);
        assertEq(iFlashRedeemFee, 5_000_000);
    }

    function testFeeOnTotalTinyPercentage() public {
        uint256 tinyFee = 1e12; // 0.0000001%
        uint256 evenTinierFee = 1e10;

        IVariableVaultFee.AssetFeeConfig memory config = IVariableVaultFee.AssetFeeConfig({
            withdrawalFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, tinyFee),
            instantWithdrawalFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, evenTinierFee),
            depositFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, evenTinierFee),
            flashRedeemFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, evenTinierFee),
            feeRecipient: feeRecipient
        });

        vm.prank(naruto);
        feeContract.registerAsset(address(USDC), config);

        uint256 dFee = feeContract.feeOnTotal(address(USDC), 1e6, IVariableVaultFee.FeeOperation.DEPOSIT);
        uint256 iFee = feeContract.feeOnTotal(address(USDC), 1e6, IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);
        uint256 wFee = feeContract.feeOnTotal(address(USDC), 1e6, IVariableVaultFee.FeeOperation.WITHDRAWAL);
        uint256 frFee = feeContract.feeOnTotal(address(USDC), 1e6, IVariableVaultFee.FeeOperation.FLASH_REDEEM);

        // if the fee value is 0, even then value is returned as 1 (rounding up)

        assertEq(dFee, 1); // Smallest fee
        assertEq(iFee, 1); // Smallest fee
        assertEq(wFee, 1); // Smallest fee
        assertEq(frFee, 1); // Smallest fee

    }

    function testFeeOnTotalHighPrecisionToken() public {
        uint256 feePercentage = 1e16; // 1%

        IVariableVaultFee.AssetFeeConfig memory config = IVariableVaultFee.AssetFeeConfig({
            withdrawalFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, feePercentage),
            instantWithdrawalFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, feePercentage),
            depositFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, feePercentage),
            flashRedeemFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, feePercentage),
            feeRecipient: feeRecipient
        });

        vm.prank(naruto);
        feeContract.registerAsset(address(USDC), config);

        assertEq(feeContract.feeOnTotal(address(USDC), 1e18, IVariableVaultFee.FeeOperation.WITHDRAWAL), 9_900_990_099_009_901); // rounded up from 9_900_990_099_009_900
        assertEq(feeContract.feeOnTotal(address(USDC), 1e18, IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL), 9_900_990_099_009_901); // rounded up from 9_900_990_099_009_900
        assertEq(feeContract.feeOnTotal(address(USDC), 1e18, IVariableVaultFee.FeeOperation.DEPOSIT), 9_900_990_099_009_901); // rounded up from 9_900_990_099_009_900
        assertEq(feeContract.feeOnTotal(address(USDC), 1e18, IVariableVaultFee.FeeOperation.DEPOSIT), 9_900_990_099_009_901); // rounded up from 9_900_990_099_009_900
    }
}
