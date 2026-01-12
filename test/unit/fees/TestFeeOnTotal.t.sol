// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {FeeBase} from "./Base.t.sol";
import {IVariableVaultFee} from "src/interfaces/IVariableVaultFee.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract TestFeeOnTotal is FeeBase {
    function setUp() public virtual override {
        super.setUp();
    }

    function testFeeOnTotalFlatHappyFlow() public {
        IVariableVaultFee.AssetFeeConfig memory _config = IVariableVaultFee.AssetFeeConfig({
            withdrawalFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.FLAT, getQuantizedValue(10)),
            depositFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.FLAT, getQuantizedValue(5)),
            instantWithdrawalFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.FLAT, getQuantizedValue(15)),
            flashRedeemFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.FLAT, getQuantizedValue(20)),
            feeRecipient: feeRecipient
        });

        vm.prank(naruto);
        feeContract.registerAsset(address(token), _config);

        uint256 withdrawalFee = feeContract.feeOnTotal(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.WITHDRAWAL);
        uint256 depositFee = feeContract.feeOnTotal(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.DEPOSIT);
        uint256 instantWithdrawalFee = feeContract.feeOnTotal(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);
        uint256 flashRedeemFee = feeContract.feeOnTotal(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.FLASH_REDEEM);

        assertEq(withdrawalFee, getQuantizedValue(10));
        assertEq(instantWithdrawalFee, getQuantizedValue(15));
        assertEq(depositFee, getQuantizedValue(5));
        assertEq(flashRedeemFee, getQuantizedValue(20));
    }

    function testFeeOnTotalPercentageHappyFlow() public {
        IVariableVaultFee.AssetFeeConfig memory _config = IVariableVaultFee.AssetFeeConfig({
            withdrawalFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, 1e16), // 1%
            depositFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, 2e16), // 2%
            instantWithdrawalFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, 3e16), // 3%
            flashRedeemFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, 4e16), // 4%,
            feeRecipient: feeRecipient
        });

        vm.prank(naruto);
        feeContract.registerAsset(address(token), _config);

        uint256 depositFee = feeContract.feeOnTotal(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.DEPOSIT);
        uint256 withdrawalFee = feeContract.feeOnTotal(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.WITHDRAWAL);
        uint256 instantWithdrawalFee = feeContract.feeOnTotal(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);
        uint256 flashRedeemFee = feeContract.feeOnTotal(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.FLASH_REDEEM);

        if(config.tokenConfig.decimals == 6){
            assertEq(depositFee, 1_960_785); // ≈ 2% of total including fees (1960784.3137254901 -> 1_960_785)
            assertEq(withdrawalFee, 990_100); // ≈ 1% of total including fees (990_099.0099009901 -> 990_100)
            assertEq(instantWithdrawalFee, 2_912_622); // ≈ 3% of total including fees (2_912_621.359223301 -> 2_912_622)
            assertEq(flashRedeemFee, 3_846_154); // ≈ 4% of total including fees (3_846_153.846153846 -> 3_846_154)
        } else if(config.tokenConfig.decimals == 8){
            assertEq(depositFee, 1_960_784_32); // ≈ 2% of total including fees (196078431.37254901 -> 196078432)
            assertEq(withdrawalFee, 990_099_01); // ≈ 1% of total including fees (99009900.99009901 -> 99009901)
            assertEq(instantWithdrawalFee, 291_262_136); // ≈ 3% of total including fees (291262135.9223301 -> 291262136)
            assertEq(flashRedeemFee, 384_615_385); // ≈ 4% of total including fees (384615384.6153846 -> 384615385)
        } else if(config.tokenConfig.decimals == 18){
            assertEq(depositFee, 196_078_431_372_549_019_7); // ≈ 2% of total including fees (1960784313725490197)
            assertEq(withdrawalFee, 990_099_009_900_990_100); // ≈ 1% of total including fees (990099009900990100)
            assertEq(instantWithdrawalFee, 291_262_135_922_330_097_1); // ≈ 3% of total including fees (2912621359223300971)
            assertEq(flashRedeemFee, 384_615_384_615_384_615_4); // ≈ 4% of total including fees (3846153846153846154)
        }else{
            revert('Condition not added for given decimals');
        }
    }

    function testFeeOnTotalRevertsIfAmountIsZero() public {
        IVariableVaultFee.AssetFeeConfig memory _config = IVariableVaultFee.AssetFeeConfig({
            withdrawalFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.FLAT, getQuantizedValue(1)),
            depositFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.FLAT, 0),
            instantWithdrawalFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.FLAT, getQuantizedValue(3)), 
            flashRedeemFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, 4e16), // 4%,
            feeRecipient: feeRecipient
        });

        vm.prank(naruto);
        feeContract.registerAsset(address(token), _config);

        vm.expectRevert(IVariableVaultFee.ZeroAmount.selector);
        feeContract.feeOnTotal(address(token), 0, IVariableVaultFee.FeeOperation.WITHDRAWAL);

        vm.expectRevert(IVariableVaultFee.ZeroAmount.selector);
        feeContract.feeOnTotal(address(token), 0, IVariableVaultFee.FeeOperation.DEPOSIT);

        vm.expectRevert(IVariableVaultFee.ZeroAmount.selector);
        feeContract.feeOnTotal(address(token), 0, IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);

        vm.expectRevert(IVariableVaultFee.ZeroAmount.selector);
        feeContract.feeOnTotal(address(token), 0, IVariableVaultFee.FeeOperation.FLASH_REDEEM);
    }

    function testFeeOnTotalRevertsIfFlatFeeExceedsAmount() public {
        IVariableVaultFee.AssetFeeConfig memory _config = IVariableVaultFee.AssetFeeConfig({
            withdrawalFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.FLAT, getQuantizedValue(200)),
            instantWithdrawalFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.FLAT, getQuantizedValue(200)),
            depositFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.FLAT, getQuantizedValue(200)),
            flashRedeemFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.FLAT, getQuantizedValue(200)), 
            feeRecipient: feeRecipient
        });

        vm.prank(naruto);
        feeContract.registerAsset(address(token), _config);

        vm.expectRevert(IVariableVaultFee.InsufficientAmount.selector);
        feeContract.feeOnTotal(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.WITHDRAWAL);

        vm.expectRevert(IVariableVaultFee.InsufficientAmount.selector);
        feeContract.feeOnTotal(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.DEPOSIT);

        vm.expectRevert(IVariableVaultFee.InsufficientAmount.selector);
        feeContract.feeOnTotal(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);

        vm.expectRevert(IVariableVaultFee.InsufficientAmount.selector);
        feeContract.feeOnTotal(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.FLASH_REDEEM);
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

        IVariableVaultFee.AssetFeeConfig memory _config = IVariableVaultFee.AssetFeeConfig({
            withdrawalFee: percentageFee,
            depositFee: percentageFee,
            instantWithdrawalFee: instantWithdrawalPercentageFee,
            flashRedeemFee: flashRedeemPercentageFee,
            feeRecipient: feeRecipient
        });

        vm.prank(naruto);
        feeContract.registerAsset(address(token), _config);

        uint256 depositFee = feeContract.feeOnTotal(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.DEPOSIT);
        assertEq(depositFee, 0);

        uint256 withdrawalFee = feeContract.feeOnTotal(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.WITHDRAWAL);
        assertEq(withdrawalFee, 0);

        uint256 instantWithdrawalFee = feeContract.feeOnTotal(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);
        assertEq(instantWithdrawalFee, 0);

        uint256 flashRedeemFee = feeContract.feeOnTotal(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.FLASH_REDEEM);
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

        IVariableVaultFee.AssetFeeConfig memory _config = IVariableVaultFee.AssetFeeConfig({
            withdrawalFee: flatFee,
            depositFee: flatFee,
            instantWithdrawalFee: instantWithdrawalFee,
            flashRedeemFee: flashRedeemFee,
            feeRecipient: feeRecipient
        });

        vm.prank(naruto);
        feeContract.registerAsset(address(token), _config);

        uint256 dFee = feeContract.feeOnTotal(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.DEPOSIT);
        assertEq(dFee, 0, "depositFee mismatch");

        uint256 wFee = feeContract.feeOnTotal(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.WITHDRAWAL);
        assertEq(wFee, 0, "withdrawalFee mismatch");

        uint256 iwFee = feeContract.feeOnTotal(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);
        assertEq(iwFee, 0, "instantWithdrawalFee mismatch");

        uint256 frFee = feeContract.feeOnTotal(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.FLASH_REDEEM);
        assertEq(frFee, 0, "flashRedeemFee mismatch");

    }

    function testFeeOnTotalRevertsIfAssetIsZeroAddress() public {
        vm.expectRevert(IVariableVaultFee.InvalidAsset.selector);
        feeContract.feeOnTotal(address(0), getQuantizedValue(1), IVariableVaultFee.FeeOperation.WITHDRAWAL);

        vm.expectRevert(IVariableVaultFee.InvalidAsset.selector);
        feeContract.feeOnTotal(address(0), getQuantizedValue(1), IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);

        vm.expectRevert(IVariableVaultFee.InvalidAsset.selector);
        feeContract.feeOnTotal(address(0), getQuantizedValue(1), IVariableVaultFee.FeeOperation.DEPOSIT);

        vm.expectRevert(IVariableVaultFee.InvalidAsset.selector);
        feeContract.feeOnTotal(address(0), getQuantizedValue(1), IVariableVaultFee.FeeOperation.FLASH_REDEEM);
    }

    function testFeeOnTotalRevertsIfAssetNotRegistered() public {
        vm.expectRevert(IVariableVaultFee.InvalidAsset.selector);
        feeContract.feeOnTotal(address(token), getQuantizedValue(1), IVariableVaultFee.FeeOperation.WITHDRAWAL);

        vm.expectRevert(IVariableVaultFee.InvalidAsset.selector);
        feeContract.feeOnTotal(address(token), getQuantizedValue(1), IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);

        vm.expectRevert(IVariableVaultFee.InvalidAsset.selector);
        feeContract.feeOnTotal(address(token), getQuantizedValue(1), IVariableVaultFee.FeeOperation.DEPOSIT);

        vm.expectRevert(IVariableVaultFee.InvalidAsset.selector);
        feeContract.feeOnTotal(address(token), getQuantizedValue(1), IVariableVaultFee.FeeOperation.FLASH_REDEEM);
    }

    function testFeeOnTotalMaxPercentage() public {
        uint256 maxFee = 5e16; // 5%

        IVariableVaultFee.AssetFeeConfig memory _config = IVariableVaultFee.AssetFeeConfig({
            withdrawalFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, maxFee),
            instantWithdrawalFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, maxFee),
            depositFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, maxFee),
            flashRedeemFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, maxFee),
            feeRecipient: feeRecipient
        });

        vm.prank(naruto);
        feeContract.registerAsset(address(token), _config);

        uint256 total = getQuantizedValue(105);
        uint256 depositFee = feeContract.feeOnTotal(address(token), total, IVariableVaultFee.FeeOperation.DEPOSIT);
        uint256 withdrawalFee = feeContract.feeOnTotal(address(token), total, IVariableVaultFee.FeeOperation.WITHDRAWAL);
        uint256 iwithdrawalFee = feeContract.feeOnTotal(address(token), total, IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);
        uint256 iFlashRedeemFee = feeContract.feeOnTotal(address(token), total, IVariableVaultFee.FeeOperation.FLASH_REDEEM);

        assertEq(depositFee, getQuantizedValue(5));
        assertEq(withdrawalFee, getQuantizedValue(5));
        assertEq(iwithdrawalFee, getQuantizedValue(5));
        assertEq(iFlashRedeemFee, getQuantizedValue(5));
    }

    function testFeeOnTotalTinyPercentage() public {
        uint256 tinyFee = 1e12; // 0.0000001%
        uint256 evenTinierFee = 1e10;

        IVariableVaultFee.AssetFeeConfig memory _config = IVariableVaultFee.AssetFeeConfig({
            withdrawalFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, tinyFee),
            instantWithdrawalFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, evenTinierFee),
            depositFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, evenTinierFee),
            flashRedeemFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, evenTinierFee),
            feeRecipient: feeRecipient
        });

        vm.prank(naruto);
        feeContract.registerAsset(address(token), _config);

        uint256 dFee = feeContract.feeOnTotal(address(token), getQuantizedValue(1), IVariableVaultFee.FeeOperation.DEPOSIT);
        uint256 iFee = feeContract.feeOnTotal(address(token), getQuantizedValue(1), IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);
        uint256 wFee = feeContract.feeOnTotal(address(token), getQuantizedValue(1), IVariableVaultFee.FeeOperation.WITHDRAWAL);
        uint256 frFee = feeContract.feeOnTotal(address(token), getQuantizedValue(1), IVariableVaultFee.FeeOperation.FLASH_REDEEM);

        // if the fee value is 0, even then value is returned as 1 (rounding up)
         if(config.tokenConfig.decimals == 6){
            assertEq(dFee, 1); // Smallest fee. (0.009999 -> 1)
            assertEq(iFee, 1); // Smallest fee
            assertEq(wFee, 1); // Smallest fee
            assertEq(frFee, 1); // Smallest fee
        } else if(config.tokenConfig.decimals == 8){
            assertEq(dFee, 1); // Smallest fee
            assertEq(iFee, 1); // Smallest fee
            assertEq(wFee, 100); // Small fee
            assertEq(frFee, 1); // Smallest fee
        } else if(config.tokenConfig.decimals == 18){
            assertEq(dFee, 9999999901); // Smallest fee
            assertEq(iFee, 9999999901); // Smallest fee
            assertEq(wFee, 999999000001); // Small fee
            assertEq(frFee, 9999999901); // Smallest fee
        } else{
            revert('Condition not added for given decimals');
        }

    }

    function testFeeOnTotalHighPrecisionToken() public {
        uint256 feePercentage = 1e16; // 1%

        IVariableVaultFee.AssetFeeConfig memory _config = IVariableVaultFee.AssetFeeConfig({
            withdrawalFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, feePercentage),
            instantWithdrawalFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, feePercentage),
            depositFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, feePercentage),
            flashRedeemFee: IVariableVaultFee.FeeConfig(IVariableVaultFee.FeeType.PERCENTAGE, feePercentage),
            feeRecipient: feeRecipient
        });

        vm.prank(naruto);
        feeContract.registerAsset(address(token), _config);

        assertEq(feeContract.feeOnTotal(address(token), 1e18, IVariableVaultFee.FeeOperation.WITHDRAWAL), 9_900_990_099_009_901); // rounded up from 9_900_990_099_009_900
        assertEq(feeContract.feeOnTotal(address(token), 1e18, IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL), 9_900_990_099_009_901); // rounded up from 9_900_990_099_009_900
        assertEq(feeContract.feeOnTotal(address(token), 1e18, IVariableVaultFee.FeeOperation.DEPOSIT), 9_900_990_099_009_901); // rounded up from 9_900_990_099_009_900
        assertEq(feeContract.feeOnTotal(address(token), 1e18, IVariableVaultFee.FeeOperation.DEPOSIT), 9_900_990_099_009_901); // rounded up from 9_900_990_099_009_900
    }
}
