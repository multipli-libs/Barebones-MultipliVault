// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {VariableVaultFee} from "src/fees/VariableVaultFee.sol";
import {FeeBase} from "./Base.t.sol";
import {IVariableVaultFee} from "src/interfaces/IVariableVaultFee.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract TestFeeOnRaw is FeeBase {
    function testFeeOnRawFlatHappyFlow() public {
        IVariableVaultFee.FeeConfig memory depositFlatFee =
            IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 0});
        IVariableVaultFee.FeeConfig memory withdrawalFlatFee =
            IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: getQuantizedValue(1)});
        
        IVariableVaultFee.FeeConfig memory instantWithdrawalFlatFee =
            IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: getQuantizedValue(2)});

        IVariableVaultFee.FeeConfig memory flashFeeFlatFee =
            IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: getQuantizedValue(3)});

        IVariableVaultFee.AssetFeeConfig memory _config = IVariableVaultFee.AssetFeeConfig({
            withdrawalFee: withdrawalFlatFee,
            depositFee: depositFlatFee,
            instantWithdrawalFee: instantWithdrawalFlatFee,
            flashRedeemFee: flashFeeFlatFee,
            feeRecipient: feeRecipient
        });

        vm.prank(naruto);
        feeContract.registerAsset(address(token), _config);

        uint256 depositFee = feeContract.feeOnRaw(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.DEPOSIT);
        uint256 withdrawalFee = feeContract.feeOnRaw(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.WITHDRAWAL);
        uint256 instantWithdrawalFee = feeContract.feeOnRaw(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);
        uint256 flashRedeemFee = feeContract.feeOnRaw(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.FLASH_REDEEM);

        assertEq(depositFee, 0);
        assertEq(withdrawalFee, getQuantizedValue(1));
        assertEq(instantWithdrawalFee, getQuantizedValue(2));
        assertEq(flashRedeemFee, getQuantizedValue(3));
    }

    function testFeeOnRawPercentageHappyFlow() public {
        IVariableVaultFee.FeeConfig memory percentageFee = IVariableVaultFee.FeeConfig({
            feeType: IVariableVaultFee.FeeType.PERCENTAGE,
            feeAmount: 1e16 // 1%
        });
        IVariableVaultFee.FeeConfig memory instantWithdrawalPercentageFee = IVariableVaultFee.FeeConfig({
            feeType: IVariableVaultFee.FeeType.PERCENTAGE,
            feeAmount: 2e16 // 2%
        });
        IVariableVaultFee.FeeConfig memory flashRedeemPercentageFee = IVariableVaultFee.FeeConfig({
            feeType: IVariableVaultFee.FeeType.PERCENTAGE,
            feeAmount: 3e16 // 3%
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

        uint256 depositFee = feeContract.feeOnRaw(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.DEPOSIT);
        assertEq(depositFee, getQuantizedValue(1));

        uint256 withdrawalFee = feeContract.feeOnRaw(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.WITHDRAWAL);
        assertEq(withdrawalFee, getQuantizedValue(1));

        uint256 instantWithdrawalFee = feeContract.feeOnRaw(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);
        assertEq(instantWithdrawalFee, getQuantizedValue(2));

        uint256 flashRedeemFee = feeContract.feeOnRaw(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.FLASH_REDEEM);
        assertEq(flashRedeemFee, getQuantizedValue(3));
    }

    function testFeeOnRawWithFeeZeroPercentageFee() public {
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

        uint256 depositFee = feeContract.feeOnRaw(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.DEPOSIT);
        assertEq(depositFee, 0);

        uint256 withdrawalFee = feeContract.feeOnRaw(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.WITHDRAWAL);
        assertEq(withdrawalFee, 0);

        uint256 instantWithdrawalFee = feeContract.feeOnRaw(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);
        assertEq(instantWithdrawalFee, 0);

        uint256 flashRedeemFee = feeContract.feeOnRaw(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.FLASH_REDEEM);
        assertEq(flashRedeemFee, 0);

    }

    function testFeeOnRawWithFeeZeroFlatFee() public {
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

        uint256 dFee = feeContract.feeOnRaw(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.DEPOSIT);
        assertEq(dFee, 0, "depositFee mismatch");

        uint256 wFee = feeContract.feeOnRaw(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.WITHDRAWAL);
        assertEq(wFee, 0, "withdrawalFee mismatch");

        uint256 iwFee = feeContract.feeOnRaw(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);
        assertEq(iwFee, 0, "instantWithdrawalFee mismatch");

        uint256 frFee = feeContract.feeOnRaw(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.FLASH_REDEEM);
        assertEq(frFee, 0, "flashRedeemFee mismatch");

    }

    function testFeeOnRawRevertsIfAssetIsZero() public {
        vm.expectRevert(IVariableVaultFee.IVariableVaultFee__InvalidAsset.selector);
        feeContract.feeOnRaw(address(0), getQuantizedValue(100), IVariableVaultFee.FeeOperation.DEPOSIT);

        vm.expectRevert(IVariableVaultFee.IVariableVaultFee__InvalidAsset.selector);
        feeContract.feeOnRaw(address(0), getQuantizedValue(100), IVariableVaultFee.FeeOperation.WITHDRAWAL);

        vm.expectRevert(IVariableVaultFee.IVariableVaultFee__InvalidAsset.selector);
        feeContract.feeOnRaw(address(0), getQuantizedValue(100), IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);

        vm.expectRevert(IVariableVaultFee.IVariableVaultFee__InvalidAsset.selector);
        feeContract.feeOnRaw(address(0), getQuantizedValue(100), IVariableVaultFee.FeeOperation.FLASH_REDEEM);
    }

    function testFeeOnRawRevertsIfAssetNotRegistered() public {
        vm.expectRevert(IVariableVaultFee.IVariableVaultFee__InvalidAsset.selector);
        feeContract.feeOnRaw(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.DEPOSIT);
        
        vm.expectRevert(IVariableVaultFee.IVariableVaultFee__InvalidAsset.selector);
        feeContract.feeOnRaw(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.WITHDRAWAL);

        vm.expectRevert(IVariableVaultFee.IVariableVaultFee__InvalidAsset.selector);
        feeContract.feeOnRaw(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);

        vm.expectRevert(IVariableVaultFee.IVariableVaultFee__InvalidAsset.selector);
        feeContract.feeOnRaw(address(token), getQuantizedValue(100), IVariableVaultFee.FeeOperation.FLASH_REDEEM);
    }

    function testFeeOnRawRevertsIfAmountIsZero() public {
        IVariableVaultFee.FeeConfig memory flatFee =
            IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: getQuantizedValue(1)});

        IVariableVaultFee.AssetFeeConfig memory _config =
            IVariableVaultFee.AssetFeeConfig({
                withdrawalFee: flatFee, 
                depositFee: flatFee, 
                instantWithdrawalFee: flatFee, 
                flashRedeemFee: flatFee,
                feeRecipient: feeRecipient
            });

        vm.prank(naruto);
        feeContract.registerAsset(address(token), _config);

        vm.expectRevert(IVariableVaultFee.IVariableVaultFee__ZeroAmount.selector);
        feeContract.feeOnRaw(address(token), 0, IVariableVaultFee.FeeOperation.DEPOSIT);

        vm.expectRevert(IVariableVaultFee.IVariableVaultFee__ZeroAmount.selector);
        feeContract.feeOnRaw(address(token), 0, IVariableVaultFee.FeeOperation.WITHDRAWAL);

        vm.expectRevert(IVariableVaultFee.IVariableVaultFee__ZeroAmount.selector);
        feeContract.feeOnRaw(address(token), 0, IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);
        
        vm.expectRevert(IVariableVaultFee.IVariableVaultFee__ZeroAmount.selector);
        feeContract.feeOnRaw(address(token), 0, IVariableVaultFee.FeeOperation.FLASH_REDEEM);
    }

    function testFeeOnRawCeilRounding() public {
        IVariableVaultFee.FeeConfig memory percentageFee = IVariableVaultFee.FeeConfig({
            feeType: IVariableVaultFee.FeeType.PERCENTAGE,
            feeAmount: 333333333333333 // 0.033333...%
        });

        IVariableVaultFee.AssetFeeConfig memory _config = IVariableVaultFee.AssetFeeConfig({
            withdrawalFee: percentageFee,
            depositFee: percentageFee,
            instantWithdrawalFee: percentageFee,
            flashRedeemFee: percentageFee,
            feeRecipient: feeRecipient
        });

        vm.prank(naruto);
        feeContract.registerAsset(address(token), _config);

        uint256 withdrawalAmount = getQuantizedValue(1000);

        uint256 withdrawalFee = feeContract.feeOnRaw(address(token), withdrawalAmount, IVariableVaultFee.FeeOperation.WITHDRAWAL);
        uint256 depositFee = feeContract.feeOnRaw(address(token), withdrawalAmount, IVariableVaultFee.FeeOperation.DEPOSIT);
        uint256 instantFee = feeContract.feeOnRaw(address(token), withdrawalAmount, IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);
        uint256 flashFee = feeContract.feeOnRaw(address(token), withdrawalAmount, IVariableVaultFee.FeeOperation.FLASH_REDEEM);

        if(config.tokenConfig.decimals == 6){
            // rounded up from 333_333.3333
            assertEq(withdrawalFee, 333_334);
            assertEq(depositFee, 333_334);
            assertEq(instantFee, 333_334);
            assertEq(flashFee, 333_334);
        } else if(config.tokenConfig.decimals == 8){
            // rounded up from 333_33333.3333
            assertEq(withdrawalFee, 333_333_34);
            assertEq(depositFee, 333_333_34);
            assertEq(instantFee, 333_333_34);
            assertEq(flashFee, 333_333_34);
        } else if(config.tokenConfig.decimals == 18){
            //Whole number value
            assertEq(withdrawalFee, 333_333_333_333_333_000);
            assertEq(depositFee, 333_333_333_333_333_000);
            assertEq(instantFee, 333_333_333_333_333_000);
            assertEq(flashFee, 333_333_333_333_333_000);
        }else{
            revert('Condition not added for given decimals');
        }

        // Should test for rounding up
        // If the decimal is more than 15, 
        // the fee will be a whole number as 
        // the denominator (1e18) cancels out 
        // the numerator and no rounding up is done
        if(token.decimals() < 15){
            assertGt(withdrawalFee * 1e18, withdrawalAmount * 333333333333333); // Strict greater ensures rounding up
            assertGt(depositFee * 1e18, withdrawalAmount * 333333333333333); // Strict greater ensures rounding up
            assertGt(instantFee * 1e18, withdrawalAmount * 333333333333333); // Strict greater ensures rounding up
            assertGt(flashFee * 1e18, withdrawalAmount * 333333333333333); // Strict greater ensures rounding up
        }
    }
}
