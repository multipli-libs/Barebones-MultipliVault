// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {VariableVaultFee} from "src/fees/VariableVaultFee.sol";
import {FeeBase} from "./Base.t.sol";
import {IVariableVaultFee} from "src/interfaces/IVariableVaultFee.sol";

contract TestFeeOnRaw is FeeBase {
    function testFeeOnRawFlatHappyFlow() public {
        IVariableVaultFee.FeeConfig memory depositFlatFee =
            IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 0});
        IVariableVaultFee.FeeConfig memory withdrawalFlatFee =
            IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 1e6});
        
        IVariableVaultFee.FeeConfig memory instantWithdrawalFlatFee =
            IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 2e6});

        IVariableVaultFee.FeeConfig memory flashFeeFlatFee =
            IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 3e6});

        IVariableVaultFee.AssetFeeConfig memory config = IVariableVaultFee.AssetFeeConfig({
            withdrawalFee: withdrawalFlatFee,
            depositFee: depositFlatFee,
            instantWithdrawalFee: instantWithdrawalFlatFee,
            flashRedeemFee: flashFeeFlatFee,
            feeRecipient: feeRecipient
        });

        vm.prank(naruto);
        feeContract.registerAsset(address(USDC), config);

        uint256 depositFee = feeContract.feeOnRaw(address(USDC), 100e6, IVariableVaultFee.FeeOperation.DEPOSIT);
        uint256 withdrawalFee = feeContract.feeOnRaw(address(USDC), 100e6, IVariableVaultFee.FeeOperation.WITHDRAWAL);
        uint256 instantWithdrawalFee = feeContract.feeOnRaw(address(USDC), 100e6, IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);
        uint256 flashRedeemFee = feeContract.feeOnRaw(address(USDC), 100e6, IVariableVaultFee.FeeOperation.FLASH_REDEEM);

        assertEq(depositFee, 0);
        assertEq(withdrawalFee, 1e6);
        assertEq(instantWithdrawalFee, 2e6);
        assertEq(flashRedeemFee, 3e6);
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

        IVariableVaultFee.AssetFeeConfig memory config = IVariableVaultFee.AssetFeeConfig({
            withdrawalFee: percentageFee,
            depositFee: percentageFee,
            instantWithdrawalFee: instantWithdrawalPercentageFee,
            flashRedeemFee: flashRedeemPercentageFee,
            feeRecipient: feeRecipient
        });

        vm.prank(naruto);
        feeContract.registerAsset(address(USDC), config);

        uint256 depositFee = feeContract.feeOnRaw(address(USDC), 100e6, IVariableVaultFee.FeeOperation.DEPOSIT);
        assertEq(depositFee, 1e6);

        uint256 withdrawalFee = feeContract.feeOnRaw(address(USDC), 100e6, IVariableVaultFee.FeeOperation.WITHDRAWAL);
        assertEq(withdrawalFee, 1e6);

        uint256 instantWithdrawalFee = feeContract.feeOnRaw(address(USDC), 100e6, IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);
        assertEq(instantWithdrawalFee, 2e6);

        uint256 flashRedeemFee = feeContract.feeOnRaw(address(USDC), 100e6, IVariableVaultFee.FeeOperation.FLASH_REDEEM);
        assertEq(flashRedeemFee, 3e6);
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

        IVariableVaultFee.AssetFeeConfig memory config = IVariableVaultFee.AssetFeeConfig({
            withdrawalFee: percentageFee,
            depositFee: percentageFee,
            instantWithdrawalFee: instantWithdrawalPercentageFee,
            flashRedeemFee: flashRedeemPercentageFee,
            feeRecipient: feeRecipient
        });

        vm.prank(naruto);
        feeContract.registerAsset(address(USDC), config);

        uint256 depositFee = feeContract.feeOnRaw(address(USDC), 100e6, IVariableVaultFee.FeeOperation.DEPOSIT);
        assertEq(depositFee, 0);

        uint256 withdrawalFee = feeContract.feeOnRaw(address(USDC), 100e6, IVariableVaultFee.FeeOperation.WITHDRAWAL);
        assertEq(withdrawalFee, 0);

        uint256 instantWithdrawalFee = feeContract.feeOnRaw(address(USDC), 100e6, IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);
        assertEq(instantWithdrawalFee, 0);

        uint256 flashRedeemFee = feeContract.feeOnRaw(address(USDC), 100e6, IVariableVaultFee.FeeOperation.FLASH_REDEEM);
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

        IVariableVaultFee.AssetFeeConfig memory config = IVariableVaultFee.AssetFeeConfig({
            withdrawalFee: flatFee,
            depositFee: flatFee,
            instantWithdrawalFee: instantWithdrawalFee,
            flashRedeemFee: flashRedeemFee,
            feeRecipient: feeRecipient
        });

        vm.prank(naruto);
        feeContract.registerAsset(address(USDC), config);

        uint256 dFee = feeContract.feeOnRaw(address(USDC), 100e6, IVariableVaultFee.FeeOperation.DEPOSIT);
        assertEq(dFee, 0, "depositFee mismatch");

        uint256 wFee = feeContract.feeOnRaw(address(USDC), 100e6, IVariableVaultFee.FeeOperation.WITHDRAWAL);
        assertEq(wFee, 0, "withdrawalFee mismatch");

        uint256 iwFee = feeContract.feeOnRaw(address(USDC), 100e6, IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);
        assertEq(iwFee, 0, "instantWithdrawalFee mismatch");

        uint256 frFee = feeContract.feeOnRaw(address(USDC), 100e6, IVariableVaultFee.FeeOperation.FLASH_REDEEM);
        assertEq(frFee, 0, "flashRedeemFee mismatch");

    }

    function testFeeOnRawRevertsIfAssetIsZero() public {
        vm.expectRevert(IVariableVaultFee.InvalidAsset.selector);
        feeContract.feeOnRaw(address(0), 100e6, IVariableVaultFee.FeeOperation.DEPOSIT);

        vm.expectRevert(IVariableVaultFee.InvalidAsset.selector);
        feeContract.feeOnRaw(address(0), 100e6, IVariableVaultFee.FeeOperation.WITHDRAWAL);

        vm.expectRevert(IVariableVaultFee.InvalidAsset.selector);
        feeContract.feeOnRaw(address(0), 100e6, IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);

        vm.expectRevert(IVariableVaultFee.InvalidAsset.selector);
        feeContract.feeOnRaw(address(0), 100e6, IVariableVaultFee.FeeOperation.FLASH_REDEEM);
    }

    function testFeeOnRawRevertsIfAssetNotRegistered() public {
        vm.expectRevert(IVariableVaultFee.InvalidAsset.selector);
        feeContract.feeOnRaw(address(USDC), 100e6, IVariableVaultFee.FeeOperation.DEPOSIT);
        
        vm.expectRevert(IVariableVaultFee.InvalidAsset.selector);
        feeContract.feeOnRaw(address(USDC), 100e6, IVariableVaultFee.FeeOperation.WITHDRAWAL);

        vm.expectRevert(IVariableVaultFee.InvalidAsset.selector);
        feeContract.feeOnRaw(address(USDC), 100e6, IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);

        vm.expectRevert(IVariableVaultFee.InvalidAsset.selector);
        feeContract.feeOnRaw(address(USDC), 100e6, IVariableVaultFee.FeeOperation.FLASH_REDEEM);
    }

    function testFeeOnRawRevertsIfAmountIsZero() public {
        IVariableVaultFee.FeeConfig memory flatFee =
            IVariableVaultFee.FeeConfig({feeType: IVariableVaultFee.FeeType.FLAT, feeAmount: 1e6});

        IVariableVaultFee.AssetFeeConfig memory config =
            IVariableVaultFee.AssetFeeConfig({
                withdrawalFee: flatFee, 
                depositFee: flatFee, 
                instantWithdrawalFee: flatFee, 
                flashRedeemFee: flatFee,
                feeRecipient: feeRecipient
            });

        vm.prank(naruto);
        feeContract.registerAsset(address(USDC), config);

        vm.expectRevert(IVariableVaultFee.ZeroAmount.selector);
        feeContract.feeOnRaw(address(USDC), 0, IVariableVaultFee.FeeOperation.DEPOSIT);

        vm.expectRevert(IVariableVaultFee.ZeroAmount.selector);
        feeContract.feeOnRaw(address(USDC), 0, IVariableVaultFee.FeeOperation.WITHDRAWAL);

        vm.expectRevert(IVariableVaultFee.ZeroAmount.selector);
        feeContract.feeOnRaw(address(USDC), 0, IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);
        
        vm.expectRevert(IVariableVaultFee.ZeroAmount.selector);
        feeContract.feeOnRaw(address(USDC), 0, IVariableVaultFee.FeeOperation.FLASH_REDEEM);
    }

    function testFeeOnRawCeilRounding() public {
        IVariableVaultFee.FeeConfig memory percentageFee = IVariableVaultFee.FeeConfig({
            feeType: IVariableVaultFee.FeeType.PERCENTAGE,
            feeAmount: 333333333333333 // 0.033333...%
        });

        IVariableVaultFee.AssetFeeConfig memory config = IVariableVaultFee.AssetFeeConfig({
            withdrawalFee: percentageFee,
            depositFee: percentageFee,
            instantWithdrawalFee: percentageFee,
            flashRedeemFee: percentageFee,
            feeRecipient: feeRecipient
        });

        vm.prank(naruto);
        feeContract.registerAsset(address(USDC), config);

        uint256 withdrawalAmount = 1000e6;

        // Should test for rounding up
        uint256 withdrawalFee = feeContract.feeOnRaw(address(USDC), withdrawalAmount, IVariableVaultFee.FeeOperation.WITHDRAWAL);
        assertEq(withdrawalFee, 333_334); // rounded up from 333_333.3333
        assertGt(withdrawalFee * 1e18, withdrawalAmount * 333333333333333); // Strict greater ensures rounding up

        uint256 depositFee = feeContract.feeOnRaw(address(USDC), withdrawalAmount, IVariableVaultFee.FeeOperation.DEPOSIT);
        assertEq(depositFee, 333_334); // rounded up from 333_333.3333
        assertGt(depositFee * 1e18, withdrawalAmount * 333333333333333); // Strict greater ensures rounding up

        uint256 instantFee = feeContract.feeOnRaw(address(USDC), withdrawalAmount, IVariableVaultFee.FeeOperation.INSTANT_WITHDRAWAL);
        assertEq(instantFee, 333_334); // rounded up from 333_333.3333
        assertGt(instantFee * 1e18, withdrawalAmount * 333333333333333); // Strict greater ensures rounding up

        uint256 flashFee = feeContract.feeOnRaw(address(USDC), withdrawalAmount, IVariableVaultFee.FeeOperation.FLASH_REDEEM);
        assertEq(flashFee, 333_334); // rounded up from 333_333.3333
        assertGt(flashFee * 1e18, withdrawalAmount * 333333333333333); // Strict greater ensures rounding up
    }
}
